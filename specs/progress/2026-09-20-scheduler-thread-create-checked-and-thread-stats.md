# `march_sched_run` checks `pthread_create`; per-scheduler counters; the thread-count test reports them

Shipped 2026-09-20, from the investigation of the PR #540 sighting tracked in
[[2026-09-20-scheduler-count-seventh-thread-never-dispatches]] (still open: the sighting
itself was not reproduced).

## Runtime defect found on the way (`runtime/march_scheduler.c`)

`march_sched_run` dropped `pthread_create`'s result. glibc stores the new handle before it
clones and frees the stack when the clone fails, so the `pthread_join` at the end of the run
read a dangling thread descriptor:

```
$ docker run --rm --pids-limit 6 ... test_scheduler_count_pinned_runner
march: fatal SIGSEGV si_code=1 addr=0xffff910ae250 ... (no green thread running on this scheduler)
exit=139
```

after a run whose green threads had all completed correctly. Any compiled March program
under a pids cgroup limit or `RLIMIT_NPROC` close to its scheduler count could do this.

Now each create is checked. A scheduler that did not start is marked `started = 0`, skipped
by the join, and never signalled by the preemption daemon (its `running` stays 0). Its deque
is initialised and empty, so other schedulers' steal attempts on it miss harmlessly;
`g_num_scheds` is deliberately not shrunk mid-run, since the running threads read it
unsynchronised. The shortfall is reported:

```
march: could not start scheduler thread 7 of 7 (pthread_create: Resource temporarily unavailable)
march: running on 6 scheduler threads, not the 7 requested
```

The same `--pids-limit 6` run now finishes every worker and exits through the test's own
FAIL (exit 1), which also serves as the test's negative control: a runtime one thread short
is reported as 6 of 7 with `scheduler 6: started=0`.

## Per-scheduler counters (`march_sched_thread_stat`)

`march_scheduler` gains `started`, `entered`, `stat_dispatches`, `stat_idle_polls`: plain
fields written only by the owning thread (`started` by `march_sched_run` before the thread
exists), one increment per dispatch or idle poll, zeroed by `march_sched_init`'s existing
`memset`. `march_sched_thread_stat(sched, MARCH_THREAD_STAT_*)` reads them; exact after
`march_sched_run` returns.

## Test (`test/test_scheduler_count.c`)

- On a thread-count mismatch (or with `SCHED_COUNT_STATS=1`) prints one line per scheduler;
  the todo lists what each pattern means.
- Asserts the runtime's account agrees: every requested scheduler `started`, and has a
  non-zero dispatch count.
- Reads the OS thread through a volatile function pointer. glibc's `pthread_self` is
  `__attribute__((const))`; an optimised build could reuse one call's result across a
  `march_sched_yield()` that migrated the green thread. The `-O0` rule in `test/dune` does
  not (verified in the object code), so this was not the CI failure; it is a guard.

## Verification

- All nine `test_scheduler*_runner` binaries pass on macOS.
- Linux container (gcc 13.3 / glibc 2.39): `--pids-limit 9` passes; `--pids-limit 6` went
  from exit 139 to the report above.
- `scripts/check-runtime-sources.sh`, `scripts/check-docs.sh` green.
