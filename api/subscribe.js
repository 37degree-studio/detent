// POST /api/subscribe: the email gate in front of Detent's code, adapted from Linejig's api/subscribe.js. Detent's
// signups are kept apart from Linejig's: one private JSON file per signup in Detent's own Vercel Blob store
// (BLOB_READ_WRITE_TOKEN on the Detent project), and, when RESEND_API_KEY is set, a contact in Detent's own Resend
// segment (RESEND_SEGMENT_ID). With neither set it refuses the signup; it never sends one anywhere else.
// Every record is tagged source "detent", and figure is the control page it came from.
// With NOTIFY_TO and NOTIFY_FROM the owner gets a short notice; with THANKS_FROM (or NOTIFY_FROM) a first-time signup
// gets a thank-you. A signup succeeds when Blob or Resend kept it.

import { thanksEmail } from './_lib/email.js';

const RESEND = 'https://api.resend.com';
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX = { email: 254, figure: 80 };

const reply = (status, body) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
const fail = (status, error) => reply(status, { ok: false, error });
const mask = (email) => email.replace(/^(.).*(@.*)$/, '$1…$2');
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

const blobPut = async (...args) => (await import('@vercel/blob')).put(...args);

async function save(env, put, record) {
  if (!env.BLOB_READ_WRITE_TOKEN) return false;
  const at = record.at.replace(/:/g, '-');
  const pathname = `signups/${at.slice(0, 10)}/${at}-${crypto.randomUUID().slice(0, 8)}.json`;
  try {
    await put(pathname, JSON.stringify(record), {
      access: 'private', addRandomSuffix: false, contentType: 'application/json', token: env.BLOB_READ_WRITE_TOKEN,
    });
    return true;
  } catch (e) {
    console.error('subscribe: blob save failed', e?.name || '', e?.message || '');
    return false;
  }
}

const siteOrigin = (request) => {
  const host = request.headers.get('x-forwarded-host') || request.headers.get('host');
  return host ? `${request.headers.get('x-forwarded-proto') || 'https'}://${host}` : new URL(request.url).origin;
};

// same origin only: a browser on another site sends its own Origin, and no CORS headers ever go back
function sameOrigin(request) {
  const origin = request.headers.get('origin');
  if (!origin) return true;
  try { return new URL(origin).host === (request.headers.get('x-forwarded-host') || request.headers.get('host')); }
  catch { return false; }
}

export function parse(body) {
  if (!body || typeof body !== 'object') return { error: 'Send a JSON object.' };
  if (text(body.website, 200)) return { spam: true };
  const email = typeof body.email === 'string' ? body.email.trim() : '';
  if (!email || email.length > MAX.email || !EMAIL.test(email)) return { error: 'Enter an email address like name@company.com.' };
  return { sub: { email: email.toLowerCase(), figure: text(body.figure, MAX.figure), source: 'detent' } };
}

async function resend(env, path, payload) {
  const r = await fetch(RESEND + path, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const data = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, data };
}

// an email that is already a contact counts as saved
const already = (res) => res.status === 409 || /already exists/i.test(String(res.data?.message || ''));

export async function handle(request, env = process.env, put = blobPut) {
  if (request.method !== 'POST') return fail(405, 'Use POST.');
  if (!sameOrigin(request)) return fail(403, 'Not allowed.');

  let body;
  try { body = await request.json(); } catch { return fail(400, 'Send a JSON object.'); }
  const { sub, spam, error } = parse(body);
  if (spam) return reply(200, { ok: true });
  if (error) return fail(400, error);

  const country = text(request.headers.get('x-vercel-ip-country'), 8);
  const saved = await save(env, put, { ...sub, at: new Date().toISOString(), ...(country ? { country } : {}) });

  if (!env.RESEND_API_KEY) {
    if (saved) return reply(200, { ok: true });
    return env.BLOB_READ_WRITE_TOKEN ? fail(502, 'Could not save that. Try again.') : fail(503, 'Signups are not set up yet.');
  }

  let known = false;   // already a contact: a repeat signup gets no second thank-you
  const contact = { email: sub.email, unsubscribed: false };
  if (env.RESEND_SEGMENT_ID) contact.segments = [{ id: env.RESEND_SEGMENT_ID }];
  const res = await resend(env, '/contacts', contact).catch(() => ({ ok: false, status: 0, data: {} }));
  known = res.ok ? false : already(res);
  if (!res.ok && !known) {
    console.error('subscribe: contact failed', res.status, mask(sub.email), res.data?.name || '');
    if (!saved) return fail(502, 'Could not save the email. Try again.');
  }

  if (env.NOTIFY_TO && env.NOTIFY_FROM) {
    const n = await resend(env, '/emails', {
      from: env.NOTIFY_FROM, to: env.NOTIFY_TO,
      subject: `Detent signup${sub.figure ? ` (${sub.figure})` : ''}`,
      text: [`Source: detent`, sub.figure && `Page: ${sub.figure}`, `Email: ${sub.email}`].filter(Boolean).join('\n\n'),
      reply_to: sub.email,
    }).catch(() => ({ ok: false, status: 0, data: {} }));
    if (!n.ok) console.error('subscribe: notify failed', n.status, n.data?.name || '');
  }

  // the thank-you, first signup only; replies go to AUTH_REPLY_TO. Never fails the signup.
  const from = env.THANKS_FROM || env.NOTIFY_FROM;
  if (from && !known) {
    const thanks = thanksEmail({ origin: siteOrigin(request), canReply: Boolean(env.AUTH_REPLY_TO) });
    const t = await resend(env, '/emails', {
      from, to: sub.email, ...thanks, ...(env.AUTH_REPLY_TO ? { reply_to: env.AUTH_REPLY_TO } : {}),
    }).catch(() => ({ ok: false, status: 0, data: {} }));
    if (!t.ok) console.error('subscribe: thanks failed', t.status, mask(sub.email), t.data?.name || '');
  }

  return reply(200, { ok: true });
}

export default { fetch: (request) => handle(request) };
