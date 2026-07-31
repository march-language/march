# Postcondition obligations enter the refinement ledger

Landed 2026-07-30.

**At landing:** `test_refinecheck` 370 (was 365, +5 `postcond-ledger` tests).
`run_compiler` 619, `run_codegen` 520, `run_eval` 256, `run_snapshots` 33,
`run_stdlib` 826 with only the pre-existing environmental `MARCH_SANITIZE`
failure, grammar corpus 45/45 — all unchanged, since this touches only
`check_post`'s bookkeeping, not its verdicts.

**What changed.** `check_post` (`lib/refinecheck/refine_check.ml`) discharges a
function's own return-type refinement — proving it, reporting a violation, or
silently giving up — but until now it filed no record of the outcome, so
`--refine-report` undercounted by every return refinement in a program, and a
function whose entire contract was its return type (`fn mk() : {Int | _ > 0}
do 100 end`) was invisible to the report. `Obligation.t` (`lib/refinecheck/obligation.ml`)
gained a `kind` field (`Precondition | Postcondition`) instead of overloading
`callee`; the existing `check_call` record site now sets `kind = Precondition`,
and `check_post` records at all five outcomes: the four early "could not even
build a goal" exits (`Unreflectable_predicate` ×2, `Sort_conflict`,
`Float_sort_gate`) and the discharge result (`Verified` → `Proved`; the
emitted-error path → `Violated`; otherwise → `Skipped Solver_undecided`).

**The double-count trap this was built around.** `check_fn_post_verdict` runs
`check_post` twice per refined-return function: once from the
`gate_unverified_posts` pre-pass with `~emit:false` (deciding whether the
postcondition is proven enough to propagate to callers) and once from the walk
with `emit = true` (the actual reporting run). Recording unconditionally would
count every postcondition twice. Fixed by threading a `~record` parameter
through `check_post`, tied to the SAME flag as `~emit` at the one call site
(`~record:emit`) — deliberately not a second independent flag, so the
invariant "the run that reports is the run that records" cannot be broken by a
future caller passing them differently. Pinned by a dedicated test case
(`postcond-ledger` case 3) that reruns the exact PL1 fixture from case 0 and
asserts exactly 1 proved, not 2.

`bin/main.ml`'s `print_refine_report` (its own `Hashtbl`-based summarizer,
independent of the test-only `Obligation.summary`) now prints a `by kind: N
precondition, M postcondition` line under each slice's headline; the headline
totals themselves are unchanged (`Precondition` and `Postcondition` verdicts
both count toward "proved"/"violated"/"skipped" identically) and the two slice
labels `user code` / `user + stdlib` are untouched, since the CI ratchet greps
them by exact text.

**Behaviour-neutral, verified by ratchet.** `stdlib/list.march`'s
`--refine-report` still reads `8 proved, 0 violated, 28 skipped` for the
`user + stdlib` slice — unchanged, and its new `by kind` line reads `36
precondition, 0 postcondition`, confirming the fixture (measured pre-work to
have zero refined return types) contributes nothing new. `cap verified` still
escalates only precondition obligations raised at call sites — escalating a
postcondition is left to a later task, which now has a `Skipped` verdict to
read rather than nothing at all.

Five new tests (`postcond-ledger` in `test/test_refinecheck.ml`), each
confirmed RED at the exact pre-fix count stated in its comment (0 proved / 0
violated / 0 skipped for the always-legal PL1–PL2 cases despite PL2 actually
being a violation that exits 1; 0 skipped for the undecidable PL3 despite exit
0; 1 proved, not 2, for the double-count guard PL4; 2 proved for the
precondition-and-postcondition interaction PL5) before the fix, and GREEN
after — reverting `lib/refinecheck/{obligation,refine_check}.ml` to their
pre-fix (HEAD) state and rebuilding reproduces every failure at the stated
count, restoring the fix makes all five pass.
