#!/usr/bin/env node
// Pre-commit hook: rebuilds site/ when a commit touches its inputs, so the commit carries pages that match them.
//
//   node tools/seo/hook.mjs --install     installs the hook (an existing pre-commit is kept as pre-commit.local and runs first)
//   node tools/seo/hook.mjs --uninstall   puts the old pre-commit back
//   node tools/seo/hook.mjs               what the hook runs
import { readFileSync, writeFileSync, existsSync, renameSync, unlinkSync, chmodSync, mkdirSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { resolve, join } from 'node:path';

const MARK = '# detent-seo-hook';
const HOOK = `#!/bin/sh
${MARK}: installed by node tools/seo/hook.mjs --install
local="$(dirname "$0")/pre-commit.local"
if [ -x "$local" ]; then "$local" "$@" || exit $?; fi
# Hooks are shared by every worktree, and older branches have no hook.mjs.
[ -f tools/seo/hook.mjs ] || exit 0
exec node tools/seo/hook.mjs
`;
const INPUTS = ['src/', 'tools/build.mjs', 'tools/seo/'];
const CHROME = process.env.CHROME || [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
].find(existsSync);

const git = (...args) => execFileSync('git', args, { encoding: 'utf8' });
const lines = out => out.split('\n').filter(Boolean);
const abort = msg => { console.error(`pre-commit: ${msg}`); process.exit(1); };
const ours = file => existsSync(file) && readFileSync(file, 'utf8').includes(MARK);

const STEPS = [
  { name: 'share cards', run: ['node', 'tools/seo/og.mjs'], when: () => CHROME || console.warn('pre-commit: no Chrome found, share cards not redrawn. Set CHROME=/path/to/chrome.') },
  { name: 'build', run: ['node', 'tools/build.mjs'], when: () => true },
  { name: 'check', run: ['node', 'tools/build.mjs', '--check'], when: () => true },
  { name: 'stage', run: ['git', 'add', '-A', '--', 'site', 'tools/seo/og-hashes.json'], when: () => true },
];

function install() {
  const dir = resolve(git('rev-parse', '--git-path', 'hooks').trim());
  const hook = join(dir, 'pre-commit'), local = join(dir, 'pre-commit.local');
  mkdirSync(dir, { recursive: true });
  if (ours(hook) && readFileSync(hook, 'utf8') === HOOK) return console.log(`Already installed: ${hook}`);
  if (existsSync(hook) && !ours(hook)) {
    if (existsSync(local)) abort(`${hook} and ${local} both exist. Merge them by hand, then install again.`);
    renameSync(hook, local);
    console.log(`Kept your pre-commit as ${local}. It runs first.`);
  }
  writeFileSync(hook, HOOK);
  chmodSync(hook, 0o755);
  console.log(`Installed ${hook}`);
}

function uninstall() {
  const dir = resolve(git('rev-parse', '--git-path', 'hooks').trim());
  const hook = join(dir, 'pre-commit'), local = join(dir, 'pre-commit.local');
  if (!ours(hook)) return console.log('Not installed. Nothing to do.');
  unlinkSync(hook);
  if (existsSync(local)) { renameSync(local, hook); console.log(`Restored ${hook}`); }
  else console.log(`Removed ${hook}`);
}

function run() {
  const touches = p => INPUTS.some(i => i.endsWith('/') ? p.startsWith(i) : p === i);
  if (!lines(git('diff', '--cached', '--name-only')).some(touches)) return;
  const loose = [...lines(git('diff', '--name-only', '--', ...INPUTS)), ...lines(git('ls-files', '--others', '--exclude-standard', '--', ...INPUTS))];
  if (loose.length) abort(`these site inputs differ from what you are committing:\n  ${[...new Set(loose)].join('\n  ')}\n`
    + 'The site is built from the working tree, so stage them or set them aside (a WIP commit, or copy them out), then commit again.');
  for (const step of STEPS) {
    if (!step.when()) continue;
    if (spawnSync(step.run[0], step.run.slice(1), { stdio: 'inherit' }).status !== 0) abort(`${step.name} failed, so the commit was stopped.`);
  }
}

const command = { '--install': install, '--uninstall': uninstall }[process.argv[2]] || (process.argv[2] ? () => abort(`unknown option ${process.argv[2]}`) : run);
command();
