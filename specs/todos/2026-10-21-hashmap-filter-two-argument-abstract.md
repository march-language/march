`[P3]` `HashMap.filter` carries no entry fact (the `Map.filter` recipe, not applied yet)

Filed 2026-10-21 by phase 4 of the multi-arg abstract refinements design
(`specs/2026-10-18-abstract-refinements-multi-arg-design.md` §7.1, §8, decision 9:
one carrier per PR; `specs/progress/2026-10-21-abstract-multiarg-phase4.md`).
`HashMap.filter(m, fn k -> fn v -> …)` has the same HAMT shape and the same curried
callback as `Map.filter`, but its signature is unannotated, so a filtered `HashMap`
carries no fact about its entries.

Recipe (what phase 4 did for `Map.filter`):
- annotate the signature honestly so P1 holds: `m : HashMap(k, v)`,
  `pred : k -> v -> Bool[p]`, and return `HashMap(k[p], v[p])` (keeping any
  container-level predicate it has) under `@[assume]` (the body goes through tuples
  and a two-step curried call, so it cannot be proved);
- extend its `doc` paragraph ("…and that every entry satisfies `pred`");
- a `Check.all` runtime witness in `test/stdlib/test_hash_map.march` over random
  `List((Int, Int))` and a threshold predicate, shown RED with the body's `if`
  inverted;
- tests m1-m8-style in a `test_refinecheck` group against the real
  `stdlib/hash_map.march`; run the full `scripts/run-tests.sh` (stdlib ratchet) before
  trusting `--check`, since a wrong stdlib annotation can typecheck to an internal
  error `--check` does not print.
