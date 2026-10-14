#!/usr/bin/env node
// browser-repl-smoke.js — prove the committed browser bundles load and run.
//
// Loads docs/assets/march_stdlib.js and docs/assets/march.js (the interpreter REPL
// behind the cookbook sidebar, the landing page and /docs/playground/) into a Node
// `vm` context that stands in for a browser window, then feeds `marchEvalLine` a
// fixed list of inputs and asserts the exact {output, error} it returns. A bundle
// that fails to load (a missing js_of_ocaml primitive or browser global), a stdlib
// module the browser list stopped loading, or a value-printer regression turns this
// red. march_compile.js (the Tetris live compiler) must compile the Tetris
// playground source with no errors.
//
// This tests the bundle, not documentation examples.
//
// Usage: node scripts/browser-repl-smoke.js [ASSETS_DIR]   (default: docs/assets)
//        node scripts/browser-repl-smoke.js --print [ASSETS_DIR]
//          prints the actual result of every case instead of asserting.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const args = process.argv.slice(2);
const print = args[0] === '--print';
if (print) args.shift();
const assets = args[0] || path.join(__dirname, '..', 'docs', 'assets');

// Each case runs in order in ONE session, so a case may use a binding an earlier
// case made. `reset: true` calls marchResetSession() before the input.
const CASES = [
  { input: "1 + 2",
    output: "3\n", error: null },
  { input: "List.map([1, 2, 3], fn x -> x * 2)",
    output: "[2, 4, 6]\n", error: null },
  { input: "String.to_uppercase(\"march\")",
    output: "\"MARCH\"\n", error: null },
  { input: "Map.to_list(Map.from_list_string([(\"b\", 2), (\"a\", 1)]))",
    output: "[(\"b\", 2), (\"a\", 1)]\n", error: null },
  { input: "match Json.parse(\"[1,2]\") do Ok(v) -> Json.to_string(v) | Err(_) -> \"bad\" end",
    output: "\"[1,2]\"\n", error: null },
  { input: "Http.encode_query([(\"q\", \"march\"), (\"page\", \"2\")])",
    output: "\"q=march&page=2\"\n", error: null },
  { input: "fn double(x) do x * 2 end",
    output: "", error: null },
  { input: "double(21)",
    output: "42\n", error: null },
  { input: "fn main() do println(\"hello from main\") end",
    output: "hello from main\n", error: null },
  { input: "let = 1",
    output: "", error: "unexpected equals sign — did you mean: let name = expr\nlet = 1\n    ^" },
  { input: "List.head([])",
    output: "", error: "runtime error: panic: List.head: empty list" },
  { input: "double(1)", reset: true,
    output: "", error: "runtime error: unbound variable: double" },
];

function browserContext() {
  const ctx = {
    console, TextDecoder, TextEncoder, setTimeout, clearTimeout, performance,
    crypto: globalThis.crypto,
  };
  // js_of_ocaml reaches the standard constructors through the global object.
  for (const name of Object.getOwnPropertyNames(globalThis)) {
    if (!(name in ctx) && /^[A-Z]/.test(name)) ctx[name] = globalThis[name];
  }
  for (const name of ['isNaN', 'isFinite', 'parseInt', 'parseFloat',
                      'encodeURIComponent', 'decodeURIComponent']) {
    ctx[name] = globalThis[name];
  }
  ctx.window = ctx; ctx.self = ctx; ctx.globalThis = ctx;
  vm.createContext(ctx);
  return ctx;
}

function load(ctx, file) {
  vm.runInContext(fs.readFileSync(path.join(assets, file), 'utf8'), ctx, { filename: file });
}

let failures = 0;
function check(label, expected, actual) {
  if (expected !== actual) {
    failures++;
    console.error(`FAIL ${label}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
  }
}

// ── Interpreter REPL ────────────────────────────────────────────────────────
const repl = browserContext();
load(repl, 'march_stdlib.js');
load(repl, 'march.js');
for (const g of ['marchEvalLine', 'marchResetSession']) {
  if (typeof repl[g] !== 'function') { console.error(`FAIL march.js does not export ${g}`); process.exit(1); }
}
for (const c of CASES) {
  if (c.reset) repl.marchResetSession();
  const r = repl.marchEvalLine(c.input);
  if (print) { console.log(JSON.stringify({ input: c.input, reset: !!c.reset, output: r.output, error: r.error })); continue; }
  check(`${JSON.stringify(c.input)}.output`, c.output, r.output);
  check(`${JSON.stringify(c.input)}.error`, c.error, r.error);
}

// ── Live compiler ───────────────────────────────────────────────────────────
const comp = browserContext();
load(comp, 'march_stdlib.js');
load(comp, 'march_compile.js');
if (typeof comp.marchCompileToJs !== 'function') { console.error('FAIL march_compile.js does not export marchCompileToJs'); process.exit(1); }
// The Tetris playground's own editable source: the program readers actually compile.
const tetris = fs.readFileSync(path.join(assets, 'tetris', 'tetris-source.march.txt'), 'utf8');
const out = comp.marchCompileToJs(tetris);
const errs = Array.from(out.errors || []);
if (print) console.log(JSON.stringify({ compile: true, js_len: out.js ? out.js.length : null, errors: errs }));
else if (!out.js || errs.length) { failures++; console.error(`FAIL marchCompileToJs: js=${out.js ? out.js.length : null} errors=${JSON.stringify(errs)}`); }

if (!print) {
  if (failures) { console.error(`browser-repl-smoke: ${failures} failure(s)`); process.exit(1); }
  console.log(`browser-repl-smoke: ${CASES.length + 1} cases passed (${assets})`);
}
