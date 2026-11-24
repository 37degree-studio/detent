# detent

Dials, knobs and switches that behave like hardware. They hold against each detent, click over and stop dead at the
ends, with synthesized sound and haptics built in. Nine controls, five or six looks each, light and dark. They are web
components with no dependencies, plus a SwiftUI file for each, and an agent skill that teaches your coding agent to
add them.

Created by 37degree, designed by Puru Sharma. MIT licensed. See them at https://detent-gamma.vercel.app.

## Use the controls

```sh
npm i detent
```

```js
import 'detent/encoder';
```

```html
<detent-encoder value="40" aria-label="Volume"></detent-encoder>
```

| Import | What it gives you |
|---|---|
| `detent` | Every control, each in its default look |
| `detent/<control>` | One control in its default look |
| `detent/<control>/looks/<look>` | One control in one look (bring only the looks you use) |
| `detent/<control>/element` | The control with no look, for a look you load later |
| `detent/feel` | The shared sound and haptics engine: `Feel.state.sound`, `Feel.state.haptics` |
| `detent/swift/<File>.swift` | The SwiftUI file for a control |

The controls are `encoder`, `pot`, `bezel`, `touch`, `switch`, `selector`, `slot`, `scrubber` and `clock`. Each fires
`input` while it moves and `change` when it settles, and has a `.value`. Set `look="…"` to pick a look, `tone="light"`
or `tone="dark"` to force a tone, and `--dial-accent` to colour the indicator. The modules use `window` when they load,
so import them in the browser only (in an effect, `onMount` or a client-only plugin).

With no build step, load a module from a CDN:

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/detent/encoder/index.js"></script>
```

## Install the agent skill

```sh
npx detent install
```

The installer finds the coding agents on your machine and copies the `detent` skill to each one's skills folder.
Tools that share `~/.agents/skills` get one copy there. If it finds none, it installs for Claude Code. It needs Node 18
or later and has no dependencies.

| Command | What it does |
|---|---|
| `npx detent install` | Install for every agent it finds |
| `npx detent install --agent cursor --agent codex` | Only these agents (`--agent` repeats) |
| `npx detent install --all` | Every agent it knows, found or not |
| `npx detent install --project` | This project only: `.claude/skills`, `.agents/skills` or `.windsurf/skills` |
| `npx detent install --project --agent agents-md` | Also add a marked block to `./AGENTS.md` (merged, never overwritten) |
| `npx detent install --dry-run` | Say what would change, change nothing |
| `npx detent install --force` | Replace a folder of that name that is not this skill |
| `npx detent list` | Show each agent, whether it was found, where it looks, what is installed |
| `npx detent uninstall` | Remove every copy it can find (add `--project` for project copies and the AGENTS.md block) |

Running `install` again is safe: an identical copy is left alone, an older copy is updated, and the AGENTS.md block is
replaced in place.

### Where it goes

| Agent | `--agent` | User-level folder | Project folder |
|---|---|---|---|
| Claude Code | `claude-code` | `~/.claude/skills/` | `.claude/skills/` |
| OpenAI Codex | `codex` | `~/.agents/skills/` | `.agents/skills/` |
| Cursor | `cursor` | `~/.agents/skills/` | `.agents/skills/` |
| Gemini CLI | `gemini` | `~/.agents/skills/` | `.agents/skills/` |
| GitHub Copilot | `copilot` | `~/.copilot/skills/` | `.agents/skills/` |
| Windsurf | `windsurf` | `~/.codeium/windsurf/skills/` | `.windsurf/skills/` |
| Devin Desktop and CLI | `devin` | `~/.agents/skills/` | `.agents/skills/` |
| OpenCode | `opencode` | `~/.agents/skills/` | `.agents/skills/` |
| Amp | `amp` | `~/.agents/skills/` | `.agents/skills/` |
| goose | `goose` | `~/.agents/skills/` | `.agents/skills/` |
| Any tool that reads AGENTS.md | `agents-md` | (project only) | `.agents/skills/` and a block in `AGENTS.md` |

Then ask your agent in plain words, for example: add a detent volume knob to the player, in the Braun look.

## How this package is made

Everything except `bin/`, `scripts/`, `templates/`, `package.json` and this README is generated from
`src/catalog.html`, the catalogue the site is built from, by `scripts/build.mjs`. It runs on every `npm pack` and
`npm publish`, so the package always matches the site.

## Licence

MIT. Detent is created by 37degree (https://37degr.ee), designed by Puru Sharma.
