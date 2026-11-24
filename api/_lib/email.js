// The one email Detent sends a person: the thank-you after the email gate. Tables and inline styles, because mail apps
// strip most CSS; the <style> block only adds dark mode where the app honours it. No images, so nothing to host.

const C = { bg: '#f6f6f5', card: '#ffffff', ink: '#1d1d1f', soft: '#5f5f66', faint: '#75757a' };
const SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif";
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export function thanksEmail({ origin, canReply = false }) {
  const p = (t, extra = '') => `<p class="d-soft" style="margin:0 0 16px;font:400 15px/1.6 ${SANS};color:${C.soft};${extra}">${t}</p>`;
  const lines = [
    "Thanks for signing up. The code for every control is unlocked on this browser now: open any control, pick its look, and press Copy.",
    "We'll email product news and new controls now and then.",
    ...(canReply ? ['Reply to any email to be taken off the list.'] : []),
  ];
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark"><title>You're on the Detent list</title>
<style>:root{color-scheme:light dark}@media (prefers-color-scheme:dark){.d-bg{background:#0b0b0c!important}.d-card{background:#19191b!important}.d-ink{color:#ededee!important}.d-soft{color:#a0a0a6!important}.d-btn{background:#ededee!important}.d-btn a{color:#1d1d1f!important}}</style>
</head>
<body class="d-bg" style="margin:0;padding:0;background:${C.bg}">
<table role="presentation" class="d-bg" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${C.bg}" style="background:${C.bg}">
  <tr><td align="center" style="padding:40px 16px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px">
      <tr><td class="d-card" bgcolor="${C.card}" style="background:${C.card};border-radius:14px;padding:40px">
        <h1 class="d-ink" style="margin:0 0 16px;font:500 24px/1.2 ${SANS};letter-spacing:-0.02em;color:${C.ink}">You're on the Detent list</h1>
        ${lines.map((l) => p(l)).join('\n        ')}
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 0">
          <tr><td class="d-btn" bgcolor="${C.ink}" style="border-radius:999px;background:${C.ink}">
            <a href="${esc(origin)}" style="display:inline-block;padding:12px 20px;font:500 15px/1 ${SANS};color:#ffffff;text-decoration:none">Open Detent</a>
          </td></tr>
        </table>
      </td></tr>
      <tr><td style="padding:20px 4px 0">
        <p class="d-soft" style="margin:0;font:400 12px/1.6 ${SANS};color:${C.faint}">You got this because this address was entered on ${esc(origin.replace(/^https?:\/\//, ''))}.<br>Detent is made by 37degree.</p>
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`;
  return {
    subject: "You're on the Detent list",
    html,
    text: [...lines, `Open Detent: ${origin}`].join('\n\n'),
  };
}
