# Simd vector types — compiled path (Tasks 2–5)

Task 1 (interpreter path — types, 127 builtins, `stdlib/simd.march`,
Show/Eq/Hash impls, tests, lane-refinement fixtures) is done; see
`specs/progress/2026-08-10-simd-vector-types-task1-interpreter.md`. The
remaining work from `docs/superpowers/plans/2026-08-10-simd-vector-types.md`
(gitignored; ledger at `.superpowers/sdd/2026-08-10-simd-vector-types/`):

- **Task 2** — runtime box (`MARCH_SIMD_TAG = -4`, `march_simd_alloc`/
  `march_simd_bounds_panic` in `runtime/march_runtime.{c,h}`), `coerce`
  vector↔ptr arms in `lib/tir/llvm_ctx.ml`, the `Simd` intercept arm + op
  lowerings in `lib/tir/llvm_emit.ml` (register-resident `<N x T>` SSA
  values inside function bodies, boxed only at escape points).
- **Task 3** — `simd_<t>_load`/`_store` lowerings with bounds checks and the
  FBIP copy-on-write contract (mirroring `native_f32_arr_set`'s in-place
  vs. copy split), plus residency fixtures proving straight-line kernels
  allocate zero boxes.
- **Task 4** — validation kernels (`bench/simd_kernels.march`: dot product,
  u8 delimiter scanner) and, conditionally, switching DataFrame Min/Max to
  a `Simd`-based fast path.
- **Task 5** — JS-target rejection message for `simd_*` builtins, docs
  (`docs/simd-vectorization.md`), changelog entry for compiled support,
  `docs/pagefind` regeneration.

Until Task 2 lands, `--compile` on any program that calls a `Simd.*`
function fails (no LLVM lowering, no runtime box) — the 127 builtins exist
only on the interpreter path today.
