# test_hcr_migrate_order: "held actor is left alone" flaked on macOS CI (fixed 2026-09-29)

CI `test (macos-15, all)` failed on PR #692 (run 36512671315, job 109228055510)
with `FAIL after the soft deadline a held actor is left alone (line 561)` in
`test_hard_deadline_kills`. Every other check in that section passed, including
"the hard deadline killed it" and "and counted the kill". PR #692 touched only
`test/two_node/*.march`. Main's recent ci.yml runs show no instance: its two
failures that week (36545524230, 36499204162) were `two-node` jobs with no
`FAIL` lines from this runner.

**Cause: a timing window in the test, not in the runtime.** The activation used
soft 20 ms / hard 80 ms. `march_hcr_drain` (runtime/march_runtime.c) spawns
`hcr_hard_proc`, a green daemon that parks until `now + hard_ms` and then kills
every actor still pinned to the drained epochs. The test's `sleep_ms(40)` is a
`march_sched_yield` busy loop. On a loaded runner the test thread came back
more than 80 ms after the activation, so the hard proc had already run and
`march_is_alive(a)` was false. The runtime behaved correctly. The check had a
40 ms margin.

**Fix.** Widen the hard deadline to 1000 ms. Keep the soft deadline at 20 ms and
the check after `2 * SOFT_MS`, so it still proves a held actor survives past the
soft deadline and is only killed at the hard one. Waiting on a state would be
better than sleeping, but nothing observable marks "the soft deadline passed"
for an actor held in a handler, so the gap is widened instead. The test now prints how many ms after
the activation the check ran. The kill-wait loop's budget grew to
`HARD_MS + 5000`. `test_hard_deadline_cancels_tasks` keeps 20/80: it never
checks liveness inside the window.

**Verified.** Perturbation `HARD_MS = 30` (below the 40 ms wait) goes RED on
this exact check. Restored, it passed 10/10 runs locally under 2×ncpu `yes`
CPU hogs; each check ran at 40–41 ms. The local load never reproduced the CI
stall, so the protection is the ~960 ms margin.
