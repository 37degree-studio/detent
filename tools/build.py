#!/usr/bin/env python3
"""Build the site into site/: the page template (src/template.html) plus the approved controls, their looks and the
SwiftUI sources, taken verbatim from the catalogue (src/catalog.html).

It writes site/index.html (the home page) and one page per control (site/encoder.html and so on, served as /encoder),
each with its own title, description, canonical link, share tags and structured data, plus sitemap.xml and robots.txt.

The public address comes from DETENT_URL (default below). Run from anywhere: python3 tools/build.py"""
import html, json, os, pathlib, re

SITE = os.environ.get('DETENT_URL', 'https://detent-gamma.vercel.app').rstrip('/')
ORG = {'@type': 'Organization', 'name': '37degree', 'url': 'https://37degr.ee'}
AUTHOR = {'@type': 'Person', 'name': 'Puru Sharma'}
REPO = 'https://github.com/37degree-studio/detent'
HOME_TITLE = 'Detent: tactile dials, knobs and switches for the web and SwiftUI'
HOME_DESC = ('Nine dials, knobs and switches that behave like hardware, with sound and haptics. Web components and '
             'SwiftUI, five looks each, light and dark. Free and MIT. Created by 37degree, designed by Puru Sharma.')

root = pathlib.Path(__file__).resolve().parent.parent
site = (root / 'src/catalog.html').read_text()
blocks = re.findall(r'<script id="src-[a-z0-9-]+">.*?</script>', site, re.S)
swift = re.findall(r'<script type="text/plain" id="swift-[a-z0-9-]+">.*?</script>', site, re.S)
a = site.index('  const PARTS = [')
b = site.index('\n  ];', a) + len('\n  ];')
parts_src = site[a:b]

# name, tag and one-line note of each control, for titles and descriptions
parts = []
for m in re.finditer(r'tag: *"(detent-[a-z]+)"(.*?)(?=tag: *"detent-|\Z)', parts_src, re.S):
    body = m.group(2)
    get = lambda k: (re.search(k + r''': *(["'])((?:(?!\1)[^\\]|\\.)*)\1''', body) or [None, None, ''])[2]
    parts.append({'tag': m.group(1), 'slug': m.group(1).removeprefix('detent-'), 'name': get('name'),
                  'note': get('note'), 'kind': get('kind')})
assert len(parts) == 9, f'expected 9 controls, found {len(parts)}'

template = (root / 'src/template.html').read_text()
assert '<!--BLOCKS-->' in template and '  //PARTS' in template and '<!--SEO-->' in template, 'template is missing placeholders'
body = template.replace('<!--BLOCKS-->', '<!-- The approved Detent controls, verbatim. -->\n' + '\n\n'.join(blocks)
                        + '\n\n<!-- SwiftUI sources -->\n' + '\n'.join(swift)).replace('  //PARTS', parts_src)
# the deployed site posts the email gate to its own endpoint; the claude.ai preview has no server, so it has no meta
body = body.replace('<title>Detent</title>', '<title>Detent</title>\n<meta name="detent-signup" content="/api/subscribe">', 1)


def head(title, desc, url, route=None, extra_ld=None):
    e = lambda s: html.escape(s, quote=True)
    ld = [{'@context': 'https://schema.org', '@type': 'SoftwareSourceCode', 'name': 'Detent', 'description': HOME_DESC,
           'url': SITE + '/', 'codeRepository': REPO, 'license': 'https://opensource.org/licenses/MIT',
           'programmingLanguage': ['JavaScript', 'Swift'], 'creator': ORG, 'author': AUTHOR, 'publisher': ORG}]
    if extra_ld: ld.append(extra_ld)
    tags = [
        f'<meta name="description" content="{e(desc)}">',
        f'<link rel="canonical" href="{e(url)}">',
        '<meta name="author" content="Puru Sharma">',
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Detent">',
        f'<meta property="og:title" content="{e(title)}">',
        f'<meta property="og:description" content="{e(desc)}">',
        f'<meta property="og:url" content="{e(url)}">',
        '<meta name="twitter:card" content="summary">',
        f'<meta name="twitter:title" content="{e(title)}">',
        f'<meta name="twitter:description" content="{e(desc)}">',
        *([f'<meta name="detent-route" content="#{route}">'] if route else []),
        '<script type="application/ld+json">' + json.dumps(ld if len(ld) > 1 else ld[0]).replace('</', '<\\/') + '</script>',
    ]
    return '\n'.join(tags)


def page(title, desc, url, route=None, extra_ld=None, summary=''):
    p = body.replace('<title>Detent</title>', f'<title>{html.escape(title)}</title>', 1)
    p = p.replace('<!--SEO-->', head(title, desc, url, route, extra_ld), 1)
    # what a crawler or a no-script reader sees before the page draws itself
    if summary:
        p = p.replace('<main id="home"></main>', f'<main id="home"><noscript>{summary}</noscript></main>', 1)
    return '<!doctype html>\n<html lang="en">\n' + p + '\n</html>\n'


