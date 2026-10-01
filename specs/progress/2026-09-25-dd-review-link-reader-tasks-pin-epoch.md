# `[P2]` ClusterNode link reader tasks pin the startup epoch and stamp remote deliveries with it

**Filed** 2026-09-25 from the distributed-deploys review's unconfirmed item 1
(`2026-09-24-dd-review-unconfirmed.md`, now triaged and deleted).

**What.** `read_data` (stdlib/cluster_node.march) runs in a task spawned when a link
forms. Tasks never advance (II.4.3), so the task holds the link's creation epoch for
the life of the link, and the local `send` its route closures make stamps every
remote delivery with that epoch (`march_sched_send_epoch`). After a deploy that
changes an actor's message type, remote messages to that actor carry a stamp older
than `msg_schema_epoch` and go through `migrate_msg` or are dropped, even when the
remote sender already sends the new format. And any long-lived link pins its epoch,
so with the hard drain deadline off by default the baseline version is never
reclaimable in a cluster process.

**Evidence so far.** Confirmed in part: in `forge test --upgrade-from` on
`forge/test/fixtures/upgrade/migrates`, 20 s after the deploy PINS still reported
`epoch 1 (6 unit(s)) still pinned by units that are not actors (tasks)`, while a
plain program with no ClusterNode drains to zero (see
`2026-09-25-name-units-pinning-old-epoch.md`). Which six tasks is not yet known, and
the stamping consequence has no repro.

**Repro to write.** A two-node hot-reload test that sends a remote message across a
message-type-changing deploy, from a sender already on the new format; assert it is
delivered, not converted or dropped. Then either run route handlers at the current
epoch or document the consequence in II.4.5.

## Fixed (2026-09-28): route handlers run at the current epoch

Taken the first of the two ways out: the readers move, rather than documenting the
stamp in II.4.5.

**Mechanism** (stdlib/cluster_node.march, "moving to a new code epoch"). There is no
builtin that reads a task's epoch or spawns at the current one, and a task never
advances (II.4.3). What stdlib code can do is Topology's placement-loop pattern: when
`epoch_draining()` turns true, ask an actor that has passed its marker to spawn the
replacement task. ClusterNode now does this for all four of its long-lived tasks:

- **Link readers** (`read_control`, `read_data`) read through their own loop,
  `read_link`, instead of `PeerReader.serve`. `serve` drops the bytes it read past a
  frame when it returns, so it cannot hand over. After reading a frame, and BEFORE
  routing it, `read_link` checks `epoch_draining()`. When it is true, the reader sends
  the node actor `MoveReader(kind, link, frame, rest)` and ends without running its
  close path. The actor spawns `read_control`/`read_data` with `Some(frame)` and
  `rest`, and the new reader handles that frame first, then continues from `rest`.
  Order is kept and nothing is read twice. The per-fd MAC state lives in NetKernel's
  Vault, not in the task, so it carries over; the new reader inherits the old one's
  share of `release_link`.
- **Ticker**: `tick_loop` sends its Tick, then moves (`MoveTicker`).
- **Acceptor**: moves after an accept (`MoveAcceptor`); the listen socket stays open.
  If the node stopped in between, the handler closes the socket instead, since no
  accept is parked on it then.

A drain can cover the current epoch too (`SessionNode.drain_epochs`, Topology's
SIGTERM drain). A moved task then finds itself still draining, so a task does not
move again within `move_interval_ms()` (1 s) of being spawned by a move. That bounds
the cost to one move per task per second during such a drain, and still lets a task
moved just before a second deploy follow it.

**Test:** `test/two_node/hcr_remote_msg_epoch`. node-b's `Recv.Sink` is routed by a
ClusterNode route (`Recv.deliver`, on the hot-reload boundary). The version-2 patch
changes Sink's message type, `Note(Int)` to `Note(Int, Int)`, and the decoder along
with it. node-a sends one version-1 message before the deploy, which forms the link
and its readers, and one version-2 message after it. The scenario builds version 1 as
a patch too, for its `.schemas.json`/`.hcr_manifest`, and passes them to the deploy as
the old schemas: a plain `--compile` baseline writes no schema file, and without one
the runtime never learns that the message type changed.

**Red without the fix** (stdlib/cluster_node.march at `4766cfc86`): node-b never
prints the version-2 line, and its reload server logs `migrate_msg: symbol not found:
__migrate_msg_Sink (old-format messages to slot 5 will be dropped and counted)`. The
old reader stamped epoch 1, and the sink, whose message schema epoch was 2, dropped
the message. With the fix it prints `version 2 sink got 7 from a version-2 sender`,
and the reload counters read `converted=0 dropped=0 killed=0 markers_lost=0`.

**Seen on the way, not fixed here.** Without the old schemas, i.e. deploying over a
baseline built with a plain `--compile`, the runtime does not know the message type
changed. The same old reader's one-field `Note(7)` then reached the version-2 handler
and was read as `Note(7, 0)`: a message misread, not converted or dropped. That is the
deploy-without-schemas path, not the reader; forge's deploys pass the old schemas.

**Not covered:**
- A reader of a connection with no traffic moves only at its next frame. A control
  connection carries SWIM every period, so in practice only an idle data connection
  lingers.
- The acceptor moves only at its next inbound connection.
- The `forge test --upgrade-from` six-unit count in
  `2026-09-25-name-units-pinning-old-epoch.md` was not re-measured here.
