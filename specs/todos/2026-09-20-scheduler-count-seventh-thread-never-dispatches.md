# `[P3]` `test_live_scheduler_threads_match_request`: one scheduler thread dispatched nothing for 120 s, cause unknown

Filed 2026-09-20. Third sighting of the family closed by
[[2026-09-20-flake-scheduler-count-thread-shortfall]], and the first one that fix's longer,
wait-only deadline could not explain. Instrumentation to decide it shipped in
[[2026-09-20-scheduler-thread-create-checked-and-thread-stats]].

## Sighting

PR #540, run 35546892704, `test (ubuntu-24.04)`, the **pinned** runner
(`test_scheduler_count_pinned_runner`); the unpinned runner passed two minutes earlier in the
same job. The PR did not touch the runtime.

```
(distinct dispatching OS threads: 6, requested 7; ran 120.0 s of a 120 s wait;
 224/224 workers left by deadline; usable CPUs 4)
```

Every worker stayed runnable and stealable for the whole 120 s, and the process then exited
cleanly (all 224 workers finished, every `pthread_join` returned).

## What is ruled out

- **A lost first wake.** There is no park/wake for scheduler threads to lose. An idle
  `sched_loop` sleeps 1 ms (`nanosleep`) and polls: global run queue, own deque, then
  `n - 1` steal attempts at random victims. 218 procs sit in six deques (~37 each), so a
  seventh thread that is polling makes ~6 attempts per ms against non-empty victims. Steal
  misses need a lost CAS or an empty victim; neither holds for 120,000 consecutive polls.
- **`MARCH_NUM_SCHEDULERS` above the CPU count being unsound to assert.** Seven runnable
  threads on four CPUs are time-sliced; none is withheld for two minutes. 720 earlier runs
  included seven schedulers on ONE CPU. The invariant stays.
- **A thread that failed to start.** Confirmed rather than assumed this time: under
  `docker run --pids-limit 6` the old runtime died with SIGSEGV in `pthread_join`, it did
  not report 6. (That crash is fixed; see the progress entry.)
- **A thread blocked forever** (mutex, malloc arena): the run would have hung in
  `pthread_join`, not failed at 120.0 s.
- **`pthread_self` hoisted across a yield.** glibc marks it `__attribute__((const))`, which
  would make every worker report only its first dispatcher. The `-O0` object code calls it
  at all three sites. The test now calls through a volatile pointer regardless.
- **The victim RNG.** The per-id LCG sequences were printed for n = 7; all ids reach all
  victims.

## Not reproduced

0 failures in about 2,040 further runs of the instrumented test with a 3 s wait, in
`ocaml/opam:ubuntu-24.04` (gcc 13.3, glibc 2.39, the CI pair): 1,200 at
`--cpuset-cpus=0-3` with eight concurrent copies, 600 at `--cpus=4` (CFS quota) with six,
240 as emulated `linux/amd64` (clang 18) with six. All earlier attempts were arm64; CI is
x86-64 on a shared VM, and nothing local reproduces that.

## What the next sighting will say

The failure now prints one line per scheduler, of this form (values illustrative):

```
(scheduler 6: started=1 entered=1 dispatches=0 idle_polls=118342)
```

- `started=0`: `pthread_create` failed (there will also be a `march: could not start
  scheduler thread` line). Look at the runner's pids/memory limits.
- `entered=0`: the thread was created and never reached `sched_loop`. Kernel/hypervisor.
- `dispatches=0`, `idle_polls` in the tens of thousands: it polled and every steal missed.
  That is a runtime bug in the steal path; start from `march_deque_steal`.
- `dispatches=0`, `idle_polls` small: it was blocked inside the loop. Find what on.
- `dispatches>0` on all seven: the test's recording is wrong, not the runtime.

Until one of those lines exists this is not actionable. Do not raise `SEEN_WAIT_S` again;
120 s already exceeds anything a late thread explains.
