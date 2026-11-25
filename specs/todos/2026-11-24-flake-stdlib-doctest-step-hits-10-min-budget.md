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
