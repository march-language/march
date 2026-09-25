# A preemption tick at worker-thread exit trapped the allocator (fixed 2026-09-25)

Filed 2026-09-24 as `specs/todos/2026-09-24-flake-supervisor-init-arg-restart-sigtrap.md`
("compiled native tests die with SIGTRAP under load"). Fixed on branch
`fix/preempt-tick-at-thread-exit`.

## Symptom

Compiled March programs and C scheduler tests occasionally died with no output:
`Trace/BPT trap: 5` (SIGTRAP) or `Killed: 9`, only under heavy parallel load, never on
rerun. Three native-golden sightings:

- 2026-09-23: a golden during PR #604 verification (46/46 clean reruns).
- 2026-09-24: `native_erased_type_id` (30 direct + 45 concurrent clean reruns).
- 2026-09-25: `native_compare_nan`, on its first run after dune built it.

It also showed up in the C unit test `test_scheduler_mbox_runner`, at about 0.3% of
runs with 32 copies in parallel, on every build including unmodified `origin/main`.
That is how the mechanism was found.

## Mechanism

Every macOS crash report had the same faulting stack, on a scheduler worker thread that
was **exiting**:

```
thread_start -> _pthread_start -> _pthread_exit -> _pthread_tsd_cleanup
  -> mfm_free                                          (dyld TLV teardown)
     or slot_release -> _tlv_get_addr -> instantiateVariable -> mfm_alloc
  <signal> _sigtramp -> march_preempt_signal_handler
     -> _tlv_get_addr -> instantiateVariable -> mfm_alloc
     -> _os_unfair_lock_recursive_abort   (EXC_BREAKPOINT, reported as SIGKILL)
     or an xzone freelist trap            (EXC_BREAKPOINT, reported as SIGTRAP)
```

1. The preempt daemon reads `g_scheds[i].running == 1`, sets `preempt_tick`, and
   `pthread_kill`s the thread.
2. The worker has meanwhile left `sched_loop` (it clears `running`, but the tick is
   already on its way) and is in `pthread_exit`. dyld is tearing its TLV block down, or
   `march_reclaim`'s `slot_release` key destructor touches `_Thread_local tl_reclaim`,
   which instantiates the TLVs again (a malloc).
3. The tick lands inside that malloc/free. The handler finds this thread in `g_scheds`
   with a pending tick and writes the `_Thread_local` `march_tls_reductions`. The TLV is
   gone, so `_tlv_get_addr` mallocs again, inside the allocator the tick interrupted,
   and the allocator's recursive-lock check or freelist check traps.

This is the "first TLS access mallocs inside a signal handler" hazard that `sched_loop`
already guards against at thread **start** (it touches `march_tls_reductions` before
publishing `running`), here at thread **exit**. Every program with more than one
scheduler thread goes through it at shutdown, which fits all the sightings: programs
that start scheduler threads, seen only under load, and slower first runs.

Of the 29 base-side crash reports from the stress runs below, all 29 have
`march_preempt_signal_handler` under `_pthread_tsd_cleanup`. Most were in dyld's own TLV
teardown (`mfm_free`), and a few were under `slot_release`. So the handler fix is the
one that closes most of them, and the `slot_release` fix closes a second route into the
same state.

## Fix

Two independent changes, each closing a separate re-entry path:

- **The handler touches TLS only while its thread is inside `sched_loop`.** There is a
  new per-scheduler `_Atomic int tls_live` (`runtime/march_scheduler.h`). `sched_loop`
  sets it right after it materialises `march_tls_reductions`, and clears it as its last
  statement. `march_preempt_signal_handler` still consumes the tick, and still treats it
  as ours (so it is not chained to the host). It writes `march_preempt_request` /
  `march_tls_reductions` only if an acquire load of `tls_live` reads 1. The skip path
  touches no TLS and calls nothing. This also applies to scheduler 0 after its loop,
  where there is no quantum left to end.
- **Worker threads block the preemption signal before they exit.**
  `sched_thread_entry` calls `pthread_sigmask(SIG_BLOCK, {march_preempt_signal()})`
  after `sched_loop` returns. A tick already pending stays pending and is discarded with
  the thread, so none is delivered during `pthread_exit`, including one that would be
  chained to a host handler. This is done on worker threads only: scheduler 0 is the
  caller's thread, and its mask must survive `march_sched_run`. How the handler is
  installed (SIGUSR1, `SA_ONSTACK`, chaining) is unchanged.
- **`slot_release` (`runtime/march_reclaim.c`) no longer touches `tl_reclaim`.** It
  works only from its argument. It used to clear `tl_reclaim.slot` so that a later key
  destructor re-entering `march_reclaim_enter` would claim a fresh slot. That job moved
  to `my_slot`, which now treats `t->slot` as ours only while it is still the key's
  value (`pthread_getspecific(g_key) == t->slot`). pthreads clears the key before it
  calls the destructor, so a stale slot is detected and a new one is claimed. The check
  runs only on the depth 0 -> 1 transition, on `resume` and on `online`, and
  `pthread_getspecific` is a TSD read with no malloc.

## Evidence

`test_scheduler_mbox_runner` was built directly with the dune rule's command
(`cc -std=gnu11 -DMARCH_NUM_SCHEDULERS=4 test_scheduler_mbox.c march_scheduler.c
march_reclaim.c`) and run with `MARCH_NUM_SCHEDULERS=""` under a 120 s `alarm` per run.
Base (unmodified `origin/main`) and fix runs were interleaved on the same machine:

| batch | binary | runs | parallel | abnormal exits | load avg (start -> end) |
|---|---|---|---|---|---|
| base1 | origin/main | 4000 | 32 | 11 (all `Killed: 9`, 137) | 5.75 -> 7.06 |
| fix1  | fix         | 4000 | 32 | 0 | 5.60 -> 7.76 |
| base2 | origin/main | 4000 | 32 | 15 (137) | 7.76 -> 8.76 |
| fix2  | fix         | 4000 | 32 | 0 | 8.76 -> 10.23 |
| fix3  | fix         | 8000 | 64 | 0 | 9.89 -> 10.31 |
| base3 | origin/main | 8000 | 64 | 22 (137) | 10.31 -> 12.82 |

In total, base had **48 / 16000** abnormal exits (0.30%) and the fix had
**0 / 16000**. The base side left 29 crash reports in `~/Library/Logs/DiagnosticReports/`
(ReportCrash throttles), and all of them show this stack. The fix side left none.

The scheduler/actor C runners (`test_scheduler*`, `test_preempt_signal`,
`test_signal_watch`, `test_hcr_migrate_order`, `test_vault_concurrency`, …) all pass.
The Linux ASAN container recipe was not run, because the Docker daemon was not running
on this machine.
