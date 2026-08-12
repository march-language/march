# `==` on a variant/tuple/record field of an opaque type used pointer identity

**Fixed:** 2026-08-12

## Bug

`lib/tir/llvm_eq.ml`'s per-ctor field-equality codegen (the field-compare
loop inside the resolved-ctor-table branch of `ensure_adt_eq_fn`, around
line 462) handles a ctor field typed `TCon _ | TTuple _ | TRecord _` by
recursively deriving that field's own structural-equality function via
`ensure_adt_eq_fn`. When that recursive call returns `None` — no `type`
declaration exists for the field's type, e.g. a compiler-builtin type
constructor like `Task`, `Pid`, or `WorkPool`, or (on branches carrying the
SIMD vector-types feature) `F32x4`/`F64x2`/`I32x4`/`I64x2`/`U8x16` — the code
fell back to a raw pointer-identity compare (`ptrtoint` both operands,
`icmp eq`) instead of `march_poly_eq`, the runtime-shape-dispatched
comparator.

The sibling arm ten lines below, for a field typed `TVar` (a truly generic/
erased field), already used `march_poly_eq` for exactly this "no eq fn
derivable" situation — added previously to fix `List(a)` structural equality
for generic containers of strings. The `TCon`/`TTuple`/`TRecord` arm's
`None` case never got the same treatment, so two distinct heap allocations
holding identical content for an opaque-typed field compared as NOT equal.

Net effect: `{ v : F32x4 }`-shaped records (or any record/tuple/ADT-ctor
field whose type has no March-level `type` declaration) would report `==`
as `false` for two structurally-identical-but-distinct values, unless the
compiler happened to share the exact same allocation.

## Fix

Changed the `None` branch of the `TCon _ | TTuple _ | TRecord _` field-eq
arm in `ensure_adt_eq_fn`'s ctor-table field loop to emit a call to
`march_poly_eq(ptr %fva, ptr %fvb)`, matching the `TVar` arm immediately
below it.

## Verification

- Added `test_eq_operator_opaque_ctor_field_uses_poly_eq` in
  `test/test_codegen.ml` (registered under the `newtype_derived_method_crash`
  suite). This worktree does not carry the SIMD vector-types feature (that
  lives on a separate branch), so the repro uses `Task(Int)` — a real
  compiler-builtin type constructor with no March-level `type` declaration —
  as a ctor field of a two-ctor variant (`Holder = HA(Task(Int)) |
  HB(Task(Int))`, deliberately non-nullary on both ctors to stay off the
  Newtype/Niche codegen shortcuts and land in the general ctor-table path).
  The test compiles to LLVM IR (`emit_actor_ir`, no execution needed — the
  bug is about which comparator gets emitted, not runtime behavior of
  `Task`) and asserts the IR contains a `march_poly_eq` call. Confirmed it
  fails pre-fix (`Received: false` — no `march_poly_eq` call emitted) and
  passes post-fix.
- Full `scripts/run-tests.sh`: 845 tests, all green (no regressions).

## Follow-up (not fixed here, out of scope of the reported finding)

Three more instances of the identical `None -> ptrtoint identity` pattern
exist in `lib/tir/llvm_eq.ml`, none reported by the original finding and
left untouched to keep this fix minimal:

- ~line 216-225: the niche/Option-shaped ctor field-compare arm (same bug
  shape as the one fixed here, but for niche-encoded types).
- ~line 546-563: the standalone tuple/record structural-equality generator's
  own field-compare loop has the same `TCon _ | TTuple _ | TRecord _ ->
  None -> ptrtoint` bug, AND its `_` wildcard arm (line 557) does not
  special-case `TVar` the way the ctor-table version's `_` arm does — it
  uses pointer identity for every unmatched field type, including generic
  ones, where it should use `march_poly_eq`.

## Files

- `lib/tir/llvm_eq.ml` — the fallback fix (one field-compare arm).
- `test/test_codegen.ml` — new `test_eq_operator_opaque_ctor_field_uses_poly_eq`
  + registration.
- `CHANGELOG.md` — user-facing `### Fixed` entry.
