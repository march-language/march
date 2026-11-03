Refinements: P1 sees through a record-typed parameter (`SortedSet.fold`, `OrderedMap.fold`); `OrderedMap.filter` filed

Closes `specs/progress/2026-10-18-refine-p1-record-typed-parameter.md` (moved from
`specs/todos/`). Container-gap batch, gap 3 of 4 (`OrderedMap.filter`), branch
`claude/refine-container-gaps`. `OrderedMap.filter` itself is NOT done; the reason
is recorded in `specs/todos/2026-10-21-ordered-map-filter-two-argument-abstract.md`.

## Root cause

`Refine_param.align` (P1, `generic_in_inferred`) walked a declared parameter type beside
the inferred one, with cases for type variables, constructors, tuples and arrows only. A
declared record that mentions a type variable (`s : {cmp: a -> a -> Int, tree:
AvlTree(a)}`) fell to the last arm (`ty_vars [] d = []`, false), so the whole function was
"not generic" and every demand through `SortedSet.fold` / `OrderedMap.fold` (and a user
fold over a record parameter) was `parametric-source-unproved`. A lost proof, never a
false one.

## Fix

One `align` case in `lib/refinecheck/refine_param.ml`: `A.TyRecord dfs` against
`T.TRecord tfs` when both have the same number of fields, each declared field aligned
with the inferred field of the same name (a missing name answers no). Every type
variable inside a field is then recorded like any other, so P1's "one unbound variable
per declared variable, occurring nowhere else" check applies unchanged.

## `OrderedMap.filter` (the gap this was meant to unblock)

Ruling: not done, filed with the reason. Why: P1 now holds for it, but its public type is
an anonymous record `{cmp, tree: Tree(k, v)}`. A record has no element slots: the marker
expansion, the assumed-return table and `demand_flow` all stop at a `TyRecord`, and a
caller has no type name to demand it with. Making it work needs either a named public
type (an API change to every signature in `ordered_map.march`) or element entries
through record fields in the checker (shared element-flow code). Cost if wrong: a lost
fact only; a demand through it stays a recorded skip, pinned by a test.

## Tests

New group `p1-record` in `test/test_refinecheck.ml` (10 cases, the batch's
`container_gap_harness` over the real `list.march`, `sorted_set.march`,
`ordered_map.march`). RED before the `align` case: `7 failures! in 0.224s. 10 tests run.`

| # | Case | RED | GREEN |
|---|---|---|---|
| 0 | user `rf(s : {t: List(a)}, acc : b, f : b -> a -> b) : b` (body `List.fold_left(s.t, acc, f)`), `need_nn(rf({t: xs}, 0, fn (a, _x) -> a + 1))` | `(1,0,0)` → `(0,0,1)` | proved |
| 1 | the tuple twin `tf(s : (List(a), Int), …)` | passes (control: tuples already aligned) | proved |
| 2 | P1 perturbation: `bad(s : {t: List(a)}, acc : b, _f) : b` whose body returns an element of `s.t` as the result (so `a` unifies with `b`) | passes | not proved |
| 3 | `rf` with `a - 1`: `accumulator-step-unproved` | fails (base: parametric-source-unproved) | step skip |
| 4 / 5 | `SortedSet.fold` proof / decreasing-step control | fail | proved / step skip |
| 6 / 7 | `OrderedMap.fold` proof / control | fail | proved / step skip |
| 8 | name capture: caller params `t`, `acc`, a lambda binder `s`, all named like the callee's own | fails | proved |
| 9 | `OrderedMap.filter` keeps no entry fact (pinned, filed) | passes | not proved |

Case 2 is shown to guard P1: with `generic_in_inferred` forced to answer yes, it FAILS
(`ASSERT not proved`; the demand on `bad({t: [0 - 5]}, …)`, which returns `-5`, was
proved), and passes again once restored.

`fold-invariants-3`: the two `skip_pin` rows for `SortedSet.fold` / `OrderedMap.fold`
(`parametric-source-unproved`) are flipped to a proof and a decreasing-step control
each, as the todo asked (`Test Successful … 22 tests run.`).

## Verification

- Refine oracle: baseline at `547552b57` (gap 2 committed), check after:
  `REFINEMENT DIAGNOSTICS IDENTICAL (8738 lines over 552 fixtures)`. No corpus program
  folds a `SortedSet`/`OrderedMap` or a record parameter under a demand. The oracle was
  not separately perturbed for this gap: the same script and tree went red on gaps 1
  and 2 of this batch (2212 and 6 differing lines), and the test-level P1 perturbation
  above shows the new case is guarded.
- Docs: `specs/lang/refinement-types.md` moves `SortedSet.fold` / `OrderedMap.fold` from
  the "do not carry it" list to the fold list; regenerated `docs/refinement-types.md`.
