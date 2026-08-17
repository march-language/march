# do_actor_death mutates cleanup_head/monitor_head without g_tbl_mu — UAF window vs monitor/demonitor/unlink

## Partially fixed 2026-08-15 (#284)

The `monitor_head` half is CLOSED. `do_actor_death` now detaches the list
under `g_tbl_mu`:

    monitors = meta->monitor_head;
    meta->monitor_head = NULL;

and walks the detached list after unlocking, so `march_monitor`'s locked
prepend can no longer write into a list being freed.

The `cleanup_head` half is STILL OPEN and is what remains of this todo. It
cannot simply take the lock: cleanup closures run arbitrary March code via
`fn_ptr(clo, unit_arg)`, which can re-enter the runtime and re-acquire
`g_tbl_mu`. The fix is the same detach-then-run shape the monitor half now
uses.

Discovered during Task 10's review (`.superpowers/sdd/2026-08-11-actor-system-hardening/`)
while auditing `g_tbl_mu` coverage of per-meta mutable fields; flagged forward
to Tasks 14/16 (which also touch `do_actor_death`) and finally filed here at
Task 17 close-out. Pre-existing — not introduced by, and not fixed as part
of, any task in this plan.

## The bug (as it stands now — the `monitor_head` half below is HISTORICAL, see the "Partially fixed" banner above; only `cleanup_head` is still open)

`do_actor_death` (`runtime/march_runtime.c:3642`) walks and nulls out
`meta->cleanup_head` with **no lock held**:

```c
static void do_actor_death(void *actor, march_death_reason reason,
                           const char *message, size_t message_len) {
    ...
    pthread_mutex_unlock(&g_tbl_mu);   /* :3673 — monitor_head already detached above, under the lock */

    if (meta && meta->cleanup_head) {                    /* :3681, UNLOCKED */
        march_cleanup_node *node = meta->cleanup_head;
        while (node) {
            ...
            fn_ptr(clo, unit_arg);                         /* :3696 — arbitrary March code */
            ...
            node = next;
        }
        meta->cleanup_head = NULL;                        /* :3703 */
    }
    ...
}
```

Meanwhile `march_demonitor` (`runtime/march_runtime.c:6122`) and
`march_unlink` (`:6159`) still run under `g_tbl_mu` as before. Neither of
them touches `cleanup_head`, so the free-then-use hazard this todo now
tracks is narrower than the original report: it only arises if a cleanup
closure itself re-enters the runtime in a way that mutates
`meta->cleanup_head` while `do_actor_death`'s unlocked walk is still
in-flight (cleanup closures run arbitrary March code via the
`fn_ptr(clo, unit_arg)` dispatch at `:3696`, so this is not merely
hypothetical — it depends on what that closure calls).

Historical snippet (fixed by #284, kept for context on what the bug used to
look like before `monitor_head` was split out — do not use these line
numbers, they no longer exist in this shape):

```c
static void do_actor_death(void *actor) {
    ...
    march_actor_meta *meta = find_meta(actor);
    if (meta && meta->cleanup_head) {
        march_cleanup_node *node = meta->cleanup_head;
        while (node) { ... free(node); node = next; }
        meta->cleanup_head = NULL;               /* old :3083 */
    }
    if (meta && meta->monitor_head) {
        march_monitor_node *mn = meta->monitor_head;
        while (mn) { ... free(mn); mn = next_mn; }
        meta->monitor_head = NULL;               /* old :3099 — now detached under g_tbl_mu instead, see banner above */
    }
    ...
}
```

## Suggested fix

Take `g_tbl_mu` around the `cleanup_head` read-and-null section in
`do_actor_death`, matching the detach-then-run shape #284 already applied to
`monitor_head` — being careful of the lock-ordering comment already
documented near `g_supervise_mu`/`g_tbl_mu` (`:2562`-`:2600`):
`do_actor_death` must not end up calling back into anything that re-acquires
`g_tbl_mu` while already holding it. The cleanup-closure call at `:3696` runs
arbitrary March code and needs auditing for this before the lock is added —
this is exactly why the monitor half could be closed with a simple
detach-under-lock while this half cannot: detach `cleanup_head` under
`g_tbl_mu` (mirroring `monitors = meta->monitor_head; meta->monitor_head = NULL;`
at `:3674`-`:3675`), unlock, and only then walk the detached list and invoke
each closure.
