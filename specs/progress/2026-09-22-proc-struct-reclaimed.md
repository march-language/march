# A dead proc's struct is freed (epoch reclamation, mechanism PR 1)

Shipped 2026-09-22. This is mechanism PR 1 of [[2026-09-17-proc-struct-reclamation]],
built as that todo's "Chosen mechanism" specifies. Metas and tombstones (PR 2) are still
open there.

## What changed

- **`runtime/march_reclaim.{c,h}`** implements epoch reclamation.
  - Each OS thread has a slot, claimed lazily and recycled through a `pthread_key`
    destructor. Slots are never freed.
  - Scheduler threads are quiescent-state based. They announce a quiescent state at the
    top of every `sched_loop` iteration and go offline while idle-sleeping.
  - Every other thread brackets its reads with `march_reclaim_enter` / `exit`.
  - `march_reclaim_retire` stamps an object with the epoch it bumped. The object is
    freed once every online slot has announced a later epoch.
  - The retire list is polled from the retire path (every 32 retires) and from the
    preempt daemon's tick. The last `march_sched_run` also polls. Nothing ever waits.
- **The PROC_DEAD reap retires the proc** instead of leaking it.
- **Every suspending `swapcontext`** (yield, exit, park, recv, recv_until, trampoline)
  aborts if the thread is inside a critical section. So does every quiescent state.
- **New stats.** `Scheduler.stat(8)` counts proc structs freed. `stat(9)` counts those
  retired but not yet freed.

## The rule, and every holder read against it

> A resolved `march_proc *` is valid only inside the reader's critical section, and
> never across a context switch.

The rule is also in the header, next to `march_proc` and the meta's `green_thread`.

