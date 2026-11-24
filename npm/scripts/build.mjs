#!/usr/bin/env node
// Builds the detent npm package from src/catalog.html, the one source of truth for the controls, so the package
// never drifts from the site. It writes, inside npm/: feel.js, index.js, one folder per control (element.js, index.js,
// looks/<look>.js), swift/, skill/detent/ and LICENSE, and it rewrites the "files" and "exports" fields of
// npm/package.json from the same table. Everything it writes is git-ignored; it runs again on every `npm pack`.
// Run from anywhere: node npm/scripts/build.mjs (or `npm run build:package` at the repo root).
import { readFileSync, writeFileSync, rmSync, mkdirSync, copyFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = join(dirname(fileURLToPath(import.meta.url)), '..');
const ROOT = join(PKG, '..');
const catalog = readFileSync(join(ROOT, 'src/catalog.html'), 'utf8');
const pkg = JSON.parse(readFileSync(join(PKG, 'package.json'), 'utf8'));

function check(ok, msg) { if (!ok) { console.error(`build: ${msg}`); process.exit(1); } }
const scripts = (re) => new Map([...catalog.matchAll(re)].map((m) => [m[1], m[2]]));
const blocks = scripts(/<script id="src-([a-z0-9-]+)">\n?([\s\S]*?)<\/script>/g);
const swift = scripts(/<script type="text\/plain" id="swift-([a-z0-9-]+)">\n?([\s\S]*?)<\/script>/g);
const literal = (name, close) => {
  const a = catalog.indexOf(`const ${name} = `);
  check(a >= 0, `no ${name} in src/catalog.html`);
  const b = catalog.indexOf(close, a) + close.length;
  return new Function(`return ${catalog.slice(a + `const ${name} = `.length, b).replace(/;$/, '')}`)();
};
const PARTS = literal('PARTS', '\n  ]');
const LOOK_NAMES = literal('LOOK_NAMES', '};');
const block = (id) => { check(blocks.has(id), `no <script id="src-${id}"> in src/catalog.html`); return blocks.get(id).trim() + '\n'; };
const docOf = (src) => (/^\/\*([\s\S]*?)\*\//.exec(src) || ['', ''])[1].split('\n').map((l) => l.trim()).join(' ')
  .replace(/ — /g, ': ').replace(/(\d)–(\d)/g, '$1 to $2').trim().replace(/^(<[^>]+>)/, '`$1`');
const all = (src, re) => [...new Set([...src.matchAll(re)].map((m) => m[1]))];

// The domain: one row per control, read from PARTS and checked against the control's own code.
const controls = PARTS.map((p) => {
  const src = block(p.fn);
  const cls = (/window\.(Detent\w+) = /.exec(src) || [])[1];
  const fallback = (/getAttribute\('look'\) \|\| '(\w+)'/.exec(src) || [])[1];
  check(cls, `src-${p.fn} sets no window.Detent… class`);
  check(fallback === p.looks[0], `${p.tag} renders "${fallback}" with no look attribute, but PARTS lists "${p.looks[0]}" first`);
  check(swift.has(p.swiftId), `no swift-${p.swiftId} block for ${p.tag}`);
  return {
    ...p, src, cls, doc: docOf(src),
    attributes: all(src, /(?:get|has)Attribute\('([a-z-]+)'\)/g).filter((a) => !['aria-label', 'tabindex'].includes(a)),
    events: all(src, /new (?:Custom)?Event\('([a-z-]+)'/g),
    props: ['value', ...all(src, /^ {4}set ([a-zA-Z]+)\(/gm).filter((x) => x !== 'value')],
    size: (/:host \{ (--(?:s|w|row): [^;]+);/.exec(src) || [])[1],
    looks: p.looks.map((id) => ({ id, name: LOOK_NAMES[id], src: block(`${p.fn}-look-${id}`), doc: docOf(block(`${p.fn}-look-${id}`)) })),
    swiftSrc: swift.get(p.swiftId),
  };
});
const used = new Set(['feel', ...controls.flatMap((c) => [c.fn, ...c.looks.map((l) => `${c.fn}-look-${l.id}`)])]);
for (const id of blocks.keys()) check(used.has(id), `src-${id} is in the catalogue but not in PARTS`);

// The package: every file it ships, as path -> contents. Each module is a catalogue block verbatim, with an import of
// what it needs first (the blocks expect window.Feel and window.Detent… to exist) and an export of what it defines.
const GEN = '// Generated from src/catalog.html by npm/scripts/build.mjs. Edit the catalogue, not this file.\n';
const files = new Map();
files.set('feel.js', `${GEN}${block('feel')}\nexport const Feel = window.Feel;\nexport default Feel;\n`);
for (const c of controls) {
  const reexport = `export { default, ${c.cls} } from`;
  files.set(`${c.fn}/element.js`, `${GEN}import '../feel.js';\n\n${c.src}\nexport const ${c.cls} = window.${c.cls};\nexport default ${c.cls};\n`);
  for (const l of c.looks) files.set(`${c.fn}/looks/${l.id}.js`, `${GEN}import '../element.js';\n\n${l.src}\n${reexport} '../element.js';\n`);
  files.set(`${c.fn}/index.js`, `${GEN}import './looks/${c.looks[0].id}.js';\n\n${reexport} './element.js';\n`);
  files.set(`swift/${c.swiftFile}`, c.swiftSrc);
}
files.set('index.js', GEN + controls.map((c) => `export { ${c.cls} } from './${c.fn}/index.js';\n`).join('') + `export { Feel } from './feel.js';\n`);

// The skill: SKILL.md from its template, plus references generated from PARTS and the controls' own header comments.
const attrText = (o) => Object.entries(o).map(([k, v]) => (v === '' ? ` ${k}` : ` ${k}="${v}"`)).join('');
const tagged = (c, o) => `<${c.tag}${attrText(o)}></${c.tag}>`;
const lookList = (c) => c.looks.map((l, i) => `\`${l.id}\`${i ? '' : ' (default)'}`).join(', ');
const table = ['| Control | Element | Import | Looks | What it is |', '|---|---|---|---|---|',
  ...controls.map((c) => `| ${c.name} | \`<${c.tag}>\` | \`detent/${c.fn}\` | ${lookList(c)} | ${c.note} |`)].join('\n');
const controlDoc = (c) => [
  `## ${c.name}: \`<${c.tag}>\``, '', c.lede, '',
  '```html', tagged(c, c.attrs.light), '```', '',
  `- **Import:** \`import 'detent/${c.fn}'\` (the element and its default look, ${c.looks[0].name}).`,
  `- **Attributes:** ${c.attributes.map((a) => `\`${a}\``).join(', ')}.`,
  `- **Events:** ${c.events.map((e) => `\`${e}\``).join(', ')}.`,
  `- **Properties:** ${c.props.map((x) => `\`.${x}\``).join(', ')}.`,
  ...(c.size ? [`- **Size:** set \`${c.size.split(':')[0]}\` on the element (default \`${c.size.split(':')[1].trim()}\`).`] : []),
  ...c.opts.map((o) => `- **${o.label}:** ${o.options.map(([v, label]) => `${label} \`${attrText(o.attr(v)).trim() || '(default)'}\``).join(', ')}.`),
  `- **In its own words:** ${c.doc}`, '',
  '**Looks**', '',
  ...c.looks.map((l, i) => `- \`${l.id}\`${i ? '' : ' (default)'}: \`import 'detent/${c.fn}/looks/${l.id}'\`, then \`look="${l.id}"\`. ${l.doc.replace(/^[^:]*"[a-z]+": (.)/, (_, c) => c.toUpperCase())}`), '',
  '**How it behaves**', '',
  ...c.behaviors.map(([k, v]) => `- **${k}.** ${v}`), '',
  `**SwiftUI:** \`${c.swiftFile}\` (${c.looks[0].name} look).`, '', '```swift', c.swiftUsage, '```', '',
].join('\n');
const controlsMd = `# Detent controls\n\nGenerated from the Detent catalogue for detent@${pkg.version}. One section per control: what it is, its attributes, events, properties, looks and SwiftUI file.\n\n${controls.map(controlDoc).join('\n')}`;
const swiftMd = ['# Detent in SwiftUI', '',
  `Each control has one SwiftUI file, in its default look. The files ship in the npm package at \`node_modules/detent/swift/\` and are at https://unpkg.com/detent@${pkg.version}/swift/<File>.swift. Add the file to the app target and use the view as below.`, '',
  '| Control | File | Look |', '|---|---|---|', ...controls.map((c) => `| ${c.name} | \`${c.swiftFile}\` | ${c.looks[0].name} |`), '',
  ...controls.flatMap((c) => [`## ${c.name}: \`${c.swiftFile}\``, '', '```swift', c.swiftUsage, '```', ''])].join('\n');
