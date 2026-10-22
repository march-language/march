# Inference-lite, phase 3: joint abstract-refinement candidates (K6)

Landed 2026-10-21. Design §1.2 row K6, §2. Plan Task 8. Not yet reachable from the CLI (Task 11).

## What landed

- `Infer_slot.k6_slots` / `k6_shapes` / `graft`: a one-argument callback `f : a -> Bool` whose `a`
  appears in an element slot of the return is a K6 slot. Shapes: `List(a[p])`, `Option(a[p])`, and
  for a 2-tuple of lists `(List(a[p]), List({a | !p(_)}))`, `(List(a[p]), List(a))`,
  `(List(a), List({a | !p(_)}))`, each with `f : a -> Bool[p]`. The hypothesis is built by
  re-spelling the signature as text and parsing it, so the parser's own sugar defines the abstract
  refinement; the parsed types are grafted onto the real definition.
- `Infer_oracle.best_k6`: TRUE by the element-return gate on the definition side (the checker's
  own-predicate induction rule applies); USEFUL when a caller site closes with `p` instantiated;
  best = most caller sites closed.
- Probes withdraw the key from `Refine_check.abstracts_tbl` (now exported): `callee_abstracts`
  memoises a function's abstract names from its unhypothesised definition.

## Tests

Group `infer-abstract` (7): A1 (`keep` passing its callback to `List.filter`), and the rediscovery
rows — stripped copies of `filter`, `find`, `take_while`, `partition` (both halves) and
`Option.filter` re-derive exactly the stdlib's hand-written annotations; a body that keeps rejected
elements is not proposed. `Deque.filter`'s row moves to the evaluation (needs a `Within`-field
container the v1 K6 grammar does not cover).
