# A dead actor's state, and an Actor.call target's record, were never released

**FIXED 2026-10-06.** Found while chasing what a cluster session still leaves behind
(specs/progress/2026-10-06-session-ops-leak.md): the per-party state of the session's
endpoint actor outlived the session. Both bugs are compiled-only and predate this branch
(main gives the same numbers).

## Measuring it

Spawn an actor, optionally message or call it, kill it, count `live_allocs()` over 50
rounds. An actor whose state is only `Int`s left nothing. One with a `List` field left
one object per actor (an empty list is a heap cell), more as the list grew, and an actor
that had answered an `Actor.call` left five.

## 1. The runtime frees an actor record shallowly

A live actor holds a reference to its own record (taken in `march_spawn_common`,
released by `actor_green_thread` as it exits). The record's last release is an ordinary
runtime `march_decrc`, which frees the cell and nothing it points to: the runtime has no
types. So every heap state field of a dead actor leaked.

Fix: `Drop.run` synthesizes `$actordrop$<A>_Actor` for each actor struct with a state
field that needs RC. It loads each such field, stores an immediate over the slot (so
nothing reading the dead record later finds a freed pointer), and drops it with the
field's typed drop. `Dce` keeps it alive through the actor's allocations, and
`Llvm_toplevel.clo_drop_registration` registers it in the closure-drop table under the
code pointer of field 0. Field 0 holds the dispatch function as a function value: a
closure cell (`<A>_dispatch$static_clo`, or a fresh cell under hot reload or the REPL)
whose code pointer is `<A>_dispatch$clo_wrap`. Registering under `@<A>_dispatch`, as a
closure's apply is registered, never matched. `actor_green_thread` looks it up and runs
it after `do_actor_death`, before it releases its own reference.

It runs on a clean loop exit only. On a crash, when a stop longjmps out of a `receive()`
nested in a handler (or in `on_stop`), or when `on_stop` panics (`actor_run_on_stop`
traps the panic and returns, so control still reaches `stopped:`; review caught this),
the handler had already moved the state fields into its locals and the record no longer
owns them: those paths leak as before (`stopped_in_handler`, set by the stop trap and by
a panicking `on_stop`). No program was found that crashes on the panicking path without
this guard (a field read through `state` is duplicated, so the slot's reference stayed
valid in every shape tried under ASAN); the guard trades a possible double release for
the old leak. A hot-reload actor gets no release
function: its state is a separately typed `$f_state` record that a migration may
replace with a different layout, and a wrong layout is worse than a leak.

## 2. Actor.call leaked a reference to its target

`actor_call` was still in `Borrow.extern_owned_builtins`, the pre-2026-09-13 default, so
every call site incremented the pid as if `march_actor_call` consumed it. The runtime
only reads it to find the target. Each call leaked one reference to the actor record,
so a called actor's record (and, before fix 1, its state) was never freed even after it
died. It moved to `extern_borrow_table` as `[true; false]`: pid borrowed, the sentinel
message owned (the runtime releases it after reading its tag).

## Test

`test/native/actor_state_released.march`: 50 actors pushed to, called and killed, 50
called twice and killed, and 50 stopped gracefully through an `on_stop`, each under 5
objects left (RED before: `false` on the first two); and 20 actors whose `on_stop`
consumes a field and panics, which must neither crash nor double-free. The
session probe (`session_party_released`) went from ~92 to ~86 objects per session.
