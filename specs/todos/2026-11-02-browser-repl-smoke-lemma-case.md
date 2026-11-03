`[P3]` Phase 2 erases lemmas in the in-browser compiler (`lib/driver/js_pipeline.ml`, after
typechecking) and blanks lemma bodies in the browser REPL (`js/march_browser.ml`), but
`scripts/browser-repl-smoke.js` has no lemma case, so the reflection design's `sound_erase_paths`
row (§9.1) is pinned for the native compiler, interpreter and `--jit` only (`reflect-lemma`
tests in `test/test_refine_lemma.ml`).

Done when the smoke compiles and runs a program with a lemma whose body would abort if run,
and checks its output equals the lemma-free program's.
