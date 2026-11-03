# Browser REPL Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship release-built browser bundles, produced by one script, kept current by a
CI freshness check and proven loadable by a Node smoke test.

**Architecture:** `scripts/build-browser-repl.sh` builds `js/march_browser.bc.js` and
`js/march_browser_compile.bc.js` with `--profile release` into a private build dir, runs
`scripts/gen-browser-stdlib.py`, and moves all three into `docs/assets/`. With `--check`
it compares instead of writing. `scripts/browser-repl-smoke.js` loads the committed
bundle in a Node `vm` context and asserts exact REPL output.

**Tech Stack:** bash, dune 3 / js_of_ocaml 6.3.2, Python 3, Node (CI: `actions/setup-node`).

**Spec:** `specs/2026-10-14-browser-repl-bundle-design.md`

## Global Constraints

- Artifact names and JS globals unchanged: `docs/assets/march.js`, `march_compile.js`,
  `march_stdlib.js`; `marchEvalLine`, `marchResetSession`, `marchCompileToJs`.
- Always `dune build --root "$ROOT"` (worktrees nest inside the main checkout).
- No `wasm_of_ocaml`, no versioned URLs, no change to which stdlib files load.
- Never overwrite `docs/assets/` unless all three artifacts were produced.

## Review Focus

- A dev-profile `_build/` present: the script must still emit release output (private `--build-dir`).
- Running from a nested worktree path: output must not embed the checkout path (determinism).
- `--check` with several stale files: names every one, exits 1.
- A failing dune build mid-script: `docs/assets/` untouched.
- `marchResetSession` actually clears a prior binding (smoke case).

---

### Task 1: Determinism probe

- [ ] Build `js/march_browser.bc.js` and `js/march_browser_compile.bc.js` with
  `--profile release` from two different checkout paths and build dirs; `cmp` both pairs.
- [ ] Record the result in the spec's acceptance criteria. Identical → byte-for-byte check.
  Different → find the cause (`--no-sourcemap`, `--debuginfo` paths) before falling back.

### Task 2: `scripts/browser-repl-smoke.js`

**Interfaces:** `node scripts/browser-repl-smoke.js [ASSETS_DIR]` (default `docs/assets`); exit 0 / 1.

- [ ] Write the harness: a `vm` context with browser globals, load `march_stdlib.js`
  then `march.js`, a table of `{input, output, error}` cases asserted exactly, a reset
  case, plus one `marchCompileToJs` case on `march_compile.js`.
- [ ] Run against the committed (dev) bundle: passes (behaviour must already match).
- [ ] Perturb one expected output: fails naming input, expected, actual. Revert.

### Task 3: `scripts/build-browser-repl.sh`

**Interfaces:** `scripts/build-browser-repl.sh [--check]`; writes or compares the three artifacts; prints raw + gzip sizes.

- [ ] Implement: `set -euo pipefail`; private build dir under `$ROOT/_build_browser`
  (gitignored); stage into a temp dir; write `march_stdlib.js` there via
  `gen-browser-stdlib.py` (needs an output-path argument); in write mode `mv` all three
  only after all succeed; in `--check` mode `cmp` each and list every stale file.
- [ ] Run it; run the smoke test against the new bundles; commit the regenerated artifacts.
- [ ] Prove `--check` is green, then red after an unregenerated stdlib comment edit. Revert.

### Task 4: CI + docs

- [ ] Add a `browser-repl` job to `.github/workflows/ci.yml`: opam setup as other jobs,
  `scripts/build-browser-repl.sh --check`, `actions/setup-node`, smoke test. Document it in
  `.github/workflows/README.md`.
- [ ] Update `js/dune` header comments and `docs/_includes/playground.html` header to point
  at the script; drop the nonexistent `@js/playground` alias.
- [ ] CHANGELOG `[Unreleased]`, `specs/progress/2026-10-14-browser-repl-release-bundle.md`.
- [ ] Manual browser pass: cookbook "run", landing REPL, `/docs/playground/`, Tetris.
