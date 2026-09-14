# `[P1]` Distributed actors 1/4: `send` to an actor on another node

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
messages need per-**type** codecs, and those already exist: `derive Json for
T` and `derive Msgpack for T`. `Node.send` requires the message type to
carry one; the compiler enforces it the way `@[endpoints]` payloads are
enforced (a missing derive is a typecheck error at the `Node.send` site, not
a runtime `to_json: cannot determine type` panic — the failure `derive Json`
on an unserialisable field currently gives, which
[[2026-09-13-generated-code-diagnostics-dropped-at-the-cli]] noted).

A `Pid` inside a payload is **not** serialisable. Sending a local pid across
the wire would produce a number meaningful only on the sending node. A
message that must carry an actor reference carries a `GlobalPid.Pid`, built
by the sender from its own node identity. Enforced by the derive: a type
with a `Pid(_)` field has no `Msgpack` instance.

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
2. **Where the frame loop lives.** Today each of SWIM, registry and monitors
   has its own decoder fed by one loop in `cluster_conn`/`swim_driver`. An
   `ACTOR_MSG` arm adds a fourth. Recommend a single `NetKernel.dispatch`
   over the tag byte with one arm per subsystem, done as its own refactor
   commit first (an oracle-able move).

## Tests

- Interpreter and compiled: two nodes over TCP loopback (`node_call_loopback`
  is the template), a `Ping` actor on B, `Node.send` from A, reply by
  `Node.send` to a `GlobalPid` carried in the payload. Golden on both.
- Reject: `Node.send` of a type without a codec; a payload with a `Pid`
  field.
- `DELIVERY_FAILED`: send to a pid that has exited; to a stale creation.
- Then the session fixture: `stream_endpoints` over two nodes with the
  `Session.Ops` network transport, trace identical to the in-process one.
