`[P2]` Build `scripts/error-one-turn.sh` (triage plan D8, never built): model + program + rendered error →
fixed in one turn?, scored per code. Run before/after each diagnostics PR. specs/plans/2026-11-02-diagnostics-depth-plan.md §M1.

2026-11-03: done. `scripts/error-one-turn.sh` (see its header). For each `test/errors/` case it strips
the full-line comments (the corpus comments often explain the bug), renders `march --check` on what is
left, asks a model for the fixed program and scores it: `fixed` (passes `--check`, or for a warning-only
case the case's code is gone, and keeps intent), `intent`, `rejected`, `noanswer`. The intent check is
mechanical: every top-level name still declared, at most max(4, 25%) of the lines changed, and an
optional `-- EXPECT-FIXED-BY: <fragment>` present. The ask command defaults to `claude -p --model haiku`
(`ONE_TURN_CMD` overrides); `--prepare DIR` / `--score DIR` let answers come from elsewhere. It refuses
to run against a stale `_build/default/stdlib` (a targeted `dune build bin/main.exe` leaves it stale,
and the stale copy adds generated-code errors to every protocol program).

Baseline, Haiku 5.5, on the tree at the start of the diag-small-items branch (307 cases; answers
produced by Haiku subagents through `--prepare`/`--score`, since a nested `claude -p` cannot
authenticate inside the desktop app): **204/307 fixed (66.4%)**, 15 intent, 88 rejected. Worst codes:
`cap_grant` 10/34, `protocol_same_participants` 0/5, `division_by_zero` 0/4, `protocol_invalid` 0/4,
`cap_root_broad` 0/3, `missing_impl` 0/3, `overlapping_impl` 0/3, `role_grant_exceeded` 0/2.
A large share of the `rejected` verdicts are cascade suppression working as designed but costing a
turn: the suppressed `cap_grant` (main does IO with no grant) is the next error once the shown one is
fixed. Every `missing_impl` case fails that way. Candidate follow-up: keep a suppressed `cap_grant` as
a one-line note on the shown error, so the one turn can fix both.

2026-11-05: re-measured on main after F2, F3, F5, F6 and X1/X4/X8 (391 cases, Haiku 5.5 subagents
through `--prepare`/`--score`, same as the baseline): **286/391 fixed (73.1%)**, 9 intent, 96
rejected. On the cases that existed at the baseline's commit (323 there, against the 307 the
baseline counted): 221/323 (68.4%); the 68 added since: 65/68. `cap_grant` had fallen to 7/34, and
27 of the 105 failures were the suppressed `cap_grant` showing up after the shown error was fixed.

Then `cap_grant` stopped being suppressed beside other errors and sorts after them
(`specs/progress/2026-11-05-diag-cap-grant-shown.md`). Re-answering the 67 cases whose output
changed: 64/67 fixed (was 4/67), `cap_grant` 31/31. Combined with the unchanged cases' answers:
**346/391 (88.5%)**; on the baseline's cases 281/323 (87.0%), against 66.4% on 2026-11-03. Still at
zero: `protocol_same_participants` 0/5, `division_by_zero` 0/4, `protocol_invalid` 0/4,
`overlapping_impl` 0/3, `role_grant_exceeded` 0/2.

2026-11-05, later: the five zero-score codes (18 cases), on this branch with the `cap_grant` change
above merged in (`specs/progress/2026-11-05-diag-zero-score-codes.md`). Haiku 5.5 subagents through
`--prepare`/`--score`; the "after" column re-answers every case whose prompt changed.

| code | main | + `cap_grant` shown | + this change |
|---|---|---|---|
| `protocol_same_participants` | 0/5 | 5/5 | 5/5 |
| `division_by_zero` | 0/4 | 3/4 | 4/4 |
| `protocol_invalid` | 0/4 | 3/4 | 4/4 |
| `overlapping_impl` | 0/3 | 2/3 | 2/3 |
| `role_grant_exceeded` | 0/2 | 0/2 | 2/2 |
| total | 0/18 | 13/18 | 17/18 |

On main, 16 of the 18 answers fixed the shown error and were rejected by the hidden `cap_grant`.
None of the `protocol_same_participants` cases is about that hint: each one's error is
`session_offer_unrefined`, and the hint sorts first. The middle column's misses: `division_by_zero_1`
divides by a pattern binder, and the advice to "annotate the divisor parameter" led the answer to
refine the constructor field; `role_grant_exceeded_1`/`_2` widened the grant, which adds a body
parameter, so the body's arity broke (that figure is read off the main-run answers, whose only
remaining error was the arity one; the round with `cap_grant` shown already had the new help); `protocol_invalid_1` moved the stranded step into the branch
as `done -> do ... end`, which does not parse. The one still failing, `overlapping_impl_1`, is a
limit of the intent check, not the message: its error is `json_derive_name_collision`, and the
answer renames the user's `Stream_Message` type as the message says, which the check counts as a
removed declaration. The other fixes (drop `@[endpoints]`, drop the derive) change what the program
does. Overall: 346/391 → 363/391 (92.8%), counting the 17 against the 0 the previous run had.
