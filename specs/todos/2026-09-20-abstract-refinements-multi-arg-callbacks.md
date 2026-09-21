# `[P3]` Abstract refinements: a callback of more than one argument cannot define one

Filed 2026-09-20 alongside `specs/2026-09-20-abstract-refinements-design.md`
(decision §9.3). An abstract refinement is defined by a one-argument callback's
codomain (`keep : ({x : a | true}) -> {Bool | _ == p(x)}`), so a combinator
whose callback takes two arguments cannot state one:

- `Map.filter`'s callback is `(k, v) -> Bool`, so a filtered map carries no
  fact about its remaining entries;
- `List.fold_left`'s `(b, a) -> b` is the other shape, where the interesting
  statement is an *invariant* on the accumulator (a negative occurrence),
  which needs its own soundness argument rather than the element rule.

A two-argument definer binding only its first argument was considered and
rejected in review as a half-measure: it would silently drop what the predicate
says about the second argument while looking like it covered the case.

What this needs: predicates of arity > 1 (`p(k, v)`), which means an
instantiation rule over several binders and a decision about what a partial
demand (`D` mentioning only the value) means. Do not start it before the
one-argument rule has landed through phase 3 of the design and the stdlib has
used it.
