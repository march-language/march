# Simd vector types — Task 2: compiled core (runtime box, coerce, inline lowerings)

Task 2 of `docs/superpowers/plans/2026-08-10-simd-vector-types.md` (gitignored;
ledger at `.superpowers/sdd/2026-08-10-simd-vector-types/`). Builds on Task 1
(interpreter path — see `specs/progress/2026-08-10-simd-vector-types-task1-interpreter.md`).

Landed the compiled core for the five 128-bit SIMD vector types
(F32x4/F64x2/I32x4/I64x2/U8x16):

- `runtime/march_runtime.h`: `MARCH_SIMD_TAG = -4`.
- `runtime/march_runtime.c`: `march_simd_alloc(kind)` (32-byte leaf box,
  payload at +16, 16-aligned; freed by the ordinary rc==0 path, no special
  tag case needed — it's a leaf cell) and `march_simd_bounds_panic`, used
  by the load/store bounds checks below.
- `lib/tir/llvm_ctx.ml`: `vec_tys`/`is_vec_ty`/`simd_kind_of_vec` + two
  `coerce` arms (vector ↔ `ptr`, box/unbox via `march_simd_alloc`), placed
  ahead of the existing `("ptr", scalar)`/`(scalar, "ptr")` generic arms —
  those match any type pair textually and would otherwise silently
  ptrtoint/inttoptr a vector value.
- `lib/tir/llvm_emit.ml`:
  - `decode_simd_call` + `simd_tys` table + narrow/widen/intrinsic-suffix
    helpers, and the `Simd` intercept arm (before the general `EApp` arm)
    lowering every `simd_<t>_<op>` builtin, INCLUDING `load`/`store`, to
    native LLVM vector instructions/intrinsics/GEPs — register-resident,
    no runtime call (`load`/`store` do call the existing
    `<w>_arr_length`/`<w>_arr_alloc_raw`/`march_decrc`/`march_simd_bounds_panic`
    runtime functions, same as `NativeArray` itself). `load`/`store` were
    originally scoped to Task 3 with a `failwith` placeholder here, but
    were pulled forward into this task after discovering that placeholder
    made ANY whole-stdlib compile fail — see "load/store: pulled forward"
    below.
  - `ELet` gets a vector-typed fast path: when the RHS's emitted type
    `is_vec_ty`, the let slot allocas the vector type itself (16-aligned)
    instead of routing through `llvm_ty`/`coerce` (which would box to `ptr`
    on every local binding) — `var_llvm_ty` records the vector type so the
    existing `AVar` load path reads it back native.
  - A hard-fail guard in the general `EApp` arm: any `simd_<t>_<op>` name
    that reaches it (i.e. slipped past the intercept arm above) raises —
    unreachable by construction, cheap insurance against the coerce
    catch-all class of bug.
  - Extended the `==`/`!=` comparison codegen (`is_int_cmp` arm) with a
    SIMD-vector branch: the general ADT-structural-equality synthesizer
    (`ensure_adt_eq_fn`) walks a `type_def`'s fields, but the 5 vector types
    are opaque compiler primitives with no `type_def`/fields (their "fields"
    are vector lanes) — without this, `Simd.make_f32x4(...) == ...` would
    fall through to the raw i64/ptr fallback and reinterpret the vector
    register as a scalar (an LLVM type mismatch at `clang -c`, not a
    runtime bug). Lowers to a per-lane `fcmp oeq`/`icmp eq` then an
    all-lanes-equal reduction — needed for `t12`'s compiled `==`/`!=` on
    `F32x4` (`impl Eq(F32x4)` and friends are plain March using this
    operator).
- `lib/tir/llvm_builtins.ml`: `PDeclare` rows for `march_simd_alloc`/
  `march_simd_bounds_panic` only — the 127 `simd_*` ops get no table rows,
  no declares (they never appear as a runtime call). Added to both
  `native_actor_items` and `wasm_scheduler_stub_items` (matching the
  existing `march_alloc_float` duplication — unconditional presence
  regardless of target, since the `coerce` vector-box arm can fire on
  either).
- `test/test_codegen.ml`: `test_simd_vector_ir` (asserts `add` lowers to
  `fadd <4 x float>`, `sum` to `llvm.vector.reduce.fadd`, and — the
  regression this task's hard-fail guard exists to catch — that
  `call ptr @simd_f32x4_add` never appears); golden preamble mirrors
  (`golden_preamble_native_actor`/`golden_preamble_wasm_stub`) updated with
  the two new declares.
- `test/native/simd_vector_core.march` + `.expected` + `test/dune` rule:
  compiled/interpreted parity fixture covering t1-t8 + t12 from
  `test_stdlib_suite.ml`'s `simd_vector` suite (make/extract lane order,
  splat/replace, wrap-on-ingest, f32 single rounding, i32 wrap, minNum NaN
  rule, sequential sum/hmin/hmax, compares/masks/select/first_set,
  and/or/xor/not/shl/shr, u8x16 lane-16 make + unsigned compares, fma/div,
  f64x2/i64x2, Show/Eq/Hash, plus a minimal load/store leg (byte scan via
  `Simd.load_u8x16`, store-round-trip + FBIP-COW witness)) — byte-identical
  compiled vs. interpreted output. Full t9/t11 bounds/residency coverage
  and t13 (actor sendability) stay Task 3's dedicated fixtures
  (`simd_vector_mem.march`/`simd_residency.march`/`simd_bounds_panic.march`
  per `task-3-brief.md`); this fixture's load/store leg is a correctness
  smoke test, not a substitute. Verified separately (ad hoc, not wired
  into a dune rule) that an out-of-bounds `Simd.load_f32x4` compiled
  binary panics with the correct stderr message and exit 1.

