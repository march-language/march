# Set refinements strengthening, Phase 3: cardinality by ground instantiation

Landed 2026-09-15. Design: `specs/2026-09-14-set-refinements-strengthening-design.md`
§4; plan: `specs/plans/set-refinements-strengthening-plan.md` (Phase 3, steps
3.1 to 3.3). Phase 4 stays open in
`specs/todos/2026-09-14-set-refinements-strengthening.md`.

## What landed

- **3.1 Vocabulary.** `card(s)` is set vocabulary (well-formed on one set
  operand). `Smt.SetCard of sort * term` renders `(card$<elem> s)`;
  `set_preamble` declares one uninterpreted `card$<elem>` per element sort a
  query uses; `resolve_sorts` types it. `Smt.children` gives a term's direct
  subterms for passes that need no per-constructor logic.
- **3.2 Ground facts.** `Refine_encode.card_facts` runs after sort resolution
  at every query site, only for a query that mentions `card`: non-negative
  counts, `empty` 0, `singleton` 1, add or remove one element by membership,
  union/inter/diff bounds, subset monotonicity, a member implies non-empty,
  and `card(elts$x) <= len$x` (or `$elts`/`$len` of one term). No quantifier.
- **3.3 Contracts.** `Set.size : {Int | _ == card(elts(s))}` and `Map.size :
  {Int | _ == card(keys(m))}`, `@[assume]`d, with property witnesses against
  a distinct-count oracle in `test/stdlib/test_set.march` and
  `test_map.march`. `reflect_scalar` takes a `foreign_measure_call` so a
  scalar contract's measure over a nested call translates.

## Verification

- `cardinality` test group: literal lists, `card <= len`, membership, empty,
  subset monotonicity, `Set.size`/`Map.size` accept cases, the size-2 reject
  control, and the non-set-shape warning.
