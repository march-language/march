# `SessionNode.party()`'s hold arrives behind the Endpoint's spawn marker, so the Endpoint advances before it holds

**DONE 2026-09-24.** The hold is part of the spawn: the stdlib-only builtin
`epoch_hold_next_spawn()` (`march_sched_hold_next_spawn`) marks the spawning proc, and
`sched_spawn_common` starts the next proc it spawns with `epoch_holds = 1` before
activation, so the spawn marker finds it held. `party()` calls it before
`spawn(Endpoint)`; the `HoldEpoch` message is gone. `test/test_hcr_migrate_order.c`
`test_spawn_hold_precedes_marker` is the harness described below: the message-held
child advances (the control), the spawn-held child stays at the parent's epoch. The flag
is the interim shape: a spawn argument is
[../todos/2026-09-24-spawn-held-as-a-spawn-argument.md](../todos/2026-09-24-spawn-held-as-a-spawn-argument.md).
Filed 2026-09-24; the text below is the finding as filed.

Filed 2026-09-24 by the distributed-deploys review (step 6, PR #612, commits
1157997f5 and 753336d36). Plan: II.4.4, D28; progress deviation 2.

## Defect

`party()` does `let ep = spawn(Endpoint)`, then `send(ep, HoldEpoch())`
(`stdlib/session_node.march:802-806`). `spawn` activates the actor at once
(`march_spawn_common(actor, 0)`, `runtime/march_runtime.c:5912`), and
`activate_actor_green_thread` (`:5793-5815`) calls `hcr_spawn_marker`
(`:6104`). When the new proc inherited an epoch older than current, that queues
an epoch marker in its mailbox. The marker is therefore ahead of `HoldEpoch`.
The Endpoint consumes the marker with no hold, advances to current, and only
then holds, at the NEW epoch.

A spawner behind current is exactly the case D28 is for: a unit still on old
code (an old-epoch actor or task) forming a session while a deploy drains. An
activation landing between the `spawn` and the `send` has the same effect
even when the spawner is current.

## Confirmed

C harness against the real runtime (`actor_green_thread`,
`march_hcr_activate`). Actor P is parked in a handler at epoch 1 while a
deploy makes epoch 2 current. Its handler then spawns child C, sends
`MSG_HOLD` (C calls `march_epoch_hold()`) and `MSG_PROBE` (C records
`march_sched_current_epoch()`). Three runs out of three:

```
deploy epoch 2; parent ran spawn at epoch 1; child handled the message after its hold at epoch 2 -> ADVANCED BEFORE THE HOLD (D28 violated)
```

Build: the `test_hcr_migrate_order_runner` rule's `cc` line from `test/dune`
with this file in place of the test. The source is in the review session's
scratchpad (`m2/repro_hold_after_marker.c`); its core:

```c
static void parent_dispatch(void *actor, void *msg) {
    ... wait for the deploy ...
    void *c = new_actor(2);                          /* spawn(Endpoint)      */
    march_decrc(march_send(c, MSG_HOLD));            /* send(ep, HoldEpoch()) */
    march_decrc(march_send(c, MSG_PROBE));
}
```

## Fix I would make

Make the hold part of the spawn, not a later message: a spawn variant (or a
stdlib-only builtin taking the new pid before activation) that starts the proc
with `epoch_holds = 1`, used by `party()`. Or defer activation
(`march_spawn_deferred`), take the hold on the not-yet-running proc, then
activate. Add the harness above as a test case.
