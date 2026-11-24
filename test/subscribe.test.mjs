// npm test  — checks the signup endpoint without touching Blob or Resend.
import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../api/subscribe.js';

const post = (body, headers = {}) => new Request('https://detent.example/api/subscribe', {
  method: 'POST', headers: { 'Content-Type': 'application/json', host: 'detent.example', ...headers }, body: JSON.stringify(body),
});
const env = { BLOB_READ_WRITE_TOKEN: 'test' };

test('saves a signup tagged detent with the page it came from', async () => {
  const saved = [];
  const r = await handle(post({ email: ' Ada@Example.com ', figure: 'detent-bezel', source: 'pricing' }, { origin: 'https://detent.example' }), env, async (path, body) => saved.push([path, JSON.parse(body)]));
  assert.equal(r.status, 200);
  assert.equal(saved.length, 1);
  assert.match(saved[0][0], /^signups\/\d{4}-\d{2}-\d{2}\//);
  assert.equal(saved[0][1].email, 'ada@example.com');
  assert.equal(saved[0][1].source, 'detent');          // set by the server, whatever the page sends
  assert.equal(saved[0][1].figure, 'detent-bezel');
});

test('refuses other sites', async () => {
  const r = await handle(post({ email: 'a@b.co' }, { origin: 'https://evil.example' }), env, async () => assert.fail('saved'));
  assert.equal(r.status, 403);
});

test('a filled honeypot looks fine but saves nothing', async () => {
  const r = await handle(post({ email: 'a@b.co', website: 'spam.biz' }), env, async () => assert.fail('saved'));
  assert.equal(r.status, 200);
});

test('rejects a bad email', async () => {
  const r = await handle(post({ email: 'nope' }), env, async () => assert.fail('saved'));
  assert.equal(r.status, 400);
});

test('with no store of its own, refuses rather than sending anywhere else', async () => {
  const r = await handle(post({ email: 'a@b.co' }), { fetch: async () => assert.fail('sent elsewhere') }, async () => assert.fail('saved'));
  assert.equal(r.status, 503);
});
