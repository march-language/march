#!/usr/bin/env node
// browser-repl-smoke.js — prove the committed browser bundles load and run.
//
// Loads the interpreter REPL (march.js, behind the cookbook sidebar, the landing page
// and /docs/playground/) the way a page does (scripts/browser-repl-node.js: startup
// stdlib, module index, on-demand per-module loading), feeds it a fixed list of inputs
// and asserts the exact {output, error} it returns. A bundle
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
const { browserContext, loadRepl } = require('./browser-repl-node');

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
  // Input is desugared before evaluation: a pipe works.
  { input: "[1, 2, 3] |> List.map(fn x -> x + 1)",
    output: "[2, 3, 4]\n", error: null },
  // Deep recursion does not depend on the JS stack (march.js is CPS-compiled,
  // js/dune): this overflowed at 243 elements before.
  { input: "List.length(List.map(List.range(0, 20000), fn x -> x + 1))",
    output: "20000\n", error: null },
  // Defining another function after `main` does not run `main` again.
  { input: "fn depth(n) do if n == 0 do 0 else 1 + depth(n - 1) end end",
    output: "", error: null },
  { input: "depth(5000)",
    output: "5000\n", error: null },
  // A main that declares its capability (the only form native March accepts
  // for a main that does IO) gets an erased () per parameter, as natively.
  { input: "fn main(io : Cap(IO)) do println(\"capped main\") end",
    output: "capped main\n", error: null },
  { input: "let = 1",
    output: "", error: "unexpected equals sign — did you mean: let name = expr\nlet = 1\n    ^" },
  { input: "List.head([])",
    output: "", error: "runtime error: panic: List.head: empty list" },
  // Loaded on demand: hash_map.march is not in the startup set.
  { input: "HashMap.size(HashMap.from_list([(\"a\", 1), (\"b\", 2)]))",
    output: "2\n", error: null },
  // Named but cannot run in a browser: a clear message, nothing evaluated.
  { input: "File.read(\"notes.txt\")",
    output: "", error: "File isn't available in the browser REPL: it needs a file system. Install March to run this." },
  // The browser's Int is 32-bit: overflow is reported, never wrapped.
  { input: "2147483647 + 1",
    output: "", error: "runtime error: +: this result does not fit the browser REPL's 32-bit Int; native March uses 63-bit Int" },
  // Package code goes through the same loader (marchLoadModule); see PACKAGE below.
  { input: "Greeter.hello(\"march\")", package: true,
    output: "\"hello, march\"\n", error: null },
  { input: "double(1)", reset: true,
    output: "", error: "runtime error: unbound variable: double" },
];

// A package module, loaded the way a package's docs will load it (project 3):
// marchLoadModule with a file name and its source.
const PACKAGE = { file: 'greeter.march',
                  source: 'mod Greeter do\n  fn hello(name) do "hello, " ++ name end\nend\n' };

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
let repl;
try { repl = loadRepl(assets); }
catch (e) { console.error(`FAIL ${e.message}`); process.exit(1); }
for (const c of CASES) {
  if (c.reset) repl.reset();
  if (c.package) {
    const r = repl.ctx.marchLoadModule(PACKAGE.file, PACKAGE.source);
    if (r.error) { failures++; console.error(`FAIL loading ${PACKAGE.file}: ${r.error}`); }
  }
  const r = repl.run(c.input);
  if (print) { console.log(JSON.stringify({ input: c.input, reset: !!c.reset, output: r.output, error: r.error })); continue; }
  check(`${JSON.stringify(c.input)}.output`, c.output, r.output);
  check(`${JSON.stringify(c.input)}.error`, c.error, r.error);
}
// A reset forgets on-demand modules too: HashMap has to load again.
{
  const again = Array.from(repl.ctx.marchModulesNeeded('HashMap.new()').load);
  if (!print && !again.includes('hash_map.march')) {
    failures++; console.error(`FAIL after reset, HashMap should need loading again; needs ${JSON.stringify(again)}`);
  }
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
