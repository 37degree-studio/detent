# Detent SEO

Written 2026-11-25, adapted from Linejig's SEO plan (`keyline-3d/website/SEO.md`). It sets out the plan and the rules for
search. Everything that lists controls is generated from `PARTS` in `src/catalog.html`. A new control needs one entry in
`tools/seo/site.json`, and nothing else in SEO changes by hand.

## Positioning

Not winnable: broad terms such as "UI components" or "toggle switch". Big libraries and tutorials own them.
Winnable, in order:

1. **One page per control**, for specific searches: "rotary knob web component", "SwiftUI knob", "toggle switch with
   haptics", "time picker dial". A live control with sound and haptics shows what a screenshot can't.
2. **The SwiftUI angle**: "SwiftUI rotary knob", "SwiftUI detent dial". Few ready-made results exist for these.
3. **Later, guides**, if they are wanted: "haptics on the web", "how a detent feels". Linejig's guides renderer
   (`website/seo/guides-lib.mjs`) can be ported then.

This is judgement, not measurement: there is no search-volume data yet. Look again once Search Console has a month of data.

## URLs (permanent)

| What | URL | File |
|---|---|---|
| Home | `/` | `site/index.html` |
| A control | `/<slug>`, e.g. `/encoder` | `site/<slug>.html`, served by `cleanUrls` |
| A hub | `/<slug>`, e.g. `/dials`, `/switches` | `site/<slug>.html`, from `hubs` in `site.json` |
| Not found | (any other path) | `site/404.html`, `noindex` |
| Share cards | `/og/<slug>.png`, `/og/home.png` | drawn by `tools/seo/og.mjs` |
| Sitemaps | `/sitemap.xml`, `/sitemap-images.xml` (each page's share card) | built by `tools/build.mjs` |
| Icons | `/apple-touch-icon.png` (180×180), `/og/favicon-32.png` | drawn by `tools/seo/og.mjs` |

Control slugs, hub slugs and the reserved names share one namespace: the build stops on a collision. A slug never
changes once published. Rename the control and its title instead. If a URL must move, add a permanent
redirect in `vercel.json`. The old `#detent-<name>` links still work: on the deployed site they move to the control's page.

## Hubs

A hub is a page for one kind of control, for searches such as "rotary knob web component" or "toggle switch with
haptics". Each is one entry in `hubs` in `site.json`: `slug`, `name` (its `<h1>`, footer link and card headline),
`title`, `description`, `intro` (the paragraph under the `<h1>`), `match.groups` (it lists the controls whose `group` is
one of these) and `card` (`part` and optional `attrs` for the control on its share card, and `line`, its short line).
A hub that matches fewer than 3 controls is not written, and the build prints a note. The `Time` group has 2, so it
has no hub. A control's breadcrumb links its group to the first hub that lists it, and every page's footer links every
hub.

## Rules for every page

1. The `<h1>` and the first paragraph are **in the HTML**. JavaScript may redraw them, but must not be the only thing
   that writes them. The home lives as static HTML in `src/template.html`. Each control's page gets its static copy from
   `tools/build.mjs`. Keep that copy word for word what `renderDetail` draws.
2. Links between pages are real `<a href>` elements carrying `data-tag`. Without a server (a file or a preview), the
   app turns them into `#tag` links.
3. Each page has a unique `<title>` of 60 characters or fewer, with the subject first and ` · Detent` last. It also has
   a `<meta name="description">` of 160 characters or fewer, and a canonical link to its clean URL on the origin in
   `site.json`.
4. Each page has Open Graph and Twitter tags and a 1200×630 card.
5. No counts typed by hand. Counts come from `PARTS` at build time, or stay out of the page.
6. Be honest. Don't invent numbers, users or ratings, in copy or in structured data. Don't name other projects or brands
   in titles or descriptions.

`node tools/build.mjs --check` enforces 1, 3 and 4. It also checks that JSON-LD parses, that the FAQ JSON-LD matches the
visible questions word for word, that links point to real pages, that every image in `sitemap-images.xml` and every
linked icon has its file, and that `site/` is up to date.

## Files

- `tools/seo/site.json`: the name, origin, repo, studio, home copy, each control's slug, title and description, and the hubs.
  Change the domain here, then run `npm run og -- --force && npm run build`.
- `tools/build.mjs`: builds every file in `site/` except the cards and `favicon.svg`: the home, one page per control,
  one page per hub, `404.html`, `sitemap.xml`, `sitemap-images.xml`, `robots.txt` and `llms.txt`. Once the icon PNGs
  exist, it links them in place of the SVG touch icon in `src/template.html`. It removes generated files that no page makes any more.
  `tools/build.py` is a shim that runs it.
- `tools/seo/og.mjs`: draws the share cards with the local Chrome, using the real controls. It redraws only the cards
  whose inputs changed (`tools/seo/og-hashes.json`). Use `--force` to redraw them all, or `--only home,clock` for some.
  It also draws the Detent mark as `site/apple-touch-icon.png` (full-bleed, iOS rounds it) and `site/og/favicon-32.png`.

Structured data: the home has `WebSite`, `SoftwareSourceCode` and `FAQPage`. Each control's page has
`SoftwareSourceCode` and `BreadcrumbList` (Components, its hub if it has one, the control). Each hub has
`CollectionPage` with an `ItemList` of its controls, and `BreadcrumbList`.
- `tools/seo/hook.mjs`: the pre-commit hook. `--install` and `--uninstall` set it up. Run with no option, it is what
  the hook runs.

## Workflow

Install the pre-commit hook once per clone. Every worktree of the clone shares it.

```bash
npm run hooks
```

A commit that touches `src/`, `tools/build.mjs` or `tools/seo/` then redraws the changed share cards, rebuilds `site/`
and runs the check. It adds `site/` and `tools/seo/og-hashes.json` to the same commit, so what Vercel deploys always
matches the source. A commit that touches none of them runs nothing.

The hook builds from the working tree. So it stops the commit when one of those inputs has unstaged changes or
untracked files: stage them or set them aside, then commit again. It never stashes, because the stash is shared with
other worktrees. If the build or the check fails, the commit stops and shows the error. Without Chrome the cards are
skipped with a warning; set `CHROME=/path/to/chrome`. An existing `pre-commit` is kept as `pre-commit.local` and runs
first. `node tools/seo/hook.mjs --uninstall` puts it back.

Without the hook, run these after any change to `src/`, to `tools/seo/site.json`, or to a control's look:

```bash
npm run og
```

```bash
npm run build
```

```bash
npm run check
```

`npm test` runs the check too.

The sitemap has no `lastmod`. A date taken from git is always one commit behind for a build made before that commit,
and Google uses `lastmod` only when it is consistently right.

## Still to do (off the code)

- **Domain**: `site.json` says `https://detent.37degr.ee`. Confirm it, add it to the Vercel project, and redraw and
  rebuild if it changes. The `*.vercel.app` copy stays `noindex`.
- **Search Console**: verify the domain and submit `/sitemap.xml` and `/sitemap-images.xml`.
- **Off the site**: point the GitHub repo's homepage at the domain and add topics such as `web-components`, `swiftui`,
  `knob`, `dial`, `haptics`. Then list Detent where people find components.