**Verified LLVM intrinsic spellings** (clang 17, `clang -O2 -c <ir> -o /dev/null`):
`llvm.vector.reduce.fadd.v4f64`/`.v2f64`, `llvm.vector.reduce.add.v4i64`/
`.v2i64`, `llvm.minnum.v4f32`/`.v2f64`, `llvm.maxnum.v4f32`/`.v2f64`,
`llvm.smin.v4i32`/`.v2i64`, `llvm.smax.v4i32`/`.v2i64`, `llvm.fma.v4f32`/
`.v2f64`, `llvm.sqrt.v4f32`/`.v2f64`, scalar `llvm.minnum.f32`/`.f64`,
`llvm.maxnum.f32`/`.f64`, `llvm.smin.i32`/`.i64`, `llvm.smax.i32`/`.i64`,
`llvm.cttz.i64`; `bitcast <N x i1> to iN` (N=2,4,16) and `icmp eq/ne iN
<const>` for arbitrary-width integer types; the ordered
`llvm.vector.reduce.fadd(double 0.0, <N x double>)` form (no `reassoc`
flag) is sequential per LangRef, matching the interpreter's
`Array.fold_left (+.) 0.0`.

**`load`/`store`: pulled forward from Task 3, implemented here.** The
brief's original Task 2/3 split deferred `load`/`store` to Task 3 with a
"lands in Task 3" `failwith` placeholder in the intercept arm. That was
wrong: `test_cap_ceiling` (part of `run_compiler`'s test suite) compiles
main-less modules with the **whole stdlib** prepended, which means
compiling `stdlib/simd.march`'s `load_*`/`store_*` wrapper *function
bodies* — triggering the `failwith` on every whole-stdlib compile, whether
or not the compiled program itself calls those ops. A "fail only if
reached" deferral can't survive being unconditionally *defined* as part of
the stdlib. Implemented instead, per `task-3-brief.md`'s Step 2 recipe:
bounds check (`<s_arr_prefix>_length` call, `icmp`+branch to a panic block
calling `march_simd_bounds_panic`+`unreachable`, matching
`simd_bounds_check`'s `0 <= i && i+lanes <= len`), then `load` = GEP
`arr+32+i*elem_size` + `load V align elem_size`; `store` = the same FBIP
contract as `native_f32_arr_set` (rc==1 → in-place store; else
`alloc_raw` + `llvm.memcpy` the payload + store + `march_decrc` the
original), with the rc==1 test modeled on the existing `EReuse` FBIP arm's
`load atomic i64 ... monotonic` + `icmp eq i64 %rc, 1` pattern.

**Pre-existing bug found, out of scope, flagged separately**: compiled
Float `!=` on NaN is wrong (`fcmp one` is false whenever either operand is
NaN; the interpreter's `!=` is a plain OCaml `<>`, true for `nan <> nan`).
Unrelated to SIMD — the fixture routes around it (uses `==` instead of
`!=` for its one NaN-detection case). Flagged as a spawned background task
during this session.

Gates: `scripts/run-tests.sh` and `dune build --root . @test/runtest` both
green — first pass (load/store still deferred) missed `test_cap_ceiling`'s
whole-stdlib-compile failure; re-run after implementing load/store, both
exit 0 (see the Task 2 report for exact commands/logs).

Not done (Tasks 3-5, still open — see
`specs/todos/2026-08-10-simd-vector-types-compiled-path.md`): the
dedicated residency (`--emit-llvm` register-residency grep rules) and
bounds-panic/COW fixtures Task 3 was also scoped to (load/store lowering
itself is now done, above), validation kernels/DataFrame fast path,
JS-target rejection + docs/changelog.
