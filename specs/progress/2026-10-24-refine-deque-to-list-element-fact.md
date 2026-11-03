# A `Deque(a[p])` element fact survives `Deque.to_list`

Landed 2026-10-24. Closes `specs/todos/2026-10-21-refine-deque-to-list-element-fact.md`
(moved here) and, with the same fix, `specs/todos/2026-10-21-refine-qualified-container-param-entry.md`
(moved to `specs/progress/2026-10-24-refine-qualified-container-param-entry.md`).

```march
fn dfilter(d : Deque.Deque(a), pred : a -> Bool[p]) : Deque.Deque(a[p]) do Deque.filter(d, pred) end
fn go(d : Deque.Deque(Int)) : Int do sum_pos(Deque.to_list(dfilter(d, fn y -> y > 0))) end
```

Before: `sum_pos` a `parametric-source-unproved` skip ("the elements of argument 1 of
`Deque.to_list` is not known to satisfy it"). Now: proved, and `dfilter`'s own return is
proved.

## Root cause

Not Deque's representation, not `to_list`'s body, and not a missing stdlib annotation. The
parametric rule already carries a `Deque` argument's element fact through `to_list : Deque(a)
-> List(a)`: the `Deque(Int, List(a), List(a))` fields are `Within` roles (leftovers phase
E), and `sum_pos(Deque.to_list(Deque.filter(d, fn y -> y > 0)))` was already proved on the
base. What failed is the user's SPELLING `Deque.Deque`. The checker's container registry
(`adt_ctors`, `ctor_param_fields`) is keyed by `adt_sort_name`, which mapped `Deque.Deque` to
`M_Deque.Deque`, a key nothing registers (the declaration is filed under `M_Deque`). So
`is_container_type "Deque.Deque"` was false: `dfilter`'s return `Deque.Deque(a[p])` had no
abstract slot (`abstract_slot_of_ty`), a `d : Deque.Deque({Int | _ > 0})` parameter had no
container entry (`elem_refinement`), and the argument of `to_list` was never a known
source. The qualified-param todo described the same failure for `Queue.Queue` and a
user-nested `Dk.Dk`.

## Fix

- `Refine_encode.canonical_type_name`: a dotted name `M.T` becomes the bare `T` exactly
  when ONE module path declares a variant `T` anywhere (`adt_decl_paths`, recorded by
  `register_adt_names`) and the qualifier `M` is that path or a dot-suffix of it (`Dk.Dk`
  written inside `PQual` for `PQual.Dk`). Otherwise the name is unchanged, i.e. unknown as
  before. `adt_sort_name` canonicalises first, so `is_container_type`, `ctor_hidden_params`
  and every sort lookup agree on the qualified spelling.
- The places that store a container's NAME use the canonical spelling, so a qualified
  annotation and the callee's `Deque(a)` compare equal: `Refine_scope.elem_app` (an entry's
  `cont`), `Refine_check.abstract_slot_of_ty` (`sl_container`) and
  `Refine_param.container_paths` (a source's path).
- No stdlib change: `Deque.to_list` needed no annotation (and so there is no
  `@[assume]`), and `Deque.filter`'s `Deque(a[p])` was already proved.

## Tests (group `gap-deque-to-list`, 7 cases)

RED on the O1 commit (`529aa43c2`) + this group: 3 failing, the controls passing.

| # | Case | RED on base | Now |
|---|---|---|---|
| 0 | the todo's `to_list(dfilter(d, fn y -> y > 0))` | `[("skipped", "parametric-source-unproved")]` | proved (and `return of dfilter` proved) |
| 1 | `d : Deque.Deque({Int \| _ > 0})`, `sum_pos(Deque.to_list(d))` | `[("skipped", "parametric-source-unproved")]` | proved |
| 2 | `let ys = Deque.to_list(d); sum_pos(ys)` | `[("skipped", "unreflectable-subject")]` | proved (under the subject `ys`) |
| 3 | unrefined `Deque.Deque(Int)` | control | a skip, not a violation |
| 4 | `Deque.Deque({Int \| _ >= 0})` into `_ > 0` | control | not proved |
| 5 | two modules declaring `Bx`, `A.Bx({…})`; one declarant | ambiguous: control; one declarant: new | ambiguous a skip; one declarant proved |
| 6 | too-weak `dfilter(d, fn y -> y >= 0)` | control | not proved |

(Case 2's assertion was relabelled to the subject `ys` the proved obligation records under;
on the base the skip was recorded under `sum_pos`, so it still fails there.)

Edited existing test, deliberately: `stdlib-refine-sweep` "a Queue.Queue-typed parameter"
was a `skip_with … "parametric-source-unproved"` pin of the qualified-param gap ("that row
flips when this is fixed"); it is now a `proof`, with a new control (a
`Queue.Queue({Int | _ >= 0})` parameter into `_ > 0` is not proved).

`scripts/run-tests.sh refinecheck`: before that edit, the only failure was that pinned row
(1615 tests); green after it.

Stdlib-signature trap: no stdlib file changed, so no annotation can typecheck to an internal
error; the full suite was run at the end of the branch anyway.

## Oracle

Baseline from the unmodified base (8742 lines over 551 fixtures), private `HOME`:
`REFINEMENT DIAGNOSTICS IDENTICAL (8742 lines over 551 fixtures)`. No corpus fixture writes
a module-qualified container with an element refinement, so nothing could move; in
particular no sort lookup of a qualified spelling changed any verdict. `stdlib/list.march`
ratchet: 37 skipped, unchanged.

## Rulings

- Ruling: resolve `M.T` only when exactly one module path declares `T` and `M` is that path
  or its dot-suffix — the registry is keyed by bare names, and an ambiguous bare name has
  per-declarant qualified keys whose module paths need not match how the user qualified it,
  so a guess could read one module's constructors for another's type — cost if wrong: an
  ambiguous container stays a skip (pinned: `A.Bx` with two `Bx`), never a false proof.
- Ruling: canonicalise in `adt_sort_name` (every consumer), not only in the element paths —
  `is_container_type`, `ctor_hidden_params` and `ctor_param_fields` are all keyed through it,
  and a half-resolved name (container yes, hidden parameters no) would be the inconsistent
  state — cost if wrong: a qualified type's SMT sort is now its real datatype sort where it
  used to be an unregistered name; the oracle shows no fixture moved.
- Ruling: a dot-suffix qualifier is accepted (`Dk.Dk` for `PQual.Dk`) — the typechecker has
  already resolved the qualified name to a declaration, and with a single declarant of `Dk`
  there is no other candidate — cost if wrong: a non-variant type (a record or alias) named
  `M.Dk` in a module whose path ends in `M` would be read as the variant; both would have
  to be declared under the same module name.