const skill = readFileSync(join(PKG, 'templates/SKILL.md'), 'utf8')
  .replaceAll('{{VERSION}}', pkg.version)
  .replaceAll('{{TAGS}}', controls.map((c) => c.tag).join(', '))
  .replaceAll('{{CONTROLS}}', table);
check(!/\{\{[A-Z]+\}\}/.test(skill), 'templates/SKILL.md has a placeholder the build does not fill');
files.set('skill/detent/SKILL.md', skill);
files.set('skill/detent/references/controls.md', controlsMd);
files.set('skill/detent/references/swiftui.md', swiftMd);

// Write: clear what an earlier run wrote, then the files, then package.json's "files" and "exports" from the same table.
const tops = [...new Set([...files.keys()].map((f) => f.split('/')[0]))];
for (const t of [...tops, 'LICENSE']) rmSync(join(PKG, t), { recursive: true, force: true });
for (const [path, body] of files) { mkdirSync(dirname(join(PKG, path)), { recursive: true }); writeFileSync(join(PKG, path), body); }
copyFileSync(join(ROOT, 'LICENSE'), join(PKG, 'LICENSE'));
const exports = { '.': './index.js', './feel': './feel.js' };
for (const c of controls) {
  exports[`./${c.fn}`] = `./${c.fn}/index.js`;
  exports[`./${c.fn}/element`] = `./${c.fn}/element.js`;
  for (const l of c.looks) exports[`./${c.fn}/looks/${l.id}`] = `./${c.fn}/looks/${l.id}.js`;
}
exports['./swift/*'] = './swift/*';
exports['./package.json'] = './package.json';
pkg.files = ['bin', ...tops.sort()];
pkg.exports = exports;
writeFileSync(join(PKG, 'package.json'), JSON.stringify(pkg, null, 2) + '\n');
console.log(`npm/: ${controls.length} controls, ${controls.reduce((n, c) => n + c.looks.length, 0)} looks, ${controls.length} SwiftUI files, the skill · ${files.size + 1} files · detent@${pkg.version}`);
