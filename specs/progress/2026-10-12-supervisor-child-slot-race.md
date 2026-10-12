`[P3]` A supervisor's child-pid slot: a data race, a lost update, and a pid published before its actor could take messages — FIXED

Found 2026-10-12 by the TSAN sweep (`MARCH_SANITIZE=thread`, `test/native/*.march` at
1, 2 and 14 schedulers). It was the one report that survived the sweep's fixes:
`proc_reclaim_kill_respawn` at 2 and 14 schedulers, in about every run.

```
Write  march_respawn_child  runtime/march_runtime.c   *sup_child_slot(supervisor, ...) = pe_pid_or_0(...)
       <- march_one_for_one_restart <- march_supervisor_notify <- do_actor_death_kind
       <- actor_green_thread                       (the CRASHED CHILD's green thread)
Read   rec_field_raw        runtime/march_extras.c   <- march_get_actor_field (Actor.get_field)
       <- the program's main green thread
Location: the supervisor's state record (heap block from Boss_spawn)
```

## What was wrong (three bugs, one word)

A supervised child's pid lives in a word of the supervisor's state (`sup_child_slot`:
`supervisor[4 + word_idx]`, or a word of the `$f_state` record under `--hot-reload`). A
restart (`march_respawn_child`) runs on whichever thread processed the death and wrote
that word directly.

1. **Data race (the TSAN report).** The write was a plain store, read from other threads
   by `Actor.get_field` and by the C restart/stop code.
2. **Lost update — the real bug.** A compiled handler (`lower_actor.ml`, `lower_handler`)
   loads *every* state field on entry and stores them *all* back on exit (`EReuse` of the
   actor record). A restart that wrote the word while the supervisor was inside a handler
   was undone by that write-back: the supervisor then named the dead child until that
   slot crashed again. Deterministic when the supervisor's handler kills its own child
   (the restart runs synchronously inside `kill`, on the supervisor's own thread, mid
   handler); at 2+ schedulers it only needs a child to die while the supervisor handles
   any message. So an atomic store alone would have silenced TSAN and left this.
3. **Pid published before activation.** The respawn wrote the word *before*
   `activate_actor_green_thread`. Until the activation, `march_send` finds no green thread
   (`MARCH_SEND_DEAD`) and drops the message, while `is_alive` already says true. A
   reader of the word (the supervisor's handlers, `Actor.get_field`) could send to a live
   child whose mailbox silently ate the message. The new fixture's first draft hit it:
   four children poisoned at once, one never crashed again (`alive=true mbox=0`).

## Restart semantics: unchanged

`specs/lang/actors.md` (supervision) and `march_child_should_restart` are untouched: the
same restarts happen, on the same threads, with the same backoff and budget. What changed
is only *when the supervisor's state word shows the replacement*:

- not handling a message (including a supervisor that receives none, as in every
  supervision golden): immediately when the restart returns, as before;
- handling a message: when that handler returns, before the supervisor takes its next
  message. A handler already saw only the state loaded at its start, so a restart
  mid-handler was never visible to it; it is now not *lost* afterwards.

## Fix (runtime only)

- `march_sup_child.cur_pid`: the runtime's own copy of each slot's current child, set with
  `__atomic` stores at registration and by every respawn (before activation). Every C
  reader uses it: the respawn's epoch inheritance, the `one_for_all` / `rest_for_one`
  sweeps, `march_actor_stop`'s teardown. They no longer depend on the state word, which a
  handler may hold stale.
- The state word is now a mirror, written only while the supervisor is *not* handling a
  message. Per-supervisor `sup_slot_lock` (a spin lock held for a few stores, never across
  a switch) guards `sup_slot_busy` / `sup_slot_dirty`. The actor loop calls
  `sup_slots_go_idle` just before it waits for a message (applying any held-back write)
  and `sup_slots_go_busy` once it has one. `sup_slot_publish` writes the word directly
  when the supervisor is idle, else marks it dirty. It writes `cur_pid` as read under the
  lock, so two out-of-order publishes of one slot still leave the newest child. The loop
  calls skip all of this for an actor with no supervised children.
- The respawn publishes the word *after* activating the replacement (bug 3).
- Writes are relaxed atomic stores; `march_get_actor_field` reads the field with a relaxed
  atomic load (the same `ldr`).
- Registration reallocs `sup_children` under `sup_slot_lock`, since the loop's apply walks
  that array.
- `march_panic_prefix` (the test runner's panic-message prefix, a global written by every
  `panic`) is accessed with relaxed atomics. Four supervised children panicking at once
  made it the next TSAN report; only `__try_call` reads it, on the panicking thread.

## Test

`test/native/supervisor_concurrent_child_crash.march`, run at 14 schedulers by its dune rule:

- phase 1: one supervisor, four children poisoned at once, 20 rounds; every slot must come
  to name a new live child;
- phase 2: a fresh supervisor parks in a handler (`sleep_ms`) while its child is killed;
  after the handler, `Actor.call` must return a live replacement.

| build | scheds | base runtime | fixed |
|---|---|---|---|
| plain | 1 / 2 / 14 | phase 2 `false` every run (lost update) | 30/30 each, golden |
| TSAN | 1 | phase 2 `false`, no report | 8/8 golden, 0 reports |
| TSAN | 2 / 14 | 4/4 aborted on reports, phase 2 `false` | 8/8 golden, 0 reports |

`proc_reclaim_kill_respawn` under TSAN: base 4/4 runs report at 2 and 14 schedulers;
fixed 8/8 golden with 0 reports at each of 1, 2 and 14. Under TSAN at 2 and 14
schedulers, 0 reports and golden output in 4 runs each for every `supervisor_*` fixture and
`actor_stop_tree` / `actor_stop_drains_mailbox`. Plain builds of the three restart
strategy goldens and this fixture: 5/5 at 1, 2 and 14.

## Left open

The same publish-before-activation window exists for the replacement's **registered
names**: `march_respawn_child` re-registers them before activation, so a send by name in
that window is dropped. Filed as `specs/todos/2026-10-12-respawn-names-before-activation.md`.
