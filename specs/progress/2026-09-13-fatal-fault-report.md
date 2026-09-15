# A fatal SIGSEGV/SIGBUS in a compiled program now says where it happened

**Landed 2026-09-13.**

## The defect

The runtime installs one handler for SIGSEGV and SIGBUS
(`march_sigsegv_handler`, `runtime/march_scheduler.c`) to grow green-thread
stacks lazily. Any fault that is not a stack-growth fault ends in `_exit(128 +
sig)`, deliberately not a re-raise: re-raising wedged the process in an
unkillable kernel wait (documented at the call site).

Outside `MARCH_DEBUG` builds that exit was **silent**. A compiled program that
crashed exited 139 or 138 with nothing on stderr. In CI this meant an
intermittent crash carried no information at all.
`specs/todos/2026-09-04-actor-monitor-down-reason-sigsegv-on-linux.md` has had
two sightings, neither saying where, and 60,000+ local runs have not reproduced
it.

## What landed

Before `_exit`, `march_report_fatal_fault` writes one line to fd 2:

```
march: fatal SIGSEGV si_code=1 addr=0x1000 pc=0x7ffffef0badd sched=0 pid=0 status=1 fault outside its stack
```

- signal, `si_code`, fault address;
- the faulting pc, read from the `ucontext` on macOS arm64/x86_64 and Linux
  x86_64/aarch64 (0 elsewhere);
- the scheduler and green thread that were current, with the proc's status;
- where the address sits relative to that proc's stack reservation: guard page
  (overflow), uncommitted region, committed stack, or outside it. With no
  current proc, it says so.

It is async-signal-safe because the heap may be the thing that is corrupt:
`write(2)` only, a fixed 512-byte stack buffer, hand-rolled hex and decimal, no
stdio, no locks, no allocation. It reads only the current proc; the
`MARCH_DEBUG` path's registry walk stays debug-only. The exit status is
unchanged (128+signo), so `$?`-based callers and the oracle sweep's
crash classification see exactly what they saw before.

## Verification

A program calling `strlen` on address `0x1000` through FFI prints the line and
exits 139:
- macOS arm64 (one scheduler and four);
- Linux x86_64 (Docker, Rosetta, clang 18);
- Linux aarch64 (Docker, native).

`march_scheduler.c` compiles with `-Wall` and no warnings on both Linux arches.
No test asserts a crashing program's stderr (checked `test/dune` and
`test/*.ml`).
