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

## The bug

`do_actor_death` (`runtime/march_runtime.c:3054`) walks and nulls out
`meta->cleanup_head` and `meta->monitor_head` with **no lock held**:

```c
static void do_actor_death(void *actor) {
    ...
    march_actor_meta *meta = find_meta(actor);
    if (meta && meta->cleanup_head) {
        march_cleanup_node *node = meta->cleanup_head;
        while (node) { ... free(node); node = next; }
        meta->cleanup_head = NULL;               /* runtime/march_runtime.c:3083 */
    }
    if (meta && meta->monitor_head) {
        march_monitor_node *mn = meta->monitor_head;
        while (mn) { ... free(mn); mn = next_mn; }
        meta->monitor_head = NULL;               /* runtime/march_runtime.c:3099 */
    }
    ...
}
```

Meanwhile `march_monitor` (`runtime/march_runtime.c:5464`), `march_demonitor`
(`:5332`), and `march_unlink` (`:5369`) all mutate the *same* `monitor_head`
list (prepending or unlinking `march_monitor_node`s) **under `g_tbl_mu`**.

If a watcher calls `march_monitor(watcher, target)` concurrently with
`target`'s death, the two sides can race on `meta->monitor_head`:
`march_monitor`'s locked prepend can write a node into a list that
`do_actor_death`'s unlocked walk is simultaneously freeing — a classic
free-then-use or lost-update, not merely a stale read. The same shape applies
to `march_demonitor`/`march_unlink` racing the cleanup-list walk if a cleanup
callback itself calls one of those APIs (cleanup closures run arbitrary
March code via the `fn_ptr(clo, unit_arg)` dispatch at `:3076`).

## Suggested fix

Take `g_tbl_mu` around the `cleanup_head`/`monitor_head` read-and-null
sections in `do_actor_death`, matching `march_monitor`/`march_demonitor`/
`march_unlink`'s existing discipline — being careful of the lock-ordering
comment already documented near `g_supervise_mu`/`g_tbl_mu` (`:2562`-`:2600`):
`do_actor_death` must not end up calling back into anything that re-acquires
`g_tbl_mu` while already holding it (the cleanup-closure call at `:3076` runs
arbitrary March code and needs auditing for this before the lock is added).
