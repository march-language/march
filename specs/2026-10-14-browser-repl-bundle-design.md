# Browser REPL bundle: release build, one build script, CI freshness and smoke checks

Date: 2026-10-14
Status: design approved in conversation; spec awaiting review

## Context

This is project 1 of 4 toward "Try it" buttons on documentation code examples. The
buttons open a sidebar REPL that runs the example. The goal is learning: a reader
loads an example, runs it, edits it and re-runs it.

The full sequence, agreed in conversation:

1. **The browser bundle (this spec):** build it from source, make it small, keep it current.
2. **Browser REPL coverage:** load more of the stdlib, and accept extra source files
   (a package and its dependencies) at startup.
3. **`march_doc` "Try it":** opt-in markers (module default plus per-fence tags),
   buttons, and a sidebar that loads nothing until clicked. A general `march_doc`
   feature, so package docs get it too.
4. **Doctest check:** extend `scripts/check-stdlib-doctests.py` to run every opted-in
   example, whole-program examples included.

Projects 2-4 get their own specs. This one is about the bundle that every REPL on the
site already uses: the cookbook sidebar, the landing page and `/docs/playground/`.
The Tetris playground uses its sibling, the live-compile bundle.

## Problem

`docs/assets/march.js` (the interpreter REPL) and `docs/assets/march_compile.js` (the
live compiler for the Tetris playground) are built by hand and copied in, as the comments
in `js/dune` describe. Two things are wrong with that:

- **They are development builds.** Dune's default profile compiles js_of_ocaml
  separately per module: no whole-program dead-code removal, pretty-printed output.
  The committed `march.js` is 232,820 lines.
- **Nothing keeps them current.** No workflow builds them; `deploy-pages.yml` only runs
  Jekyll and Pagefind over committed files. `march.js` was last rebuilt in July. A
  stdlib change can silently fail to reach the browser REPL, which already happened
  once (`specs/progress/2026-07-23-browser-cookbook-playground-repl-was-missing-the-vault-stdlib.md`).
  The `@js/playground` alias that the `js/dune` comments mention does not exist.

Measured 2026-10-14 (js_of_ocaml 6.3.2; gzip `-9`, brotli default):

| Bundle | Build | Raw | gzip | brotli |
|---|---|---|---|---|
| `march.js` | committed (dev) | 19,761,362 | 2,137,840 | 1,351,343 |
| `march.js` | `--profile release` | 1,866,373 | 408,211 | 297,389 |
| `march_compile.js` | committed (dev) | 16,408,079 | 2,200,066 | 1,416,894 |
| `march_compile.js` | `--profile release` | 2,117,059 | 505,995 | 366,458 |

The release `march.js` was checked in Node against the committed one on six inputs:
arithmetic, `List.map`, `String.to_uppercase`, `Http.encode_query`, a `main`
definition, and one failing call. The output and errors were identical; the first
evaluation (which loads the stdlib) took about 160 ms on both.

## Goals

- Every browser bundle on the site is a release build, built by one script from the
  current source.
- CI fails when a committed bundle or `march_stdlib.js` no longer matches what the
  script would produce.
- CI proves the interpreter bundle loads and evaluates code.
- No change to the bundles' file names or JS interface, so every existing page gets
  the smaller bundle with no other edit.

## Non-goals

- `wasm_of_ocaml`. Not installed, would add a toolchain, and the release JS is already
  about 300 KB compressed. Revisit only if load time is measured to be a problem.
- Versioned bundle URLs (for example `/assets/repl/v0.5.0/march.js`) for package
  docs. That belongs to project 3, where the need arises.
- Loading more stdlib modules in the browser (project 2).
- Any change to how pages load the REPL (project 3 and the existing pages).
- Running documentation examples in the browser REPL. The user chose to check examples
  with the native doctest check instead (project 4). The smoke test below tests the
  bundle, not the examples.

## Design

### 1. `scripts/build-browser-repl.sh`

One entry point that produces every committed browser artifact:

1. `dune build --root "$ROOT" --profile release --build-dir <private dir> js/march_browser.bc.js js/march_browser_compile.bc.js`.
   A private `--build-dir` keeps the release profile from rebuilding the developer's
   `_build/` in release mode (and the reverse). The dune cache still shares identical
   actions.
2. Copy the outputs to `docs/assets/march.js` and `docs/assets/march_compile.js`.
3. Run `scripts/gen-browser-stdlib.py` to regenerate `docs/assets/march_stdlib.js`
   from `stdlib/`.
