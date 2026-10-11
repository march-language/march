# `[P2]` `native_run_until_idle_ping_pong` segfaulted once at 14 schedulers (CI, amd64)

Seen 2026-10-04 in `test (ubuntu-24.04, rest)` of #767's CI run 37167730689 (job
111334108065), on a tree that had just merged Observe R2 (#766: the crash ring and
`spawned_by` in `runtime/march_scheduler.c`). The dune rule runs
`MARCH_NUM_SCHEDULERS=14 ./native_run_until_idle_ping_pong`; it printed
`Segmentation fault (core dumped)` and nothing else. No other CI run in the preceding day
shows it.

Not reproduced: 0/100 on macOS arm64 and 0/300 in `ci/Dockerfile.ubuntu` (linux/arm64),
both at 14 schedulers on the same tree. CI is amd64.

A 14-scheduler segfault has a known cause in this runtime: a `tl_sched`-reading helper
inlined across a green-thread switch, which reads the old thread's scheduler after the proc
migrated (the fix is `noinline`). Check any helper Observe R2 added on the dispatch or
park path for that first. Next step: a loop of this binary on an amd64 machine (or
`--platform linux/amd64` emulation), with a core dump to get the faulting pc.

## TSAN on macOS, 2026-10-11: nothing, apart from a TSAN-only wedge

`MARCH_SANITIZE=thread` build (macOS arm64, LLVM 22), 14 schedulers: no TSAN report, but
every run (11 of 11) wedges before printing anything. A 1000-ball version wedges in 9 of
11 runs at 2 schedulers and finishes at 1. It never wedges in plain or ASAN+UBSan builds,
and it still wedges with the runtime at `-O0` (so it is not the TLS-hoist class named
above) and with `-DMARCH_DEBUG` (no run-queue tripwire fires). That is a lost-proc hang,
not a SIGSEGV, so it does not explain this crash. Filed as
`specs/todos/2026-10-11-macos-tsan-scheduler-wedge.md`. The only refcount race TSAN
reported (the immortal-check read in `march_decrc`, now relaxed-atomic) cannot cause a
fault: a mortal count can never reach the 2^40 immortal threshold.
