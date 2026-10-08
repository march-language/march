# DONE 2026-10-07: A7, `march query` (the query interface)

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §12, "A7 —
the interface". The coarse memo layer the same section assesses (B6) is not
part of this.

## What landed

- **`lib/query/query.ml`** (library `march_query`, on `march_tir` +
  `march_cas`): the requests and their argument parsing, the snapshot
  collector, the cache-key record and its diff, and each answer as text and
  JSON. The driver feeds it; it holds no pipeline of its own.
- **`march query <sub> ... FILE [--json] [compiler flags]`** (`bin/main.ml`):
  peels the query's own arguments and runs the normal compile path on the
  rest, answering at one of two early exits:
  - after the TIR pipeline, where `--dump-tir` stops (`--emit-llvm` mode, so
    the pipeline is the compiled one and nothing is emitted): `fn`, `origin`,
    `callers`, `callees`, `repr`, `verify`;
  - at the post-TIR cache key, before any lookup, emit or link (`--compile`
    mode, with the source-level lookup and every store skipped): `key`,
    `why-miss`.
- **The collector** is the plan's "snap-based collector": installed as the
  pipeline's `snap` and `opt_snap` observer, it keeps the printed body of only
  the functions the query is about at each stage (a whole module per stage
  would hold the stdlib ~40 times). `fn NAME` reports the stages where the
  body appeared, changed or was removed, including `Opt`'s inner passes.
- **Answers about a name the optimiser removed** say so: `callers area` on an
  inlined `area` gives the last stage that had it, and `--no-opt` keeps it.
  Misspelt names get suggestions from every function the provenance table saw.
- **`why-miss`, the one the plan says pays first.** Every successful build now
  writes a key record, `<project>/.march/cas/keyrecords/<digest of entry +
  target>`: target, flags, compiler and runtime identities (runtime directory
  canonicalised), stdlib digest, the source-key mode (B7.2 depend or full
  walk), each keyed file's digest, and both keys. It records what the next run
  keys on (the depend-mode key over this run's load set). `why-miss` recomputes
  the inputs, diffs them field by field, and says which layer will hit:
  source-level, post-TIR (a comment edit), or neither. `key` prints the inputs
  and whether each key is in the store.
- **`march-lsp query`** proxies the compile queries to `march query`
  (`MARCH_BIN`, else a sibling `march`, else the dune layout, else `PATH`),
  passing stdout, stderr and the exit code through.

## Not done (plan §12 rows)

- `owners NAME` (per-variable borrow/RC verdicts) needs A1 check 3 (RC
  balance), which is not built.
- `bisect` / `reduce` are A4, not built.
- `key --unit ID` needs B3/B4 units, which do not exist.
- `why-miss` covers the native compile path's keys; `--check`'s own key and
  the JS/WASM targets' are not recorded.

## Verified

- `test/test_march_query.ml` (compiler suite, 5 cases) drives the real
  compiler in a fresh project with a private HOME and reads every answer as
  JSON. The cache case is pinned to reality: after `why-miss` predicts a
  post-TIR hit for a comment edit, the real compile must print `(cached)`.
  Red first: with the key record's write disabled, the case fails
  ("recorded").
- `lsp/test/test_query_cli.ml`: the proxy returns `march`'s exit codes.
- A query stores no artifact, load set or key record (asserted); it may fill
  the refinement checker's SMT memo (`.march/cas/vc`), as `--check` does.
