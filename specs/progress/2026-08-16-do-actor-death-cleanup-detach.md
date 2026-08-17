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
    pthread_mutex_unlock(&g_tbl_mu);   /* :3677 — monitor_head already detached above, under the lock */

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

## Resolved 2026-08-16

Both halves of this todo are now closed: the `monitor_head` half by #284
(2026-08-15), and the `cleanup_head` half here.

The fix has two sides, not one, because the original suggested-fix text
(above) assumed `march_on_cleanup`/`march_register_resource`'s prepend onto
`meta->cleanup_head` already ran under `g_tbl_mu` — it did not. Verified
directly: `march_register_resource` (`runtime/march_runtime.c`, formerly
~6346-6358) did the two-line prepend

    node->next = meta->cleanup_head;
    meta->cleanup_head = node;

with no lock held at all. Locking only the `do_actor_death` side (as the
monitor half did) would have been necessary but not sufficient: with the
prepend still unlocked, a concurrent `march_register_resource` could still
race the detach in `do_actor_death` — losing the node it just linked, or
linking onto a head `do_actor_death` was concurrently nulling out.

The landed fix locks both ends:

1. `do_actor_death` detaches `cleanup_head` under `g_tbl_mu`, in the same
   critical section as the existing `monitor_head` detach, and walks the
   detached local (`cleanups`) after unlocking. The closures themselves
   still run with no lock held — they are arbitrary March code via
   `fn_ptr(clo, unit_arg)` and can re-enter the runtime and re-acquire
   `g_tbl_mu`, which is exactly why the list is detached-then-walked rather
   than walked-and-freed while locked.
2. `march_register_resource` now takes `g_tbl_mu` around its two-line
   prepend, matching the discipline `march_monitor`/`march_demonitor`/
   `march_unlink` already use for `monitor_head`.

Why the distinction (detach-under-lock, not hold-lock-across-closures) is
load-bearing: if the lock were instead held across the `fn_ptr` call, any
cleanup closure that touches an actor API (spawn, monitor, kill, another
`march_register_resource`, ...) would re-acquire the same non-recursive
`g_tbl_mu` on the same thread and self-deadlock. Detaching under the lock
and walking after unlocking gets the same memory-safety guarantee (the list
a thread walks is one nothing else can still reach) without that hazard.

Lock-ordering check for the newly-locked `march_register_resource` path:
it calls `find_meta` (lock-free bucket walk, no locking at all) and
`march_incrc` (a relaxed `atomic_fetch_add` on the object header, no
destructor path — only `march_decrc`, which is not called here, can free).
Neither can re-enter and re-acquire `g_tbl_mu`, so no new lock-ordering
hazard is introduced.

No new test: per the 2026-08-16 ruling, this race cannot be forced
deterministically across two OS threads, so a fixture here would pass
identically before and after the fix. The evidence is the structural
argument above plus the existing suites staying green (`run_stdlib`,
`run_codegen`, and `dune build @test/runtest` all clean post-fix).
