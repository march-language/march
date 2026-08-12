# Simd vector types — Task 1: interpreter path

Implemented the interpreter half of the explicit 128-bit SIMD vector types
feature (`F32x4`/`F64x2`/`I32x4`/`I64x2`/`U8x16`), per Task 1 of
`docs/superpowers/plans/2026-08-10-simd-vector-types.md` (plan doc is
gitignored under `docs/superpowers/`; the ledger at
`.superpowers/sdd/2026-08-10-simd-vector-types/` tracks per-task status).

## What landed

- **Types**: `F32x4`, `F64x2`, `I32x4`, `I64x2`, `U8x16` registered arity-0,
  sendable (`lib/typecheck/typecheck.ml` `builtin_types`).
- **127 builtins** (`simd_<t>_<op>`) registered in all three interpreter
  registries: typecheck signatures, `lib/eval/eval.ml` implementations, and
  `lib/tir/defun.ml` `builtin_names`. Op grid: 17 shared ops (splat/make/
  extract/replace/load/store/eq/lt/gt/and/or/xor/not/select/any/all/
  first_set) on all 5 types, plus 11 float-only ops (add/sub/mul/div/min/
  max/fma/sqrt/sum/hmin/hmax) on f32x4+f64x2, plus 10 int-only ops (add/sub/
  mul/min/max/shl/shr/sum/hmin/hmax) on i32x4+i64x2. u8x16 has no
  arithmetic. Total 28+28+27+27+17 = 127.
- **Eval representation**: `VF32x4`/`VF64x2 of float array`,
  `VI32x4 of int array`, `VU8x16 of int array`, and — the one representation
  choice that needed care — `VI64x2 of int64 array` (NOT `int array`):
  OCaml's native `int` is 63-bit, so exact 64-bit two's-complement wrap for
  i64x2 lane arithmetic needs the `Int64` module. Known documented parity
  edge: `extract_i64x2`/`sum_i64x2`/`hmin_i64x2`/`hmax_i64x2` narrow the
  int64 lane back to the interpreter's native-int `VInt` via `Int64.to_int`,
  losing the top bit outside ±2^62 — tests stay within that range.
- **Semantics implemented exactly per the plan's Global Constraints**: f32
  lane ops round through `f32_round` (reused from the narrow-array P10
  work); i32 wraps via `i32_wrap`; u8 via `u8_wrap`; float min/max use
  minNum/maxNum (a NaN operand loses to the other, both-NaN is NaN);
  `sum` accumulates SEQUENTIALLY (ordered, not tree-reduced) in double for
  float types / native int for i32x4 / int64 for i64x2 — the ordering
  matters because Task 2's compiled `llvm.vector.reduce.*` lowering must
  match it bit-for-bit; compares produce all-ones/all-zero lanes (bit
  patterns, not booleans) so `select`/`any`/`all`/`first_set` can be
  mask-driven the same way the LLVM lowering will read bits.
- **Stdlib `mod Simd`** (`stdlib/simd.march`, synced to
  `share/march/simd.march`): one `<op>_<t>` wrapper per builtin with
  refinement-typed lane indices (`{Int | 0 <= _ && _ < LANES}`) on
  extract/replace, plus `impl Show/Eq/Hash for` each of the five types
  (pure March, written against `extract_*` so both the interpreter and the
  eventual compiled path share the exact same impl bodies). Registered in
  `lib/modules/stdlib_manifest.ml`'s eager `stdlib_file_list` (right after
  `native_array.march`) so it's auto-loaded and covered by the
  `Stdlib_manifest_test` exhaustiveness test.
- **Tests**: new `simd_vector` group in `test/test_stdlib_suite.ml` (13
  cases, t1–t13 from the plan) covering lane order, splat/replace wrap
  behavior, the f32-single-rounding parity witness (`2^24 + 1` rounds back
  to `2^24` under true f32 arithmetic — this is the case that would catch a
  double-arithmetic-then-round-once emulation bug), i32 wraparound, the
  minNum NaN rule, sequential-sum (expected constant computed in OCaml at
  test time via `f32_round`, not hand-typed), compare/mask/select, a u8
  byte-scan (find a delimiter via `eq_u8x16` + `first_set_u8x16`),
  load/store round-trip with an explicit COW witness (aliased binding held
  across a `store_f32x4` sees the ORIGINAL array unchanged), a load bounds
  panic (asserted via `Eval_error` catch, since the interpreter doesn't
  have a Result-wrapping bounds-check helper to reuse), Show/Eq/Hash
  (Show's exact rendering pinned by running it — `to_string(1.0)` in this
  interpreter renders `"1."`, not `"1.0"`), and actor sendability (an
  `I32x4` crosses a `send`/actor-message boundary and is read back from
  actor state).
- **Type-corpus fixtures**: `specs/lang/types/reject/t171` and `t172` (a
  literal out-of-range lane index on `extract_f32x4`/`extract_u8x16`
  respectively, rejected by the refinement-check pass — same shape as
  `reject/t71`'s `take_n(-3)`), `accept/t173` (the twin: the LAST legal
  lane index for each type). `specs/lang/types/INDEX.md`'s count line
  updated 282→285 (136 accept, 149 reject).
- **Doc-count fallout**: adding `stdlib/simd.march` bumped the stdlib
  module count 112→113; updated the four/five docs that hardcode it
  (`README.md`, `CLAUDE.md`, `docs/stdlib.md`,
  `.claude/skills/march-lang/SKILL.md` ×2) and added
  `doc-lint:ignore-count` markers to the two genuinely historical
  "112 stdlib modules" mentions in `specs/lang/refinement-types.md` and
  `specs/lang/types/INDEX.md` (both describe a blast-radius sweep run on
  2026-08-04, before this module existed).

## Deviations from the brief

- String concatenation in `stdlib/simd.march`'s `Show` impls uses `++`
  (March's actual string-concat operator), not `<>` — the brief's example
  snippet used OCaml's operator by mistake; caught immediately by
  `--check` ("I got stuck here" at the first `<>`).
- `impl Show for F32x4 do` (the brief's example syntax) does not exist in
  March; the real, load-bearing syntax (confirmed against
  `stdlib/decimal.march`, `stdlib/bigint.march`, etc.) is
  `impl Show(F32x4) do`. Used the real syntax throughout.
- Bounds-check test (t11) asserts via catching `March_eval.Eval.Eval_error`
  directly rather than a Result-wrapping helper — no such helper exists for
  native-array-style interpreter builtins, matching the brief's fallback
  instruction ("if none exists, assert on Result-catching wrapper or skip
  the panic assertion interpreted").
- Show's exact string was pinned by running it rather than assumed
  (`"F32x4[1., 2., 3., 4.]"`, not `"F32x4[1.0, 2.0, 3.0, 4.0]"` — this
  interpreter's float-to-string formatting for `to_string` drops the
  trailing zero).

## What's NOT done (compiled path — Tasks 2–5)

No LLVM/runtime-C code was written or touched; no `--compile` tests were
run, per this task's explicit scope. The 127 builtins exist ONLY on the
interpreter path today — a `--compile` build referencing `Simd.*` will fail
(no LLVM lowering, no runtime box, no `march_simd_alloc`/
`march_simd_bounds_panic` helpers). See
`docs/superpowers/plans/2026-08-10-simd-vector-types.md` Tasks 2 (runtime
box + coerce arms + inline op lowerings), 3 (load/store + bounds +
residency fixtures), 4 (dot-product/scanner benchmarks + DataFrame Min/Max),
5 (JS-target rejection + docs + changelog).