| Holder | How it satisfies the rule |
|---|---|
| `sched->current`, the proc's own green thread (`march_sched_current`, `march_self`, `task_wait_done`'s `self`) | Its own proc. A RUNNING proc is never reaped. |
| Run queues (deques, global runq, pin queue) | Membership only while RUNNABLE. A proc is reaped only after it has switched out, and it is in no queue then. `march_task_cancel_by_id` no longer stores DEAD blindly (below), so no proc is reaped while still registered anywhere. |
| `g_registry` slots | NULLed (release, under `g_registry_mu`) before the retire. The locked walkers (`march_sched_wait_idle`, `wake_idle_daemons`) see only unremoved procs. `march_sched_find` (lock-free, now with atomic slots) is only called inside a critical section, and its result is used only there. |
| `MARCH_DEBUG` fault-handler registry walk | Not converted, by argument. On a scheduler thread it runs inside the implicit critical section. On any other thread it is a signal-context diagnostic on the way to `_exit` and cannot enter one. There is a comment at the site. |
| BLOCK waiter list: the waiter | A live parked proc. It always unlinks itself before leaving `mbox_block_register_and_park`. |
| BLOCK waiter list: the sender's `target` held across its park | Converted. The critical section is suspended around the park. Afterwards `target` is dereferenced only if `self->send_wait_linked` still reads 1. Every unlinker clears that flag after its last touch of the link, and the reap drain clears it before the retire, so 1 proves the target has not been freed. `march_sched_send` then re-resolves `target` by pid. The foreign-thread sleep-poll also suspends and re-resolves. |
| Timer heap (WAKE and SEND) | Converted: entries store the **pid**. `timer_service` resolves each one inside a critical section (the daemon is a foreign thread). `wait_idle`'s timer scan does the same. |
| fd-wait entries | Bounded. The entry lives on the waiter's stack and is removed under `g_fdwait_mu` before the waiter returns. The daemon wakes under the same mutex. |
| Resolver request | Bounded by the `done`/`woke` handshake: the caller cannot leave until the wake has been issued. |
| Reap-time waiter wakes, `wake_idle_daemons` | The procs they wake are live (a parked waiter; a registered daemon under the mutex). |
| meta `green_thread` | NULLed by the actor's own thread at both exits of `actor_green_thread`, before its proc can die. The readers: |
| - `march_send` | Load and `march_sched_send` inside one critical section. |
| - `march_actor_call` | A NULL test only, outside. Then reload and send inside a critical section that ends before the waits (the waits park). |
| - `march_send_after` | Load and push inside a critical section. The entry keeps the pid. |
| - `deliver_monitor_down` | The first load is a NULL test only. The second load and `march_sched_send_control` run inside a critical section, under `g_tbl_mu`. |
| - `do_actor_death` | Load and `march_sched_request_stop` inside a critical section. |
| - `march_actor_stop` | Load, request_stop, and the identity test against the current proc inside a critical section. Outside it, a freed address could be reused by the caller's own proc. The wait runs outside. |
| - `hcr_send_markers` | Load and inject (a send) inside a critical section. |
| - `march_mailbox_size`, `march_actor_set_mbox_limit` | Load and use inside a critical section. |
| - `hcr_marker_orphaned`, `hcr_snapshot`, `activate_actor_green_thread` | NULL tests, or the writer. No dereference. |
| - `march_test_actor_bind_green_thread`, `march_actor_inject_migrate_msg` | Test seams. `test_broadcast_migrate_leak.c` now uses a stand-in DEAD struct, because a real reaped proc is freed. |
| Task word 2 | Converted: a tagged **pid**. `march_task_cancel_by_id` resolves it inside a critical section. |
| Task word 5 | `task_wait_done` clears it (compare-exchange self→0, so another waiter's registration survives) on **every** exit. The trampoline loads and wakes inside one critical section. |
| Reply-ref field 0 | Converted: a tagged **pid**. `march_actor_reply` resolves it inside a critical section. A caller that timed out and exited resolves to NULL, which is a dead send, as before. The "legacy raw proc pointer" path is gone: nothing produced one, and a non-reply-ref value is now dropped. |

### Findings on the way

- **A dormant data race in `march_sched_find`.** It did a plain read of a registry slot
  that the reaper writes under the mutex. ThreadSanitizer reported it on the first
  fixture run. Harmless while nothing called it. The slots are atomic now.
- **`march_task_cancel_by_id` could make sched_loop reap a parked proc.** A blind
  `PROC_DEAD` that landed between a park's `PROC_PARKED` store and its `swapcontext`
  made sched_loop reap a proc still registered as a waiter. That already recycled a
  live stack before this change. It is now a compare-exchange from RUNNABLE or RUNNING
  only.
- **The driver's CAS key does not distinguish `MARCH_SANITIZE=thread` from any other
  value.** An "ASAN" build returned the cached TSAN binary (`nm`: `__tsan_init`, no
  `__asan_init`). Filed separately. Every sanitizer build below cleared
  `.march/cas` first and was checked with `nm`.

## Evidence

The fixture is `test/native/proc_reclaim_kill_respawn.march`. It is also a native golden,
but the golden only proves the fixture runs and frees procs. Each of 1500 rounds does:

- spawn a worker with a 4-deep BLOCK mailbox,
- hammer it from a task (256 sends),
- make three 1 ms timed calls (every 10th round against a handler that replies long
  after the caller has exited),
- `send_after` to it,
- await a task from inside another task,
- kill the **previous** round's worker while its traffic is still in flight,
- then await and `task_cancel_by_id` the previous round's tasks, which are finished and
  usually already reaped.

An instrumented copy of the runtime confirmed each converted path runs on every run:

| path | per run |
|---|---|
| BLOCK park | ~37k |
| BLOCK re-resolve → NULL | ~270 |
| timer SEND to a reaped pid | ~1.3k |
| timer WAKE for a reaped pid | ~2.5k |
| reply to a reaped caller | ~15 |
| cancel of a reaped pid | ~3k |
| word-5 clears | ~3k |

**Sanitizers.** All runs were in `march-sbx-test-ubuntu` (Linux/aarch64, clang 18) with
`MARCH_NUM_SCHEDULERS=4`.

| build | runs | result |
|---|---|---|
| ASAN (`MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`) | 10 | **10/10 clean**, rc 0 |
| TSAN (`MARCH_SANITIZE=thread`) | 40 | **0 use-after-free.** No report signature absent from base (below) |
| **Red control**: `march_reclaim_retire` frees immediately (no grace period), ASAN | 10 | **10/10 `heap-use-after-free`**. The reports are in `march_sched_wake` via `do_actor_death`, and via `march_send → march_sched_send`: the original bug's sites |
| Red control, TSAN | 10 | `heap-use-after-free` in 7/10 (`mbox_lock_acquire` / `march_sched_send` / `mbox_user_count` from `march_send`) |

- **TSAN against base.** The same fixture was compiled against the base runtime and run
  10 times, with this change's build run alongside. Excluding the preemption-flag reports
  (`march_preempt_request` is a deliberately plain global written by the signal handler,
  and `signal handler spoils errno`), both builds have exactly one remaining signature:
  `march_sched_send | sched_loop`. It is a green thread reading its own scheduler's
  `current` field, which TSAN's fiber model sees as cross-thread. Its rate is the same on
  both builds, so it is pre-existing.
- **One unexplained hang.** One TSAN run hung, 1 of the first 5, on the build before
  the atomic-slot fix. Two threads were spinning and the rest asleep. The container has
  no ptrace, so no backtrace. The 40 runs since, on the final build, all completed.
  macOS native: 100/100 at 4 schedulers.

**Suites.** `scripts/run-tests.sh` (every alcotest suite, including the z3-backed
refinement suite) and `dune build @runtest` (the dune-rule tests the script skips). The
new fixture had to be added to `test/refine_audit/corpus.baseline`, which is what its
audit sweep covers. One golden, `native_actor_monitor_down_reason`, was SIGKILLed (137)
at iteration 55 of its 100-run loop **with correct output**, while three other sessions
were running their own full suites at load average 143. Re-measured at load 11-17,
alternating with a base-runtime build of the same fixture: **0 of 300 failures on each**.
That is the documented load artifact, not a finding.

**Retained memory**, compiled `--opt 2`, macOS, peak RSS:

| workload | base | this change |
|---|---|---|
| actor churn (spawn, send, kill), 50k | 106.3 MB | 95.9 MB |
| actor churn, 200k | 196.5 MB | 148.6 MB |
| → per dead actor (slope) | **601 B** | **351 B** |
| 200k sequentially awaited tasks | 62.0 MB | 13.1 MB |
| 400k awaited tasks | 120.8 MB | **22.9 MB** |
| → per finished task (slope) | **308 B** | **~50 B** |

The actor term drops by the 256 B proc struct. The ~350 B that remains is the meta, which
is PR 2. The task remainder is the registry's 8 B slot per pid, plus its leaked growth
arrays; both are out of scope in the todo. `stat(8)`: 199,966 of 200,001 procs freed at
exit, 34 still in their grace period.

**`bench/actors/fanin_flood.march`.** Compiled `--opt 2` against a compiler built at the
base commit, on the same box, run order shuffled. The box is shared: load average 11–50
during these runs.

| | base | this change | change with every `march_reclaim_*` a no-op |
|---|---|---|---|
| fanin_flood (400k msgs), n=60 | 129.8 ms | 140.7 ms (+8%) | 125.8 ms (n=50) |
| 10× variant, n=30 | 1066 ms | 1269 ms (+19%) | 1037 ms |
| 10× variant, `MARCH_NUM_SCHEDULERS=1`, n=8 | 420.8 ms | 428.6 ms (+1.9%) | 425.1 ms |

- **This is a regression, and it is not fully explained.** The no-op column says the
  other edits (pid holders, atomic slots, the flag) cost nothing. The cost is in the
  reclaim calls.
- **Single-threaded the calls cost about 2 ns per send.** Counted: 4M enters, all on
  the scheduler-thread path. Only about 12k fenced announcements happen, from idle
  wake-ups. About 19k BLOCK suspends.
- **At 8 threads the gap is 8–19%.** It could not be pinned to one entry point.
  Ablations (enter/exit, quiescent states, the waiter flag) each moved the median by
  less than the p10–p90 spread at that load. `sample` shows no significant self time in
  `march_reclaim_*`: the run is dominated by `mbox_lock` spinning on the sink.
- **So the likely mechanism is contention timing, not instruction count.** That is not
  proven. It is recorded in the todo as open, for a decision (see "Mechanism PR 1 as
  landed").

## Deviations from the design

- **A quiescent state stores without a fence.** Only an offline-to-online transition
  needs the Dekker fence.
- **Everything else is as specified.**
