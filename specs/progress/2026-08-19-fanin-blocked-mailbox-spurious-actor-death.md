# A wake with an empty mailbox killed a live actor (compiled, multi-scheduler)

**Fixed 2026-08-19.** Found during a pre-0.3.0 actor stress sweep.

## Symptom

`bench/actors/fanin_flood.march` — one of the four gates `scripts/actor-load.sh`
runs — intermittently printed `call failed: actor not alive` instead of
`delivered 400000`, with exit code **0**, no crash, no signal, empty stderr. The
`Sink` actor it calls is never killed, never supervised, never crashes.

Measured **4 failures in 100 runs (~4%)** on the compiled binary. A single clean
run — all the harness or a developer normally does — does not catch it.

Two variables each fully suppressed it, which is what scoped the search:

| Variable | Result |
|---|---|
| Remove `Actor.set_queue_limit(pid, 1024, 3)` (drop the BLOCK policy) | 0/30 failures |
| `MARCH_NUM_SCHEDULERS=1` | 0/30 failures |

## Root cause

`march_sched_send` pushes the message under `mbox_lock` but issues its wake
**after** releasing the lock. Two senders racing one receiver therefore produce
two wakes for messages the receiver drains as a single batch:

1. Sender A pushes `msg1`, reads `status == PROC_PARKED`, releases the lock.
2. Sender B pushes `msg2`, reads `status == PROC_PARKED`, releases the lock.
3. A's `march_sched_wake` resumes the receiver, which pops **both** messages,
   runs both handlers, returns to `recv`, finds the mailbox empty, and re-parks.
4. B's already-issued wake now lands, resuming the receiver with a
   **legitimately empty** mailbox.

`march_sched_recv_mode` returned `MARCH_RECV_NO_MSG` for step 4.
`actor_green_thread` (`runtime/march_runtime.c`) reads that as "I was killed":

```c
void *msg = march_sched_recv_user();
if (msg == MARCH_RECV_NO_MSG) break;  /* woken without message (killed) */
```

so it broke its dispatch loop and ran `do_actor_death` on an actor whose
`$alive` word was still **1** — confirmed by instrumentation printing
`alive=1` at the death site. A later `Actor.call` on that pid then failed the
`actor_alive_load` check in `march_actor_call` with `"actor not alive"`.

The BLOCK policy made the window reachable so often because
`mbox_wake_send_waiters_if_low` is a wake-**all**: it releases a whole herd of
blocked senders at once, which is precisely the many-concurrent-senders burst
step 1–2 needs. `MARCH_NUM_SCHEDULERS=1` suppressed it because the sender's
wake and the receiver's re-park cannot then interleave across OS threads.

### How it was pinned (not deduced)

Argument-by-elimination was not trusted. A temporary `g_dbg_wake_src` tag was
set at each of the six `march_sched_wake` call sites and printed at the
`NO_MSG` decision point. All three captured failures reported `wake_src=1` =
`march_sched_send`, ruling out `wake_idle_daemons` (the one path whose
*documented purpose* is ending a daemon's recv without a message), the timer
service, control sends, and the send-waiter drains.

Note `march_actor_call`'s **timed** path already looped for exactly this reason
("Woken with an empty mailbox but time remains"). Two of the three `NO_MSG`
consumers coped with spurious wakes; the actor dispatch loop and the
wait-forever path did not.

## Fix

`MARCH_RECV_NO_MSG` from the untimed receive is now reserved for a **real stop
request**, rather than meaning "you happened to wake with an empty mailbox":

- New `march_proc.stop_requested` + `march_sched_request_stop(p)`
  (`runtime/march_scheduler.{h,c}`).
- `march_sched_recv_mode` parks in a **loop**, re-checking the mailbox on every
  wake and re-parking unless `stop_requested` (or `PROC_DEAD`) is set.
- The only two callers entitled to end a blocking receive without a message now
  go through the flag: the shutdown endgame (`wake_idle_daemons`) and actor
  death (`do_actor_death`, i.e. kill/crash/supervised stop).

No lost wakeup is introduced: the emptiness check and the `PROC_PARKED` store
both happen under `mbox_lock`, which senders also hold across
push-then-read-status, so the two critical sections are serialized.

### The regression this fix introduced first, and why it is worth recording

The first version of the loop wrote `swapcontext(&p->ctx, &tl_sched->sched_ctx)`
inline in the loop body. That traded the 4% death for a **~2.5% hard deadlock**.

`tl_sched` is `_Thread_local`, and a proc that parks is resumed by whichever
scheduler wins the wake — possibly on a **different OS thread**. `noinline` on
`march_sched_recv_mode` only stops *its callers* from hoisting the TLS read; it
does nothing about the function's own loop-invariant code motion. So the
compiler cached `tl_sched` in a register, and after a migration iteration 2
swapcontext'd into a **stale scheduler's** `sched_ctx`. The real scheduler then
never ran that proc's `PROC_PARKED → PROC_WAITING` transition, so every waker
spun on `PROC_PARKED` forever.

Diagnosed from a live hang with a spin-timeout dump:

```
[wake] STUCK >3s target=0x1015fa890 status=4 wake_pending=1 daemon=1
       wait_mode=2 mbox_count=1 send_waiters=0x0
```

`status=4` is `PROC_PARKED`, `mbox_count=1` — a message sitting undelivered
while every scheduler thread was idle.

This is the same hazard `mbox_block_register_and_park` already documents, with
the same remedy: the park now lives in its own `NOINLINE` helper
(`mbox_recv_park_once`) that the loop calls fresh every iteration, so the
`tl_sched` read cannot be hoisted across the migration. Caching `p` across
iterations remains fine — the proc object is the same one whichever thread
resumes it.

## Verification

| Check | Result |
|---|---|
| `fanin_flood`, 120 bounded runs post-fix | 120/120, 0 deaths, 0 hangs |
| `fanin_flood` pre-fix baseline | 4/100 failed |
| First (inline-swapcontext) attempt | 1 hang in 40 — rejected, see above |
| `test_scheduler_mbox` post-fix | passes |
| `test_scheduler_mbox` against **pre-fix** `march_scheduler.c` | fails on `g_sw_got_nomsg == 0`, exit 134 |

## Regression test

`test/test_scheduler_mbox.c` → `test_spurious_wake_does_not_end_recv()`.

**Deterministic, no race required** — which is the point, per
`specs/todos/2026-08-14-deterministic-premature-free-reproducer.md`'s argument
that a test which only fails statistically is not a regression guard. The
prodder spins until it *observes* the receiver in `PROC_WAITING`, then issues a
bare `march_sched_wake` with no message pushed at all, reproducing the exact
state the send/consume race produces without having to win that race. It then
asserts the receiver returned to `PROC_WAITING` under its own steam (it
re-parked rather than reporting `NO_MSG` and dying) and still received a
subsequent real message.

Non-vacuity was confirmed by compiling the same test against the pre-fix
`runtime/march_scheduler.c` from `git show HEAD:` — it aborts on the first
assertion. The file's existing `alarm(30)` watchdog also converts the
deadlock-regression variant into a test failure rather than a wedged run.
