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
// playground source with no errors, and its marchCheck must print, for every program
// the error playground offers (docs/_includes/error-playground.html), exactly what
// docs/error-messages.md shows `march --check` printing for it.
//
// This tests the bundle, not documentation examples (the error-playground programs
// are the one exception: the page promises they match the native compiler).
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
  // js/dune): this overflowed at 243 elements before, and again under
  // js_of_ocaml 6.5 until the evaluator bounced the stack on the return path
  // too (Eval.call_return_hook, set in js/march_browser.ml).
  { input: "List.length(List.map(List.range(0, 20000), fn x -> x + 1))",
    output: "20000\n", error: null },
  // The same for an exception unwinding a deep recursion: under js_of_ocaml 6.5
  // the panic below overflowed the JS stack on its way up until the bounce ran
  // in apply's ~finally (both return paths), not only after a normal return.
  { input: "fn deep_panic(n) do if n == 0 do panic(\"bottom\") else 1 + deep_panic(n - 1) end end",
    output: "", error: null },
  { input: "deep_panic(20000)",
    output: "", error: "runtime error: panic: bottom" },
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
  // A sigil names no module but desugars to calls into one: ~H"..." loads IOList.
  { input: "~H\"<p>${\"<b>\"}</p>\"",
    output: "Segments([Str(\"<p>\"), Str(\"&lt;b&gt;\"), Str(\"</p>\")])\n", error: null },
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

