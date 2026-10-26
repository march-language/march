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

## 2026-10-26 design note: what it would take (container-gap batch, gap 4; not done)

Ruling: not attempted in the container-gap batch. It cannot be made sound with bounded
work there: it is a new element kind threaded through every element-flow site, in
shared code another builder was editing at the same time. The cost of waiting is lost
proofs only.

What it needs, measured against `lib/refinecheck` at `547552b57`:

1. **A representation.** `Refine_scope.elem` is `Refined | Container of entry`. A pair
   element needs its components as slots and relations between them. The cheapest
   sound form is a pseudo-container entry, `{ cont = "$Tuple2"; slots = [a; b]; rels }`,
   built by `elem_refinement` from `TyTuple [A; B]` in an element position. It reuses
   the relational machinery of multi-arg phase 1 (R1). Every consumer that matches on
   `entry.cont` against a registered container (`follow`, `entry_implies`, the
   subtyping query, `is_container_type`) must accept or reject the pseudo-name
   explicitly. A silent fall-through would read a tuple as an unknown container, which
   is a lost fact today but a false one if a default arm treats it as "no slots, so
   vacuously true".
2. **Establishment** (each a soundness obligation):
   - a literal `[(1, 2)]` checks each component;
   - a `match` arm `(k, v) ->` on an element lends each component its slot;
   - `let (k, v) = pair` likewise;
   - a hidden-field construction stays a skip (phase 0's rule extends unchanged).
3. **Flow.**
   - `container_paths` must descend `TyTuple` as `($Tuple2, j)` path steps, so
     `zip(xs : List(a), ys : List(b)) : List((a, b))` and `unzip` get sources.
   - `demand_flow`'s `pair` must match a `TyTuple` return against a `$Tuple2` demand.
   - `agreed_elem_slot` must follow a `$Tuple2` step.
   - The phase-1b ruling stays: no relation is carried through a generic function.
4. **Abstract refinements over a pair** (`List.filter(pairs, fn kv -> …)`). A tuple
   domain is ONE argument (multi-arg §1.1), so `p` is unary over a tuple. The lambda
   translator must then read `match kv do (k, v) -> … end` (today declined: "a `match`
   on anything but a Bool"), or `Tuple.first`/`second` (declined: a call with no proved
   contract). Each component's fact is a projection of `p`.
5. **SMT.** A slot fact over a pair element needs two fresh constants per element and
   the relation over both. This is the R1 encoding with the tuple's components as the
   entry's slots. No new theory is needed.
6. **Tests.** Every row needs a reject or skip control: literal, `match`, `zip`,
   `List.map` to pairs, `filter` over pairs. Run the refine oracle and the stdlib sweep,
   because `List((k, v))` is everywhere in `Map`, `OrderedMap` and `HashMap` bodies, so
   new facts there can turn skips into violations.

Once it lands, `Map.filter`'s `@[assume]` could be replaced by a proof only if `insert`'s
entry flow (now parametric, `2026-10-26-map-element-flow.md`) also carries the relation
between key and value, which the phase-1b ruling forbids for a generic function. So the
assumed entry stays even after tuples are modelled.
