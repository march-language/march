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
