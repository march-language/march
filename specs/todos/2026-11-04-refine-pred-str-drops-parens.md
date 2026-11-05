`[P4]` The refinement report prints a predicate without its parentheses.

Found 2026-11-04 (stdlib lemma sweep S1). `Math.min_int`'s result type
`{Int | _ <= a && _ <= b && (_ == a || _ == b)}` is printed in `--refine-report-sites` rows
and obligation text as `_ <= a && _ <= b && _ == a || _ == b`, which reads as a different
predicate. `clamp_int`'s `high < low || (_ >= low && _ <= high)` prints as
`high < low || _ >= low && _ <= high`, which happens to read right only by precedence.
Display only: the verdict uses the tree. The printer is `pred_str` in
`lib/refinecheck/refine_scope.ml`.

Done when a printed predicate re-parses to the same tree (parenthesise a lower-precedence
child), with a test on `min_int`'s row.
