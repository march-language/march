`[P3]` Stdlib lemma sweep, phase S3: the laws that need encoder work.

Design: `specs/2026-11-04-stdlib-lemma-sweep-design.md` §3. Phases S1 and S2 shipped
(`specs/progress/2026-11-04-stdlib-lemma-sweep-s1.md`,
`specs/progress/2026-11-06-stdlib-lemma-sweep-s2.md`).

- ~~Tuples as a predicate sort~~: done (`specs/progress/2026-11-06-stdlib-lemma-sweep-s3-tuples.md`).
  `Tuple.swap(Tuple.swap(p)) == p` and the `first`/`second`/`swap` laws prove at a caller by
  unfolding, so they need no stdlib lemma (S1's rule).
- **`zip` / `unzip` round trip.** `List.unzip(List.zip(xs, ys)) == (xs, ys)` (equal lengths) is
  `reflect-fuel` even on literals: both are accumulator loops ending in `reverse`. It needs S2's
  treatment: lift `zip`'s and `unzip`'s `go` to `pfn`s, then accumulator lemmas
  (`zip_onto(xs, ys, acc) == append(reverse(acc), zip(xs, ys))` and the `unzip` analogue) before
  the round trip. Check with ir-oracle and `bench/list_ops.march`.
- **`List.is_empty(xs) == (len(xs) == 0)`.** The qualified name now resolves (it proves `Nil` and
  is violated on `Cons`); the law itself stops at three encoder gaps: a result type
  `{Bool | _ == (len(xs) == 0)}` is `solver-undecided`, a lemma theorem comparing a Bool call
  with a comparison is `unreflectable-predicate`, and `List.length(xs) == 0` as an argument is
  `unreflectable-subject` (`specs/todos/2026-11-04-stdlib-call-subjects-unreflectable.md`).

Done when each law has a lemma or result type in the stdlib, admitted by `stdlib/lemmas.verified`,
and a `reflect-stdlib-sweep` case shows a caller proving with it and not without it.
