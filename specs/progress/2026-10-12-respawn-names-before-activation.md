`[P4]` A restarted child's registered names resolved before it could take messages — FIXED

Found 2026-10-12 while fixing `specs/progress/2026-10-12-supervisor-child-slot-race.md`.

## What was wrong

`march_respawn_child` (`runtime/march_runtime.c`) re-registered the crashed incarnation's
names on the replacement (`march_actor_register`) *before* `activate_actor_green_thread`.
In that window `whereis(name)` returned the replacement's pid and `is_alive` said true,
but `march_send` found no green thread (`meta_gt` NULL, `MARCH_SEND_DEAD`): `send`
returned `None` and dropped the message, `Actor.call` failed at once. The replacement then
lived on. `specs/lang/actors.md` promises that a name holder "keeps reaching whichever
incarnation is current".

Registering after the activation instead opens a different hole: a replacement that dies
before its names are registered has nothing in its reverse index (`reg_names`), and
`stash_child_for_restart` reads that index to carry the names to the *next* replacement.
That next respawn can run synchronously on the dying thread, before the first respawn gets
back to registering, so putting the names back on the slot afterwards is too late.

## Fix (runtime only)

Name registration on a respawn is split in two, around the activation:

1. **Reserve** (`registry_reserve_name`, before the activation, under `g_registry_mu`):
   apply the usual "first live claim wins" check and add the name to the replacement's
   reverse index only. A death from here on stashes it, exactly as before.
2. **Publish** (`registry_publish_names`, after the activation, still inside the
   respawn's reclamation critical section, under `g_registry_mu`): write the forward entry
   that `whereis` reads, for each reserved name the replacement is still alive and still
   holds in its index. If another live actor claimed the name in between, the claim stands
   and the reservation is dropped from the index. A stale (dead) holder is unindexed as
   `march_actor_register` does (shared helper `registry_unindex_stale_locked`).

Between the two steps `whereis` answers `None`, as it already did from the crash until the
restart; there is no longer a moment where it names a pid that drops messages.
`march_actor_register`, `whereis` and the send paths are unchanged.

## Test

`test/native/supervisor_respawn_names_before_activation.march`, run at 14 schedulers by its
dune rule. Two tasks each own one registered supervised child and loop 300 rounds:
poll `whereis` (with `task_yield`) until the name names a pid other than the one just
crashed, send it three `Inc`, `Actor.call` it (the reply is the handled count), then poison
it. The client is the only sender and poisons only after the call returned, so every send
must be accepted and every call answered with 3.

| build | scheds | base runtime | fixed |
|---|---|---|---|
| plain | 1 | 5/5 golden (one scheduler never interleaves the respawn) | 5/5 |
| plain | 2 / 14 | 0/5 each: 3 sends refused, 1 call failed, then the dropped Poison stalls the round | 5/5 each |
| TSAN | 1 | 4/4 golden, 0 reports | 4/4, 0 reports |
| TSAN | 2 / 14 | 0/4 each, 0 reports | 4/4 each, 0 reports |

The first draft polled without yielding: at 1 and 2 schedulers under TSAN that starved the
crashing child and the delayed restart (TSAN defers the preemption signal to its next
intercepted call) on the base runtime too, so the round timed out with no message lost.

`scripts/tsan-sweep.sh` over the 40 `supervisor_*`, `actor_*` and `proc_reclaim_*` fixtures
at 1, 2 and 14 schedulers (fixed runtime): 120 runs, 0 TSAN reports, 0 deadlines. Two
fixtures differ from their `.expected` only because their dune rules set an environment
the sweep does not (`supervisor_deflected_crash_absorbed`: `MARCH_SUP_TRACE`,
`MARCH_SUP_TEST_STALL_MS`, `2>&1`; `actor_init_params_schema`). The 38 dune-built plain
goldens among them all match.
