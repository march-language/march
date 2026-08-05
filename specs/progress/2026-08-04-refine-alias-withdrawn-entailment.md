# `alias-withdrawn` attribution now requires the guard to actually entail the obligation

**Filed:** 2026-08-03 (as `[P4]` "applies the spelling" ≠ "would have
discharged") · **Fixed:** 2026-08-04.

## Background

`alias_withdrawal_cause` decides whether a `Solver_undecided` skip should be
re-attributed to a withdrawn measure alias (a competing `List.length` /
`String.byte_size` definition, or the bare `string_byte_length` builtin,
shadowing the one the checker measures `len` through). Two shadowing bugs in
this decision were fixed 2026-08-03 (see
`specs/progress/2026-08-03-refine-alias-withdrawn-attribution-shadow-fixes.md`);
this was the third and last item in that family.

Condition 3 of that decision tested only that a positive guard *applies* the
withdrawn spelling to the obligation's own subject — not that the guard, read
as a fact, would have *proved* the predicate. `if List.length(ys) >= 0 do
head(ys) …` therefore blamed the withdrawal even though `len(ys) >= 0` is a
tautology over a non-negative measure that proves nothing about the goal
`len(ys) > 0`: that call is skipped whether or not the alias was withdrawn.
Blaming the withdrawal sends the author to rename an unrelated competing
definition instead of guarding the call.

## What changed

`lib/refinecheck/refine_check.ml`, `alias_withdrawal_cause`: added a fifth
conjunct requiring the guard's comparison to *entail* the predicate's
comparison, not merely mention the same measure.

- `atomic_cmp`: reads a comparison `X op n` (`==`/`!=`/`<`/`<=`/`>`/`>=`
  against an integer literal, either operand order) whose measured side
  matches a caller-supplied recognizer — used once against `pred` itself
  (recognizing the predicate's own measure application) and once, recursively,
  against the guard.
- `interval_of` / `interval_subset`: reads `X op n` as a half-open/closed
  integer interval and asks whether the guard's interval is a subset of the
  predicate's. `!=` is not convex, so it never entails anything by this
  check — a missed proof, not a wrong one.
- `exists_discharging`: searches the full guard expression, not just its
  top level, for a subterm matching this shape — mirroring
  `expr_applies_to_free`'s shadow-respecting descent exactly (same lambda/
  `let`/match-arm capture rules), because a genuinely discharging comparison
  can be nested inside an opaque call the checker cannot otherwise reason
  about (`check(fn q -> List.length(ys) > 0, zs)`).
- Where the shapes don't match this pattern — anything but a single
  comparison against a literal — entailment is undecided, and per the
  fail-closed stance of the whole function, undecided means *do not blame the
  withdrawal*: the honest `solver-undecided` message stays.

One pre-existing test ("a FREE occurrence under a non-colliding binder still
attributes", fixture `LA8`) asserted that a guard comparing an *unrelated*
bound variable (`any_over(zs, fn q -> q > n)`, `n` the laundered length) still
counted as discharging. That was itself an instance of the bug this task
fixes — `q > n` entails nothing about `n`'s sign — so its assertions were
corrected to expect the now-honest `solver-undecided` outcome; the underlying
free-occurrence coverage (the thing the test was originally written to pin)
is unchanged.

`test/test_refinecheck.ml`: added `LA14` (a non-discharging `>= 0` guard is
not blamed) and `LA15` (the `> 0` control is still blamed), using
`refine_error_text_d` — `Alias_withdrawn` is only ever emitted at `Error`
severity, and only inside `cap verified`; outside it, it produces no
diagnostic at all (excluded from the general non-strict hint), which is why
every fixture in this suite (including LA14/LA15) uses `cap verified`.

## Scope discipline (verified, not merely asserted)

This is message-quality only: the obligation's verdict never changes, still
`Skipped` either way. Verified directly by running `--refine-report` against
matched LA14/LA15 fixtures with both the pre-fix and post-fix checker: the
`(proved, violated, trusted, skipped)` tuple is identical before and after
for both fixtures; only LA14's reason label moves from the wrong
`alias-withdrawn` to the honest `solver-undecided`.

## Verification

- `./_build/default/test/test_refinecheck.exe test alias-attribution`: 22
  tests, 0 failures.
- `./_build/default/test/test_refinecheck.exe -e`: 461 tests run, 0 failures,
  0 skips (z3 available).
- Load-bearing: neutralising the new conjunct (`guard_discharges` forced to
  `true`) turned LA14 and the corrected LA8 fixture red again; restored to
  green after undoing the mutation.
- No stdlib/native sweep run — no verdict changes anywhere, so there is
  nothing a compiled-artifact sweep could catch that the ledger comparison
  above didn't already rule out.

See `.superpowers/sdd/2026-08-04-refinement-remaining-seven/task-5-report.md`
for the full evidence trail.
