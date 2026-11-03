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
