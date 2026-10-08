# `[P3]` Flake: `native_actor_state_released` exited non-zero once on macOS CI, cause unknown

**Seen** 2026-10-07, once: main's CI run 37584120564, job `test (macos-15, all)`
(112670247761), on 0cdea7c35 (merge train D, which landed the fixture with PR #828).
Every alcotest suite in the job passed, and so did train D's own CI (run 37573786349,
same fixture, macOS). The re-run of the same job (attempt 2, job 112773607957) passed
it: all 20 panic lines, no failure header. That job then hit its 75-minute
`Test (all)` timeout, a separate problem.

## What the log shows

dune printed the failure header for the RUN rule (`test/dune`, the one that runs
`./native_actor_state_released` into its `.out`), not for the `diff` rule after it.
So the binary exited non-zero (or died of a signal). Whether the output was right
was never checked. Its stderr was 13 copies of
`march: actor on_stop callback failed (the actor still stops): panic: on_stop blew up`,
but the fixture's last phase stops 20 `Messy` actors, each of which logs that line
once. No exit code or signal was shown: **dune prints no status for a failed action
whose stderr is non-empty** (checked with dune 3.21: `exit 1` and `kill -TRAP $$`
both print only the header and the stderr). Since this change the rule echoes the
status itself.

So either the process died during the 14th `Messy` stop, or 7 `on_stop`s did not run
(the stopper's deadline killed those actors first) and the process died later.

## Ruled out (locally, M-series Mac, Darwin 25)

- **A plain fault.** The scheduler's SIGSEGV/SIGBUS handler always writes
  `march: fatal SIGSEGV|SIGBUS ...` before `_exit(128 + sig)`, and nothing like that
  was printed. An unsupervised panic prints `panic: ...` and a backtrace. Every
  RC-underflow, `march_free`-of-shared and TRMC abort prints a line first.
- **The panicking-`on_stop` path itself.** 192 processes, each stopping 3,000
  panicking `Messy` actors (576k panics), on 3 and 14 schedulers: all exited 0.
  `Messy_on_stop`'s IR copies the `xs` field with an incref before `List.reverse`
  consumes it, so the record still owns a live reference when the panic longjmps out.
- **A deadline kill racing `on_stop`.** With the fixture's stop timeout cut to 1 or
  2 ms, stderr shows the same signature as CI (11 to 17 panic lines of 20), but
  2,700 runs on 1, 3 and 14 schedulers all exited 0.
- **Load and starvation.** 1,200 runs with 24 CPU hogs on 1, 2, 3 and 14 schedulers;
  80 runs under `taskpolicy -b` (efficiency cores, lowest priority) beside 16
  normal-priority hogs; 5,228 runs looped beside the full `run_stdlib` and
  `run_eval` suites. All exited 0.
- **Memory.** Peak RSS is 5.6 MB, so jetsam is not plausible.

Not tried: macOS 15 (CI's version; local is 26), CI's Xcode clang, and ASAN. A
`MARCH_SANITIZE=1` build of even a one-actor hello-world spins forever on this
machine before printing anything, which is a separate problem.

## Leads, in order

1. **Something outside the process.** Everything above points away from the
   runtime, and a silent, non-wedging death matches SIGKILL/SIGTERM/SIGUSR2 from
   outside (see 2026-09-24-flake-upgrade-from-traffic-driver-sigkilled.md for the
   same shape). One way it could happen: `march_process_kill_proc` sends SIGTERM to
   a stored pid even after `march_process_wait_proc` has reaped it. In an hour-long
   job, macOS pids can wrap, so a late call could hit an unrelated process.
2. **A macOS 15 (or Apple clang 16) difference** in `setjmp`/`longjmp` or
   `swapcontext` when a green thread migrates OS threads between `actor_run_on_stop`'s
   `setjmp` and the panic's `longjmp` (`Messy_on_stop` begins with a preemption
   yield).

**Next time it happens:** the rule now prints
`native_actor_state_released: exit status N (above 128: signal N-128)`. A status of
137, 143 or 159 points outside the process (lead 1). 133 (TRAP) or 134 (ABRT)
points at the runtime (lead 2). 1 is an `exit(1)` whose message went to stdout.

Also hardened: the `released:` polls now wait up to 5 s instead of 2 s before
reporting `false`, so a stalled runner cannot fail the diff rule after a clean run.

## Second sighting: the signal is SIGILL (2026-10-08)

Merge train R's CI (run 37773065148, job `test (macos-15, all)`) hit it again,
and #841's exit-status reporting caught the cause this time:

```
native_actor_state_released: exit status 132 (above 128: signal 4)
```

Signal 4 is SIGILL: on arm64 macOS that's a trap instruction (`brk`), which is
what `__builtin_trap`, a failed `__builtin_unreachable` path, or an LLVM
`unreachable` emits, not a memory fault. All 20 `on_stop blew up` lines were
printed this time, so the trap came after the last panicking `on_stop`, during
or after the final assertions or teardown. Train R contained #877 (static
nullary cells, owned-call drop fusion, per-object alloc/free changes); every
other job passed, and the fixture's first failure (above) predates #877.

## Sightings 3 and 4, and the rate (2026-10-08)

Same signature (`exit status 132 (above 128: signal 4)`, `on_stop blew up` lines
printed) on merge train U's CI (run 37794937229, `test (macos-15, all)`) and train V's
(run 37813005310). Counting every full macOS `test (all)` job that ran this fixture
since it landed, by what the run's head contained:

| runs | contained #877 (per-object alloc/free: TSD gauge, mimalloc TLS slot) | hit |
|---|---|---|
| train D, E-era runs before it | no | 1 of ~6 (the first sighting, 2026-10-07) |
| trains R, U, V | yes | 3 of 3 |
| trains S, T (cancelled/other reds) | yes | not run to completion |

Small numbers, so this is a lead and not a finding: the rate looks higher once
#877 is in main, and #877's allocator change keeps a thread-local slot, which is
the state that goes wrong when a green thread migrates OS threads between
`actor_run_on_stop`'s `setjmp` and the panic's `longjmp` (lead 2 above: the
cached TLS address is then the old thread's). Worth checking first: any
thread-local address (or `__thread` / TSD key lookup) computed before a
`swapcontext`/`longjmp` point and reused after it, in the code #877 added. Local
runs still cannot reproduce it (macOS 26 here, CI is macOS 15).