4. Print each artifact's raw and gzip size, so a large size jump shows up in the
   build log and the PR.

Flags: `--check` builds into a temporary directory and compares against `docs/assets/`
instead of writing. It exits 1 and names each stale file. CI uses this mode.

The `js/dune` header comments and `docs/_includes/playground.html:4-6` are updated to
point at the script and to drop the nonexistent `@js/playground` alias.

Why a script and not a dune rule that writes into `docs/`: dune rules write into
`_build/`, and promoting into a committed site directory on every `dune build` would
tie ordinary compiler builds to the site's assets. Other committed generated files
follow the same pattern (`scripts/gen-stdlib-docs.sh`, `scripts/gen-lang-docs.py`).

### 2. CI freshness check

A new job, or a step in an existing Linux job, runs `scripts/build-browser-repl.sh --check`.

This depends on js_of_ocaml producing byte-identical output on every build: same
source, same toolchain, different checkout path and machine. **The first
implementation task checks this:** build twice in different directories (and,
through CI, on a different OS), then `cmp`.

- If the output is identical, compare the bundles byte for byte.
- If not, find the cause (embedded paths, hash ordering) and fix it with flags if
  that is possible. If it can't be fixed, the check compares `march_stdlib.js` byte
  for byte, and compares each bundle by its `buildInfo` header plus the smoke test
  below. The spec's acceptance criteria record which of these was used.

The opam toolchain pins js_of_ocaml (6.3.2 today). A toolchain bump that changes the
output is a legitimate regeneration, made in the same PR as the bump.

### 3. CI smoke test

`scripts/browser-repl-smoke.js`, run with Node:

- Loads `docs/assets/march_stdlib.js` and then `docs/assets/march.js` into a `vm`
  context that provides the browser globals js_of_ocaml needs (`TextDecoder`,
  `TextEncoder`, typed arrays, `crypto`, and so on).
- Calls `marchEvalLine` on a fixed list of inputs and asserts the exact `output` and
  `error` fields. The list covers:
  - arithmetic;
  - a stdlib call from each of a few modules (List, String, Map, Json, Http);
  - a declaration followed by a use;
  - `main` printing output;
  - a parse error;
  - a runtime error;
  - `marchResetSession`, which must clear a binding.
- Exits non-zero on any mismatch or exception.

This catches a bundle that fails to load (a missing primitive, a global js_of_ocaml
expects), a stdlib module the browser list no longer loads, and a value-printer
regression. `march_compile.js` gets one smoke case: `marchCompileToJs` on a small
program returns non-empty `js` and no errors.

### 4. Regenerated artifacts

The implementing PR runs the script and commits the three regenerated files. Nothing
that loads them changes. The one compatibility risk is how the release build behaves
on inputs the comparison above did not cover. The smoke test and a manual pass
cover it: the cookbook "run" buttons, the landing-page REPL, `/docs/playground/` and
the Tetris playground, each in a browser.

## Error handling

- Script: `set -euo pipefail`. A dune failure, a missing output or a failing
  `gen-browser-stdlib.py` aborts before anything in `docs/assets/` is overwritten.
  The script writes to temporary files and moves them into place only after all three
  succeed.
- `--check` lists every stale file, not just the first.
- The smoke test prints the input, expected and actual for each failure.

## Testing

- The smoke test above, in CI.
- The freshness check, shown to fail on an intentional change: edit a stdlib doc
  comment without regenerating, and `--check` must exit 1 naming `march_stdlib.js`.
- A manual browser pass over the four REPL surfaces, recorded in the PR.
- Size before and after, recorded in the PR and in `specs/progress/`.

## Acceptance criteria

- `docs/assets/march.js` and `march_compile.js` are release builds (brotli under about
  400 KB each) produced by `scripts/build-browser-repl.sh`.
- CI fails when any of the three artifacts is stale, and fails when the interpreter
  bundle cannot load or evaluate the smoke inputs.
- Cookbook, landing page, playground and Tetris pages work unchanged.
- Whether the freshness check compares bundles byte for byte, or falls back as
  described in section 2, is recorded here and in `specs/progress/`.
- `CHANGELOG.md` `[Unreleased]`: the browser REPL downloads about a tenth as much and
  is kept in sync with the stdlib.

## Open questions

None blocking. Whether the build is byte-identical everywhere is answered by the
first implementation task, and section 2 defines both outcomes.
