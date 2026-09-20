# `test_live_scheduler_threads_match_request`: the wait now measures only the wait, and lasts 120 s

Shipped 2026-09-20. Test-only fix; no runtime change. Closes the `[P3]` todo filed
2026-09-17 (`flake-scheduler-count-thread-shortfall`). Follows
[[2026-09-15-test-scheduler-count-thread-observation-rendezvous]].

## Symptom

Sighted on PR #509 (run 35261673191) and again on PR #534 (run 35532918696, attempt 1),
both the 4-CPU ubuntu-24.04 `test` job, both green on rerun, neither PR touching the
runtime:

```
  (distinct dispatching OS threads: 6, requested 7)
  FAIL [test_live_scheduler_threads_match_request:218]: ... the workers stayed runnable
  for up to SEEN_WAIT_S waiting for the missing thread, so this is a real shortfall
```

## What was established

The failure was **not reproduced**: 0 failures in about 500 runs of the unmodified test
in an `ubuntu-24.04` container pinned to 4 CPUs (`--cpuset-cpus=0-3`), including 8 CPU
hogs in the same cpuset and six concurrent copies of the test. Instrumented runs under
that 6x contention ruled out the two candidate mechanisms:

- **Not work distribution.** Yielded procs go back to the yielder's *local* deque, not
  the global run queue (the old test comment said otherwise), so a late thread gets work
  only by stealing. It does: a scheduler that just ran a yielder steals before popping
  its own deque, so procs migrate constantly. Per-thread dispatch counts over a run were
  within ~25% of each other (about 1300 each of ~9000), and the last thread was first
  seen within 90 ms in 180/180 runs. "Zero dispatches" is not a tail of that distribution.
- **Not a thread that failed to start.** `march_sched_run` does not check
  `pthread_create`'s result, but on glibc a failed create would have crashed in
  `pthread_join(0)` rather than reporting 6 and finishing every worker.

What the old test could not tell us is how long it had really waited. `SEEN_WAIT_S` was
10 s of wall clock armed *before* the spawn loop, running concurrently with a floor of
224 x 40 x `burn(200000)` in an `-O0` build: 2.3 s on 4 fast CPUs under contention, more
on the runner. The failure message asserted a 10 s wait the test had no way to know it
performed. The residual explanation is one OS thread not being run for seconds on a
shared runner; it is a residual, not a finding.

## Fix (`test/test_scheduler_count.c`)

- Floor cut from 40 rounds to `FLOOR_ROUNDS` (4); a healthy run is ~40 ms instead of ~1 s.
- The deadline is armed immediately before `march_sched_run`, and `SEEN_WAIT_S` is 120 s
  (`#ifndef`-overridable). It bounds a hang; a healthy run leaves the wait the moment the
  seventh thread is seen, so the larger value costs nothing.
- The assertion is unchanged (exactly as many dispatching OS threads as requested), so a
  genuine shortfall still fails. The failure line now reports elapsed wall time, how many
  workers left by deadline rather than by rendezvous, and usable CPUs, so a further
  sighting says whether the wait was really served.

## Verification

- macOS: both runners 20x each, 0 failures, then the pinned runner 20x more after the
  final comment edit.
- Linux container, pinned + unpinned builds, six concurrent loops: 240 runs each at
  `--cpuset-cpus` 0-3, 0-1 and 0 (7 schedulers on ONE CPU): 0 failures in 720.
- **Negative control (RED proven):** a scratch copy of `march_scheduler.c` that creates
  and joins one worker thread too few, built with `-DSEEN_WAIT_S=3.0`, fails with
  `distinct dispatching OS threads: 6, requested 7; ran 3.0 s of a 3 s wait; 224/224
  workers left by deadline`.

## Reopen if

It fails again. The new failure line decides it: `ran 120 s` with all workers leaving by
deadline means a scheduler thread truly never dispatched in two minutes, which is a
runtime bug to chase (start with an accessor for how many threads set
`g_scheds[i].running`), not a test to loosen.
