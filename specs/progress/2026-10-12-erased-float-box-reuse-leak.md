# Erased-slot Float box leaked when a match branch reuses its cell (FBIP)

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): 7 fixtures reported
`march_alloc_float < march_string_to_float < Json.parse_number`.

## The bug

`Option(Float)` is niche-unsafe, so a `Some` cell holds its payload as a
`march_alloc_float` box in an erased slot. `lib/tir/llvm_case.ml` already binds
such a field as a raw double and releases the box on the `march_decrc_freed`
path when the branch starts with `dec_rc scrut`
(`2026-10-06`'s erased-float-slot fix). It exempted branches whose body REUSES
the scrutinee cell (FBIP), keeping the box-typed binding there. On that path
nothing released the box:

- `Some(f) -> Ok(f)` (generic RC-checked reuse): `f` re-boxed into the reused
  cell, old box orphaned.
- `Some(f) -> N(f)` with `N(Float) | Z` (niche-shaped target: release + fresh
  cell): the double stored inline, the old box orphaned when the release freed
  the cell.
- `Some(f) -> KN(f)` with a three-ctor `K`, after inlining (`let o = $t; case o`
  with the reuse token `$t`): the reuse took the "token is its own niche
  payload" guard in `Llvm_emit_alloc`, which allocates fresh WITHOUT touching
  the token — but a boxed `Option(Float)` token is a real cell, so the cell
  and its box both leaked.

`Json.parse_number` is `Some(f) -> Ok((Number(f), e2))`: one box per number.

## The fix

- `llvm_case.ml`: an erased-slot Float/aggregate field is always bound as a
  copy. When the body reuses the scrutinee (or a `let` copy of it — tracked by
  the new per-function `Llvm_ctx.let_alias`), the boxes go into
  `Llvm_ctx.reuse_orphan_boxes`, keyed by the scrutinee's alias root, for the
  branch body's duration.
- `llvm_emit_alloc.ml`: every reuse emitter releases those boxes exactly where
  the cell is taken over or freed — the in-place arm of the RC-checked ctor,
  uniform and TRMC-hole reuses, and (via `march_decrc_freed`) the newtype and
  niche-target arms. Never on the shared/fresh arm, where the surviving cell
  still owns the box.
- The niche-token guard now applies only when the token really is niche-encoded
  (`Kind.repr_of` of the token's instantiated type is not `Boxed`); a boxed
  token takes the RC-checked path.

## Verification

- `test/native/erased_float_reuse_leak_probe.march`: four reuse shapes
  (niche target, boxed target, erased target, identity rebuild) plus
  `Json.parse` over 2,000 iterations each — every `live_allocs()` delta was
  4,000 to 10,000 before, 0 after. Its shared legs reuse a cell with RC > 1
  (double-free witnesses).
- ASAN error sweep (339 native fixtures × 1 and 14 schedulers, Linux arm64)
  re-run on the fixed compiler: same verdicts as before the change.
