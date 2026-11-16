`[P4]` Refinement: indexed fold invariants (`_ == len(xs)`) are not provable

Filed 2026-10-18 with phase 2 of `specs/2026-10-18-fold-accumulator-invariants-design.md`
(§7, "Indexed invariants"). The fold rule (phases 1-2) instantiates the accumulator's type
variable with a FIXED invariant `{b | D}`: every value the fold holds meets `D`. A property
that relates the accumulator to the part of the list consumed so far is not of that form:

```march
fn count(xs : List(Int)) : {Int | _ == len(xs)} do
  List.fold_left(xs, 0, fn (n, _x) -> n + 1)    -- not provable: `n + 1 == len(xs)` is no invariant
end
```

Liquid Haskell states it with an abstract refinement indexed by the consumed prefix
(`foldr :: forall <p :: L a -> b -> Prop>. (xs:_ -> x:_ -> b<p xs> -> b<p (C x xs)>) -> …`),
which needs the step to RECEIVE that prefix. March's folds do not pass one, so this needs
either a prefix-passing fold signature or a definition-side induction over the fold body
(design §1 option (ii), rejected for v1). Today such a demand is a skip, never a false proof:
a relational demand is not traced at all yet (`2026-10-18-refine-relational-scalar-demand.md`),
and once it is, the fixed reading's step `n == len(xs) ⇒ n + 1 == len(xs)` is refuted.

## Compare two encodings before choosing an API (2026-11-07)

[Abstract Refinement Types](https://goto.ucsd.edu/~rjhala/papers/abstract_refinement_types.html)
is the starting point for indexing an accumulator relation by traversal progress.

1. Prototype a definition-side inductive summary for the existing `fold_left`: base case at
   the empty prefix; step from `P(prefix, acc)` to `P(prefix ++ [x], step(acc, x))`; result at
   the entire input. The prefix is logical state; do not construct runtime prefixes or incur
   quadratic traversal. A ghost index can cover length-only properties, not every content law.
2. Compare with a separate indexed/prefix-aware combinator whose signature exposes the required
   relationship. State the cost and erasure rules if a prefix argument is ghost. Do not change
   the ordinary fold's runtime API merely to make the proof rule convenient.
3. Measure both on count/length, sum of a mapped list, and reverse via an accumulator. Include
   an off-by-one initial value and a bad callback, proving both base and preservation checks
   are necessary. Reject any circular use of the desired fold postcondition.

Keep the present fixed-invariant path unchanged. Select an encoding only after these examples
show the additional annotations, solver cost and compatibility with higher-order callbacks.
