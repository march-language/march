`[P3]` A list of pairs `List((k, v))` has no element slots, so no relation over its entries

Filed 2026-10-21 by phase 4 of the multi-arg abstract refinements design
(`specs/2026-10-18-abstract-refinements-multi-arg-design.md` §7.1, §8;
`specs/progress/2026-10-21-abstract-multiarg-phase4.md`). A tuple element is not a
container application, so `List.filter(pairs, fn kv -> …)` over `List((Int, Int))`
carries nothing about the pairs' components, and `List({(Int, Int) | …})` /
`List(({x : Int | true}, {y : Int | y > x}))` is not a relation the checker models.

This is also why `Map.filter` (`entries(m)` is a `List((k, v))`) and
`OrderedMap.filter` (`tree_min : Option((k, v))`) cannot prove an entry fact.

Fix direction: tuple-as-container, treating a tuple type `(A, B)` inside an element
position as an entry of two slots, entry-shaped by construction, so phase 1b's
relations and phase 2's two-argument abstract refinements apply. Then the same recipe:
tests with a REJECT/SKIP control per accept, the refine oracle, and the stdlib sweep.