out = root / 'site'
links = ''.join(f'<li><a href="/{x["slug"]}">{html.escape(x["name"])}</a>: {html.escape(x["note"])}</li>' for x in parts)
(out / 'index.html').write_text(page(HOME_TITLE, HOME_DESC, SITE + '/', summary=(
    f'<h1>Detent</h1><p>{html.escape(HOME_DESC)}</p><ul>{links}</ul><p><a href="{REPO}">Source on GitHub</a></p>')))

for x in parts:
    title = f'{x["name"]}: a tactile {x["kind"].lower() or "control"} for the web and SwiftUI · Detent'
    desc = f'{x["note"]} With sound and haptics, five looks, light and dark. Web component and SwiftUI, MIT.'
    url = f'{SITE}/{x["slug"]}'
    ld = {'@context': 'https://schema.org', '@type': 'SoftwareSourceCode', 'name': f'{x["name"]} · Detent',
          'description': x['note'], 'url': url, 'codeRepository': REPO, 'license': 'https://opensource.org/licenses/MIT',
          'isPartOf': {'@type': 'SoftwareSourceCode', 'name': 'Detent', 'url': SITE + '/'}, 'creator': ORG, 'author': AUTHOR}
    (out / f'{x["slug"]}.html').write_text(page(title, desc, url, route=x['tag'], extra_ld=ld, summary=(
        f'<h1>{html.escape(x["name"])}</h1><p>{html.escape(x["note"])}</p><p><a href="/">All Detent controls</a></p>')))

# 404: a small page of its own, in the same colours and type, with Linejig's signpost
(out / '404.html').write_text("""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Page not found · Detent</title>
<meta name="robots" content="noindex">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Funnel+Display:wght@300;400&family=Funnel+Sans:wght@400;500&display=swap">
<script>try{const v=localStorage.getItem('detent-theme');if(v==='light'||v==='dark')document.documentElement.dataset.theme=v}catch{}</script>
<style>
:root { --bg:#f6f6f5; --ink:#1d1d1f; --muted:#75757a; --faint:#a6a6aa; color-scheme:light }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#0b0b0c; --ink:#ededee; --muted:#8b8b90; --faint:#55555a; color-scheme:dark } }
:root[data-theme="dark"] { --bg:#0b0b0c; --ink:#ededee; --muted:#8b8b90; --faint:#55555a; color-scheme:dark }
body { margin:0; min-height:100vh; display:grid; place-items:center; background:var(--bg); color:var(--ink); font:400 16px/1.55 "Funnel Sans", system-ui, sans-serif; padding:32px 16px; box-sizing:border-box }
main { display:grid; gap:18px; justify-items:center; text-align:center; max-width:440px }
h1 { margin:0; font:300 clamp(34px,6vw,52px)/1.05 "Funnel Display", system-ui, sans-serif; letter-spacing:-.04em }
p { margin:0; color:var(--muted) }
a.btn { display:inline-flex; align-items:center; height:40px; padding:0 18px; border-radius:999px; background:var(--ink); color:var(--bg); text-decoration:none; font-weight:500; font-size:14px }
figure { margin:0; display:grid; gap:8px; justify-items:center; width:100% }
iframe { border:0; width:100%; max-width:400px; aspect-ratio:5/4; height:auto; opacity:0; transition:opacity .3s }
iframe.drawn { opacity:1 }
figcaption { font-size:12px; color:var(--faint) } figcaption a { color:var(--muted) }
</style>
</head>
<body>
<main>
  <figure><iframe id="fig" title="A signpost, live illustration" width="400" height="320"></iframe>
    <figcaption>Illustration from the <a href="https://linejig.com/library?utm_source=detent&amp;utm_medium=credit&amp;utm_campaign=404">Linejig library</a></figcaption></figure>
  <h1>This page doesn't exist.</h1>
  <p>The address may be mistyped, or the page has moved. Every control is on the home page.</p>
  <a class="btn" href="/">Back to Detent</a>
</main>
<script>
  const f = document.getElementById('fig');
  const theme = document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  f.src = 'https://linejig.com/404-signpost/index.html?embed=1&style=brand&brand=f2641e&plate=f6f6f5,0b0b0c&intro=draw&dpr=1&theme=' + theme;
  addEventListener('message', e => { if (e.origin === 'https://linejig.com' && e.data?.type === 'drawn') f.classList.add('drawn'); });
  setTimeout(() => f.classList.add('drawn'), 3000);
</script>
</body>
</html>
""")
(out / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + ''.join(f'  <url><loc>{u}</loc></url>\n' for u in [SITE + '/'] + [f'{SITE}/{x["slug"]}' for x in parts]) + '</urlset>\n')
(out / 'robots.txt').write_text(f'User-agent: *\nAllow: /\nDisallow: /api/\n\nSitemap: {SITE}/sitemap.xml\n')
print(f'site/: home + {len(parts)} control pages, 404, sitemap, robots · {len(blocks)} control scripts, {len(swift)} SwiftUI files · {SITE}')
