# Tuple parameters are still always owned

`Kind.borrowable_of` is true for `TRecord` since
`specs/progress/2026-11-18-record-param-borrow.md` but still false for
`TTuple`, so a function that only reads a tuple parameter releases it and its
callers retain it.

Tuples were left out on purpose:

- They are the usual shape of loop state (`loop((acc, i))`), the case
  `5bedb1232` made owned, so the gain is smaller and the loop-carried rule
  would fire more often.
- `Borrow.loop_carried_flips` matches `TRecord` only. Extending it means
  matching `TTuple` there and re-running the tuple fixtures
  (`test/native/aggregate_*.march`, `mixed_tail_aggregate_drop.march`) under the sanitizer.

Also open: a nominal record type that reaches a parameter as a `TCon` was
already borrowable through the plain `TCon` arm and is not covered by the
loop-carried rule. No leak is known; it relies on the deferred-drop list
(`march_tco_defer_push`), which holds one cell per iteration until the loop
exits. Decide whether the rule should cover it.
