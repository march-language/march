`[P3]` Stdlib lemma sweep, phases S2 and S3: the laws that need a refactor or encoder work.

Design: `specs/2026-11-04-stdlib-lemma-sweep-design.md` §3. Phase S1 shipped
(`specs/progress/2026-11-04-stdlib-lemma-sweep-s1.md`).

- **S2:** lift the accumulator loops of `List.length`, `sum_int`, `product_int`, `minimum_int` and
  `maximum_int` to `pfn`s, as phase 3 did for `reverse_onto`. Then add the accumulator lemmas,
  `length : {Int | _ == len(xs)}`, and the `sum_int` / `product_int` laws over `append` and
  `reverse`. Check with ir-oracle (phase 3's normalising rename diff) and
  `bench/list_ops.march` at `--opt 2`.
- **S3:** tuples as a predicate sort (`Tuple.swap` laws, `zip` / `unzip`), and qualified
  `List.is_empty` (see `2026-11-03-reflect-type-name-clash-with-stdlib`).

Done when each law has a lemma or result type in the stdlib, admitted by `stdlib/lemmas.verified`,
and a `reflect-stdlib-sweep` case shows a caller proving with it and not without it.
