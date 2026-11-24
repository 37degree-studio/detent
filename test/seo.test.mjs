import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));

test('site/ is built and every page keeps the SEO rules (tools/seo/SEO.md)', () => {
  // Throws with the check's own errors if a page breaks a rule or site/ is out of date.
  const out = execFileSync('node', ['tools/build.mjs', '--check'], { cwd: root, encoding: 'utf8', stdio: 'pipe' });
  assert.match(out, /indexable pages pass/);
});
