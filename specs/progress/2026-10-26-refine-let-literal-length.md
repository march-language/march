# A `let`-bound list literal carries its length (L1)

Landed 2026-10-26 on `claude/refine-length-facts`. No todo tracked it; the source is row 2 of
the 2026-10-24 stdlib refinement audit (the "let-bound list literal" skip source), which drove
15 of the 30 user-code skips in the audit's 67-program sweep (`examples/stats_basic.march`,
every `Stats.*` call on `let temps = [..]`).

```march
fn v1() : Int do
  let t = [1, 2, 3]
  List.head(t)        -- was: unconstrained-subject skip; now proved
end
fn v4() : Int do List.head([1, 2, 3]) end   -- already proved
```

## Root cause

The direct call reflects its literal argument's length at the goal (`Refine_call`'s
`resolve_measure`, `list_len a`). A bare-name argument instead loads the name's SCOPE entry
(`load_scope_measure_facts`) and meets the goal on the memoized `len$t` symbol. A `let`
bound to a literal filed no scope entry at all (`Refine_scope.scope_add_binding` admitted
only an annotation or a call with a postcondition), so `len$t` was unconstrained.

## Fix (`lib/refinecheck/refine_scope.ml`)

`scope_add_binding`: an unannotated `let n = e` whose `e` is a Cons/Nil chain ending in `Nil`
(`list_len_pred`) files `(n, ("_", len(_) == k, Some (meas_sort_name "List")))`: exactly the
entry `refined_scope_ty` gives a parameter `n : {List(_) | len(_) == k}`, so the existing
consumer reads it unchanged. Retirement is the scope channel's own: `scope_shadow` at the
`let` itself and at every later binder (a `let`, a `match` arm, a lambda parameter).
Declined when a user `@[measure]` is named `len` or `List` is not a registered datatype.

## Tests (`gap-let-literal-len`, 7 cases)

RED on the base (`test/test_refinecheck.ml`, each received value):

- `let t = [1, 2, 3]` then `List.head(t)` / `need_len3(t)`: `("skipped", "unconstrained-subject")`, expected proved.
- a let-bound Float literal then `List.head`: same.
- `let t = []` then `need_z(t)`: skipped, expected proved; `let t = Nil` then `List.head(t)`: expected violated.
- nested `let t = [[1, 2, 3], [4]]` then `need_len2(t)`: skipped, expected proved (the
  `need_len3(List.head(t))` half stays not proved: the inner length is not the outer's).
- rebinding control `let t = [1, 2, 3]; let t = [1]; need_len3(t)`: expected a VIOLATION
  (had the old fact survived, `len == 3 && len == 1` would prove anything); `let t = mk()`
  stays unconstrained.
- match-arm shadow control (`Some(t) -> need_len3(t)`): not proved, before and after.
- name capture: `need_same(t : List(Int), ys : {List(Int) | len(_) == len(t)})` called as
  `need_same([9], t)` with a caller `let t = [1, 2, 3]`: expected violated (the callee's `t`
  is `[9]`), and `need_same([7, 8, 9], t)` proved.

GREEN: all 7.

## Oracle

`scripts/refine-oracle.sh check` after this gap: REFINEMENT DIAGNOSTICS IDENTICAL (7873 lines over 552 fixtures). No corpus fixture passes a let-bound literal to a length demand, so the new entry changes no recorded verdict; the 67-program sweep (final report) is where it shows.

## Rulings

- Ruling: a literal's length is filed in the SCOPE channel (as a refined parameter's is), not
  as a path equality — the scope consumer already meets the goal on `len$t`, and the scope
  channel's shadow discipline (`scope_shadow`) already retires on every binder — cost if
  wrong: none for soundness (the fact is the literal's cell count); at worst a consumer that
  ignores `$Meas:` entries misses it (a lost proof).
- Ruling: only a constructor chain counts; `let ys = xs` is not given `len(ys) == len(xs)` —
  an alias is already handled by the other channels and is out of this gap's scope — cost if
  wrong: a lost proof.
