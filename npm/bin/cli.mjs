#!/usr/bin/env node
// detent installer: copies the Detent skill folder to every installed coding agent's skills directory.
// Zero dependencies, Node 18+. The agents, their folders and their checks follow Linejig's installer (npm/README.md).
import { cpSync, existsSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { delimiter, dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const NAME = 'detent', SITE = 'https://detent-gamma.vercel.app';
const SOURCE = join(dirname(fileURLToPath(import.meta.url)), '..', 'skill', NAME);
const HOME = homedir(), CWD = process.cwd();

// user: the user-level skills directory (relative to HOME); project: the project-level one (relative to the cwd).
// Several tools read the shared ~/.agents/skills and .agents/skills, so one copy there serves all of them.
// detect: config directories under HOME and commands on PATH that show the tool is installed.
const AGENTS = [
  { id: 'claude-code', aliases: ['claude'], name: 'Claude Code', user: '.claude/skills', project: '.claude/skills',
    detect: { dirs: ['.claude'], bins: ['claude'] },
    check: `run /skills in Claude Code and look for ${NAME}` },
  { id: 'codex', aliases: ['openai-codex'], name: 'OpenAI Codex', user: '.agents/skills', project: '.agents/skills',
    detect: { dirs: ['.codex'], bins: ['codex'] },
    check: `in Codex run /skills, or type $ and look for ${NAME} (restart Codex if it is missing)` },
  { id: 'cursor', name: 'Cursor', user: '.agents/skills', project: '.agents/skills',
    detect: { dirs: ['.cursor'], bins: ['cursor', 'cursor-agent'] },
    check: `restart Cursor, then open Customize > Skills, or type / in Agent chat and search ${NAME}` },
  { id: 'gemini', aliases: ['gemini-cli'], name: 'Gemini CLI', user: '.agents/skills', project: '.agents/skills',
    detect: { dirs: ['.gemini'], bins: ['gemini'] },
    check: `run \`gemini skills list\` (or /skills list in a session) and look for ${NAME}` },
  { id: 'copilot', aliases: ['github-copilot', 'vscode'], name: 'GitHub Copilot', user: '.copilot/skills',
    project: '.agents/skills', detect: { dirs: ['.copilot'], bins: ['copilot'], ext: ['github.copilot'] },
    check: `in a new Copilot chat (VS Code agent mode or Copilot CLI) type / and look for ${NAME}` },
  { id: 'windsurf', name: 'Windsurf', user: '.codeium/windsurf/skills', project: '.windsurf/skills',
    detect: { dirs: ['.codeium/windsurf'], bins: ['windsurf'] },
    check: `open Customize > Skills in Windsurf, or type /${NAME} in Cascade` },
  { id: 'devin', aliases: ['devin-desktop'], name: 'Devin (Desktop and CLI)', user: '.agents/skills', project: '.agents/skills',
    detect: { dirs: ['.config/devin', '.devin'], bins: ['devin'] },
    check: `open Customize > Skills, or type /${NAME}` },
  { id: 'opencode', name: 'OpenCode', user: '.agents/skills', project: '.agents/skills',
    detect: { dirs: ['.config/opencode'], bins: ['opencode'] },
    check: `ask OpenCode to "load @${NAME}" and look for the skill tool call` },
  { id: 'amp', name: 'Amp', user: '.agents/skills', project: '.agents/skills',
    detect: { dirs: ['.config/amp'], bins: ['amp'] },
    check: `run \`amp skills list\` and look for ${NAME}` },
  { id: 'goose', name: 'goose', user: '.agents/skills', project: '.agents/skills',
    detect: { dirs: ['.config/goose'], bins: ['goose'] },
    check: `run \`goose skills list\` and look for ${NAME}` },
  { id: 'agents-md', name: 'AGENTS.md (any tool that reads it)', user: null, project: '.agents/skills', block: 'AGENTS.md',
    detect: null,
    check: `open AGENTS.md: the ${NAME} block points the agent at .agents/skills/${NAME}/SKILL.md` },
];

const HELP = `${NAME}: tactile dials, knobs and switches, and the agent skill that adds them to a project.

Usage
  npx ${NAME} install       Install the skill for every coding agent found on this machine
  npx ${NAME} uninstall     Remove every copy this installer can find
  npx ${NAME} list          Show the agents, where each looks, and what is installed

Options
  --agent <id>   Only this agent (repeatable): ${AGENTS.map((a) => a.id).join(', ')}
  --all          Every agent, found or not
  --project      Use this project's folders (.claude/skills, .agents/skills, ...) instead of your home folder;
                 with --agent agents-md (or --all) it also adds a marked block to ./AGENTS.md
  --dry-run      Say what would change, and change nothing
  --force        Replace a folder of that name that is not this skill (updates never need it)
  --help         Show this help

The controls themselves: npm i ${NAME}, then import '${NAME}/encoder'. More: ${SITE}`;

// ---------- arguments ----------
function fail(msg) { console.error(`${NAME}: ${msg}\nRun "npx ${NAME} --help" for usage.`); process.exit(1); }
const argv = process.argv.slice(2), flags = new Set(), agentsAsked = [], commands = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--agent' || a === '-a') { if (!argv[i + 1] || argv[i + 1].startsWith('-')) fail('--agent needs an agent id'); agentsAsked.push(argv[++i]); }
  else if (a.startsWith('--agent=')) agentsAsked.push(a.slice(8));
  else if (a.startsWith('-')) flags.add(a);
  else commands.push(a);
}
const KNOWN = new Set(['--all', '--project', '--dry-run', '--force', '--help', '-h', '--list']);
if (flags.has('--list')) commands.unshift('list');
if (flags.has('--help') || flags.has('-h') || commands.length === 0) { console.log(HELP); process.exit(commands.length || flags.size ? 0 : 1); }
const unknown = [...flags].filter((f) => !KNOWN.has(f));
if (unknown.length) fail(`unknown option ${unknown.join(', ')}`);
if (commands.length > 1) fail(`expected one command, got ${commands.join(' ')}`);
const PROJECT = flags.has('--project'), DRY = flags.has('--dry-run'), FORCE = flags.has('--force');
const byId = (id) => AGENTS.find((a) => a.id === id || (a.aliases || []).includes(id));
for (const id of agentsAsked) if (!byId(id)) fail(`unknown agent "${id}". Known: ${AGENTS.map((a) => a.id).join(', ')}`);

// ---------- detection ----------
const onPath = (bin) => (process.env.PATH || '').split(delimiter).filter(Boolean).some((d) =>
  (process.platform === 'win32' ? ['', '.exe', '.cmd', '.bat'] : ['']).some((x) => existsSync(join(d, bin + x))));
function detected(a) {
  if (!a.detect) return null;
  for (const d of a.detect.dirs || []) if (existsSync(join(HOME, d))) return `~/${d}`;
  for (const b of a.detect.bins || []) if (onPath(b)) return `${b} on PATH`;
  for (const e of a.detect.ext || []) {
    const ext = join(HOME, '.vscode', 'extensions');
    if (existsSync(ext) && readdirSync(ext).some((f) => f.startsWith(e))) return 'its VS Code extension';
  }
  return null;
}
const tilde = (p) => (p === HOME || p.startsWith(HOME + sep) ? '~' + p.slice(HOME.length) : p);
const show = (p) => (PROJECT ? (relative(CWD, p) || '.') : tilde(p));
const base = (a) => (PROJECT ? (a.project && join(CWD, a.project)) : (a.user && join(HOME, a.user)));

function chooseAgents({ forRemoval = false } = {}) {
  if (agentsAsked.length) return [...new Set(agentsAsked.map((id) => byId(id)))];
  if (flags.has('--all') || forRemoval) return AGENTS;
  const found = AGENTS.filter((a) => detected(a));
  if (found.length) return found;
  console.log(`No coding agent found on this machine; installing for Claude Code.\n` +
    `Use --agent <id> or --all for others ("npx ${NAME} list" shows them).\n`);
  return [byId('claude-code')];
}

// ---------- the skill folder ----------
function tree(dir, at = '') {   // every file under dir, as { relativePath: contents }
  const out = {};
  for (const f of readdirSync(join(dir, at))) {
    const p = at ? `${at}/${f}` : f, full = join(dir, p);
    if (statSync(full).isDirectory()) Object.assign(out, tree(dir, p)); else out[p] = readFileSync(full);
  }
  return out;
}
function same(a, b) {
  const ta = tree(a), tb = tree(b), ka = Object.keys(ta).sort(), kb = Object.keys(tb).sort();
  return ka.length === kb.length && ka.every((k, i) => k === kb[i] && ta[k].equals(tb[k]));
}
// a skill folder is ours when its SKILL.md says name: detent
const ours = (dir) => { try { return new RegExp(`^name:\\s*${NAME}\\s*$`, 'm').test(readFileSync(join(dir, 'SKILL.md'), 'utf8')); } catch { return false; } };

// ---------- the AGENTS.md block: marked, merged, never touching the rest of the file ----------
const START = `<!-- ${NAME}:start (added by npx ${NAME}; replaced on reinstall, removed by "npx ${NAME} uninstall --project --agent agents-md") -->`;
const END = `<!-- ${NAME}:end -->`;
const BLOCK = `${START}
## Tactile controls

For dials, knobs, switches and other controls that should feel like hardware, read
\`.agents/skills/${NAME}/SKILL.md\` first and follow it, opening its \`references/\` files as it says.
${END}`;
const blockRe = new RegExp(`<!-- ${NAME}:start[^\\n]*-->[\\s\\S]*?<!-- ${NAME}:end -->`);
function readBlockFile(file) {
  if (!existsSync(file)) return { text: null, eol: '\n' };
  const raw = readFileSync(file, 'utf8'), eol = raw.includes('\r\n') ? '\r\n' : '\n';
  const starts = raw.split(`<!-- ${NAME}:start`).length - 1, ends = raw.split(END).length - 1;
  if (starts !== ends || starts > 1) throw new Error(`${show(file)} has a broken or repeated ${NAME} block; fix it by hand, then run again`);
  return { text: raw.replace(/\r\n/g, '\n'), eol };
}
function writeBlock(file) {
  const { text, eol } = readBlockFile(file);
  let next, how;
  if (text === null) { next = BLOCK + '\n'; how = 'created'; }
  else if (blockRe.test(text)) { next = text.replace(blockRe, BLOCK); how = 'updated'; }
  else { next = (text.trim() ? text.replace(/\s*$/, '\n\n') : '') + BLOCK + '\n'; how = 'appended'; }
  if (text === next) return 'unchanged';
  if (!DRY) writeFileSync(file, next.replace(/\n/g, eol));
  return how;
}
function removeBlock(file) {
  const { text, eol } = readBlockFile(file);
  if (text === null || !blockRe.test(text)) return 'absent';
  const next = text.replace(new RegExp(`\\n*${blockRe.source}\\n?`), '\n').replace(/^\n+/, '');
  const empty = !next.trim();
  if (!DRY) { if (empty) rmSync(file); else writeFileSync(file, next.replace(/\s*$/, '\n').replace(/\n/g, eol)); }
  return empty ? 'removed (the file held nothing else, so it was deleted)' : 'removed';
}

// ---------- commands ----------
let problems = 0;
const verb = (done, would) => (DRY ? would : done);

function groups(list) {   // agents that share one directory get one copy
  const out = new Map();
  for (const a of list) {
    const b = base(a);
    if (!b) { if (agentsAsked.length) { problems++; console.log(`${a.name}: there is only a project location; add --project.`); } continue; }
    if (!out.has(b)) out.set(b, []);
    out.get(b).push(a);
  }
  return out;
}

function install() {
  if (!existsSync(join(SOURCE, 'SKILL.md'))) fail(`the packaged skill is missing at ${SOURCE}`);
  const list = chooseAgents();
  if (PROJECT) for (const a of list) if (a.block) readBlockFile(join(CWD, a.block));   // refuse a broken block before writing anything
  if (DRY) console.log('Dry run: nothing is written.\n');
  for (const [dir, agents] of groups(list)) {
    const target = join(dir, NAME);
    let what;
    if (!existsSync(target)) what = verb('installed', 'would install');
    else if (same(SOURCE, target)) what = 'already up to date';
    else if (ours(target) || FORCE) what = verb(FORCE && !ours(target) ? 'replaced' : 'updated', FORCE && !ours(target) ? 'would replace' : 'would update');
    else {
      problems++;
      what = `NOT changed: a folder there that is not ${NAME}. Run again with --force to replace it`;
    }
    if (!DRY && /^(installed|updated|replaced)/.test(what)) {
      mkdirSync(dir, { recursive: true });
      rmSync(target, { recursive: true, force: true });
      cpSync(SOURCE, target, { recursive: true });
    }
    console.log(`${show(target)}: ${what}`);
    for (const a of agents) {
      if (a.block) { const r = writeBlock(join(CWD, a.block)); console.log(`  ${a.block}: block ${r === 'unchanged' ? 'already up to date' : verb(r, 'would be ' + r)}`); }
      console.log(`  ${a.name}, check it worked: ${a.check}`);
    }
  }
  console.log(`\nThen ask, for example: add a ${NAME} volume knob to the player, in the Braun look`);
}

function uninstall() {
  const list = chooseAgents({ forRemoval: true });
  if (DRY) console.log('Dry run: nothing is removed.\n');
  let any = false;
  for (const [dir, agents] of groups(list)) {
    for (const a of agents) {
      if (!a.block || !PROJECT) continue;
      const r = removeBlock(join(CWD, a.block));
      if (r !== 'absent') { any = true; console.log(`${a.block}: block ${DRY ? 'would be ' : ''}${r}`); }
    }
    const target = join(dir, NAME);
    if (!existsSync(target)) continue;
    any = true;
    if (!ours(target) && !FORCE) { problems++; console.log(`${show(target)}: NOT removed: it is not the ${NAME} skill. Use --force to remove it anyway`); continue; }
    if (!DRY) rmSync(target, { recursive: true, force: true });
    console.log(`${show(target)}: ${verb('removed', 'would remove')} (read by ${agents.map((a) => a.name).join(', ')})`);
  }
  if (!any) console.log(`Nothing to remove: no ${NAME} skill in any ${PROJECT ? 'project' : 'user-level'} location${agentsAsked.length ? ' for that agent' : ''}.`);
}

function list() {
  console.log(`${PROJECT ? 'Project locations, in ' + CWD : 'User-level locations (~ is ' + HOME + ')'}:\n`);
  const rows = AGENTS.map((a) => {
    const b = base(a), found = detected(a), where = b ? show(join(b, NAME)) : '(project only: add --project)';
    const here = b && existsSync(join(b, NAME)) ? (same(SOURCE, join(b, NAME)) ? 'installed' : 'installed, a different version') : '';
    return [a.id, a.detect ? (found ? `found (${found})` : 'not found') : 'on request', where, here];
  });
  const w = [0, 1, 2].map((i) => Math.max(...rows.map((r) => r[i].length)));
  for (const r of rows) console.log(`  ${r[0].padEnd(w[0])}  ${r[1].padEnd(w[1])}  ${r[2].padEnd(w[2])}  ${r[3]}`.trimEnd());
  console.log(`\n"npx ${NAME} install" installs for every agent marked found (Claude Code if none is).`);
}

try {
  const cmd = commands[0];
  if (cmd === 'install') install();
  else if (cmd === 'uninstall') uninstall();
  else if (cmd === 'list') list();
  else fail(`unknown command "${cmd}"`);
} catch (err) {
  fail(err.code === 'EACCES' || err.code === 'EPERM' ? `permission denied: ${err.path || err.message}` : err.message);
}
process.exit(problems ? 1 : 0);
