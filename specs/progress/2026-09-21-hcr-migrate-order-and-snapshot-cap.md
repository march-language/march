# HCR actor migration: queued messages ran new code on old state; >2048 actors never migrated

Landed 2026-09-21. Two hot-code-reload bugs in actor state migration, found by
code reading and both reproduced before the fix by
`test/test_hcr_migrate_order.c`.

## Bug 1: new handler code ran against the old state

A migrating activation (`runtime/march_reload.c`) called
`march_dispatch_publish[_epoch]`, which advances the slot's current version,
and only THEN `march_actor_broadcast_migrate`, which appends a migrate message
to the TAIL of each actor's mailbox. The actor receive loop entered "current"
for every message, so every message already queued ran the NEW
`<Actor>_dispatch` against the OLD state record (`a[4]`): wrong field offsets,
out-of-bounds reads if the layout grew. Repro: 6 of 6 queued messages (a gate
plus 5 increments) dispatched to v2 against v1 state; 5 increments lost.
`docs/hot-code-reload.md` claimed actors migrate "before they handle any new
messages", which was false for queued messages.

**Semantics now (decided with the user):** messages queued before the switch
run on the OLD code against the OLD state. The migrate message is a marker.
At the marker the actor runs `migrate_state` and switches to the new version.
A bounded drain deadline then drops (and reports) whatever old messages
remain.

**Mechanism:**
- `march_actor_meta.hcr_pin` (0, or ring version + 1): a per-actor code pin.
  `hcr_enter` dispatches a pinned actor through the new
  `march_dispatch_enter_version` (a specific ring version) instead of
  current. The pin also holds one dispatch ref, so the old ring slot cannot be
  reclaimed while any actor still needs it.
- `march_actor_publish_migrating(slot, fn, ..., migrate_fn, drain_ms)` is the
  new activation entry point, used by both `do_activate` and
  `do_activate_inner` through `publish_activation`: (1) snapshot and pin every
  live actor of the type to the version it runs now, (2) publish, (3) arm the
  drain deadline and append a marker carrying `{meta, pin}` to each mailbox.
  Pinning precedes publishing, so `hcr_enter`'s re-read of the pin after
  entering "current" closes the window where an actor loads "unpinned" just
  before a pin lands.
- The pin is released exactly once (CAS in `hcr_release_pin`) by whichever
  comes first: the actor processing its marker (`hcr_switch`: migrate, then
  unpin), the actor's death (both exit paths of `actor_green_thread`), or the
  marker being disposed while its target is dead (`hcr_marker_orphaned`:
  DEAD send, reap-time dispose). A marker lost while the actor is alive
  (dropped by `DROP_NEW`, evicted by `DROP_OLD`, eaten by a nested
  `receive()`, or a failed malloc) sets `hcr_marker_lost`, and the actor
  migrates at its next message boundary instead.
- `march_actor_recv` (nested `receive()` inside a handler) no longer hands a
  marker to user code as a value. That leak predates this change, but with
  pinning it would also have stranded the actor on the old version.
- Drain deadline: `drain_ms` (< 0: `$MARCH_HCR_DRAIN_MS`, else 5000 ms; 0 = no
  deadline), stored per meta as an absolute `march_now_ms()` (0 = none, so a
  calloc'd meta has none). The actor zeroes it, and `hcr_marker_lost`, BEFORE
  releasing its pin. Found in self-review: an earlier draft reset it in the
  activator after the pin CAS, so an actor could pair a fresh pin with the
  previous migration's already-expired deadline and drop valid messages.
  Past the deadline, a pinned actor drops each pre-marker message (disposed
  via `march_actor_msg_dispose`) and counts it. `hcr_switch` prints the
  per-actor count on stderr; `march_hcr_drain_dropped()` is the process total.
- A second migrating activation while any actor is still pinned is refused
  (-1, nothing changed, the pins it took released). With
  `MARCH_MAX_LIVE_VERSIONS` 2 the ring would refuse it anyway. The explicit
  check keeps a raised cap from stacking a third state layout on one actor.
- `march_actor_broadcast_migrate` is kept (unpinned markers, the old
  semantics) for `test/test_broadcast_migrate_leak.c`. Its header comment now
  says it gives no ordering guarantee and that deploys must not use it.

## Bug 2: actors past the snapshot cap were never migrated

`march_actor_broadcast_migrate` snapshotted into a fixed
`march_actor_meta *snaps[2048]`, so any matching actor past the 2048th got no
migrate message and ran the new code on the old state for good. Repro: 2100
live actors, 2048 migrations, 52 left on the v1 layout. The snapshot
(`hcr_snapshot`) is now a heap-grown array with no cap. It exits on OOM,
because a partial snapshot would be the same silent skip.

## Verification

- `test/test_hcr_migrate_order.c` (dune runtest rule
  `test_hcr_migrate_order_runner`): real actor green threads, the real receive
  loop, the real `march_actor_publish_migrating`. Cases: queued messages on
  old code (bug 1), 2100 actors (bug 2), drain deadline drop and count, second
  deploy refused while draining (no pin leaked, the old slot reclaimable
  after), a second migration of the same actor not inheriting the first's
  expired deadline, and an actor killed before its marker giving its pin
  back. 30 checks. Pre-fix (publish + `march_actor_broadcast_migrate`, the old
  `march_reload.c` sequence): 6 of 8 checks failed. Post-fix: 40 of 40 runs
  green at load average 40-50 (an earlier 27-check draft: 30 of 30 at 91).
- Perturbations, each RED on exactly its checks: skip the pre-publish pin
  (bug 1 returns, 9 fails); cap the snapshot at 2048 (bug 2 returns, 3 fails);
  suppress pin release for a dead actor (the death case fails); skip the
  actor's deadline reset (the inherited-deadline case fails).
- `test_broadcast_migrate_leak`, `test_dispatch`, `test_reload_activate4`
  (both modes) green. `scripts/check-runtime-sources.sh` green.

## Not covered

A newly spawned actor's initial state comes from its (inlined) spawn site's
code version, not from the dispatch slot. See
`specs/todos/2026-09-21-hcr-spawn-site-state-layout.md` (suspected, not
reproduced).
