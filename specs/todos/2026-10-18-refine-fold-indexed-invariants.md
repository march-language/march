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
