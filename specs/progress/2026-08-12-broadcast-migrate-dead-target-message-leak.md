# march_actor_broadcast_migrate leaks the malloc'd migrate message when the target dies between snapshot and send

Discovered during Task 10's review (`.superpowers/sdd/2026-08-11-actor-system-hardening/`)
while auditing `march_actor_broadcast_migrate`'s two-phase snapshot/inject
design; noted in the ledger as "broadcast_migrate phase-2 leaks mm on dead
target" and deferred to Task 17. Pre-existing.

## The bug

`march_actor_broadcast_migrate` (`runtime/march_runtime.c:3261`) snapshots
matching actors under `g_tbl_mu` (incrementing each one's refcount to keep it
alive), releases the lock, then injects one `malloc`'d
`march_migrate_msg_t` per snapshotted actor:

```c
for (int i = 0; i < n; i++) {
    march_migrate_msg_t *mm = (march_migrate_msg_t *)malloc(sizeof(*mm));
    if (mm) {
        mm->_rc        = 1;
        mm->_tag       = MARCH_MIGRATE_TAG;
        mm->migrate_fn = migrate_fn;
        march_sched_send(snaps[i]->green_thread, mm);   /* runtime/march_runtime.c:3292 */
    }
    march_decrc(snaps[i]->actor);
}
```

The comment above Phase 1 explicitly documents the gap this leaves open:
the actor is kept *alive* (refcount held) for the snapshot-to-send window,
but nothing prevents its green thread from exiting/being torn down in that
window (a normal exit, a supervised crash, or `march_kill` racing the
broadcast). `march_sched_send` is not guaranteed to deliver into a mailbox
that a dying/dead target no longer drains — the scheduler's own dead-proc
disposal path (`march_sched_set_msg_dtor`, documented at `:3135`-`:3163`)
frees messages still sitting in a proc's mailbox when it is reaped, but only
messages that made it *into* the mailbox. If `march_sched_send` here is a
no-op or silently drops (target's queue/proc already torn down), the `mm`
allocated on this line is never freed by anyone — a small, bounded (`n <=
MARCH_MIGRATE_SNAPSHOT` = 2048 per broadcast call) but real leak, `malloc`'d
memory outside the March GC's tracking (it is deliberately not
march-heap-allocated — see the dtor comment at `:3144`-`:3148` — specifically
so it survives being freed with plain `free()`).

## Suggested fix

Check `march_sched_send`'s return value (or otherwise detect
non-delivery) and `free(mm)` on the non-delivered path, mirroring how the
scheduler's own `march_sched_set_msg_dtor` frees an undelivered migrate
message via `free()` (never `march_decrc`, since it's malloc'd — see the
comment at `:3144`-`:3153`). If `march_sched_send` currently has no
delivery-status return, that's the first thing to check/add.

## Fix landed

`march_sched_send` already had the delivery-status return this todo asked to
check for — no signature change needed. Its documented contract
(`runtime/march_scheduler.h`): `MARCH_SEND_OK` (0) means the message was
enqueued (the mailbox now owns it); `MARCH_SEND_DROPPED` (1) means an
overflow policy rejected it but already handed it to the registered dtor
(`march_actor_msg_dispose`, which frees a `MARCH_MIGRATE_TAG` message);
`MARCH_SEND_DEAD` (-1) means neither happened — the caller still owns the
one reference it allocated. `march_send` (`runtime/march_runtime.c`, a few
hundred lines below `march_actor_broadcast_migrate`) already consumed this
contract correctly; `march_actor_broadcast_migrate`'s Phase 2 was the one
caller that dropped the return value on the floor.

Fix, in `march_actor_broadcast_migrate`'s Phase 2 loop:

```c
if (march_sched_send(snaps[i]->green_thread, mm) == MARCH_SEND_DEAD) {
    free(mm);
}
```

`free()`, never `march_decrc`, matching `march_actor_msg_dispose`'s handling
of this same malloc'd-not-march-heap-allocated shape.

### Verification

A byte-for-byte deterministic reproduction of the exact snapshot-to-send
race inside `march_actor_broadcast_migrate` itself would need the target
actor's green thread to fully die (on a background scheduler thread the
runtime starts automatically) in the narrow window between Phase 1's
`g_tbl_mu` unlock and Phase 2's `march_sched_send` call — a genuine
cross-thread race with no public hook to pin the interleaving, short of
adding test-only synchronization to production code. That was judged out of
scope for a narrow leak fix, and a loop-and-hope stress test would only be
probabilistically likely to land in the window — exactly the flaky-repro
outcome to avoid.

Instead, `test/test_broadcast_migrate_leak.c` (wired into `dune runtest` via
`test/dune`, linking only `runtime/march_scheduler.c` — no dependency on
`march_runtime.c`) reproduces the condition Phase 2 actually hits when the
race fires, fully deterministically and single-threaded: it drives a plain
scheduler proc to `PROC_DEAD` via the raw scheduler API with
`march_sched_run()` run to completion on the calling thread (no background
thread involved, so no race at all — `march_proc` structs are deliberately
never freed on death, so the now-dead proc pointer is still safe to pass to
`march_sched_send`), then calls `march_sched_send` on it using the *exact*
malloc + send + conditional-free pattern now in Phase 2. It asserts:
`MARCH_SEND_DEAD` is returned; the pre-fix pattern (malloc + send, ignore
the result) leaks exactly one allocation per call (red control, proving the
scenario really did leak); the fixed pattern leaks nothing, including over
256 repeated calls against the same dead target (green).

Commands run: `dune build --root . test/run_eval.exe test/run_codegen.exe
test/run_stdlib.exe` (clean); `dune build --root . test/test_broadcast_migrate_leak_runner`
then running the binary directly (5/5 assertions pass); `scripts/run-tests.sh -q`
(passed, modulo unrelated system-load timeouts on `run_codegen`/`run_stdlib`
from heavy concurrent activity in sibling worktrees on the same machine —
re-run individually to confirm, see the commit's own report for detail).
