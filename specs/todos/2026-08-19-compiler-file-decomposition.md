# Compiler file decomposition

The six largest compiler files carry most of their mass in single giant
definitions (`emit_expr` 4,319 lines = 76% of `llvm_emit.ml`; `base_env` 5,274
lines = 43% of `eval.ml`; `check_call` 1,361 lines behind a twelve-parameter
signature).

Plan: `specs/plans/2026-08-19-compiler-file-decomposition.md`

## Status

**Phases 0 and 1 landed (2026-08-25). Phases 2-6 open.**

- **Phase 1 complete** — `lib/eval/eval.ml` **12,264 → 4,304 lines** (target
  ~5,000), split into `eval_builtins.ml` (5,294), `eval_runtime.ml` (1,242),
  `eval_net.ml` (1,183), `eval_simd.ml`, `eval_session.ml`, `eval_types.ml`,
  `eval_prim.ml`. Exit gate: full suite 2,761 tests exit 0, and an interleaved
  A/B against a compiler built at `f31145eb` shows +1.0% on `fib` and +1.0% on
  `binary_trees` — inside noise, under the 5% gate. Details and the two places
  the plan's shape had to change:
  `specs/progress/2026-08-25-eval-decomposition-phase1.md`.

- Task 0.1 — `scripts/ir-oracle.sh`, the LLVM-IR hashing oracle over the
  243-program corpus (240 emit, 3 skip). Proven non-vacuous: a comment-only edit
  to `lib/tir/llvm_emit.ml` kept it GREEN; changing `int_arith_op`'s `"+" ->
  "add"` to `"add nsw"` turned it RED (131 of 240 programs changed hash, exit 1);
  reverting returned it to GREEN.
- Task 0.2 — full-suite baseline at `8d2b22fb`: **2,759 tests, 0 failures,
  exit 0** (`run_compiler` 936, `run_eval` 273, `run_codegen` 591, `run_stdlib`
  878, `test_stdlib_march` 61, `test_jit` 20 — the last measured separately,
  since #347 added it to `scripts/run-tests.sh` mid-pass). TIR snapshots: 33
  tests, exit 0. **There are no pre-existing failures to inherit.**
- Task 0.3 — interpreter-performance baseline (tag `decomp-baseline-8d2b22fb`
  in `bench/results/2026-08-25-interp-arm64.jsonl`). Added because the IR oracle
  cannot see `lib/eval/eval.ml` — the interpreter is never emitted as LLVM IR,
  which is exactly the file Phase 1 dismantles. Phase 1's exit gate (Task 1.5)
  must re-run it.

The plan was also re-anchored against the current tree in the same pass: the
interpreter/startup/JIT performance project (PRs #334/#335/#341/#342/#344) moved
code inside `lib/eval/eval.ml`, `bin/main.ml` and `lib/tir/llvm_emit.ml` after
the plan was written, invalidating many of its hard-coded `sed`/`awk` ranges.
See the plan's "Re-anchored 2026-08-25" and "Re-anchoring pass" sections for what
was corrected versus what re-measured clean.

Phase 2 must not start until an executing agent re-reads that section. Note also
that Phase 1's ranges were stale again by the time it executed — re-derive every
`sed`/`awk` boundary by `grep` anchor, and assert balanced comment delimiters
before cutting (see the Phase 1 progress note's "doc-comment trap").
