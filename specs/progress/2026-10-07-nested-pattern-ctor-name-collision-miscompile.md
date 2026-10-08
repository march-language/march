`[P1]` Nested constructor pattern on a name the stdlib also uses matched wrongly in compiled code — FIXED

Found 2026-10-07 while writing `test/native/static_nullary_ctor.march` (filed as a
todo on that branch, PR #861; fixed before the todo reached main, so there is no
todo file to move).

## Problem

A user type whose constructors share short names with a stdlib type's
constructors (`Leaf`/`Node`: stdlib `OrderedMap.Tree` declares both) took the
wrong arm for a NESTED pattern on those constructors in compiled code. The
interpreter was right.

```march
type Tree = Leaf | Node(Tree, Int, Tree)
pfn shrink(t : Tree) : Tree do
  match t do
    Leaf -> Leaf
    Node(Leaf, _, Leaf) -> Leaf
    Node(l, v, r) -> Node(shrink(l), v, shrink(r))
  end
end
-- leaves(shrink(make(2))): interpreted 2, compiled 4
```

The emitted LLVM for the nested `case $f of Leaf()` switched on `33554504`
(`OrderedMap.Tree.Leaf`) while `alloc Tree.Leaf` stores `33554515`.

## Root cause

`Lower_match.compile_matrix` mints each field's sub-pattern variable (`$f…`).
`field_ty_at` (lib/tir/lower_match.ml) deliberately leaves it at
`unknown_ty` (`TVar "_"`) whenever ANY row binds that field to a plain name
(`Node(l, v, r)` here): a concrete scalar type there would make the
`let l = $f` rebinding elide the uniform-to-natural untag (the `Result(Int)`
regression documented beside it). The nested `case $f of Leaf` therefore
reached codegen with an erased scrutinee. `Llvm_case.qualified_br_key` can
only qualify a bare tag with a `TCon` scrutinee type, so the bare `"Leaf"`
fell to `Llvm_data.ctor_entry`'s `".<Ctor>"` suffix resolver, which picks
among every type declaring `Leaf` by arity (both are nullary) and then by
hashtable order: `OrderedMap.Tree.Leaf` won. The earlier fix for nested
`Row(..)` patterns (described in `field_ty_at`'s comment: concrete types for
fields no row binds by name) does not reach a field that some row names.

## Fix

- `Lower_match.pat_tag_and_subs`: when the scrutinee variable's type is not a
  `TCon`, take the type the typechecker recorded at the constructor pattern's
  own span (`Lower_state.ty_of_span`), use it for the existing tag-resolution
  logic (collision qualification, module-qualified patterns, reserved monitor
  ctors), and qualify a bare tag with it (`"Tree.Leaf"`). Codegen's
  `qualified_br_key` then hits the exact `ctor_info` key, as it does for a
  top-level scrutinee. The sub-variable's own `v_ty` stays erased, so the
  rebinding untag is untouched. If the qualified key is not found, codegen
  still degrades to the old bare-name path.
- `Llvm_case.emit_case`: the two erased-scrutinee recovery helpers
  (`branches_match_niche_shape`, `newtype_recovery_payload`) compared the raw
  `br_tag` against bare ctor names. They now split a qualified tag into ctor
  and type qualifier, and the qualifier narrows the owning typedefs (so a
  nested `Some(Some(x))` still takes the niche path, and the recovery is more
  precise, not less).

## Other sites checked

- Allocation / FBIP reuse restamp (`Llvm_emit_alloc`, `EAlloc`/`EReuse`):
  keyed by the type-qualified ctor lowering builds from the `ECon`'s type.
  Not affected.
- Equality (`Llvm_eq.ensure_adt_eq_fn`): resolved by TYPE name, unioning
  every same-short-name type's ctors; colliding types have globally unique
  tags, so this is safe. Not affected.
- Show / derived Eq and Show: generated March code, top-level scrutinees are
  typed. Checked with a user `Tree` deriving `Eq` and `Show` (compiled output
  equals interpreted). Not affected.
- Perceus scrutinee free / `perceus_scrut` / borrow / beta_adt / drop / JS:
  only act on a `TCon` scrutinee or compare short names. Not affected.

## Still open (separate bug)

A user type whose TYPE name equals a stdlib one (user `Tree` with a 3-field
`Node`, alongside a call into `OrderedMap`) makes the compiler ICE
(`constructor Tree.Node has 3 field(s) but field index 3 was requested`):
OrderedMap's own scrutinees are typed with the bare `Tree`, which then
resolves to the user's `Tree.Node`. That is the "TCon stays bare" type-name
collision, not this ctor-name one; it predates this change. Filed as
[../todos/2026-10-07-user-type-named-like-stdlib-type-ctor-ice.md](../todos/2026-10-07-user-type-named-like-stdlib-type-ctor-ice.md).

Also found while checking nested `Option` patterns, and also pre-existing: a
`Float`-returning match over `Option(Option(Float))` returns garbage compiled.
Filed as [../todos/2026-10-07-option-option-float-return-garbage.md](../todos/2026-10-07-option-option-float-return-garbage.md).

## Verification

- Fixture `test/native/nested_pattern_ctor_name_collision.march` (+ `.expected`
  = interpreter output; dune rule in `test/dune`): top-level match on the
  colliding ctor, one- and two-level nesting, a colliding ctor with fields as
  the nested pattern, nesting inside a let-bound tuple, a record field and an
  `Option` payload. RED on the unfixed compiler (4 of 20 lines differ:
  `shrink` x2, `left_spine`, `tuple_case`), GREEN after.
- `scripts/run-tests.sh -q compiler codegen` (exit 0: 1290 + 675 tests);
  `test/run_snapshots.exe` (57 tests, no TIR snapshot changed).
- Spot checks, compiled == interpreted: derived `Eq`/`Show` on the colliding
  `Tree`, FBIP reuse in a rebuilding match, nested `Some(Some(n))`,
  `Ok(Some(n))`, `Cons(W(n), rest)` over a newtype, `Some(Red)` over an enum,
  and a tuple column mixing `Option` and an enum.
- Audit baseline lines added to `test/refine_audit/corpus.baseline`.
