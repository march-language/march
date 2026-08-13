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
