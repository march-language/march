`[P3]` Stdlib lemma sweep, phase S3: the laws that need encoder work.

Design: `specs/2026-11-04-stdlib-lemma-sweep-design.md` §3. Phases S1 and S2 shipped
(`specs/progress/2026-11-04-stdlib-lemma-sweep-s1.md`,
`specs/progress/2026-11-06-stdlib-lemma-sweep-s2.md`).

- Tuples as a predicate sort (`Tuple.swap` laws, `zip` / `unzip`). Tuple-typed function bodies
  reflect since `specs/progress/2026-11-06-reflection-float-string-records-tuples.md`; what is
  missing is a tuple-typed variable in a predicate (`specs/todos/2026-10-31-reflection-encoder-gaps.md`).
- Qualified `List.is_empty` (filed against `2026-11-03-reflect-type-name-clash-with-stdlib`,
  which `specs/progress/2026-11-06-predicate-names.md` closed for names declared at different
  arities; same-arity names wait on `2026-10-13-same-short-name-nested-types-unify`. Re-check
  whether `List.is_empty` still declines before starting).

Done when each law has a lemma or result type in the stdlib, admitted by `stdlib/lemmas.verified`,
and a `reflect-stdlib-sweep` case shows a caller proving with it and not without it.
