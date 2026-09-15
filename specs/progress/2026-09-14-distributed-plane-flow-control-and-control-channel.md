# Distributed actors 2/4: flow control, a control channel, and a delivery contract for monitors

**Closed as a design record 2026-09-14.** Steps 1 and 2 shipped (`PeerReader`
#459; the control/data split #465, plus linear `recv_frame` and the
handshake exact-read fix #466). Steps 3 and 4 are their own items now:
[[2026-09-14-credit-based-flow-control]] and
[[2026-09-14-monitor-fire-at-least-once]].


Filed 2026-09-14. The design the three open plane items in
[[2026-08-11-actor-hardening-distributed-plane]] (items 1, 2, 3) said they
needed. Sequenced after [[2026-09-14-remote-send-to-a-global-pid]]: without
an actor-message stream there is nothing to flow-control, and the control
split is only observable once data traffic can starve it.

## What is measured today

- Outbound frames go straight to `Socket.write` (`NetKernel.send_frame`).
  A peer that stops reading makes `write` block the green thread, or, if
  the socket buffer absorbs it, grows nothing on our side — there is no
  queue to grow *yet*, because there is no async remote send. With
  `Node.send` there will be.
- One TCP connection per peer carries SWIM, registry sync, monitors and
  RPC. `MONITOR_FIRE` is written from `do_actor_death` by the C runtime
  (`march_dist_monitor_fire_pid`), best-effort, ignoring `write` errors,
  onto the watcher's fd — the same fd a large RPC reply may be mid-write on
  from another thread. Nothing serialises those writes; a fire can
  interleave into another frame.

## Design

### Flow control: per-peer credit, decided at the sender

Each peer connection holds an outbound queue with a **byte budget**
(default 4 MiB) and a credit counter the receiver replenishes:

- The receiver sends `CREDIT(n)` (tag `0x0B`) after it has *consumed* — not
  merely read — `n` bytes of data frames; consumption is the point at which
  the frame's message is enqueued to a local mailbox (or rejected with
  `DELIVERY_FAILED`).
- The sender decrements credit on write; at zero it stops writing and the
  queue absorbs new sends up to the budget.
- At the budget, the policy is the sender's per-`Node.send` choice, the same
  three the local bounded mailbox has (`Actor.set_queue_limit` policies):
  `drop_new` (return `Err(Backpressure)` immediately), `drop_old`,
  `block_sender` (park the sending green thread until credit returns; the
  native scheduler can, the interpreter cannot — see
  [[2026-09-14-distributed-plane-known-gaps]]).

Why credit and not just a bounded queue: a bounded queue alone still lets
the sender fill the kernel socket buffer of a peer that has stalled, and the
stall is invisible until the next write blocks. Credit tells the sender the
peer is *processing*, which is also the signal SWIM's suspicion should read
before declaring a slow-but-alive peer dead.

### Control channel: a second connection per peer

Open two connections per peer during the handshake, tagged in the hello
(`role: control | data`), authenticated identically. Control carries SWIM,
registry sync, `MONITOR_REQ`/`FIRE`, `CREDIT`, `DELIVERY_FAILED`; data
carries `ACTOR_MSG` and RPC. The control connection has no credit scheme
(its frames are small and bounded in rate) and its writes are serialised
through one writer per peer, which removes the interleaving above.

Cost: doubles fds per peer and the handshake count. Alternative considered:
priority lanes on one connection. Rejected because TCP has no way to let a
control frame overtake bytes already written; only a second stream can.

### `MONITOR_FIRE`: at-least-once, deduped by `(target_pid, creation, watcher_ref)`

Today: at-most-once, and lost if the watcher's connection is mid-reconnect
or the monitor registered after the death. Contract:

- The firing node keeps the fire in a per-watcher-node retry table until
  the watcher's control channel returns `MONITOR_ACK(ref)`, retrying on
  reconnect with backoff; entries expire when the watcher node is declared
  dead by SWIM (its watchers get `NodeDown` locally anyway).
- A `MONITOR_REQ` for a pid that has already exited answers with an
  immediate `MONITOR_FIRE(reason)` — the "registered after death" race
  becomes a normal fire.
- Watchers dedupe by `(target_pid, creation, ref)`, so a retried fire after
  a lost ack delivers one `Down`.

This is the contract the supervised-endpoint fixtures assume implicitly: a
`DistSupervisor` that never learns a remote child died restarts nothing.

## Order of work

1. **A per-peer receive loop — new, not a refactor.** Measured 2026-09-14
   while building `NodeSend`: there is no net-kernel receive loop to
   refactor. Every consumer reads its own frames off the fd it was handed
   (`NodeCall.recv_reply`/`serve_one`, `NodeSend.recv_failure`/`serve_one`,
   the `node_discovery` fixture calling `SwimDriver.decode_msg`, the
   `DistLink` callers), each skipping frames it does not recognise — which
   means a frame for one consumer is silently consumed and dropped by
   another reading the same connection. The "single `NetKernel.dispatch`"
   the remote-send spec proposed as a refactor is therefore the first piece
   of new machinery here: one reader per peer connection, dispatching by
   tag to registered consumers, which is also the only place credit
   accounting and the control/data split can live.
