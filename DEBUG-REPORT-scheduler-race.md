# Scheduler burst-spawn data race — debug report

## Summary

The non-deterministic startup crash on a burst of `task_spawn`s is a **data race
on the Task heap object** in `march_task_spawn_thunk` (runtime/march_runtime.c),
**not** an ABA/UAF in the scheduler's run queues. The Treiber-stack ABA hazard
the prompt flagged was already fixed on this branch (the external-spawn stack was
replaced by a mutex FIFO `g_runq_*`), and the Chase-Lev deque is textbook-correct.

TSan pinned the real race; two secondary real-but-benign races and a cluster of
TSan false positives (from a correct release-fence idiom TSan can't model) were
also addressed so the repro runs 100 % clean under `MARCH_SANITIZE=thread`.

## Minimal repro

`/tmp/burst2.march` (and the committed regression `test/native/task_burst_await.march`):
`main` spawns a burst of `task_spawn(fn _ -> …)` tasks up front, each running a
short `fib`, some themselves spawning a sub-task (the conduit worker→heartbeat
shape), then awaits/joins them. Compile with `MARCH_SANITIZE=thread` and run in a
loop; TSan reports on essentially every run before the fix.

## The racing pair (TSan)

```
WARNING: ThreadSanitizer: data race
  Write of size 8 at 0x…720 by thread T4 (the spawned proc):
    #0 march_thunk_trampoline  march_runtime.c:1833   task[2] = march_sched_current()
    #1 proc_trampoline         march_scheduler.c:589
  Previous write of size 8 at 0x…720 by thread T1 (the spawner / main green thread):
    #0 march_task_spawn_thunk  march_runtime.c:1895   task[2] = p   (also task[3]=0, task[4]=0)
  Location is heap block of size 40 (the Task object) allocated by march_alloc.
```

## Mechanism (the real bug)

`march_task_spawn_thunk` published the proc via `march_sched_spawn(...)` and *then*
initialised the Task object:

```c
march_proc *p = march_sched_spawn(march_thunk_trampoline, wa);
if (task) { task[2] = p; task[3] = 0; task[4] = 0; }   // <-- AFTER publish
```

With the M:N work-stealing scheduler, the instant `march_sched_spawn` returns
another OS thread may already have stolen and run `march_thunk_trampoline`, which
writes `task[2]` (proc handle, line 1833), `task[3]` (tagged result, line 1847)
and release-stores `task[4]=1` (done flag, line 1849). The spawner's post-publish
stores race those with **no synchronization** between them, and can **clobber a
completed result and reset the done flag to 0** → `task_await` hangs forever, or a
zeroed/garbage-tagged result is returned. The author had already moved the
`task[2]` write into the trampoline to "close the race where the spawning thread
writes task[2]=p only AFTER march_sched_spawn returns" (comment at runtime.c:1828)
but left the three racy post-publish stores in place.

This is genuinely unsynchronized because the trampoline only ever synchronizes
with the spawn *setup* (via the deque push→steal edge, which happens-before line
1893); the spawner's stores at 1895-1897 execute *after* that edge, concurrently
with the running trampoline.

## The fix (minimal)

runtime/march_runtime.c — in both `march_task_spawn_thunk` and
`march_task_spawn_with_cancel_thunk`, **remove the post-spawn stores entirely**.
They are redundant: `march_alloc` (calloc) already zero-inits result/done, and the
trampoline records `task[2]` itself as its first action. Nothing may touch the
Task object after the proc is published. (This completes the author's intended
fix.)

### Secondary fixes (correctness / TSan-cleanliness)

1. **`march_scheduler.running` made `_Atomic`** (march_scheduler.h + the three
   accesses in march_scheduler.c: sched_loop set 1 / set 0, preempt_daemon read).
   A real data race: the preemption daemon read the plain `int running` of every
   scheduler while each scheduler thread wrote its own — TSan `sched_loop:776`
   write vs `preempt_daemon:1339` read. Benign in effect (worst case a missed or
   spurious SIGUSR1) but a real non-atomic race; now release-store / acquire-load.

2. **`march_deque_push` publishes `bottom` with `memory_order_release`** instead of
   a standalone `atomic_thread_fence(release)` + relaxed store (march_deque.h).
   Both are correct Chase-Lev formulations (Lê et al., PPoPP'13), but TSan does not
   model that a standalone release fence turns a following relaxed store into a
   release op, so it reported the proc-init writes in `sched_spawn_common`
   (`:656/:663/:665`) as racing the stealing scheduler's dispatch writes
   (`sched_loop:908/909/914`). These were **false positives** — the deque was never
   buggy — confirmed because switching to the release-store form made exactly those
   reports vanish while the fix required no logic change. This is the one "make
   TSan happy" change; it is a strict correctness-preserving tightening.

## Evidence

| check | before | after |
|---|---|---|
| minimal burst under TSan (100×) | data-race report ~every run | **0 reports / 100** |
| await-burst regression under TSan (50×) | race / wrong sum | **0 reports, 797200 every run** |
| minimal burst plain (300×) | (rare crash; not reproduced locally) | **0 crashes / 300** |
| await correctness plain (50×) | — | **203385 / 797200 every run** |
| codegen suite (`run_codegen.exe`) | — | **405 tests, Test Successful** |
| eval suite (`run_eval.exe`) | — | **232 tests, Test Successful** |

### forgepm full-stack repro

With the fixed toolchain installed to `origin-test`, the WORKER-REPRO build now
**reliably progresses past the crash point** — it prints both
`WORKER-REPRO: registering performers` and `WORKER-REPRO: starting conduit
workers/cron` (3/3 runs), where before the fix it died there with the
non-deterministic garbage-tag/SIGSEGV. It now hits a **new, separate,
deterministic error**: an RC underflow at a stable `seq=24499` with an identical
stack every run — `Bastion.Logger.debug → Logger.do_log` inside
`Conduit.Worker.start_workers` (a Perceus RC-accounting double-decref in the
logger path; the diagnostic address/tag varies only as heap-address noise, the
stack and seq are deterministic). This is distinct from — and downstream of — the
scheduler race fixed here, and is out of scope for this task.

Note: `test/test_scheduler_mt` (and `test_scheduler`) **wedge** — they spawn procs
and call `march_sched_run()` but never `march_sched_request_shutdown()`, so the
scheduler idles forever. Verified pre-existing: the MT runner wedges identically
when compiled against the pristine `git HEAD` runtime (rc=137, no output). Matches
the known "wedging scheduler tests" repo quirk; unrelated to this change.

## Regression test

`test/native/task_burst_await.march` (+ `.expected` `797200`, wired into
`test/dune` under `runtest`): spawns a burst of tasks up front, awaits them all,
checks the exact sum, over 40 rounds — a clobbered result/done flag yields the
wrong sum or a hang. Header documents running it under `MARCH_SANITIZE=thread`.

## Files changed

- runtime/march_runtime.c — remove post-publish Task stores (both spawn thunks)
- runtime/march_scheduler.h — `_Atomic int running`
- runtime/march_scheduler.c — atomic access to `running` (3 sites)
- runtime/march_deque.h — release-store `bottom` in push
- test/native/task_burst_await.march, .expected, test/dune — regression
