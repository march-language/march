# `alias-withdrawn` attribution now respects binder shadowing on both paths

**Filed:** 2026-07-31 (probe PE review) · **Fixed:** 2026-08-03, in two tasks.

## Background

`alias_withdrawal_cause` decides whether an undischarged obligation should be
blamed on a withdrawn alias (e.g. a competing, non-canonical `List.length`
definition shadowing the one the checker measures `len` through). Condition 3
of that decision requires a guard that applies the withdrawn spelling to the
obligation's own subject — checked via a discard-only, shadow-blind helper
(`iter_all`) that was safe only when used to *discard* a candidate fact, never
to *accept* one as evidence.

Two bugs shared this root cause, on the two ways a guard can reach the
withdrawn spelling:

1. **Laundered path** (`let n = List.length(ys); if n > 0 …`) — fixed
   2026-07-31/08-03: `expr_mentions_free` replaced the discard-only
   `expr_mentions` when checking whether a condition mentions the laundering
   name `n`, and the laundering-chain walk (`lets`) was extended to follow a
   chain of `let`s of any length instead of stopping after one hop.
2. **Direct path** (`if check(fn ys -> List.length(ys) > 0, zs) do head(ys) …`)
   — fixed 2026-08-03 (this task): a new `expr_applies_to_free`, modeled on
   `expr_mentions_free`, replaces the discard-only `expr_applies_to` in
   `guard_applies`, on both the direct condition and the laundered RHS.

## What changed (2026-08-03, Task 2)

`lib/refinecheck/refine_check.ml`:

- Added `expr_applies_to_free (name : string) (subject : string) (e : A.expr) :
  bool` — same traversal shape as `expr_mentions_free` (sequential `EBlock`
  scoping, lambda/`let fn` parameter capture, match-arm binder capture), but
  testing "does `e` contain a FREE application of `name` to the exact argument
  `EVar subject`" rather than "does `e` mention `m` free". The thing that must
  stay free here is the *argument reference*, not the applied function's own
  name.
- `guard_applies` (inside `alias_withdrawal_cause`) now calls
  `expr_applies_to_free` instead of `expr_applies_to` on both call sites: the
  direct condition and the laundered RHS. The laundered RHS was equally
  exposed to the same shadowing hazard and is fixed by the same change.

`expr_applies_to` itself is untouched and kept — it and `expr_applies` remain
correct for their existing discarding-position uses (see the comment on
`expr_mentions` vs `expr_mentions_free` for why the two flavors must not be
collapsed into one).

## Verification

- New tests in `test/test_refinecheck.ml`'s `alias-attribution` suite:
  - `"a guard's lambda param colliding with the subject name is not evidence"`
    (LA11) — `if check(fn ys -> List.length(ys) > 0, zs) do head(ys) …`: the
    guard's `ys` is the lambda's own parameter, never the outer `ys` `head`'s
    argument names. Confirmed RED against the pre-fix code (file-copy revert,
    rebuild, rerun; `[FAIL]` for the stated reason, "Expected: `true`,
    Received: `false`" on "stays general (solver-undecided)"), then restored
    and confirmed GREEN.
  - `"a FREE occurrence of the subject under a non-colliding binder still
    attributes"` (LA12) — companion control: `fn q -> List.length(ys) > 0`
    still attributes, proving the fix does not over-retire.
- Full `test/test_refinecheck.exe -e`: **432 tests run, 0 failures** with the
  fix in place (same 432/1-failure at the pre-fix revert, isolating the single
  new failure to LA11 as expected).
- Stdlib sweep (`bin/main.exe --check` over all `stdlib/*.march`, grepping for
  `alias-withdrawn`) after the fix: **zero files** mention `alias-withdrawn`,
  matching the pre-fix sweep. Per the fix's own construction (the free-
  occurrence check is strictly more conservative than the old unconditional
  one — see the comment in `alias_withdrawal_cause`), a difference could only
  ever be a file *losing* a mention it never should have had; none did.

## Closes

`specs/todos/2026-07-31-refine-alias-withdrawn-attribution-residuals.md`
sub-item 3 (direct-path shadowing). Sub-item 1 (laundering chain length) was
closed by the prior commit on this branch
(`refinecheck: alias-withdrawn attribution follows a laundering chain of any
length`). Sub-item 2 ("applies the spelling" vs "would have discharged") is
deliberately deferred — renamed and retitled to
`specs/todos/2026-08-03-refine-alias-withdrawn-applies-vs-discharges.md` as
the sole remaining item in that family.
