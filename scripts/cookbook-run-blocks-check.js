#!/usr/bin/env node
// cookbook-run-blocks-check.js — every cookbook "run" button must run without error.
//
// Every page with `layout: cookbook` (docs/cookbook/*.md, docs/coming-from-*.md) gets a
// "run" button on each ```march block (docs/assets/cookbook.js), which sends the block,
// trimmed, to the sidebar REPL. This feeds every such block to the browser REPL the
// way the button does (scripts/browser-repl-node.js: on-demand stdlib loading; a pasted
// `march>` transcript split into its prompt lines, as MarchRepl.splitTranscript does),
// each block in a FRESH session (marchResetSession first): a reader clicks blocks in
// any order, so a block must not need one above it.
//
// A block that cannot run in a browser (it reads files, opens a socket, is a fragment
// of a larger program) is marked display-only with an HTML comment on the line before
// its fence:
//
//     <!-- repl:skip -->
//     ```march
//
// (other comment lines, such as `<!-- scroll:skip -->`, may sit between the two).
// cookbook.js gives such a block a copy button but no run button. This script skips
// it, and fails on every other block whose evaluation returns an error.
//
// Usage: node scripts/cookbook-run-blocks-check.js [ASSETS_DIR]   (default: docs/assets)
//        node scripts/cookbook-run-blocks-check.js --verbose [ASSETS_DIR]
//          also prints each block's output.
'use strict';
const fs = require('fs');
const path = require('path');
const { loadRepl } = require('./browser-repl-node');

const args = process.argv.slice(2);
const verbose = args[0] === '--verbose';
if (verbose) args.shift();
const docs = path.join(__dirname, '..', 'docs');
const assets = args[0] || path.join(docs, 'assets');

// A block still running after this long counts as failing (it loops, or waits on input).
const TIMEOUT_MS = 20000;
const SKIP = /^\s*<!--\s*repl:skip\s*-->\s*$/;
const FENCE_OPEN = /^(\s*)```march\s*$/;

// Every markdown page under docs/ rendered with the cookbook layout.
function cookbookPages(dir) {
  const out = [];
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (/^(_|assets$|docs$|downloads$|pagefind$|node_modules$)/.test(ent.name)) continue;
      out.push(...cookbookPages(p));
    } else if (ent.name.endsWith('.md')) {
      const head = fs.readFileSync(p, 'utf8').split('\n', 12).join('\n');
      if (/^---\n[\s\S]*?^layout:\s*cookbook\s*$/m.test(head)) out.push(p);
    }
  }
  return out.sort();
}

// [{line, code, skip}] for each ```march fence in a page.
function marchBlocks(src) {
  const lines = src.split('\n');
  const blocks = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(FENCE_OPEN);
    if (!m) continue;
    // The marker may share the run of comment lines above the fence with others
    // (`<!-- scroll:skip -->`, scripts/gen-scrollmd.py), in either order.
    let skip = false;
    for (let prev = i - 1; prev >= 0; prev--) {
      if (lines[prev].trim() === '') continue;
      if (!/^\s*<!--.*-->\s*$/.test(lines[prev])) break;
      if (SKIP.test(lines[prev])) { skip = true; break; }
    }
    const body = [];
    let j = i + 1;
    for (; j < lines.length && !/^\s*```\s*$/.test(lines[j]); j++) {
      body.push(lines[j].startsWith(m[1]) ? lines[j].slice(m[1].length) : lines[j]);
    }
    blocks.push({ line: i + 1, code: body.join('\n').trim(), skip });
    i = j;
  }
  return blocks;
}

// MarchRepl.splitTranscript (docs/assets/march-repl.js).
function splitTranscript(code) {
  const inputs = [];
  for (const line of code.split('\n')) {
    const m = line.match(/^\s*march>(?:\s(.*))?$/);
    if (m) inputs.push(m[1] || '');
  }
  return inputs.length ? inputs : [code];
}

const repl = loadRepl(assets);
let total = 0, skipped = 0;
const failures = [];
for (const page of cookbookPages(docs)) {
  const rel = path.relative(path.join(docs, '..'), page);
  for (const b of marchBlocks(fs.readFileSync(page, 'utf8'))) {
    if (!b.code) continue;
    total++;
    if (b.skip) { skipped++; continue; }
    repl.reset();
    let error = null, output = '';
    for (const input of splitTranscript(b.code)) {
      if (!input.trim()) continue;
      const r = repl.run(input, { timeout: TIMEOUT_MS });
      output += r.output;
      if (r.error !== null) { error = r.error; break; }
    }
    if (verbose) console.log(`${rel}:${b.line}\n${output}${error ? 'ERROR ' + error + '\n' : ''}`);
    if (error !== null) {
      failures.push(`${rel}:${b.line}: ${error.split('\n')[0]}`);
      console.error(`FAIL ${failures[failures.length - 1]}`);
    }
  }
}

const ran = total - skipped;
if (failures.length) {
  console.error(`cookbook-run-blocks-check: ${failures.length} of ${ran} runnable blocks failed ` +
                `(${skipped} marked <!-- repl:skip -->). Fix the block, or mark it display-only.`);
  process.exit(1);
}
console.log(`cookbook-run-blocks-check: ${ran} runnable blocks passed, ${skipped} display-only (${assets})`);
