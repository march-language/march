#!/usr/bin/env node
// browser-repl-doc-sweep.js — run every stdlib `march>` doc example in the browser REPL.
//
// Each example is evaluated the way a page would (scripts/browser-repl-node.js: on-demand
// module loading included), in one session, in file order. An example passes when it
// evaluates without error, or when it fails with exactly the error listed for it in
// EXPECTED_FAILURES below. Anything else fails the run: an example that newly errors in
// the browser, and an allowlisted one that now passes (so the list cannot rot).
//
// This checks that examples RUN in the browser, not what they print; their printed
// values are checked natively by scripts/check-stdlib-doctests.py.
//
// Usage: node scripts/browser-repl-doc-sweep.js [ASSETS_DIR]   (default: docs/assets)
'use strict';
const fs = require('fs');
const path = require('path');
const { loadRepl } = require('./browser-repl-node');

const assets = process.argv[2] || path.join(__dirname, '..', 'docs', 'assets');
const stdlib = path.join(__dirname, '..', 'stdlib');

// "<file>: <expression>" -> the start of the error it must fail with.
const EXPECTED_FAILURES = {
  // Modules that cannot run in a browser (scripts/gen-browser-stdlib.py UNAVAILABLE).
  'cluster.march: Cluster.from_env()': "Cluster isn't available in the browser REPL",
  'cluster.march: Cluster.from_list([("127.0.0.1", 29852), ("10.0.0.2", 29853)])': "Cluster isn't available in the browser REPL",
  'dir.march: Dir.list("/this/path/does/not/exist")': "Dir isn't available in the browser REPL",
  'dir.march: Dir.list_full("/this/path/does/not/exist")': "Dir isn't available in the browser REPL",
  'dir.march: Dir.exists("/")': "Dir isn't available in the browser REPL",
  'dir.march: Dir.exists("/this/path/does/not/exist")': "Dir isn't available in the browser REPL",
  'http_server.march: HttpServer.method_to_string(:get)': "HttpServer isn't available in the browser REPL",
  'http_server.march: HttpServer.method_to_string(:patch)': "HttpServer isn't available in the browser REPL",
  'http_server.march: HttpServer.method_to_string(:not_a_verb)': "HttpServer isn't available in the browser REPL",
  // Examples that document a panic (the native doctest shows `** panic ...`).
  'env.march: Env.require("MARCH_DOCTEST_NEVER_SET")': 'runtime error: panic: Env: required variable not set',
  'env.march: Env.require_int("MARCH_DOCTEST_NEVER_SET")': 'runtime error: panic: Env: required variable not set',
  'option.march: Option.unwrap(None)': 'runtime error: panic: Option.unwrap called on None',
  'path.march: Path.assert_no_traversal("../etc/passwd")': 'runtime error: panic: path traversal detected',
};

module.exports = { EXPECTED_FAILURES };
if (require.main !== module) return;

const repl = loadRepl(assets);
const seen = new Set();
const problems = [];
let total = 0, passed = 0;
for (const file of fs.readdirSync(stdlib).filter(f => f.endsWith('.march')).sort()) {
  const src = fs.readFileSync(path.join(stdlib, file), 'utf8');
  // A `march>` line in a doc string, or in a module's `--` header comment.
  for (const m of src.matchAll(/^\s*(?:--\s*)?march>\s?(.*)$/gm)) {
    total++;
    const key = `${file}: ${m[1].trim()}`;
    const r = repl.run(m[1]);
    const expected = EXPECTED_FAILURES[key];
    if (expected !== undefined) {
      seen.add(key);
      if (!r.error) problems.push(`now passes, remove it from EXPECTED_FAILURES: ${key}`);
      else if (!r.error.startsWith(expected)) problems.push(`${key}\n  expected error: ${expected}\n  actual error:   ${r.error.split('\n')[0]}`);
      else passed++;
    } else if (r.error) {
      problems.push(`${key}\n  error: ${r.error.split('\n')[0]}`);
    } else {
      passed++;
    }
  }
}
for (const key of Object.keys(EXPECTED_FAILURES)) {
  if (!seen.has(key)) problems.push(`no such example any more, remove it from EXPECTED_FAILURES: ${key}`);
}
if (problems.length) {
  console.error(problems.map(p => 'FAIL ' + p).join('\n'));
  console.error(`browser-repl-doc-sweep: ${problems.length} problem(s) in ${total} examples`);
  process.exit(1);
}
console.log(`browser-repl-doc-sweep: ${total} examples, ${total - Object.keys(EXPECTED_FAILURES).length} run cleanly, ` +
            `${Object.keys(EXPECTED_FAILURES).length} fail as expected (${assets})`);
