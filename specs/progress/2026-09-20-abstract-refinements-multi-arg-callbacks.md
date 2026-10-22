# `[P3]` Abstract refinements: a callback of more than one argument cannot define one

**Closed 2026-10-21** by the multi-arg abstract refinements design
(`specs/2026-10-18-abstract-refinements-multi-arg-design.md`), phases 1a-4
(`specs/progress/2026-10-21-abstract-multiarg-phase{1a,1b,2,3,4}.md`). A callback of
two arguments is a curried chain `k -> v -> Bool[p]` defining a `p` of two, and a
return relates two sibling slots through it (`Assoc(k[p], v[p])`); the partial-demand
question is answered by projection (a demand on the values alone is proved from
`p(k, v)` with a fresh key). `Map.filter` now carries it, ASSUMED (phase 4):
`@[assume] fn filter(m : Map(k, v), pred : k -> v -> Bool[p], cmp : k -> k -> Bool)
: {Map(k[p], v[p]) | subset(keys(_), keys(m))}`, with a runtime property witness in
`test/stdlib/test_map.march`. The fold bullet was dropped earlier (below). What is
still out of scope is filed: `specs/todos/2026-10-21-map-element-flow-through-combinators.md`,
`…-hashmap-filter-two-argument-abstract.md`, `…-ordered-map-filter-two-argument-abstract.md`,
`…-tuple-elements-list-of-pairs-abstract.md`. One correction to the text below:
`Map.filter`'s callback is `k -> v -> Bool` (curried), not `(k, v) -> Bool`, which
in March is a callback of ONE tuple argument.

The original item, as filed:

Filed 2026-09-20 alongside `specs/2026-09-20-abstract-refinements-design.md`
(decision §9.3). An abstract refinement is defined by a one-argument callback's
codomain (`keep : ({x : a | true}) -> {Bool | _ == p(x)}`), so a combinator
whose callback takes two arguments cannot state one:

- `Map.filter`'s callback is `(k, v) -> Bool`, so a filtered map carries no
  fact about its remaining entries.

(`List.fold_left`'s `(b, a) -> b`, the other shape this item used to list, is
not an abstract refinement at all: its accumulator invariant shipped through
parametricity instead, `specs/2026-10-18-fold-accumulator-invariants-design.md`
phases 1-2, `specs/progress/2026-10-18-fold-invariants-phase2.md`.)

A two-argument definer binding only its first argument was considered and
rejected in review as a half-measure: it would silently drop what the predicate
says about the second argument while looking like it covered the case.

What this needs: predicates of arity > 1 (`p(k, v)`), which means an
instantiation rule over several binders and a decision about what a partial
demand (`D` mentioning only the value) means. Do not start it before the
one-argument rule has landed through phase 3 of the design and the stdlib has
used it.
