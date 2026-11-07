# Stdlib lemma sweep S3, part 1: tuples as a predicate sort (2026-11-06)

Todo: `specs/todos/2026-11-04-stdlib-lemma-sweep-s3.md` (its tuple item), and the tuple half of
"a tuple- or record-typed variable in a predicate" in
`specs/todos/2026-10-31-reflection-encoder-gaps.md`. Built on S2 (`claude/stdlib-lemma-sweep-s2`).

## The gap

Tuple-typed function bodies reflect since `2026-11-06-reflection-float-string-records-tuples`
(`$Tup<n>` datatypes), but a tuple-typed VARIABLE in a predicate did not:

- `fn need_eq(a : (Int, Int), _b : {(Int, Int) | _ == a})` filed no obligation at all:
  `refined_param_ty` has no tuple arm, so the refinement was dropped before any check
  (`--refine-audit`: "refined_param_ty does not accept this declared base type").
- A tuple-typed parameter, lemma parameter or caller value was declared `Int`
  (`instance_sort_of_ty` and `sort_of_tc_ty` had no tuple arm), so
  `Tuple.swap(Tuple.swap(p)) == p` in a lemma was `unreflectable-predicate` and a guard
  `if p == q` gave a `sort-conflict`.
- A tuple literal in a predicate (`_ == (1, 2)`) did not translate and printed `<predicate>`.

## What changed

- `Refine_encode`: `tuple_adt`/`tuple_ctor` moved above the sort functions; `is_tuple_adt`;
  `instance_sort_of_ty` (`A.TyTuple`) and `sort_of_tc_ty` (`T.TTuple`) give a tuple the
  datatype `$Tup<n>` at its components' sorts.
- `Refine_scope`: `refined_param_ty` files a tuple refinement with the marker `tuple_adt n`
  (always built by that call, so the sort is registered before any query declares a constant
  at it); `smt_of_r_marked` translates a tuple literal to `$tup<n>(…)`; `pred_str` prints it.
- `Refine_call.check_call`: a tuple-typed refined value or parameter takes its datatype sort in
  stage 1 too (other datatypes only in stage 2), because a tuple has no scalar reading; a
  guard's tuple-typed caller variable is declared at the caller's instance (`$Tup2(Int, Int)`),
  not the bare `$Tup2`, so the guard and the goal agree on the name's sort.

No stdlib lemma: `Tuple.swap(Tuple.swap(p)) == p` and the `first`/`second`/`swap` laws now prove
at a caller by unfolding (S1's rule: ship a law only where unfolding cannot get it).

## Verification

| Check | Result |
|---|---|
| `reflect-stdlib-sweep` S3 cases (4): tuple precondition (2 proved, 2 violated), a guard `p == q` proves and `p != q` does not, a tuple literal `_ == (1, 2)` (proved / violated, no `<predicate>`), tuple lemmas (`swap_swap` at `(Int, Int)` and generic proved, `swap(p) == p` not proved) | RED (no row / `sort-conflict` / `unreflectable-predicate`) → GREEN |
| `scripts/affected.sh --run --full` | see the PR |

## Left for later

- The `zip`/`unzip` round trip and `List.is_empty`'s law (the S3 todo says what each needs).
- A tuple RETURN refinement and record-typed predicate variables (the encoder-gaps todo).
