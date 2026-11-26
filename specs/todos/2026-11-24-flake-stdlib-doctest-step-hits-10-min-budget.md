`[P3]`

# CI: the stdlib doctest step finishes at its 10-minute budget and is killed (2026-11-24)

`conformance` job, step "Check stdlib `march>` doctests"
(`scripts/check-stdlib-doctests.py --check`, `timeout-minutes: 10` in
`.github/workflows/ci.yml`).

On PR 1318 (run 45483689252, 2026-11-24) the step started at 21:20:24, printed
`stdlib doctests: 2082 run, 971 skipped, 1 programs, 0 failed` at 21:30:24, and
was killed by the timeout in the same second. The PR added no doctest and
changed no stdlib file.

The step took 6 min 41 s (2026-11-23) and 7 min 23 s (2026-11-24) on the two
passing `main` runs checked, so a runner 35% slower than usual fails it. The
comment above the step in `ci.yml` records the same thing happening on
2026-11-10.

What to do: the comment says to read the per-session lines before raising the
budget. Either cut the work (the cold prelude precompile is about 60 s and the
86 REPL sessions run one after another), or raise the budget with the measured
numbers. Closing rule for a flake (pre-1.0 decision D-n): 10 clean CI runs on
the leg.

## 2026-11-25: budget raised to 15 minutes

Two more PR runs timed out the same way (1331 run 45721885025 and 1333 run 45731876068),
each after printing `2081 run ... 0 failed`. Per-session lines, as the comment asks:

| run | sessions | sum | actor.march | control.march |
|---|---|---|---|---|
| main 45711459643 (passed, 8 min 02 s) | 87 | 473 s | 51.0 s | 57.5 s |
| PR 1333 (killed) | 87 | 598 s | 68.2 s | 73.9 s |
| PR 1331 (killed) | 87 | 597 s | 63.4 s | 73.7 s |

Every session on the killed runs is 24 to 34% slower than on main and none is out of
line, so it is the runner, not a session. The budget is now 15 minutes (`ci.yml`).

Still open: the step's own cost. 473 s on a normal runner is up from about 285 s on
2026-11-10 with the same shape, so the growth is per-session start-up, which is where to
cut next (one process for all sessions, or the sessions in parallel). The closing rule
stands: 10 clean runs on the leg.
