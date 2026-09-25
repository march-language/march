# `[P3]` Replace the hold-next-spawn flag with a spawn argument

**Logged 2026-09-24**, filing the interim shape of
[../progress/2026-09-24-dd-review-party-hold-queued-behind-spawn-marker.md](../progress/2026-09-24-dd-review-party-hold-queued-behind-spawn-marker.md).

`SessionNode.party()` starts its Endpoint actor held (D28) by setting a flag on the
spawning proc (`epoch_hold_next_spawn()`, `march_proc.hold_next_spawn`) that the very
next spawn consumes, so the child's `epoch_holds` is 1 before its activation and its
spawn marker is deferred. The flag is bound to that one spawn (consumed by it, cleared at
every actor message boundary and at the proc's reap; `test_hcr_migrate_order.c`
`test_spawn_hold_precedes_marker` checks that the following spawn is not held), but it
is proc state, not part of the call: a future refactor that spawns something between the
builtin and `spawn(Endpoint)` would hold the wrong child and never the Endpoint.

**What to do.** Make the hold an argument of the spawn once the lowering can express it:
a stdlib-only `spawn_held(Actor)` form, or a HOLD flag on `march_spawn_common(actor,
flags)` that the generated `ActorName_spawn` glue passes through. Then delete
`hold_next_spawn` and `epoch_hold_next_spawn`, keep the C test (it asserts the behaviour,
not the mechanism), and update `party()`.
