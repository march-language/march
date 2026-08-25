# Compiler file decomposition

The six largest compiler files carry most of their mass in single giant
definitions (`emit_expr` 4,319 lines = 76% of `llvm_emit.ml`; `base_env` 5,274
lines = 43% of `eval.ml`; `check_call` 1,361 lines behind a twelve-parameter
signature).

Plan: `specs/plans/2026-08-19-compiler-file-decomposition.md`

## Status

**Phase 0 landed (2026-08-25, at `8d2b22fb`). Phases 1-6 open.**

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

Phase 1 must not start until an executing agent re-reads that section.
