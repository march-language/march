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

## Sightings 3 and 4, and a lead on the rate (2026-10-08)

Same signature (`exit status 132 (above 128: signal 4)`, `on_stop blew up` lines
printed) on merge train U's CI (run 37794937229, `test (macos-15, all)`) and train V's
(run 37813005310). The sightings so far, against whether the run's head contained
#877 (per-object alloc/free: TSD gauge, mimalloc TLS slot):

- before #877: once (the first sighting, main after train D, 2026-10-07; train D's own
  CI and the re-run of that job both passed it);
- with #877 in the tree: trains R, U and V hit it; train T's full macOS job passed it;
  train S was cancelled before that job finished.

That is 3 hits in the 4 macOS runs that finished with #877 in the tree. I did not
count the macOS runs before #877 (many passed it), so this is a lead, not a rate.
#877's allocator change keeps a thread-local slot, and thread-local state is what
goes wrong when a green thread migrates OS threads between `actor_run_on_stop`'s
`setjmp` and the panic's `longjmp` (lead 2 above: a cached TLS address is then the
old thread's). Worth checking first: any thread-local address (or `__thread` / TSD
key lookup) computed before a `swapcontext`/`longjmp` point and reused after it, in
the code #877 added. Local runs still cannot reproduce it (macOS 26 here, CI is
macOS 15).

## 2026-10-12: did not reproduce under ASAN on Linux arm64

30 runs at `MARCH_NUM_SCHEDULERS=14` under `MARCH_SANITIZE=1
MARCH_DEBUG_RUNTIME=1` (`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`), Docker
`march-ci-ubuntu-step6b` (arm64, glibc 2.39), concurrently with a 6-way ASAN
sweep for load: 0 failures, no sanitizer report. The fixture is also clean in
the full `scripts/native-sanitize-sweep.sh` error pass at 1 and 14 schedulers.

## 2026-10-12: fifth sighting, and SIGILL is not a `brk`

Main's CI run 38226974123, job `test (macos-15, all)` (114736773585), on
0c50b9a4c: `Illegal instruction: 4`, `exit status 132`, after 19 of the 20
`on_stop blew up` lines. So the trap point moves: 13, 20, 19 lines across
sightings (whether the last stdout line was written is never shown, since
stdout goes to the `.out` file).

**SIGILL rules out every trap the earlier notes listed.** On arm64 macOS a
`brk` (`__builtin_trap`, `llvm.trap`, an `unreachable` lowered as a trap, a
UBSAN trap) raises SIGTRAP, exit 133, not SIGILL; measured with a two-line C
program: `__builtin_trap()` exits 133, executing `.inst 0x00000000` exits 132.
SIGILL means the CPU fetched a word that is not an instruction: control
reached a bad address that is executable (zero padding, `__TEXT,__const` such
as mimalloc's all-zero `_mi_page_empty`, `__TEXT,__cstring`), or an
instruction M1 (CI) lacks and M3 (local) has. Neither has been shown. Also:

- The fixture's IR has 5 `unreachable`s, all `switch` defaults (in `pushed`,
  `__drop$List_Int`, `__drop$List_String`, `__drop$Option_T0_`,
  `__drop$Result_V0_String`); clang folds them, and the local binary contains
  no `brk` at all (`otool -tV`), and in any case they would be SIGTRAP.
- No `-mcpu` is passed by default (`--target-cpu` unset), so codegen targets
  the arm64-apple-macosx baseline (apple-m1).
- mimalloc's `MI_TLS_SLOT=89` (#877): libpthread's `tsd_private.h` assigns
  keys 80-89 to CoreData, which this program does not load. Not ruled out on
  macOS 15, but no consumer is known.
- Darwin's `setjmp`/`longjmp` (libsystem_platform, disassembled): the munge
  token is TSD slot 7, process-wide; `longjmp` restores the setjmp thread's
  signal mask and resets the alt-stack flag on the CURRENT thread. Nothing in
  it depends on staying on one OS thread.

## 2026-10-12: still does not reproduce; the next sighting will name the site

- 1,800 runs of the `--opt 2` binary (300 each, two loops at once at 1, 4 and
  14 schedulers, machine load average 55-75 from other sessions), 1,200 with
  `MARCH_DEBUG_RUNTIME=1`, 1,200 at `--opt 0`: all exit 0 (M3 Max, macOS 26,
  Apple clang 17).
- 180 runs under ASAN+UBSAN (`MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`,
  `halt_on_error=1`) on Linux arm64 (`march-ci-ubuntu-step6b`) at 1, 4 and 14
  schedulers, concurrently: all exit 0, no report.

The runtime now handles SIGILL and SIGTRAP (specs/progress/2026-10-12-fatal-trap-report.md):
it prints the fault line, `static pc=... lr=... insn=...` and a frame-pointer
walk, and this fixture's rule sets `MARCH_FATAL_BACKTRACE=1`, so the next CI
sighting prints symbol names for the trapping pc and its callers (the CI binary
is not kept, so names are what matter). Read the frames and the `insn=` word
first: a zero word or ASCII bytes means a wild jump (look at who called
through a pointer); a real encoding means an instruction M1 lacks.
