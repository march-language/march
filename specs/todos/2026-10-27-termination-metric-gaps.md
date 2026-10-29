`[P3]` Termination metrics: the gaps phase 2 left

Filed 2026-10-27 by phase 2 of `specs/2026-10-26-termination-checking-design.md`
(`specs/progress/2026-10-27-termination-phase2.md`). Each gap makes the checker say
"unproved" (or reject an annotation) where a proof exists; none can make it say "proved"
wrongly.

- **A multi-head function's metric cannot name its parameters.** Desugaring merges
  `fn f(0) … fn f(n) …` into one clause over `__arg0`, so `@[decreases(n)]` on it is
  `invalid_decreases` ("`n` is not a parameter of `f`"). Either resolve a metric name
  against every clause's own binder at that position, or document `__arg0`-free
  spelling. Probe: `fn p3(n : Int) : Int when n > 0 do p3(n - 1) end` plus a fallback
  clause.
- **A recursive call in a match-arm guard is never reached.** `Refine_check.visit`
  does not walk an arm's `when` guard, so its termination obligation is never
  discharged and the SCC is `unproved:not-decreasing` ("the checker did not reach this
  call"). Fail-closed by design (test "a call the walk never reaches"); walking guards
  would also check their preconditions, which is a refinement change of its own.
- **Division in an argument reflects only through inlining.** `Refine_resolve.reflect_scalar`
  has no `/`/`%` arm, so an actual `n / 2` is unreflectable as a call argument. Phase 2
  inlines plain Int arithmetic into the predicate (where `smt_of` reads `/` by a literal);
  an argument mixing arithmetic with a field or call still goes through
  `reflect_scalar` and skips.
- **`pred_str` drops the parentheses of a right-nested subtraction.** The ledger shows
  `grow(n - (0 - 1))`'s obligation as `$c_n - 0 - 1`; the predicate itself is right.
  Cosmetic, in the shared printer (`Refine_scope.pred_str`).
- **A metric whose parameter is rebound before the call** is `unproved:shadowed`, even
  where the rebinding is harmless (`let n = n` ). Renaming the entry value apart, as
  `Refine_post.rename_free` does for returns, would prove those.
- **A model can be missing on a warm cache.** The counterexample in
  `termination_unproved` comes from the solver's model; a VC answered from the cache
  without one prints the warning with no `e.g.`. Not observed in the tests, which pass
  cold and warm.
