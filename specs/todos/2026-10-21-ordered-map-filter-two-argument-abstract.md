`[P3]` `OrderedMap.filter` carries no entry fact

Filed 2026-10-21 by phase 4 of the multi-arg abstract refinements design
(`specs/2026-10-18-abstract-refinements-multi-arg-design.md` §7.1, §8;
`specs/progress/2026-10-21-abstract-multiarg-phase4.md`). `OrderedMap.filter(m, fn
(k, v) -> …)` keeps no fact about its entries.

Why it is not the `Map.filter` recipe as is: the inner `Tree(k, v)` is entry-shaped and
`tree_filter` calls `f(k, v)` uncurried, the ideal case for a PROVED two-argument
return. But the public type is an anonymous record `{cmp, tree}` (no element slots
through `TyRecord`), and the body routes entries through `tree_min : Option((k, v))`
(tuples) and `balance`.

Options: (a) the `Map.filter` recipe (`@[assume]` on an `OrderedMap(k[p], v[p])`
return, honest annotations for P1, a `Check.all` witness in
`test/stdlib/test_ordered_map.march` shown RED with the predicate inverted); (b) prove
it, which needs element slots through a record type and tuple elements (see
`2026-10-21-tuple-elements-list-of-pairs-abstract.md`).

## 2026-10-26: P1 is fixed; the record is still the blocker (container-gap batch, gap 3)

`Refine_param.align` now walks a declared record against the inferred one
(`specs/progress/2026-10-26-refine-p1-record-parameter.md`), so P1 holds for
`OrderedMap.filter`'s `m : {cmp: k -> k -> Int, tree: Tree(k, v)}` and `OrderedMap.fold`
/ `SortedSet.fold` carry accumulator invariants. `filter` still carries no entry fact,
and this is not a signature problem. Ruling (not soundly doable with bounded work):

- There is nothing to write. The return would be `{cmp: k -> k -> Int, tree: Tree(k[p],
  v[p])}`; the abstract-marker expansion, `has_elem_return`, `elem_ret_assumed`, and the
  demand side (`demand_flow` matches a `TyCon` return against a `TyCon` demand) all stop
  at a `TyRecord`. A caller has no name to demand it with either: `OrderedMap` has no
  public type, so a demand would spell the module-internal `OrderedMap.Tree` inside an
  anonymous record.
- What it would take, either:
  (a) give the public type a name: `ptype OrderedMap(k, v) = OM(k -> k -> Int, Tree(k,
      v))` (or an `opaque type` record), then the `Map.filter` recipe (`@[assume]`,
      `OrderedMap(k[p], v[p])`, a `Check.all` witness), or, since `Tree(k, v)` is
      entry-shaped and `tree_filter` calls `f(k, v)` uncurried, a proof once the body
      no longer routes entries through `tree_min : Option((k, v))`. This is a public API
      change (every signature in `ordered_map.march` names the record, and callers may
      read `.cmp` / `.tree`), so it needs its own decision;
  (b) element entries through record fields in the checker: a record type as an entry
      whose slots are its fields' slots (contenv, `check_elements`, `demand_flow`,
      marker expansion, relations across fields). Larger than this batch, and it touches
      shared element-flow code another builder is editing.
- Pinned by `p1-record` "OrderedMap.filter keeps no entry fact (filed)": a demand through
  `OrderedMap.values(OrderedMap.filter(…, fn (_k, v) -> v > 0))` is recorded and not
  proved.
