# Process enumeration: `Actor.list()`

Landed 2026-09-08. Partial completion of
[`specs/todos/2026-08-12-per-actor-introspection-and-alarms.md`](../todos/2026-08-12-per-actor-introspection-and-alarms.md),
which stays open, trimmed, for the growing-mailbox alarm, per-actor state
inspection, and tracing.

## Why this piece first

It was the one closing a live contradiction in shipped documentation.
`docs/overload-resilience.md` tells readers to poll `mailbox_size(pid)` to
decide when to shed load, but `mailbox_size` needs a `Pid` and there was no way
to obtain one for an actor you could not name in advance — so the documented
loop could not be closed at all. The doc now shows `Actor.list()` doing it.

## Shape

`actor_pid_indices() : List(Int)` in the runtime; `Actor.list()` in the stdlib
maps `pid_of_int` over it. Ints rather than Pids on the C side deliberately:
the result then carries no actor references at all, so there is no ownership
question about a list of N actor pointers, and the Int → Pid round trip is the
same one every supervisor's Int-typed child fields already make.

Lock-free: the bucket-head walk `find_meta` uses. Task 10 took `find_meta` off
`g_tbl_mu` to keep sends lock-free, and an enumeration grabbing that mutex on a
monitoring timer would re-serialise exactly the path that work freed.

Sorted ascending and deduplicated, so the snapshot is deterministic (bucket
order is an artifact of heap addresses) and identical on both backends.

## Two traps, both found by the flakiness they caused

**1. The obvious stale-meta guard drops LIVE actors.** The first version
skipped any meta that `find_meta_by_pid_index` did not resolve back to, to
avoid listing a stale meta whose actor address had been recycled. But that
guard is itself a lock-free walk of a table being inserted into concurrently:
a three-actor program listed two, with a *different* one missing run to run.
Silently omitting live actors defeats the entire feature, whose point is
finding the actor you did not already know about. Duplicates are removed by the
sort instead, and a stale index that survives resolves through `pid_of_int` to
a live actor — which every `Pid` consumer already handles.

**2. Gate on "has not died", not on `is_alive`.** `march_spawn` returns before
the new actor's green thread has run, and the actor's `$alive` word is still 0
until it does — so an `actor_alive_load` gate drops actors the caller has just
created. The interpreter's `ai_alive` is true from the moment of spawn, so that
gate also made the two backends disagree. Gating on `terminal_set` (claimed by
`do_actor_death`) still excludes dead actors, includes just-spawned ones, and
matches the interpreter.

The consequence, documented in the fixture: a listed `Pid` is not guaranteed to
answer `is_alive`. On the compiled backend an idle actor can also finish and
exit between two consecutive calls. A snapshot cannot promise otherwise, and
`test/native/actor_enumeration.march` deliberately does not assert it — the
first draft did, and flapped 4 runs in 10.

## Test

`test/native/actor_enumeration.march`, compiled and interpreted against one
`.expected`: spawn order, a killed actor leaving the snapshot, a stopped actor
leaving it too. Checked stable over ten consecutive compiled runs.
