`[P3]` Phase 2 erases lemmas in the in-browser compiler (`lib/driver/js_pipeline.ml`, after
typechecking) and blanks lemma bodies in the browser REPL (`js/march_browser.ml`), but
`scripts/browser-repl-smoke.js` has no lemma case, so the reflection design's `sound_erase_paths`
row (§9.1) is pinned for the native compiler, interpreter and `--jit` only (`reflect-lemma`
tests in `test/test_refine_lemma.ml`).

Done when the smoke compiles and runs a program with a lemma whose body would abort if run,
and checks its output equals the lemma-free program's.

## Done (2026-11-07)

`scripts/browser-repl-smoke.js` has a lemma-erasure section. It builds the
`erase_src`-shaped program from `test/test_refine_lemma.ml` with a lemma `boom` whose
`assert cat(xs, xs) == xs` is false, so running its body would abort. For both browser
paths it requires the program with the lemma to print exactly what the lemma-free
program prints (`2`):
- compiled: `marchCompileToJs`, the module written next to the Tetris
  `march_runtime.mjs` in a temp dir and run under node;
- REPL: the module's body (main unwrapped to a top-level `fn main()`) through `run`.

A control runs the same program with `@[lemma]` removed and requires it to fail, so the
case cannot pass vacuously (both paths abort on the assert there).
