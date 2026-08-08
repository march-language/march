# Revived the standalone C scheduler unit tests (2026-08-08)

`test/test_scheduler.c` (10 cases) and `test/test_scheduler_mt.c` (3 cases, 4
schedulers) are back on `dune runtest`. Their RUN had been disabled: the
binaries still built (a standalone compile-check of `march_scheduler.c`), but
running them hung.

## Why they hung

`march_sched_run()` no longer auto-terminates when the run queues drain. It
loops until shutdown has been **requested** (`g_sched_shutdown`) **and** no live
procs remain (`g_live_procs <= 0`) — see `runtime/march_scheduler.c`'s idle
branch. In a compiled program `main` runs as a green thread and its return
supplies the shutdown request; a plain C test harness that spawns worker procs
and calls `march_sched_run()` has no main green thread, so `g_all_done` was
never set and the loop idle-`nanosleep`ed forever (lldb: stuck in
`march_sched_run` → `nanosleep`). This had been masked for weeks: the
`Signal.watch` commit (`9c97391a`) added a `march_signal_drain()` call that broke
the standalone LINK (the tests link only `march_scheduler.c`), so `dune build`
was silently red until a weak no-op `march_signal_drain` in `march_scheduler.c`
restored the link (2026-07-18) and exposed the hang.

## The fix

Each test spawns a finite, self-terminating batch of work. The harness now
requests shutdown up front — `march_scheduler.h` documents
`march_sched_request_shutdown()` as the required pre-run call — via a small
`run_to_quiescence()` helper that both files route their `march_sched_run()`
calls through. Requesting shutdown before the run means "stop once everything
drains": the spawned procs still run to completion (they keep `g_live_procs`
above zero until they finish), and only when the last one drains does the idle
branch observe `g_live_procs <= 0 && g_sched_shutdown` and exit. Regular
(non-daemon) procs keep `g_live_nondaemon` positive, so the premature
wake-idle-daemons endgame path never fires for these tests.

## Verification

Both runners compile clean and terminate. Stressed 25× each under host load ~10:
`ok=25 hangs=0 fails=0` for both (`test_scheduler`: 10 passed; `test_scheduler_mt`:
3 passed). The scheduler itself remains covered by every compiled actor
integration test; this restores the direct unit coverage of spawn/nested-spawn/
send-recv/wakeup/try-recv/stack-growth and the multithreaded spawn-10000/
send-recv/work-stealing paths.
