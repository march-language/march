#!/usr/bin/env node
// check-doc-try-it.js — every "Try it" example on the generated stdlib pages runs.
//
// march_doc (`forge doc --stdlib --try-it`, scripts/gen-stdlib-docs.sh) marks the
// runnable examples on docs/docs/stdlib/<Module>.html with data-try (the code) and
// data-try-kind (transcript | program); the page's button feeds them to the
// in-browser REPL. This replays each page's examples the same way, through
// scripts/browser-repl-node.js (on-demand module loading included), in one
// session per page, and fails when:
//   * an example errors, unless it is a documented failure listed in
//     scripts/browser-repl-doc-sweep.js EXPECTED_FAILURES (e.g. a panic the docs show);
//   * a module that cannot run in a browser (march_stdlib_index.js "unavailable")
//     has any "Try it" example;
//   * no page has any example at all (the generator stopped marking them).
//
// Usage: node scripts/check-doc-try-it.js [PAGES_DIR] [ASSETS_DIR]
//        defaults: docs/docs/stdlib docs/assets
'use strict';
const fs = require('fs');
const path = require('path');
const { loadRepl } = require('./browser-repl-node');
const { EXPECTED_FAILURES } = require('./browser-repl-doc-sweep');

const root = path.join(__dirname, '..');
const pages = process.argv[2] || path.join(root, 'docs', 'docs', 'stdlib');
const assets = process.argv[3] || path.join(root, 'docs', 'assets');

// Documented failures, keyed by expression (a page does not know its source file).
const expected = new Map();
for (const [key, err] of Object.entries(EXPECTED_FAILURES)) {
  expected.set(key.slice(key.indexOf(': ') + 2), err);
}

const unescape = s => s.replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

const indexSrc = fs.readFileSync(path.join(assets, 'march_stdlib_index.js'), 'utf8');
const index = JSON.parse(indexSrc.slice(indexSrc.indexOf('=') + 1).trim().replace(/;$/, ''));

const repl = loadRepl(assets);
const problems = [];
let examples = 0, inputs = 0, pagesWith = 0;
for (const file of fs.readdirSync(pages).filter(f => f.endsWith('.html')).sort()) {
  const mod = file.slice(0, -'.html'.length);
  const html = fs.readFileSync(path.join(pages, file), 'utf8');
  const blocks = [...html.matchAll(/<pre data-try="([^"]*)" data-try-kind="(transcript|program)">/g)];
  if (!blocks.length) continue;
  pagesWith++;
  const entry = index.modules[mod];
  if (entry && entry.unavailable) {
    problems.push(`${file}: ${mod} cannot run in a browser (${entry.unavailable}) but has ${blocks.length} "Try it" example(s)`);
    continue;
  }
  repl.reset();
  for (const [, payload, kind] of blocks) {
    examples++;
    const code = unescape(payload);
    const runs = kind === 'transcript' ? code.split('\n').filter(l => l.trim()) : [code];
    for (const input of runs) {
      inputs++;
      const r = repl.run(input);
      if (!r.error) continue;
      const want = expected.get(input.trim());
      if (want !== undefined && r.error.startsWith(want)) continue;
      problems.push(`${file}: ${JSON.stringify(input)}\n  error: ${r.error.split('\n')[0]}`);
    }
  }
}
if (!examples) problems.push(`no "Try it" examples found under ${pages} (was the docs generated with --try-it?)`);
if (problems.length) {
  console.error(problems.map(p => 'FAIL ' + p).join('\n'));
  console.error(`check-doc-try-it: ${problems.length} problem(s)`);
  process.exit(1);
}
console.log(`check-doc-try-it: ${examples} "Try it" examples (${inputs} inputs) on ${pagesWith} pages run in the browser REPL`);
