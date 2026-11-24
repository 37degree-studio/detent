// Local preview: serves site/ and runs api/subscribe.js the way Vercel would.
// With no BLOB_READ_WRITE_TOKEN in the environment, signups are written to .signups/ in this folder instead of Blob,
// and Resend is skipped, so the whole gate can be tried without touching the real list.
// Run: node tools/dev.mjs  (port 4341, or PORT=...)
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { handle } from '../api/subscribe.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const port = Number(process.env.PORT || 4341);
const types = { '.html': 'text/html; charset=utf-8', '.svg': 'image/svg+xml', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png' };

const live = Boolean(process.env.BLOB_READ_WRITE_TOKEN);
const env = live ? process.env : { ...process.env, BLOB_READ_WRITE_TOKEN: 'local', RESEND_API_KEY: '' };
const localPut = async (pathname, body) => {
  const file = join(root, '.signups', pathname);
  await mkdir(join(file, '..'), { recursive: true });
  await writeFile(file, body);
};

createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === '/api/subscribe') {
    const chunks = []; for await (const c of req) chunks.push(c);
    const request = new Request(url, { method: req.method, headers: req.headers, body: req.method === 'POST' ? Buffer.concat(chunks) : undefined });
    const out = await handle(request, env, live ? undefined : localPut);
    res.writeHead(out.status, Object.fromEntries(out.headers)); res.end(await out.text());
    return;
  }
  let path = normalize(url.pathname === '/' ? '/index.html' : url.pathname);
  if (!extname(path)) path += '.html';   // /encoder serves encoder.html, as cleanUrls does on Vercel
  try {
    const body = await readFile(join(root, 'site', path));
    res.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream' }); res.end(body);
  } catch { res.writeHead(404); res.end('Not found'); }
}).listen(port, '127.0.0.1', () => console.log(`Detent on http://localhost:${port} (signups ${live ? 'go to the real Blob store' : 'saved to .signups/'})`));