2. Control/data split — a handshake and connection change, testable by
   asserting a `MONITOR_FIRE` arrives while a 64 MiB RPC reply is in flight
   on the data channel (today it would queue behind it).
3. Credit-based flow control on the data channel, with the three policies.
4. Monitor at-least-once with acks and the after-death answer.

## Tests

- Two-node loopback (native): a stalled reader (peer stops calling
  `recv`) → sender's queue stops at the budget and `Node.send` returns
  `Err(Backpressure)` under `drop_new`; resumes when the reader drains.
- Control latency under data load: fire arrives within one scheduler tick
  while the data channel is saturated.
- Monitor: kill a target before the watcher's `MONITOR_REQ` arrives → one
  `Down`; drop the watcher's connection between death and ack → one `Down`
  after reconnect, not two.


---

## Shipped so far (2026-09-14): step 1, the per-peer reader

`stdlib/peer_reader.march` (`PeerReader`): `tag_of(frame)` reads the tag
without decoding the rest; `serve(fd, buf, on_frame)` reads frames once and
hands each to the caller's dispatch with its tag, carrying bytes past a frame
boundary to the next read (every ad-hoc reader dropped them). The dispatch is
injected, as in `NodeRpc`/`NodeSend`, because a library cannot name an
actor's constructors. RPC frames carry no tag (a request begins with the
`RemoteRef`, a reply with its correlation `Int`, which lands anywhere in the
tag space), so RPC keeps its own connection until the control/data split
gives it a tagged envelope — that is the one wire change the split makes.

Witness: `test/native/peer_reader_loopback.march` — three frames for two
consumers written in one burst, all three delivered in order by one reader.
Proved non-vacuous: with the leftover bytes dropped (the ad-hoc readers'
behaviour), only the first frame arrives and the reader waits forever.
Unit test `test/stdlib/test_peer_reader.march` covers every frame family's
tag, an untagged RPC request, and garbage.

## Shipped so far (2026-09-14): step 2, the control/data split

`Handshake.Hello` carries a `role` (`"control"` | `"data"`), a fifth
element on the wire; a four-element hello — every node before the split —
decodes as control, so the shapes interoperate. `NetKernel.handshake_role`
returns the peer's identity and the role it announced;
`PeerRegistry.Peer` gains `data_fd` (`no_fd()` = -1 for a pre-split peer;
`add_data`, `has_data`); `ClusterConn.connect_split` dials control then
data, `accept_split` takes a peer's two connections in that order.
`NodeSend.serve_one_reply(fd, reply_fd, …)` sends DELIVERY_FAILED on the
control connection while the message arrived on data. The single-connection
`connect_to_peer` / `accept_one` stay.

Witness: `test/native/control_channel_loopback.march` — node-b writes a
16 MiB frame on data and, a quarter of the way through, a SWIM ping on
control; node-a's two readers timestamp the ping's arrival before the data
stream's completion (on one connection the ping would sit behind the
remaining 12 MiB). 5/5 identical runs.

Measured on the way: `NetKernel.recv_frame` accumulated the frame with
`List.append` per 4 KiB chunk, quadratic in the frame size — a 16 MiB frame
was impractical through it, so the witness streams the body as raw bytes.
**Fixed the same day:** once the 4-byte prefix is in the buffer the rest of
the body is read with one `tcp_recv_exact` and appended once (linear per
frame; API unchanged). `test/native/net_frame_large_loopback`: a 1 MiB
frame in 0.3 s against 4.1 s before, with a small frame arriving in the
same `recv()` to check the leftover carry. Credit accounting (step 3)
should still carry frames as `Bytes` rather than `List(Int)`; the list is
now merely large, not quadratic.

Found by the witness on the macOS CI leg and reproduced locally only under
load (2 runs in 20 with eight `yes` processes; never unloaded): the
handshake read its two frames with `recv_frame`, which reads in 4 KiB
chunks and returns the over-read as a leftover — and the handshake DROPPED
that leftover. A peer that finished its side and immediately wrote (node-b's
first 8 bytes on the data connection) lost them whenever they landed in the
same `recv()` as the proof. Same class `PeerReader` exists for, one layer
earlier. Fixed: `NetKernel.recv_frame_exact` reads the prefix and exactly
the body, and the handshake uses it, so a connection is handed over with the
peer's first real frame still unread in the socket; 30/30 under load after.

Not yet moved to the control connection: the C runtime's `MONITOR_FIRE`
write (`march_dist_monitor_fire_pid`) still targets the fd `DistLink`
registered, which is whatever connection the MONITOR_REQ arrived on — a
caller that receives MONITOR_REQ on control (as the split intends) already
gets fires on control. Steps 3–4 (credit, monitor acks) remain.
