#!/usr/bin/env python3
"""Build site/index.html: the page template (src/template.html) plus the approved controls, their looks and the
SwiftUI sources, taken verbatim from the catalogue (src/catalog.html). Run from the project root: python3 tools/build.py"""
import re, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
site = (root / 'src/catalog.html').read_text()
blocks = re.findall(r'<script id="src-[a-z0-9-]+">.*?</script>', site, re.S)
swift = re.findall(r'<script type="text/plain" id="swift-[a-z0-9-]+">.*?</script>', site, re.S)
a = site.index('  const PARTS = [')
b = site.index('\n  ];', a) + len('\n  ];')

page = (root / 'src/template.html').read_text()
assert '<!--BLOCKS-->' in page and '  //PARTS' in page, 'template is missing its placeholders'
page = page.replace('<!--BLOCKS-->', '<!-- The approved Detent controls, verbatim. -->\n' + '\n\n'.join(blocks)
                    + '\n\n<!-- SwiftUI sources -->\n' + '\n'.join(swift))
page = page.replace('  //PARTS', site[a:b])
# the deployed site posts the email gate to its own endpoint; the claude.ai preview has no server, so it has no meta
page = page.replace('<title>Detent</title>', '<title>Detent</title>\n<meta name="detent-signup" content="/api/subscribe">', 1)
if not page.lstrip().lower().startswith('<!doctype'):
    page = '<!doctype html>\n<html lang="en">\n' + page + '\n</html>\n'
(root / 'site/index.html').write_text(page)
print(f'site/index.html: {len(blocks)} control scripts, {len(swift)} SwiftUI files, {len(page) // 1024} KB')
