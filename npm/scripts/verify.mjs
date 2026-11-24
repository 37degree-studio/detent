#!/usr/bin/env node
// Proves the packed package works from the outside: packs it, installs the tarball into a fresh project outside the
// repo, loads every control and look in headless Chrome through the package's own "exports", and runs the installer
// against a throwaway HOME. Run: node npm/scripts/verify.mjs [scratch-dir]   (CHROME=/path/to/chrome to override)
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = process.argv[2] ? (mkdirSync(process.argv[2], { recursive: true }), mkdtempSync(join(process.argv[2], 'verify-'))) : mkdtempSync(join(tmpdir(), 'detent-verify-'));
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
let failed = 0;
const ok = (cond, msg) => { console.log(`${cond ? 'ok  ' : 'FAIL'} ${msg}`); if (!cond) failed++; };
const run = (cmd, args, opts = {}) => execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts });
console.log(`scratch: ${OUT}\n`);

// 1. pack: the tarball holds exactly bin/, the generated files, LICENSE, README and package.json
const packOut = run('npm', ['pack', '--json', '--pack-destination', OUT], { cwd: PKG });   // prepack's build log comes first
const [packed] = JSON.parse(packOut.slice(packOut.indexOf('[')));
const listed = packed.files.map((f) => f.path).sort();
const pj = JSON.parse(readFileSync(join(PKG, 'package.json'), 'utf8'));
const walk = (d, at = '') => readdirSync(join(d, at), { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? walk(d, join(at, e.name)) : [join(at, e.name)]);
const expected = ['LICENSE', 'README.md', 'package.json', ...pj.files.flatMap((f) => f.endsWith('.js') ? [f] : walk(PKG, f))].sort();
ok(JSON.stringify(listed) === JSON.stringify(expected), `npm pack lists exactly the intended ${expected.length} files`);
ok(!listed.some((f) => /^(scripts|templates)\//.test(f)), 'no build scripts or templates in the tarball');
for (const [k, v] of Object.entries(pj.exports)) if (!k.includes('*')) ok(listed.includes(v.slice(2)), `export ${k} -> ${v} is in the tarball`);

// 2. install the tarball into a fresh project
const app = join(OUT, 'app');
mkdirSync(app);
writeFileSync(join(app, 'package.json'), '{ "name": "app", "private": true, "type": "module" }\n');
run('npm', ['install', join(OUT, packed.filename), '--no-audit', '--no-fund', '--offline'], { cwd: app });
const exports = JSON.parse(readFileSync(join(app, 'node_modules/detent/package.json'), 'utf8')).exports;
const resolved = run('node', ['--input-type=module', '-e',
  `console.log(import.meta.resolve('detent/encoder'), import.meta.resolve('detent/encoder/looks/index'), import.meta.resolve('detent/swift/MachinedDial.swift'))`], { cwd: app });
ok(/encoder\/index\.js .*encoder\/looks\/index\.js .*swift\/MachinedDial\.swift/.test(resolved), 'Node resolves detent/encoder, a look and a swift file through "exports"');

// 3. the browser: an import map built from the installed package's "exports", so the page resolves the way a bundler would
const map = { imports: Object.fromEntries(Object.entries(exports).filter(([k]) => !k.includes('*'))
  .map(([k, v]) => [k === '.' ? 'detent' : `detent/${k.slice(2)}`, `/node_modules/detent/${v.slice(2)}`])) };
const looks = Object.keys(map.imports).filter((k) => k.includes('/looks/'));
const page = (body, script) => `<!doctype html><html><head><meta charset="utf-8"><script type="importmap">${JSON.stringify(map)}</script></head>
<body style="background:#f6f6f5">${body}<pre id="out">pending</pre><script type="module">
const errors = []; addEventListener('error', (e) => errors.push(String(e.message)));
try { ${script} } catch (e) { errors.push(String(e)); }
await new Promise((r) => setTimeout(r, 200));   // headless Chrome under a virtual-time budget runs timers, not frames
const els = [...document.querySelectorAll('*')].filter((el) => el.localName.startsWith('detent-'));
document.getElementById('out').textContent = JSON.stringify({ errors, els: els.map((el) => ({ tag: el.localName, look: el.getAttribute('look') || '(default)',
  defined: !!customElements.get(el.localName), shadow: el.shadowRoot ? el.shadowRoot.innerHTML.length : 0,
  w: Math.round(el.getBoundingClientRect().width), h: Math.round(el.getBoundingClientRect().height), value: String(el.value) })) });
</script></body></html>`;
writeFileSync(join(app, 'encoder.html'), page('<detent-encoder value="40"></detent-encoder> <detent-encoder look="index" value="72"></detent-encoder>',
  `const { DetentEncoder } = await import('detent/encoder'); await import('detent/encoder/looks/index'); window.cls = DetentEncoder.name;`));
writeFileSync(join(app, 'all.html'), page(looks.map((k) => { const [, fn, , look] = k.split('/'); return `<detent-${fn} look="${look}"></detent-${fn}>`; }).join('\n')
  + Object.keys(map.imports).filter((k) => /^detent\/[a-z]+$/.test(k) && k !== 'detent/feel').map((k) => `<detent-${k.split('/')[1]}></detent-${k.split('/')[1]}>`).join('\n'),
  `await import('detent'); for (const k of ${JSON.stringify(looks)}) await import(k);`));

const types = { '.html': 'text/html', '.js': 'text/javascript' };
const server = createServer((req, res) => {
  const file = join(app, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(app) || !existsSync(file)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream' }); res.end(readFileSync(file));
}).listen(0, '127.0.0.1');
await new Promise((r) => server.once('listening', r));
const url = (p) => `http://127.0.0.1:${server.address().port}/${p}`;
const chrome = (args) => new Promise((resolve) => {   // async, so this process keeps serving while Chrome loads the page
  import('node:child_process').then(({ execFile }) => execFile(CHROME, ['--headless=new', '--disable-gpu', '--no-first-run',
    `--user-data-dir=${mkdtempSync(join(OUT, 'chrome-'))}`, '--virtual-time-budget=4000', ...args], { encoding: 'utf8', maxBuffer: 1e8 },
    (err, stdout) => resolve(stdout || '')));
});
const results = async (p) => {
  const dom = await chrome(['--dump-dom', url(p)]);
  const m = /<pre id="out">([\s\S]*?)<\/pre>/.exec(dom);
  return m && m[1] !== 'pending' ? JSON.parse(m[1].replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')) : null;
};
if (!existsSync(CHROME)) ok(false, `Chrome not found at ${CHROME}; set CHROME to run the browser checks`);
else {
  const enc = await results('encoder.html');
  ok(enc && enc.errors.length === 0, `encoder page: no errors ${enc ? JSON.stringify(enc.errors) : '(no result)'}`);
  for (const e of enc ? enc.els : []) ok(e.defined && e.shadow > 0 && e.w > 0 && e.h > 0, `encoder page: <${e.tag} look=${e.look}> defined, rendered ${e.w}x${e.h}, value ${e.value}`);
  const every = await results('all.html');
  ok(every && every.errors.length === 0, `every control and look: no errors ${every ? JSON.stringify(every.errors) : '(no result)'}`);
  const bad = (every ? every.els : []).filter((e) => !(e.defined && e.shadow > 0 && e.w > 0 && e.h > 0));
  ok(every && every.els.length === looks.length + 9 && bad.length === 0,
    `every control and look: ${every ? every.els.length : 0} elements (${looks.length} looks + 9 defaults) rendered${bad.length ? ', not: ' + JSON.stringify(bad) : ''}`);
  await chrome(['--screenshot=' + join(OUT, 'encoder.png'), '--window-size=520,300', url('encoder.html')]);
  await chrome(['--screenshot=' + join(OUT, 'all.png'), '--window-size=1400,2400', url('all.html')]);
  console.log(`     screenshots: ${join(OUT, 'encoder.png')}, ${join(OUT, 'all.png')}`);
}
server.close();

// 4. the installer, against a throwaway HOME
const home = join(OUT, 'home'), proj = join(OUT, 'project');
mkdirSync(home); mkdirSync(proj);
const cli = (args, cwd = app) => { const r = spawnSync(cwd === app ? 'npx' : join(app, 'node_modules/.bin/detent'), cwd === app ? ['detent', ...args] : args, { cwd, encoding: 'utf8', env: { ...process.env, HOME: home } });
  console.log(`\n$ HOME=${home} ${cwd === app ? 'npx detent' : 'app/node_modules/.bin/detent'} ${args.join(' ')}   (exit ${r.status})\n${(r.stdout + r.stderr).trim()}`); return r; };
ok(/Usage/.test(cli(['install', '--help']).stdout), 'npx detent install --help prints usage');
const dry = cli(['install', '--all', '--dry-run']);
ok(/would install/.test(dry.stdout) && !existsSync(join(home, '.claude')), '--dry-run says where it would go and writes nothing');
cli(['install', '--agent', 'claude-code', '--agent', 'cursor']);
ok(existsSync(join(home, '.claude/skills/detent/SKILL.md')) && existsSync(join(home, '.agents/skills/detent/references/controls.md')), 'install writes the skill for Claude Code and the shared .agents folder');
ok(/already up to date/.test(cli(['install', '--agent', 'claude-code']).stdout), 'a second install is a no-op');
cli(['install', '--project', '--agent', 'agents-md'], proj);
ok(/detent:start/.test(readFileSync(join(proj, 'AGENTS.md'), 'utf8')), '--project --agent agents-md adds the AGENTS.md block');
cli(['uninstall', '--agent', 'claude-code', '--agent', 'cursor']);
ok(!existsSync(join(home, '.claude/skills/detent')), 'uninstall removes it');

console.log(`\n${failed ? `${failed} check(s) failed` : 'all checks passed'} · ${OUT}`);
process.exit(failed ? 1 : 0);
