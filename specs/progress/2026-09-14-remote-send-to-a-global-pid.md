# Distributed actors 1/4: `send` to an actor on another node

**Closed as a design record 2026-09-14.** Everything below shipped except the
typed wrapper, which is its own item now:
[[2026-09-14-typed-node-send-wrapper]]. Shipped: the wire and delivery
contract (`NodeSend`, #454), `pid_to_int` (#461), `DELIVERY_FAILED` as a
message to the sending actor (`cast_from`/`on_failure`, #462), the
`Session.Ops` network transport (`stream` scenario, #462), the per-peer
reader (`PeerReader`, #459).


Filed 2026-09-14. The piece the phrase "distributed actors" implies and the
cluster stack does not have. The other three files in this set
([[2026-09-14-distributed-plane-flow-control-and-control-channel]],
[[2026-09-14-two-node-failure-semantics-harness]],
[[2026-09-14-distributed-plane-known-gaps]]) each presuppose this one's
traffic.

## The gap

Everything cross-node today is a **call** or a **monitor**:

- `NodeCall.call(fd, fref, args, …)` — synchronous RPC to an enrolled
  function, typed by `RemoteRef`, admitted by CAS hash, with a deadline.
- `DistLink.monitor` — `MONITOR_REQ` (tag 7) / `MONITOR_FIRE` (tag 8) frames,
  registered in the C runtime (`march_monitor_registry.c`).
- SWIM ping/ack/req and registry sync (tags 0–2, 5–6).

`GlobalPid.Pid = { node_id, local_pid, creation }` exists as a value and can
be encoded, but no operation takes one. An actor on node A cannot `send` a
message to an actor on node B; a `DistSupervisor` child is *started* by a
remote call and then never spoken to. The choreography line's "network
transport" (`Session.Ops` over nodes) has the same hole: `emit` would need
exactly this.

## Design

### Surface

```march
Node.send(conn : Cap(Node.Peer), to : GlobalPid.Pid, msg : m) : Result((), SendError)
```

where `m` is any message type with a `Json`/`Msgpack` derive, and

```march
type SendError = PeerDown | NotSerialisable(String) | Backpressure
```

Not a change to the builtin `send`. Local `send(pid, msg)` is a scheduler
primitive on a `Pid(state)`; making it accept a `GlobalPid` would hide a
network round trip, a serialisation step, and a failure mode behind a call
that today cannot fail. The remote form is a library function that returns
a `Result`, takes the peer connection as a capability (there is no ambient
cluster, the same rule `Session` follows), and is named so the reader sees
the hop.

### Wire

One new frame tag, `0x09 ACTOR_MSG`:

```
[tag=9, to_local_pid:Int, to_creation:Int, type_tag:Str, payload:Bin]
```

`type_tag` is the message type's fully-qualified name, so the receiver can
reject a message for a type it does not know without decoding the payload;
`payload` is the derived codec's bytes. `creation` guards against a pid
reused by a restarted node (see harness spec, scenario 3).

### Serialisation: derive, not reflection

RPC serialises through compiler-emitted stubs per enrolled function. Actor
messages need per-**type** codecs, and one already exists: `derive Json for
T` (a `derive Msgpack` would be new; `@[endpoints]` ships Json over
`Bytes`). `Node.send` requires the message type to
carry one; the compiler enforces it the way `@[endpoints]` payloads are
enforced (a missing derive is a typecheck error at the `Node.send` site, not
a runtime `to_json: cannot determine type` panic — the failure `derive Json`
on an unserialisable field currently gives, which
[[2026-09-13-generated-code-diagnostics-dropped-at-the-cli]] noted).

A `Pid` inside a payload is **not** serialisable. Sending a local pid across
the wire would produce a number meaningful only on the sending node. A
message that must carry an actor reference carries a `GlobalPid.Pid`, built
by the sender from its own node identity. Enforced by the derive: a type
with a `Pid(_)` field gets no codec instance.

### Delivery

The receiving node's net-kernel loop (the one that today dispatches tags
5–8) gains an `ACTOR_MSG` arm: check `creation` against the node's current
creation; look the local pid up; decode by `type_tag`; enqueue with the
ordinary local `send`. Every failure is a **`DELIVERY_FAILED` (tag 0x0A)**
frame back to the sender carrying the original frame's sequence number and
a reason, which the sender's `Node.send` future resolves to `Err`. Without
that, a remote send is fire-and-forget into a black hole, which is the
`MONITOR_FIRE` problem the hardening file already records.

Ordering: per (sender node, receiver pid) FIFO, which the single TCP
connection gives for free — and which the control/data split in
[[2026-09-14-distributed-plane-flow-control-and-control-channel]] must
preserve for the data channel.

### One transport for endpoints and actors

The `Session.Ops` network transport then writes itself: `emit(ep, to, msg)`
is `Node.send(conn, owner_of(to), Deliver(ep, from, msg))`, `suspend` is
local (the continuation or the parked state stays on the endpoint's node),
and the routing table is the global registry (`GlobalRegistry` maps a name
to `(node, pid)`), which the supervised fixtures already showed is the right
key for a replaceable host. Nothing in `Session.Ops` changes.

## Decisions to make before building

1. **Ack or not.** Whether `Node.send` returns after the frame is written
   (fast, `Err` only for local failures) or after `DELIVERY_FAILED`/`ACK` —
   the second needs a sequence number and a pending table, and is what makes
   `Backpressure` reportable. Recommend: written-to-socket returns `Ok`;
   `DELIVERY_FAILED` is delivered later as a **`Down`-style message** to the
   sending actor (`Node.SendFailed(seq, reason)`), matching how monitors
   report. Synchronous acks belong to `NodeCall`.
2. **Where the frame loop lives.** *(Corrected 2026-09-14 while building:
   there is no loop. Each consumer reads frames off the fd itself and skips
   what it does not recognise, so two consumers on one connection steal each
   other's frames. A single per-peer reader dispatching by tag is new
   machinery, and is step 1 of
   [[2026-09-14-distributed-plane-flow-control-and-control-channel]].)*

## Tests

- Interpreter and compiled: two nodes over TCP loopback (`node_call_loopback`
  is the template), a `Ping` actor on B, `Node.send` from A, reply by
  `Node.send` to a `GlobalPid` carried in the payload. Golden on both.
- Reject: `Node.send` of a type without a codec; a payload with a `Pid`
  field.
- `DELIVERY_FAILED`: send to a pid that has exited; to a stale creation.
- Then the session fixture: `stream_endpoints` over two nodes with the
  `Session.Ops` network transport, trace identical to the in-process one.


---

## Shipped so far (2026-09-14): the wire and the delivery contract

`stdlib/node_send.march` (`NodeSend`): `ACTOR_MSG` (tag 9) and
`DELIVERY_FAILED` (tag 10) frames, `cast`, `serve_one` with the creation
check and the injected dispatch, `recv_failure`. Fixture
`test/native/node_send_loopback.march` (compiled-only, like
`node_call_loopback`: the interpreter's `tcp_accept` fails with EINTR on this
shape, pre-existing) delivers a `Ping` into a remote actor's mailbox, gets a
`Pong` back by the same primitive, then receives all three failure replies.
Soaked 20/20 deterministic. Unit tests for the codecs in
`test/stdlib/test_node_send.march`.

Changed from the design while building:

- **`cast`, not `send`.** `send` is the local actor primitive's reserved
  name; a stdlib `fn send` does not parse.
- **The receiving side is an injected dispatch, as in `NodeRpc`.** The
  design's "look the local pid up; decode by type_tag; enqueue with the
  ordinary local send" cannot live in the library: the message constructor
  is minted by the actor that declares it. `serve_one` checks the creation
  and reports; the dispatch names the actor and the constructor.
- **No pid-to-int builtin existed.** The fixture first read the integer out
  of `to_string(pid)` (`"Pid(N)"`). `pid_to_int(pid)` now exists on both
  backends (the compiled runtime already had the symbol, `march_pid_index_of`,
  as the lowering's internal name for supervisor child registration; the
  surface name maps to it) — see
  [[2026-09-14-pid-to-int-builtin]] in `specs/progress/`. Both loopback
  fixtures use it.
- **`run_until_idle` never returns while a task is parked in a socket
  read.** The fixture prints the reply from main's own thread and drains only
  after the server task has finished.

One trap for the next person: a manual `march --compile` of a `test/native`
or `test/session` fixture writes `<name>.ll` beside the source, and dune
then copies it read-only into the sandbox, where the rule's own compile
fails with `Permission denied` on the `.ll`. Delete the stray `.ll` before
`@test/runtest`.

Still open from the design: the typed wrapper (a `Node.send(conn, to, msg)`
whose codec the compiler checks). The per-peer reader shipped as
`PeerReader` (2/4 step 1); `DELIVERY_FAILED` as a message to the sending
actor shipped as `NodeSend.cast_from` / `on_failure` (below).

## Shipped 2026-09-14: `DELIVERY_FAILED` as a message to the sending actor

Decision 1's recommendation, built: `NodeSend.cast_from(fd, seq, from, to,
type_tag, payload)` records the sending actor under the seq (one Vault per
node process, `node_send_pending`) before writing; the per-peer reader hands
a DELIVERY_FAILED frame to `NodeSend.on_failure(frame, deliver)`, which
finds the sender, forgets the seq, and calls `deliver(sender, seq, reason)`
— the caller's dispatch mints the actor's own constructor (`SendFailed`),
as everywhere else in this layer. `recv_failure` stays for the synchronous
cases. Witness `test/native/node_send_failed_msg.march`: a `Sender` actor
casts to a pid node-b does not host and receives the refusal in its own
mailbox. `NodeSend` now `needs IO.Mut` (reached only through these two).

## Shipped 2026-09-14: the `Session.Ops` network transport

`test/two_node/stream/` — the Stream protocol's two endpoints on two OS
processes (Prod on node-a, Cons on node-b), run by the harness of
[[2026-09-14-two-node-failure-semantics-harness]]. The transport is the
mailbox transport of `stream_actor.march` with one change, exactly as the
design said: `emit` writes a `NodeSend` ACTOR_MSG (`Deliver [to, from, msg]`)
to the peer node's endpoint actor instead of enqueueing for a local drain;
`suspend`/`close` are unchanged and the session state still rides in the
continuation. The receiving node's `PeerReader` loop hands each Deliver to
its endpoint actor and runs that turn to completion before the next frame,
the same one-delivery-per-turn rule the mailbox transport uses. The
generated `@[endpoints]` API and the endpoint code are byte-identical to the
in-process fixtures. Each node's trace is its projection of
`stream_endpoints.expected`, in order (one actor prints per node); 6/6 runs
identical, an order-swapped expectation fails. Nothing in `Session.Ops`
changed. Routing is by the peer's announced `GlobalPid`; the global registry
as the routing table is the multi-peer generalisation.
