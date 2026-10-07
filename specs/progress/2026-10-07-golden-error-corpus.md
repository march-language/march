# DONE 2026-10-07: D7, golden rendered-diagnostic corpus

Diagnostics plan (`specs/plans/diagnostics-and-triage-plan.md`) §11. Builds on
D3 (codes and `[slug]` suffix, `specs/progress/2026-10-07-diagnostic-code-registry.md`).

## What landed

- **`test/run_errors.ml`** (dune `(test)` stanza `run_errors`; `scripts/run-tests.sh errors`):
  for every `test/errors/<name>.march` it runs `march --check` and
  `march --check-json` and compares, byte for byte:
  - `<name>.expected`: `exit: N`, the rendered stderr (carets, labels, notes, the
    `[slug]` suffix, the `march --explain` pointer), then each machine fix from the
    JSON rendered as a before/after diff of the lines it touches;
  - `<name>.json.expected`: the `--check-json` lines.
  A source with `-- EXPECT-ERROR: <fragment>` must also contain that fragment in
  its rendered output, so a seeded twin cannot silently stop exercising the error
  it was copied for. Each program runs in a fresh temp dir as `errors/<file>` under
  a private `HOME` (stable header path, no cross-worktree cache); runs are started
  in parallel up front (`MARCH_JOBS`, default 8) and the cases only compare.
  ~46 s for 269 programs on an M-series laptop at load ~15.
- **`scripts/seed-error-corpus.sh`**: adds a twin for every
  `specs/lang/types/reject/` and `specs/lang/grammar/reject/` program and the
  failing program of every `specs/lang/errors/` page, named by the slug of its
  first diagnostic. Idempotent (skips a program whose text is already present,
  never renames or overwrites). 269 programs at landing: 245 type rejects, 14
  grammar rejects, 10 page programs. The `specs/lang` corpora are untouched, so
  doc-lint Check C's counts are unchanged.
- `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e` regenerates; the
  `.expected` diff is the review artifact for any message change.
- `CLAUDE.md` has a short paragraph next to the TIR-snapshot one.

## Verified

- Two consecutive runs green (determinism); no temp path or `HOME` leaks into
  any `.expected` (grep for `/var/folders`, `/tmp/`).
- Red: changing `[type_mismatch]` in `type_mismatch_1.expected` fails exactly that
  case; changing a twin's `EXPECT-ERROR` fragment fails it with
  "no longer contains its EXPECT-ERROR fragment".
- The seeding first found seven reject programs with no `[slug]`: desugar
  diagnostics went through the CLI's compact `file:line:col:` printer. Fixed on
  the D3 branch (the compact form now carries the suffix) before seeding.

## Not done here (by design)

The ~200 alcotest message-fragment assertions (`test_compiler.ml`,
`test_codegen.ml`, `test_refinecheck.ml`, `test_eval.ml`, `test_alloc_contract.ml`)
are **not** migrated; they move into this corpus as each is touched (plan §11,
risk table).
