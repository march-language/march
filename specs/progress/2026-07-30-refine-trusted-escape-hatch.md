# `@[trusted]` — a per-function escape hatch from `cap verified`

Landed 2026-07-30.

**At landing:** `test_refinecheck` 375 (was 370, +5 `trusted` tests). Typing
corpus 235/235 (was 233/233, +1 accept `t132`, +1 reject `t133`). `run_compiler`
619, `run_codegen` 520, `run_eval` 256, `run_snapshots` 33, `run_stdlib` 826
with only the pre-existing environmental `MARCH_SANITIZE` failure, grammar
corpus 45/45 — all unchanged.

**What changed.** `cap verified` was all-or-nothing at the module level: one
obligation the checker could not discharge anywhere forced dropping the
capability for the *entire* module, since the only outs were `assert` or
removing `cap verified`. `@[trusted]` on a `fn` (`lib/refinecheck/refine_check.ml`)
is a per-function escape hatch: a `trusted_fn : bool ref`, scoped exactly like
`strict_verified` but to one function instead of a decl list (set from
`List.mem "trusted" fd.A.fn_attrs`, saved/restored with `Fun.protect` around
`visit_fn`'s body walk). `check_call`'s `note` upgrades a `Skipped _` verdict
to a new `Obligation.Trusted` verdict when `!trusted_fn` is true, *before* it
is recorded — so the escalation match, which only fires on `Skipped`, never
sees it and the error is suppressed.

**Deliberately loud, deliberately narrow.** `Trusted` is its own
`Obligation.verdict` constructor, never folded into `Proved` —
`--refine-report`'s headline now reads `N proved, N violated, N trusted, N
skipped`, so a reader can tell at a glance how much of a module's
"verification" is actually an assertion rather than a proof. Two hard limits,
both pinned by tests: `@[trusted]` never suppresses a `Violated` (only a
`Skipped _` is eligible — a predicate the solver *proved* can never hold is a
bug in the annotation, not an incompleteness to wave through), and it is
scoped to exactly the function that carries the attribute — an ordinary
sibling in the same `cap verified` module still escalates. `@[trusted]` on a
function in a module WITHOUT `cap verified` now warns that the attribute has
no effect, rather than silently doing nothing — the standing failure mode
this subsystem keeps producing (five prior wildcard-decl-walk bugs, per
`specs/lang/refinement-types.md`).

**Exhaustiveness, not a wildcard.** Adding the `Trusted` constructor broke two
`match`es on `Obligation.verdict`, both fixed by naming the new arm
explicitly rather than adding `| _ ->`: `obligation.ml`'s `summary` (which
deliberately still returns the SAME 3-tuple, `(proved, violated, skips)` —
every existing caller destructures it that way, and `Trusted` belongs in none
of those three buckets; its count is queried directly off `Obligation.all ()`
instead) and `bin/main.ml`'s own duplicate `Hashtbl`-based tally (which does
not call `summary` at all and needed its own `trusted` counter).

Five new tests (`trusted` in `test/test_refinecheck.ml`), non-vacuous by two
independent measurements: reverting `lib/refinecheck/{obligation,refine_check}.ml`
to their pre-fix (HEAD) state does not even COMPILE the test file (`Unbound
constructor Obligation.Trusted`); and re-adding just the `Trusted` type
without the `trusted_fn`/warning logic reproduces 3 of the 5 failures at
exactly the predicted assertions (cases 0, 1, 4 — the two that pass either way,
2 and 3, are true regardless of `@[trusted]`'s existence and so are not
discriminating on their own, which is why the full quartet plus the warning
case together are what pin the feature). Bracketed by
`accept/t132_refine_trusted_rescues_cap_verified` /
`reject/t133_refine_trusted_violation_not_rescued`.
