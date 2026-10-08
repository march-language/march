# `[P3]` Flake: a native fixture dies of a bare kernel SIGSEGV on Linux CI, cause unknown

**Seen** twice, both on `test (ubuntu-24.04, rest)`, both as a bare
`Segmentation fault (core dumped)` from the fixture's `sh -c ./native_X` rule:

- 2026-10-07, `native_branch_alias_tail_drop`: run 37670650765 (merge train I,
  PR #860, head 365ab779c), job 112961244787.
- 2026-10-04, `native_run_until_idle_ping_pong` (`MARCH_NUM_SCHEDULERS=14`):
  run 37167730689, job 111334108065.

The two fixtures share no code path beyond the runtime's startup and shutdown
(one is a single green thread doing string/record work, the other a 14-scheduler
actor ping-pong). Neither PR in train I touched either.

## Why "bare" matters

A compiled March program installs a SIGSEGV/SIGBUS handler in `march_sched_init`
(`runtime/march_scheduler.c`, `install_stack_growth_handler`) before `main` runs.
For any fault it does not handle as stack growth it writes
`march: fatal SIGSEGV si_code=... addr=... pc=... sched=... pid=...` and
`_exit(139)`. The shell then prints nothing. A shell-printed
`Segmentation fault (core dumped)` therefore means the process was killed by the
kernel's default action, which happens only if:

1. the signal arrived before the handler was installed (the first few ms), or
2. the handler itself faulted (SIGSEGV is blocked while it runs, so the kernel
   kills; e.g. `tl_sched->current` pointing at a dead `march_proc`), or
3. the kernel could not push a signal frame onto the per-thread 64 KiB alternate
   stack (`force_sigsegv`), e.g. a preemption tick or the SIGSEGV itself landing
   on an alt-stack page it could not fault in.

No core survives on a stock runner: its `core_pattern` pipes to apport, which drops
cores of unpackaged binaries.

## Ruled out

- **The fixture itself.** `branch_alias_tail_drop` compiled `--opt 2` from main
  d9fbbf179 (train I's code) ran clean 54,000 times on a real
  `ubuntu-24.04` x86_64 runner (AMD EPYC 7763; 24,000 idle, 30,000 under
  `stress-ng --cpu 8 --vm 2 --vm-bytes 60%`), and `run_until_idle_ping_pong` at
  14 schedulers 3,000 times under the same load: every exit 0, every output
  right (temporary workflow on a scratch branch, run 37693004310).
  Locally (Docker, Ubuntu 24.04): ~5,000 runs on arm64 (idle, 16-way parallel,
  4 schedulers pinned to one or two CPUs), 200 under `MARCH_SANITIZE=1` (ASAN
  clean), ~2,700 on x86_64 under Rosetta, all clean.
- **A full `rest` shard** (`MARCH_CI_RUNTEST_SPLIT=1 dune runtest -j 4`, arm64,
  7 GB, cores captured): no March binary crashed. (One unrelated C harness did:
  `test_reload_activate4_runner` faulted in `__march_init` of a dlopen'd stub on
  the reload-server thread. That was a pre-`march_sched_init` spawn overrunning
  its stack reservation, fixed separately:
  `specs/progress/2026-10-07-preinit-spawn-stack-overruns-reservation.md`.)
- **A signal sent from outside.** Nothing in `test/` or `scripts/` sends SIGSEGV
  to a process, so a stray kill of a recycled PID cannot produce this.
- **Memory pressure (OOM) in the failing job.** Its log has no OOM-killer or
  allocation-failure trace.
- **The runtime-object cache.** `lib/cas/runtime_archive.ml` publishes each `.o`
  with an atomic rename, so concurrent compiles cannot link a torn object.

The 54,000 clean runs set the per-run rate outside `dune runtest` at well under
1/50,000. CI hit two in roughly 37,000 native executions (about 150 Linux runs
times 250 fixtures since 2026-10-01). These are close enough that a plain rare
race is not excluded (P(0 in 57,000) is about 5% at CI's rate). Both crashes
came after the vendored mimalloc landed (fac1b606f, 2026-10-01); 52 failed
Linux job logs from September have none. That is weak evidence (P about 0.3).

## Next step

`ci.yml` now captures cores on the Linux `test` shards (`/tmp/march-cores`,
`ulimit -c unlimited`) and, when the job fails, backtraces them and uploads the
`cores-<os>-<shard>` artifact. On the next occurrence, `p $_siginfo` separates
the three cases above: `si_code` 128 (`SI_KERNEL`) is case 3, a fault code
(1, 2) with the runtime's line missing is case 1 or 2, and the backtrace says
which; 0 or a negative code would mean a signal sent by a process after all.
Fix from that evidence, then move this file to `specs/progress/`.
