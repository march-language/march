# Browser REPL: on-demand stdlib modules, "not in the browser" errors, Int overflow (2026-10-14)

Design and results: `specs/2026-10-14-browser-repl-modules-design.md`. This is project 2
of 4 toward "Try it" buttons on documentation examples.

- `scripts/gen-browser-stdlib.py` writes:
  - `march_stdlib_index.js`: 140 modules with file, dependencies and an "unavailable"
    reason;
  - one `docs/assets/stdlib/<file>.js` per stdlib file;
  - the startup `march_stdlib.js`, as before.
- `js/march_browser.ml` gains `marchModulesNeeded(code)` and
  `marchLoadModule(file, source)`; the old hand-kept file list is gone. The core set
  comes from the index, and `marchResetSession` forgets loaded modules.
- `docs/assets/march-repl.js` fetches and loads what each input needs before
  evaluating. A module that can't run in a browser (files, sockets, processes,
  cluster, 63-bit Int) gets "X isn't available in the browser REPL: <reason>.
  Install March to run this: <link>".
- `lib/eval/`: on a narrow host (js_of_ocaml, 32-bit int) the Int builtins report
  overflow instead of wrapping. On native the check is a constant `false`. The
  lexer's oversized-literal message names the browser's limit only there.
- Results:
  - stdlib doc examples running in the browser: 63 → 197 of 210, the other 13
    explained and pinned in `scripts/browser-repl-doc-sweep.js` (new CI step);
  - startup unchanged (about 160 ms);
  - smoke test 12 → 17 cases;
  - cookbook `HashMap` snippets run.
- Native suites green; interpreter bench within noise.
- Found and filed: modest recursion overflows the browser's JS stack
  (`specs/todos/2026-10-14-browser-repl-stack-depth.md`).
