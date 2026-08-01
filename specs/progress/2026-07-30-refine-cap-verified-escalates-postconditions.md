# `cap verified` escalates undischarged postconditions too

Landed 2026-07-30.

**At landing:** `test_refinecheck` 379 (was 375, +4 `postcond-strict` tests). Typing
corpus 237/237 (was 235/235, +1 accept `t135`, +1 reject `t134`). `run_compiler`
619, `run_codegen` 520, `run_eval` 256, `run_snapshots` 33, `run_stdlib` 826
with only the pre-existing environmental `MARCH_SANITIZE` failure, grammar
corpus 45/45 — all unchanged.

**What changed.** `check_call`'s `note` (`lib/refinecheck/refine_check.ml`)
already escalated a `Skipped` precondition obligation raised at a call site
into a hard error under `cap verified`; `check_post`'s `note` recorded the
identical shape of obligation into the ledger (same day, earlier commit) but
never escalated it, so a `cap verified` module with an undecidable RETURN
refinement exited 0 — the last place a fact was granted without obliging
anyone. `check_post`'s `note` now mirrors `check_call`'s exactly: `@[trusted]`
upgrades a `Skipped _` verdict to `Trusted` (run before recording, so the
ledger and diagnostic agree), and any `Skipped` verdict that survives that
rescue is reported as a `cap verified` compile error naming the function, the
return predicate, and the reason — worded for a return position ("strengthen
the return expression …") rather than reusing `check_call`'s "guard the call"
advice, which makes no sense for a postcondition. Escalation is gated on
`record` (threaded from `check_fn_post_verdict` as `~record:emit`), so only
the emitting run reports: `gate_unverified_posts`'s pre-pass calls `check_post`
a second time with `~record:false` purely to decide propagation, and must
never also error, or one contract would produce two diagnostics.

**The blast-radius sweep — the point of this task.** Turning a silent skip
into a hard error risks a false positive on existing code, which March treats
as strictly worse than a missed catch. `stdlib/*.march` has zero refined
return types, so the sweep (`for f in stdlib/*.march; do march --check "$f" |
grep -iE "cannot verify|refinement violation"; done`) printed nothing — zero
blast radius. The CI obligation ratchet is unaffected: `stdlib/list.march`'s
`--refine-report` is still `8 proved, 0 violated, 0 trusted, 28 skipped`
(ceiling 28 unchanged — none of the 28 is a postcondition), and
`t118_refine_length_guard_discharges.march`'s `1 proved, 0 violated, 0
trusted, 0 skipped` floor holds.

Four new tests (`postcond-strict` in `test/test_refinecheck.ml`), non-vacuous:
pre-fix, case 1 ("cap verified escalates an undischarged postcondition")
failed (`mk(z : Int) : {Int | _ > 0} do z end` under `cap verified` exited 0);
post-fix all four pass, including the false-positive control (a genuinely
PROVED postcondition stays silent) and the `@[trusted]` rescue. Bracketed by
`reject/t134_refine_postcondition_strict_undischarged` (first-line
`-- EXPECT-ERROR: cap verified`) / `accept/t135_refine_postcondition_strict_trusted`
(the same function rescued by `@[trusted]`).
