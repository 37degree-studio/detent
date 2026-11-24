#!/usr/bin/env node
// Share cards (tools/seo/SEO.md): one 1200×630 PNG per indexable page in site/og/, drawn by the local Google Chrome
// in headless mode from the real controls. Node 18+, no dependencies.
//
//   node tools/seo/og.mjs              draws the cards whose inputs changed (hashes in tools/seo/og-hashes.json)
//   node tools/seo/og.mjs --force      draws every card
//   node tools/seo/og.mjs --only clock,home
//
// Then run npm run build: pages link a card only once its PNG exists.
import { readFileSync, writeFileSync, existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const root = fileURLToPath(new URL('../..', import.meta.url));
const at = (...p) => join(root, ...p);
const args = process.argv.slice(2);
const FORCE = args.includes('--force');
const ONLY = args.includes('--only') ? args[args.indexOf('--only') + 1].split(',') : null;
const CHROME = process.env.CHROME || [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
].find(existsSync);
if (!CHROME) { console.error('No Chrome found. Set CHROME=/path/to/chrome.'); process.exit(1); }

const cfg = JSON.parse(readFileSync(at('tools/seo/site.json'), 'utf8'));
const catalog = readFileSync(at('src/catalog.html'), 'utf8');
const a = catalog.indexOf('  const PARTS = ['), b = catalog.indexOf('\n  ];', a) + '\n  ];'.length;
const PARTS = new Function(catalog.slice(a, b) + '\nreturn PARTS;')();
const block = id => catalog.match(new RegExp(`<script id="src-${id}">[\\s\\S]*?</script>`))?.[0] || '';
const ORDER = ['braun', 'nothing', 'index', 'aqua', 'pedal', 'original'];
const lookOf = p => [...p.looks].sort((x, y) => ORDER.indexOf(x) - ORDER.indexOf(y))[0];
const esc = t => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const host = new URL(cfg.origin).host;

const cardHtml = ({ kicker, headline, line, part, attrs }) => {
  const look = attrs.look || lookOf(part);
  const all = { ...part.attrs.light, ...attrs };
  if (look === part.looks[0]) delete all.look; else all.look = look;
  const el = `<${part.tag}${Object.entries(all).map(([k, v]) => v === '' ? ` ${k}` : ` ${k}="${esc(v)}"`).join('')}></${part.tag}>`;
  return `<!doctype html><html lang="en"><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Doto:wght@600;800&family=Funnel+Display:wght@300;400&family=Funnel+Sans:wght@400;500&family=JetBrains+Mono:wght@400;500&display=block">
<style>
html, body { margin: 0; width: 1200px; height: 630px; overflow: hidden; background: #f6f6f5; color: #1d1d1f; -webkit-font-smoothing: antialiased }
.card { display: grid; grid-template-columns: 1fr 520px; gap: 48px; height: 100%; box-sizing: border-box; padding: 56px }
.text { display: grid; grid-template-rows: auto 1fr auto; min-width: 0 }
.mark { display: flex; align-items: center; gap: 12px; font: 500 24px/1 "Funnel Sans", system-ui, sans-serif; letter-spacing: -.01em }
.mark i { width: 34px; height: 34px; border-radius: 10px; background: radial-gradient(circle at 50% 30%, #fbfbfa, #efefee); box-shadow: inset 0 0 0 1px #e3e3e1, 0 2px 3px -1px #00000026; position: relative }
.mark i::after { content: ""; position: absolute; left: 50%; top: 6px; width: 3px; height: 10px; translate: -50% 0; border-radius: 2px; background: #1d1d1f }
.words { align-self: center; display: grid; gap: 22px }
.kicker { font: 500 18px/1 "JetBrains Mono", ui-monospace, monospace; color: #75757a; text-transform: uppercase; letter-spacing: .04em }
h1 { margin: 0; font: 300 ${headline.length > 14 ? 76 : 96}px/1 "Funnel Display", system-ui, sans-serif; letter-spacing: -.045em }
p { margin: 0; font: 400 26px/1.35 "Funnel Sans", system-ui, sans-serif; color: #75757a; max-width: 24ch }
.foot { font: 500 18px/1 "Funnel Sans", system-ui, sans-serif; color: #a6a6aa }
.plate { display: flex; align-items: center; justify-content: center; border-radius: 44px; background: #efefee; box-shadow: inset 0 0 0 1px #e3e3e1, 0 1px 0 #fff, 0 30px 60px -36px #00000040; overflow: hidden }
</style>
<div class="card">
  <div class="text">
    <div class="mark"><i></i>${esc(cfg.name)}</div>
    <div class="words">${kicker ? `<div class="kicker">${esc(kicker)}</div>` : ''}<h1>${esc(headline)}</h1><p>${esc(line)}</p></div>
    <div class="foot">${esc(host)}</div>
  </div>
  <div class="plate" id="plate">${el}</div>
</div>
${block('feel')}
${block(part.fn)}
${block(`${part.fn}-look-${look}`)}
<script>
// Fit the control to the plate, never cropped, and keep it still.
window.Feel && (Feel.state.sound = false, Feel.state.haptics = false);
requestAnimationFrame(() => requestAnimationFrame(() => {
  const plate = document.getElementById('plate'), el = plate.firstElementChild;
  const room = Math.min(plate.clientWidth, plate.clientHeight) - 90, w = el.offsetWidth, h = el.offsetHeight;
  if (w && h) el.style.zoom = Math.min(room / w, room / h, 1.6).toFixed(3);
}));
</script>
</html>`;
};

const cards = [
  { name: 'home', headline: cfg.home.card.headline, line: cfg.home.card.line, part: PARTS.find(p => p.tag === cfg.home.card.part), attrs: cfg.home.card.attrs || {} },
  ...PARTS.map(p => ({ name: cfg.parts[p.tag].slug, kicker: p.kind, headline: p.name, line: 'A tactile control for the web and SwiftUI, with sound and haptics.', part: p, attrs: {} })),
  ...(cfg.hubs || []).filter(h => PARTS.filter(p => h.match.groups.includes(p.group)).length >= 3)
    .map(h => ({ name: h.slug, headline: h.name, line: h.card.line, part: PARTS.find(p => p.tag === h.card.part), attrs: h.card.attrs || {} })),
].map(c => ({ name: c.name, png: `site/og/${c.name}.png`, size: [1200, 630], html: cardHtml(c) }));

const hashFile = at('tools/seo/og-hashes.json');
const hashes = existsSync(hashFile) ? JSON.parse(readFileSync(hashFile, 'utf8')) : {};
mkdirSync(at('site/og'), { recursive: true });
const tmp = mkdtempSync(join(tmpdir(), 'detent-og-'));
let drawn = 0;
try {
  for (const c of cards) {
    if (ONLY && !ONLY.includes(c.name)) continue;
    const hash = createHash('sha256').update(c.html).digest('hex').slice(0, 16), png = at(c.png);
    if (!FORCE && hashes[c.name] === hash && existsSync(png)) continue;
    const file = join(tmp, `${c.name}.html`);
    writeFileSync(file, c.html);
    execFileSync(CHROME, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1', `--window-size=${c.size}`,
      '--virtual-time-budget=6000', `--user-data-dir=${join(tmp, 'profile')}`, `--screenshot=${png}`, pathToFileURL(file).href], { stdio: 'pipe' });
    hashes[c.name] = hash; drawn++;
    console.log(c.png);
  }
} finally { rmSync(tmp, { recursive: true, force: true }); }
writeFileSync(hashFile, JSON.stringify(Object.fromEntries(Object.entries(hashes).sort()), null, 2) + '\n');
console.log(drawn ? `${drawn} card${drawn > 1 ? 's' : ''} drawn. Now run npm run build.` : 'Every card is up to date.');
