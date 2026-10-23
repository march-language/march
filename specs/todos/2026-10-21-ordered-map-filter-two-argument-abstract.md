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
