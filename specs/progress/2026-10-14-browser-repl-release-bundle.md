# Browser REPL and live compiler: release builds, one script, bot-owned, repaired (2026-10-14)

Design: `specs/2026-10-14-browser-repl-bundle-design.md`; plan:
`specs/plans/2026-10-14-browser-repl-bundle.md`. This is project 1 of 4 toward "Try it"
buttons on documentation examples.

- `scripts/build-browser-repl.sh` builds `docs/assets/march.js` (interpreter REPL) and
  `march_compile.js` (Tetris live compiler) with `--profile release`, and regenerates
  `march_stdlib.js`, the Tetris playground source, `tetris.mjs` and its two runtimes.
  Modes: write, `--out DIR`, `--check`.
  - `march.js`: 19,761,362 → 1,866,373 bytes (gzip 2.1 MB → 408 KB).
  - `march_compile.js`: 16,408,079 → 2,117,832 bytes (gzip 2.2 MB → 506 KB).
- The committed artifacts are bot-owned: `.github/workflows/gen-browser-repl.yml`
  regenerates them after a merge. `ci.yml` job `browser-repl` builds them fresh and runs
  `scripts/browser-repl-smoke.js`, which pins 12 REPL results and requires the live
  compiler to compile the Tetris source.
- The committed July bundles were stale. In the REPL, `Json` failed with
  `unbound variable: string_byte_at`. The live compiler could not compile any program,
  so editing the Tetris playground and pressing Run has been broken since at least July.
  The repair has three parts:
  - add `bytes.march` to both browser stdlib lists;
  - call `note_stdlib_decls` in `js/march_browser_compile.ml`;
  - give the Tetris demo's `main` the `IO.Foreign` grant and regenerate its stale
    (`Dom`, pre-#201) playground source.
- Checked in a browser, on Jekyll serving this branch:
  - `/docs/playground/`: every example chip gives the expected result; `march.js` is
    1.8 MB and there are no console errors.
  - Tetris: an edited source recompiles and the game runs.
  - Cookbook: `march.js` is not fetched until the first "run"; 18 run buttons exercised.
- Pre-existing and unchanged: 57 of 151 cookbook / `coming-from-*` ` ```march ` blocks
  fail in the browser REPL (identical on the old and new bundles, apart from one now
  fixed). Feeds project 3; see `specs/todos/2026-10-14-cookbook-run-blocks-fail-in-browser-repl.md`.
