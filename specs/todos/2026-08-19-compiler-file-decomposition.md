# Compiler file decomposition

The six largest compiler files carry most of their mass in single giant
definitions (`emit_expr` 4,319 lines = 76% of `llvm_emit.ml`; `base_env` 5,274
lines = 43% of `eval.ml`; `check_call` 1,361 lines behind a twelve-parameter
signature).

Plan: `specs/plans/2026-08-19-compiler-file-decomposition.md`

## Status

**Phases 0-3 and 5 landed. Phases 4 and 6 open.**

- **Phase 5 complete (2026-08-26)** — `bin/main.ml`'s CAS cache key is built in
  exactly one place (`build_cas_key`), alongside `cas_target_label` and
  `effective_opt`, which were duplicated the same way. The two flag lists were
  **byte-identical**, so no live cache-collision bug existed — the hazard was
  latent, waiting for the next codegen flag. Phase 5 deliberately does not split
  `compile`. Verified by flag-list diff (the CAS key includes the compiler's own
  digest, so cross-build key comparison is structurally meaningless), by a direct
  distinct-vs-reused CAS test with a value-revealing program, and by the IR oracle
  (IDENTICAL across 240 programs). Details:
  `specs/progress/2026-08-26-cas-flags-single-constructor.md`.

- **Phase 3 complete (2026-08-26)** — `lib/refinecheck/refine_check.ml` gains 23
  § section headers and a table of contents (comments only), `check_call` goes
  from 13 parameters to 8 behind a documented `call_ctx` record, and a new
  `refine_check.mli` cuts 198 inferred vals to 17 (91% was internal). New
  oracle: `scripts/refine-oracle.sh`, 297 fixtures / 5,638 pinned diagnostic
  lines, proven non-vacuous (RED 1,528 differing lines for a perturbed
  message + verdict, GREEN for a comment-only edit). Note it needs a private
  `HOME`: `~/.cache/march`'s Marshal'd stdlib typecheck env is shared across
  worktrees and its spans carry the populating worktree's paths. Details:
  `specs/progress/2026-08-26-refine-check-decomposition-phase3.md`.

- **Phase 2 complete (2026-08-26)** — see
  `specs/progress/2026-08-26-llvm-emit-decomposition-phase2.md`.

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
