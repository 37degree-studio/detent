#!/usr/bin/env python3
"""The build moved to tools/build.mjs (it writes the home, a page per control, the sitemap and the rest; tools/seo/SEO.md).
This stays so `python3 tools/build.py` keeps working."""
import subprocess, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
sys.exit(subprocess.call(['node', str(root / 'tools/build.mjs'), *sys.argv[1:]]))