// ── Pasted doc transcript ───────────────────────────────────────────────────
// docs/assets/march-repl.js (hand-maintained, so always read from the repo, not
// from ASSETS_DIR) splits a pasted stdlib-doc transcript into one input per
// "march> " line and drops the expected-output lines. The Sort.html report:
// the pasted output line "[1, 2, 2, 5, 8]" was the block's last expression, so
// the REPL printed it as if heapsort had dropped 9999999.
const TRANSCRIPT_CASES = [
  { paste: "march> Sort.heapsort_by([8, 5, 2, 9999999, 1, 2], fn a -> fn b -> a <= b)\n[1, 2, 2, 5, 8]",
    inputs: ["Sort.heapsort_by([8, 5, 2, 9999999, 1, 2], fn a -> fn b -> a <= b)"],
    outputs: ["[1, 2, 2, 5, 8, 9999999]\n"] },
  // Several prompts, each with its output, in order; leading indentation and a
  // blank line survive the paste.
  { paste: "  march> let xs = [3, 1, 2]\n  [3, 1, 2]\n\n  march> List.sort(xs)\n  [1, 2, 3]\n",
    inputs: ["let xs = [3, 1, 2]", "List.sort(xs)"],
    outputs: ["", "[1, 2, 3]\n"] },
  // No prompt line: the text is one input, unchanged (a multi-line block).
  { paste: "let y = 40\ny + 2",
    inputs: ["let y = 40\ny + 2"],
    outputs: ["42\n"] },
  // A single line is unchanged too.
  { paste: "1 + 1", inputs: ["1 + 1"], outputs: ["2\n"] },
];
{
  const replCtx = { window: null };
  replCtx.window = replCtx;
  vm.createContext(replCtx);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'docs', 'assets', 'march-repl.js'), 'utf8'),
                  replCtx, { filename: 'march-repl.js' });
  const split = replCtx.MarchRepl && replCtx.MarchRepl.splitTranscript;
  if (typeof split !== 'function') { console.error('FAIL march-repl.js does not export MarchRepl.splitTranscript'); process.exit(1); }
  repl.reset();
  for (const c of TRANSCRIPT_CASES) {
    const inputs = split(c.paste);
    if (print) console.log(JSON.stringify({ paste: c.paste, inputs }));
    else check(`splitTranscript(${JSON.stringify(c.paste)})`, JSON.stringify(c.inputs), JSON.stringify(inputs));
    inputs.forEach((input, i) => {
      const r = repl.run(input);
      if (print) { console.log(JSON.stringify({ input, output: r.output, error: r.error })); return; }
      check(`transcript ${JSON.stringify(input)}.output`, c.outputs[i], r.output);
      check(`transcript ${JSON.stringify(input)}.error`, null, r.error);
    });
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

// marchCheck, against the native `march --check` output docs/error-messages.md pins
// (scripts/gen-error-tour.py). The header line names the file, which differs, and its
// dashes pad that name to a fixed width; both are normalised away.
let checkCases = 0;
if (typeof comp.marchCheck !== 'function') { failures++; console.error('FAIL march_compile.js does not export marchCheck'); }
else {
  const docs = path.join(__dirname, '..', 'docs');
  const page = fs.readFileSync(path.join(docs, 'error-messages.md'), 'utf8');
  const include = fs.readFileSync(path.join(docs, '_includes', 'error-playground.html'), 'utf8');
  const header = s => s.replace(/^(-- .*?) -+ \S+\.march$/gm, '$1 --- FILE').replace(/\s+$/, '');
  for (const [, name] of include.matchAll(/<option value="([\w-]+)"/g)) {
    checkCases++;
    const m = page.match(new RegExp(`<!-- error-tour: ${name} -->\\n[\\s\\S]*?\`\`\`text\\n([\\s\\S]*?)\`\`\`\\n<!-- /error-tour -->`));
    if (!m) { failures++; console.error(`FAIL marchCheck ${name}: no output block on docs/error-messages.md`); continue; }
    const src = fs.readFileSync(path.join(docs, 'assets', 'error-tour', name + '.march'), 'utf8');
    const r = comp.marchCheck(src);
    if (print) { console.log(JSON.stringify({ check: name, rejected: r.rejected, output: r.output })); continue; }
    if (!r.rejected || header(r.output) !== header(m[1])) {
      failures++;
      console.error(`FAIL marchCheck ${name}: rejected=${r.rejected} (if the native message changed on purpose, run scripts/gen-error-tour.py)\n--- expected (docs/error-messages.md)\n${m[1]}--- actual\n${r.output}`);
    }
  }
}

// ── Lemma erasure ───────────────────────────────────────────────────────────
// A lemma is proof-only: the live compiler erases it after typechecking
// (lib/driver/js_pipeline.ml) and the REPL blanks its body (js/march_browser.ml),
// so a lemma body never runs (the reflection design's sound_erase_paths row, pinned
// natively by test/test_refine_lemma.ml). boom's body would abort: its assert is
// false. The program with the lemma must print exactly what the lemma-free program
// prints, compiled (run under node with the Tetris runtime) and in the REPL; and as
// a control, the same program with boom an ordinary function must fail.
function lemmaProgram(mode) { // 'lemma' | 'none' | 'plain' (boom not a lemma)
  const keep = mode !== 'none';
  return [
    'mod Main do',
    '  needs IO.Console',
    '  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do',
    '    match xs do',
    '      Nil -> ys',
    '      Cons(h, t) -> Cons(h, cat(t, ys))',
    '    end',
    '  end',
    mode === 'lemma' ? '  @[lemma]' : '',
    keep ? '  fn boom(xs : List(Int)) : {Unit | cat(xs, xs) == xs} do' : '',
    keep ? '    assert cat(xs, xs) == xs' : '',
    keep ? '    ()' : '',
    keep ? '  end' : '',
    '  fn main(_cap : Cap(IO.Console)) do',
    '    let xs = Cons(1, Cons(2, Nil))',
    keep ? '    boom(Cons(1, Nil))' : '',
    '    println(int_to_string(List.length(cat(xs, Nil))))',
    '  end',
    'end',
    ''].join('\n');
}
// Compile with the live compiler and run the module under node: {ok, stdout, error}.
function compileAndRun(src) {
  const { execFileSync } = require('child_process');
  const os = require('os');
  const out = comp.marchCompileToJs(src);
  const errs = Array.from(out.errors || []);
  if (!out.js || errs.length) return { ok: false, stdout: '', error: `compile: ${JSON.stringify(errs)}` };
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'march-smoke-'));
  try {
    fs.copyFileSync(path.join(assets, 'tetris', 'march_runtime.mjs'), path.join(dir, 'march_runtime.mjs'));
    fs.writeFileSync(path.join(dir, 'main.mjs'), out.js);
    try {
      return { ok: true, stdout: execFileSync(process.execPath, [path.join(dir, 'main.mjs')],
                                              { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }) };
    } catch (e) { return { ok: false, stdout: e.stdout || '', error: String(e.stderr || e.message) }; }
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}
// The REPL runs a top-level main when it is defined: unwrap the module.
function replRun(src) {
  const body = src.split('\n').filter(l => !/^(mod Main do|end|  needs IO\.Console)$/.test(l))
                  .map(l => l.replace(/^  /, '')).join('\n')
                  .replace('fn main(_cap : Cap(IO.Console))', 'fn main()');
  repl.reset();
  const r = repl.run(body);
  return { ok: r.error === null, stdout: r.output, error: r.error };
}
let lemmaCases = 0;
for (const [label, runner] of [['compiled', compileAndRun], ['REPL', replRun]]) {
  lemmaCases++;
  const withLemma = runner(lemmaProgram('lemma'));
  const without = runner(lemmaProgram('none'));
  const plain = runner(lemmaProgram('plain'));
  if (print) { console.log(JSON.stringify({ lemma: label, withLemma, without, plain })); continue; }
  if (!without.ok || without.stdout !== '2\n') {
    failures++; console.error(`FAIL lemma (${label}): the lemma-free program should print "2": ${JSON.stringify(without)}`);
  } else if (!withLemma.ok || withLemma.stdout !== without.stdout) {
    failures++; console.error(`FAIL lemma (${label}): a lemma body ran, or the output differs from the lemma-free program's\n  with:    ${JSON.stringify(withLemma)}\n  without: ${JSON.stringify(without)}`);
  }
  // The control must fail on boom's assert, not on something else (a compile error
  // would make the case vacuous too).
  if (plain.ok || !/\[assert_failed\]/.test(plain.error || '')) {
    failures++; console.error(`FAIL lemma (${label}) control: boom as an ordinary function should abort on its assert, so this case can fail; got ${JSON.stringify(plain)}`);
  }
}

if (!print) {
  if (failures) { console.error(`browser-repl-smoke: ${failures} failure(s)`); process.exit(1); }
  console.log(`browser-repl-smoke: ${CASES.length + TRANSCRIPT_CASES.length + 1 + checkCases + lemmaCases} cases passed (${assets})`);
}
