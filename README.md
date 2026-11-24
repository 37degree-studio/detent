# Detent

Dials, knobs and switches that behave like hardware: they hold against each detent, click over, and stop dead at the ends. Nine controls, five looks each, light and dark, with sound and haptics built in. Web components with no dependencies, plus a SwiftUI file for each.

Created by [37degree](https://37degr.ee/?utm_source=detent&utm_medium=readme), designed by Puru Sharma. MIT licensed.

## This folder

| Path | What it is |
|---|---|
| `src/catalog.html` | The approved controls: every control, look and SwiftUI file, as `<script id="src-…">` blocks, plus the `PARTS` catalogue. The source of truth. |
| `src/template.html` | The site's page: home, component pages, bottom bar, email gate. |
| `tools/build.mjs` | Puts the two together into `site/`: the home, one page per control (`/encoder`, `/clock`, …), the 404, sitemap, robots and llms.txt. |
| `tools/seo/` | Search: titles, descriptions and URLs (`site.json`), the share cards (`og.mjs`) and the rules (`SEO.md`). |
| `site/` | What gets deployed. |
| `api/subscribe.js` | The email gate's endpoint, a copy of Linejig's, writing to the same Blob store and Resend segment. Every record is tagged `source: "detent"`. |
| `swift/` | The SwiftUI files on their own. |

## Work on it

Run `npm run hooks` once. A commit that changes `src/` or `tools/seo/` then rebuilds `site/` and carries it along, so what Vercel deploys always matches the source.

```bash
npm run build
```

After a change to a control or its look, redraw the share cards first with `npm run og`. `npm run check` reports any
page that breaks the search rules in `tools/seo/SEO.md`.

```bash
npm run dev
```

The dev server runs on http://localhost:4341. Without a `BLOB_READ_WRITE_TOKEN` it saves signups to `.signups/` here instead of the real list, so the gate can be tried safely.

```bash
npm test
```

## Deploy (Vercel)

1. Create a Vercel project from this folder. Output directory is `site`, there's no build command (run `npm run build` before deploying). `vercel.json` turns on clean URLs, so `site/encoder.html` is served at `/encoder`.
2. Copy these environment variables from the Linejig project so signups land in the same list:
   - `BLOB_READ_WRITE_TOKEN` (the `keyline-signups` store)
   - `RESEND_API_KEY` and `RESEND_SEGMENT_ID`
   - optional: `NOTIFY_TO`, `NOTIFY_FROM` (a notice per signup), `THANKS_FROM`, `AUTH_REPLY_TO` (the thank-you email, and where replies go)
3. Add the domain, then rebuild with it so canonical links and the sitemap use it: `DETENT_URL=https://your.domain npm run build`, and deploy again.

The `*.vercel.app` address sends `noindex`, so search engines only index the real domain.

The endpoint only accepts requests from its own domain, so it has to be served from the same domain as the site.

## The email gate

Code and Copy on the site appear only after someone leaves an email. One email unlocks every control in that browser. It's a soft gate: the controls run in the page, and the public repo has the same code, as with Linejig.
