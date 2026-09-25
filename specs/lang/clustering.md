---
layout: docs
title: Clustering & RPC
nav_order: 10.5
permalink: /docs/clustering/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Clustering & RPC

March's distributed layer lets multiple nodes form a cluster, discover each other, detect failures, and call functions across node boundaries with type-safety guarantees. The full stack is built from composable pure modules layered on top of the [actor runtime]({{ site.baseurl }}/docs/actors/) and its [supervision trees]({{ site.baseurl }}/docs/supervision/).

> **This page is an API reference, not a runnable quickstart.** The code below shows how
> the layers fit together, but the end-to-end examples are *skeletons*; two things can
> only come from a real build, not from copy-paste: the actual byte transport over each
> socket, and the `sig_hash` / `impl_hash` values the compiler bakes into your binary for
> the specific functions you enroll (see [Putting It Together](#putting-it-together)). For
> a complete executing example, the cluster integration tests under the project's `test/`
> tree run the whole accept → handshake → enroll → call → reply loop.
>
> **New to March concurrency?** Don't start here. Begin with
> [Actors]({{ site.baseurl }}/docs/actors/) (`spawn` / `send`) and
> [Supervision Trees]({{ site.baseurl }}/docs/supervision/): clustering is the
> distributed generalization of those, and this page assumes them throughout.

---

## From one node to a cluster

Start from where [Supervision Trees]({{ site.baseurl }}/docs/supervision/) leaves off: a supervised actor app running on a single machine. You `spawn` a worker, it gets a `Pid`, and locally you might register it under a name so other parts of the program can find it without threading the `Pid` around.

**Clustering is that exact pattern, stretched across machines.** `GlobalRegistry` is *the distributed version of spawning and registering an actor*: instead of a name → `Pid` map living in one process, it's a cluster-wide, gossip-replicated name → `{node_id, pid}` map that every node converges on. Register a worker under a cluster name on Node A, and Node B can look that name up and call it, without holding A's raw `Pid` at any point.

Here's the whole arc in miniature. On Node A, a supervised worker registers itself under a cluster-wide name:

```march
-- Node A: register a local worker under a cluster-wide name.
-- `my_clock` is this node's VectorClock; `42` is the worker's local Pid as an Int.
let reg = GlobalRegistry.empty()
let reg = GlobalRegistry.register(reg, "image-resizer", "a@127.0.0.1", 42, my_clock)
```

That `reg` is gossiped to peers (every `merge` is idempotent, so re-delivery is safe). On Node B, after the registry has converged, a second node looks the name up and issues a `RemoteCall` against it:

```march
-- Node B: find the worker by name, then call it across the cluster.
match GlobalRegistry.lookup(reg, "image-resizer") do
  None ->
    -- not registered yet (or tombstoned) — retry later
    ()
  Some((node_id, pid)) ->
    -- Build a type-safe remote reference and a request addressed to that pid.
    let fref      = RemoteCall.remote_ref("Image", "resize", sig_hash, impl_hash)
    let reply_to  = GlobalPid.make(my_id.node_id, 1, 1)
    let args      = Msgpack.encode(Msgpack.int(800))
    let req       = RemoteCall.request(fref, args, reply_to, 5000, 1)
    -- `RemoteCall.encode_request(req)` is the frame to send to `node_id`;
    -- the reply is decoded with `NodeRpc.interpret`. (Full loop below.)
    ()
end
```

The rest of this page is the infrastructure that makes those two snippets safe: how nodes authenticate (handshake), how they agree on who's alive (membership + SWIM), how a name resolves to a node (`GlobalRegistry`), and how a call is type-checked before the remote body runs (`RemoteCall` / `NodeRpc`). Read it top-to-bottom for the layered model, or jump to [Putting It Together](#putting-it-together) for an end-to-end two-node skeleton.

> `GlobalRegistry.lookup` returns `Option((String, Int))`: the holder's `node_id` and its **local** `pid` on that node. You address remote calls with a `GlobalPid` (node + local pid + creation counter), which is what remains valid across a restart unambiguously.

---

## A running node: `ClusterNode`

Everything below this section is the layer cake: pure modules and socket glue you can
assemble by hand. `ClusterNode` is the assembled node, and most programs should start with it:

```march
-- MARCH_NODE_NAME=a MARCH_NODE_PORT=4001 MARCH_CLUSTER_NODES=10.0.0.2:4001 \
-- MARCH_CLUSTER_SECRET=... MARCH_NODE_ADVERTISE=10.0.0.1:4001
-- (or, instead of the secret, MARCH_NODE_CERT / MARCH_NODE_KEY /
--  MARCH_CLUSTER_OPERATOR_PUBKEY: see "Authentication & Handshake")
-- inside `fn main(io : Cap(IO))`, in a module that declares `needs ClusterNode.Live`
match ClusterNode.config_from_env() do
  Err(e) -> panic(e)
  Ok(cfg) ->
    match ClusterNode.start(io, cfg) do
      Err(e) -> panic(e)
      Ok(node) ->
        let _ = ClusterNode.subscribe(node, fn ev -> println(ClusterNode.event_text(ev)))
        let _ = ClusterNode.register(node, "image-resizer", worker)   -- a local Pid
        match ClusterNode.lookup(node, "image-resizer") do
          Some(gpid) -> ()          -- a GlobalPid: node_id, local pid, creation
          None -> ()
        end
    end
end
```

What `start` gives you:

- **Joining.** The node listens, dials its seeds, and exchanges member lists with every
  peer it links to. Each member carries its *advertised* address, so a node reaches peers it
  was never configured with. Set `MARCH_NODE_ADVERTISE` to an address other machines can
  reach; it defaults to `127.0.0.1:<port>`. A node that reaches no seed runs alone and keeps
  retrying.
- **One connection pair per peer.** Everything (failure detection, the registry, remote
  monitors, actor messages) shares one authenticated control connection and one data
  connection per peer.
- **Failure detection.** SWIM runs continuously. `subscribe` reports `NodeUp`,
  `NodeSuspect`, `NodeDead(info, cause)` and `NodeRejoined`. A connection that closes only
  makes a peer *suspect* and triggers a reconnect; a refused reconnect (nothing listening)
  or SWIM's timeout makes it *dead*. A dead peer is reconnected on a backoff and rejoins when
  it proves it is alive. A peer that restarted is a new *creation*: the old one is reported
  dead and the new one as rejoined.
- **Names.** `register(node, name, pid)`, `unregister`, `lookup`, and `watch(node, name, f)`,
  which reports `Bound`, `Unbound` and `Lost`. A registration is pushed to every peer at
  once and repaired by periodic anti-entropy. `lookup` hides a binding whose holder is dead,
  or has restarted since it registered. The registered process is monitored, and its death
  unregisters the name.

**Messages and monitors over the node.** Every actor message, remote monitor and flow-control
frame between two nodes shares the node's one connection pair.

```march
-- receiving side: deliveries for a local process arrive through a route
let _ = ClusterNode.route(node, pid_to_int(worker), fn d -> do
  send(worker, Job(Node.payload(d)))
  Ok(())
end)
-- sending side: through the peer's data queue (credit flow control)
let _ = ClusterNode.send_msg(node, gpid, "Jobs.Job", bytes, NodeQueue.BlockSender(5000))
-- or typed: Node.enqueue(q, gpid, msg, policy) with q = ClusterNode.queue_for(node, gpid.node_id)
let _ = ClusterNode.monitor_remote(node, gpid, fn reason -> send(me, WorkerDown(reason)))
```

`on_peer_closed(node, f)` tells you when a peer's data connection ends, after its last
delivery, and says why (`"node b dead: suspect timeout"`, `"connection lost"`).
`on_delivery_failed` reports messages the peer refused. Use `send_msg` or `Node.enqueue`,
never `Node.send(peer, ...)`, on a node's connections: `Node.send` writes the socket directly
and would interleave with the queue.

**A global name is not a lock.** During a network partition, each side can register the same
name. When the partition heals, one binding wins everywhere: a registration made after seeing
the other is causally newer and wins; otherwise a deterministic tiebreak picks. The node
whose binding lost gets `Lost(name, winner)` on its watchers. It should stop acting as the
holder and must not unregister (the name is not its own any more). Use a global name for
discovery, where a brief duplicate is harmless, and never for mutual exclusion.

**The node is a capability.** `start(io, cfg)` returns a `Cap(ClusterNode.Live)`, minted
from the program's `Cap(IO)`: code that holds it can use the cluster, and code that does not
cannot. A module whose signatures name it declares `needs ClusterNode.Live`, as for any
capability. Like every proof capability, only `ClusterNode` can create one, so your own
function cannot return a node it started. Start the node in `main` (or wherever you hold
`Cap(IO)`) and pass the capability down; a helper that waits for peers takes it as a
parameter:

```march
fn main(io : Cap(IO)) do
  let node = match ClusterNode.start(io, cfg) do
    Ok(n) -> n
    Err(e) -> panic(e)
  end
  joined(node)          -- pfn joined(n : Cap(ClusterNode.Live)) : () do ... end
  ...
end
```

**Testing without a network.** Every operation above goes through the capability's
dictionary, a record of functions (`ClusterNode.ClusterOps`, one field per operation). `start`
attaches the real one. A test attaches its own with `ClusterNode.attach(io, ops)`, and code
written against a real node then runs against it. `ClusterNode.ops_stub(node_id)` is a
dictionary whose every operation panics with its own name; override the ones the code under
test uses:

```march
let ops = { ClusterNode.ops_stub("n0") with
  members: fn _ -> fake_members(fake),
  subscribe: fn f -> fake_subscribe(fake, f) }
let node = ClusterNode.attach(io, ops)
-- the test now calls the subscribers itself: NodeDead(info, "suspect timeout"), ...
```

A zero-argument operation takes `()`: `members: fn _ -> ...`. This is how membership
reactions are tested with no sockets: `test/session/cluster_placement.march` injects
`NodeDead` into a placement that moves roles off dead nodes.

---

## Overview

A March cluster is a set of named nodes connected by authenticated TCP links. The stack is organized in layers:

| Layer | Module(s) | Responsibility |
|-------|-----------|----------------|
| L1 | `NetFrame`, `Socket` | Length-prefixed framing over TCP |
| L2 | `NetKernel`, `ClusterConn` | Node-to-node channels, authenticated handshake |
| L3 | `Membership`, `Swim`, `PeerRegistry` | Failure detection, live member set |
| L4 | `RemoteCall`, `NodeRpc`, `GlobalPid` | Safe cross-node function calls |
| L5 | `GlobalRegistry` | Cluster-wide name → pid registry (CRDT) |

---

## Node Identity

Every node has a stable identity captured in a `NodeIdentity.Identity` record:

```march
let id = NodeIdentity.make("alice@host", "alice-public-key", 1)
-- { name: "alice@host", node_id: <sha256 of pubkey>, incarnation: 1 }
```

`make(name, pubkey, incarnation)` derives the `node_id` by hashing the public key (`Crypto.sha256(pubkey)`). The resulting `node_id` is the primary key used in every distributed data structure, and it must be unique across the cluster. `incarnation` increments each time the node restarts, so peers can tell a fresh start from a stale one.

### Serialisation

Node identities are serialised to MessagePack for transport:

```march
let bytes = NodeIdentity.encode(id)   -- List(Int)
match NodeIdentity.decode(bytes) do
  Ok(id2) -> id2
  Err(e)  -> ...
end
```

---

## Authentication & Handshake

Before any cluster traffic flows, two nodes run a challenge-response handshake.
A node authenticates in one of two modes:

| mode | a node holds | set with |
|---|---|---|
| shared secret (default) | one secret every node shares | `MARCH_CLUSTER_SECRET` |
| certificate | its own ed25519 key and a certificate for it, signed by the cluster's operator key | `MARCH_NODE_CERT`, `MARCH_NODE_KEY`, `MARCH_CLUSTER_OPERATOR_PUBKEY` |

`ClusterNode.config_from_env` picks the mode: with `MARCH_NODE_CERT` set it
uses certificate mode and ignores `MARCH_CLUSTER_SECRET`, otherwise shared-secret
mode. Each certificate-mode variable holds the value itself or names a file
holding it. The two modes do not mix: a certificate node refuses a
shared-secret peer and the other way round, and each says which variables the
other side needs. Operator setup (keys, issuing, renewal, revocation) is in
[Cluster Certificates]({{ site.baseurl }}/docs/cluster-certificates/).

### Shared-secret mode

```march
let secret = Crypto.random_hex(32)   -- random hex String shared by all nodes
```

Each side sends a hello with a fresh nonce and answers the peer's nonce with
`ClusterAuth.prove(secret, nonce)`, which is `HMAC-SHA256(secret, nonce)`. The
secret never goes on the wire. Every node must hold the same secret. Any holder
can join as any node, so this mode cannot limit what a node may do (see the
threat model below).

### Certificate mode

A certificate (`NodeCert`) names one node, what it may do, and when it expires:

| field | example |
|---|---|
| `node` | `spiffe://prod.example/pool/web/node/web-1` |
| `roles` | `["Checkout.Ledger:offer", "Checkout.Client:initiate"]` |
| `flags` | `["raw_send"]` |
| `not_after` | unix seconds, inclusive |
| `issuer` | `spiffe://prod.example/operator/<16 hex digits of the operator key>` |
| `pubkey` | the node's ed25519 public key, hex |
| `serial` | what a revocation names |

Names are SPIFFE-style URIs so that a service mesh can carry the same
identities later; March does not implement SPIFFE itself. In the handshake each
hello carries the sender's certificate and a fresh X25519 key. Each side checks
the peer's certificate: the operator's signature, `not_after`, the node's
revocation list, and that it names the node the hello claims to be. Then each
side signs the peer's nonce together with a hash of both hellos, and checks the
peer's signature under the key its certificate names. `NodeCert.verify(cert,
operator_pubkey, now)` is the certificate check on its own.

A verified certificate stays with its peer: `ClusterNode.peer_cert(c, node_id)`
returns it (`ClusterConn.peer_cert` for direct connections), and
`ClusterNode.own_cert(c)` returns the node's own. What a node may do with its
roles and flags is in [Authorization](#authorization) below.

### Per-frame MAC

After the handshake every frame on the connection is sealed: it carries a
sequence number and an HMAC-SHA256 tag under a key for that connection and
direction. The key comes from HKDF over a hash of the two hellos. In
certificate mode its input is an X25519 agreement between the two ephemeral
keys, which the signed handshake binds to the two certificates. In shared-secret
mode its input is the secret. The length prefix covers the 40 bytes this adds.

The receiver accepts each sequence number once, within a window of 32. A
frame whose tag fails, or whose number was seen already, is dropped and
counted (`ClusterNode.frames_rejected`), and on-security-event subscribers get
`FrameRejected(node_id, n)`. After three such frames on one connection it is
closed, and the peer is handled like any lost connection. A shared-secret node
offers the MAC in its hello, so a node from before the MAC still connects,
unsealed.

**This is integrity, not confidentiality.** Frames are not encrypted, and
anyone on the network path can read them. The MAC stops a party without the
connection's key from changing, injecting or replaying frames. It does not
detect a frame that is dropped in transit, since an attacker who can drop
frames can drop the connection too. Encryption is deferred (decision D4 of the
distributed-deploys plan); run the cluster on a private network or under a
mesh that encrypts.

### Expiry and revocation

A node rechecks each peer's certificate every tick. When it has expired, or a
revocation names it, the node closes the peer's connections and reports
`NodeDead(info, "certificate expired")` or `NodeDead(info, "certificate
revoked")`, so sessions with the peer are cancelled as for any dead node. The
peer's handshakes are refused from then on, until it presents a valid
certificate.

A revocation is signed by the operator key and names a certificate's serial,
or a whole node. `ClusterNode.revoke(c, token)` takes the token `forge cluster
revoke` prints; `MARCH_CLUSTER_REVOCATIONS` gives a node its list at start
(tokens separated by commas or whitespace, or a file of them). Nodes pass
revocations on to every peer, and a revocation counts only if the operator
signed it, so a member cannot revoke another.

`ClusterNode.on_security_event(c, f)` reports refused handshakes
(`HandshakeRejected(who, why)`) and rejected frames (`FrameRejected(node_id,
n)`).

### Threat model

Certificates limit what a misbehaving *member* can do on a trusted network:
who may join, and which conversations each node may take part in (see
[Authorization](#authorization)). They do not provide confidentiality, availability against a
member that lies in SWIM gossip, or protection inside a node that runs foreign
code.

### The handshake in code

`ClusterNode` runs all of this itself. At the connection level:

```march
-- Either mode: ClusterAuth.Secret(secret) or ClusterAuth.Certified(credentials)
match NetKernel.handshake_auth(fd, my_id, auth, NetKernel.fresh_nonce(), Handshake.role_control(), "", 5000) do
  Ok(peer) -> -- peer.identity, peer.cert (certificate mode), peer.mac
  Err(e)   -> -- reject and close fd
end

-- The shared-secret spelling, unchanged
match NetKernel.handshake(fd, my_id, secret, NetKernel.fresh_nonce()) do
  Ok(peer_id) -> -- connection authenticated; peer_id is their NodeIdentity
  Err(e)      -> -- reject and close fd
end
```

`ClusterConn.connect_split_auth` and `accept_split_auth` open a peer's control
and data connections in either mode and return its certificate.
`ClusterConn.accept_one` wraps accept, handshake and enrolment for the
listening side in shared-secret mode:

```march
match ClusterConn.listen(9000) do
  Ok(listen_fd) ->
    let loop = fn _ ->
      match ClusterConn.accept_one(registry, listen_fd, my_id, secret) do
        Ok(peer_id) -> log("connected: " ++ peer_id.node_id)
        Err(e)      -> log("rejected: " ++ e)
      end
      loop(Nil)
    loop(Nil)
  Err(e) -> ...
end
```

---

## Authorization

In certificate mode a node checks what each peer's certificate lets it do, not
only who the peer is. Every check below applies **in certificate mode only**. A
shared-secret cluster has no certificates: any node holding the secret may
offer or initiate any role, so a shared-secret cluster should be one where
every node is equally trusted.

### Roles: who may form a session

A certificate names the protocol roles its node may play, as
`Proto.Role:offer` (it may offer the role at an access point) and
`Proto.Role:initiate` (it may start a session in the role). When a session
forms at access points, both sides check
([Choreography: access points]({{ site.baseurl }}/docs/choreography/#access-points-many-sessions-and-starting-again)):

| who checks | what | on failure |
|---|---|---|
| the initiator, before inviting | the certificate of the node that **holds** each offer names `Proto.Role:offer` | the offer is skipped; `NoOffer`'s reasons say `node-b not authorized for Checkout.Ledger, not invited` |
| the offer, on each invitation | the certificate of the node the invitation came from names `Proto.Role:initiate` for the role it plays | the offer refuses: `initiator node-a not authorized for Checkout.Client` |
| each party, once the session forms | every role's endpoint is on a node whose certificate allows that role | `Connect(role, "... is held by node-c: not authorized for ...")` |
| a node, opening an offer | its own certificate names `Proto.Role:offer` | `Err(Unauthorized(role, why))` |

The checks read the certificate the node verified in its handshake with that
peer. They never trust the registry: offer names and session names are
registry names that any member can write, and the node an invitation came from
is the link it arrived on (`NodeSend.Delivery.from_node`), not anything in the
frame. The pure check is `SessionAP.authorize(cert, proto, role, mode)`, and
`ClusterNode.authorize_peer(c, node_id, proto, role, mode)` applies it to a
peer (always `Ok` in shared-secret mode).

### What authorization does not cover

Authorization is about **authority**: which conversations a misbehaving member
can join, and so, since every message in a session is checked against the
protocol, what it can say. It is not about availability or confidentiality:

- A member can still lie in SWIM gossip, refuse to answer, or drop what it
  receives.
- Frames are not encrypted. The per-frame MAC stops a party without the
  connection's key from changing or injecting frames, but anyone on the path can
  read them.
- Nothing constrains what code inside a node does, including foreign code
  (`IO.Foreign`). Isolate such code on its own node, whose certificate names
  only the roles it needs.
- A node's messages are untrusted input. Payload refinements on message types
  are checked by the receiver, and are a security boundary as well as a
  correctness one.

---

## Membership & Failure Detection

### Membership CRDT

`Membership` maintains the set of known cluster members as a last-write-wins CRDT. Each member includes a `MemberStatus` (`Alive`, `Suspect`, or `Dead`) and an `incarnation` counter for causal ordering. You build a `Member` value with `alive`/`suspect`/`dead`, then fold it into the view with `observe`.

```march
let members = Membership.empty()
let members = Membership.observe(members, Membership.alive("alice@192.168.1.10", 1))
-- Mark a member dead by observing a Dead status at its current incarnation
let members = Membership.observe(members, Membership.dead("bob@192.168.1.11", 1))

-- Merge two views (safe to call repeatedly — idempotent)
let merged = Membership.merge(local_view, remote_view)

-- Query
let alive  = Membership.alive_members(members)   -- List(Member)
let member = Membership.get(members, "alice@192.168.1.10")   -- Option(Member)
```

### SWIM failure detection

`Swim` implements the SWIM gossip protocol as a pure state machine. It produces `Action` values that tell the runtime what to send; no sockets inside.

```march
let cfg   = Swim.config(200, 2000, 3)   -- ack_timeout_ms, suspect_timeout_ms, indirect_k
let state = Swim.make("alice@192.168.1.10", 1, members, cfg)

-- Tick: begin a probe period by directly pinging a (caller-chosen) target
let (state, action) = Swim.begin_period(state, now_ms, "bob@192.168.1.11")
-- action is SendPing(target)

-- Process an incoming ack
let state = Swim.on_ack(state, "bob@192.168.1.11")

-- Escalate an overdue direct ping to indirect ping-reqs via helper nodes
let (state, actions) = Swim.escalate_indirect(state, now_ms, helpers)

-- End the period: an unacked probe marks its target Suspect and gossips it
let (state, actions) = Swim.end_period(state, now_ms)

-- Advance suspect timeouts: promote expired Suspects to Dead
let (state, actions) = Swim.expire_suspects(state, now_ms)
```

Each `Action` maps to a message to send over the cluster connection:

| Action | Meaning |
|--------|---------|
| `SendPing(target)` | Direct probe to `target` |
| `SendPingReq(target, intermediary)` | Indirect probe via `intermediary` |
| `Gossip(member)` | Piggyback member state on next message |

---

## Global Registry

`GlobalRegistry` is a cluster-wide name → `{node_id, pid}` mapping that merges correctly under concurrent updates (CRDT with vector-clock causal ordering and deterministic tiebreak).

```march
let reg = GlobalRegistry.empty()

-- Register a name on this node
let reg = GlobalRegistry.register(reg, "worker-1", "alice@192.168.1.10", 42, my_clock)

-- Look up a name — returns Option((node_id, pid))
match GlobalRegistry.lookup(reg, "worker-1") do
  Some((node_id, pid)) -> pid      -- Int (local pid on node_id)
  None                 -> ...
end

-- Remove a name (tombstone — converges with concurrent registrations)
let reg = GlobalRegistry.unregister(reg, "worker-1", my_clock)

-- Merge two registry views (idempotent)
let reg = GlobalRegistry.merge(local_reg, remote_reg)

-- Enumerate
let names = GlobalRegistry.names(reg)   -- List(String)
let n     = GlobalRegistry.size(reg)
```

Merge is idempotent: applying the same remote view twice produces the same result. This makes gossip-based propagation safe: broadcast to all peers and let them forward.

---

## Remote Calls

### GlobalPid: cluster-wide process identifiers

A `GlobalPid` uniquely identifies a process across the cluster:

```march
let pid = GlobalPid.make("alice@192.168.1.10", 42, 1)
-- { node_id: "alice@192.168.1.10", local_pid: 42, creation: 1 }

-- Serialise / deserialise (for inclusion in RPC messages)
let v    = GlobalPid.to_value(pid)
let pid2 = GlobalPid.of_value(v)   -- Result(GlobalPid.Pid, String)
```

The `creation` counter lets the runtime distinguish a new process at the same local pid from a restarted one.

### RemoteRef: type-safe function references

A `RemoteRef` pins a remote function by both its type signature hash and its implementation hash:

```march
let fref = RemoteCall.remote_ref("Math", "add", sig_hash, impl_hash)
-- { module_name: "Math", fn_name: "add", sig_hash: ..., impl_hash: ... }
```

| Field | Hash of | Guards against |
|-------|---------|----------------|
| `sig_hash` | Public type signature | Calling a function with a different type |
| `impl_hash` | Function body (Merkle root) | Calling a different version of the same function |

The hashes are recorded in the compiled binary. The responder node's RPC dispatcher rejects any call where they don't match its local copy.

### Making a call

Build a `CallRequest`, encode it, send it over the connection, then decode the reply:

```march
let reply_pid = GlobalPid.make(my_node_id, my_local_pid, 1)
let fref      = RemoteCall.remote_ref("Math", "add", sig_hash, impl_hash)
let args      = Msgpack.encode(Msgpack.array(Cons(Msgpack.int(2), Cons(Msgpack.int(3), Nil))))
let req       = RemoteCall.request(fref, args, reply_pid, deadline_ms, correlation_id)

-- Encode to bytes for transport
let frame = RemoteCall.encode_request(req)

-- On the caller side, when a reply arrives:
match NodeRpc.interpret(reply) do
  Ok(payload) ->
    -- payload is raw Msgpack bytes; decode them
    match Msgpack.decode(payload) do
      Ok(Msgpack.Int(n)) -> n
      _                  -> ...
    end
  Err(err) ->
    -- err is a CallError — see below
    ...
end
```

### CallError taxonomy

| Error | Meaning |
|-------|---------|
| `DeadlineExceeded` | No reply before the deadline |
| `NoConnection` | The peer is unreachable or has disconnected |
| `RemoteExit(msg)` | The target function raised an error |
| `TypeMismatch` | `sig_hash` did not match; type API changed |
| `VersionSkew` | `sig_hash` matched but `impl_hash` did not; different body version |
| `NoTarget` | No function enrolled under that module/function name |

`TypeMismatch` and `VersionSkew` are safe: the remote body was **never invoked**.

### Caller-side helpers

```march
-- Check whether a reply belongs to a given request (by correlation id)
NodeRpc.matches(req, reply)    -- Bool

-- Timeout check (compare current time to request deadline)
NodeRpc.timed_out(now_ms, req.deadline)   -- Bool

-- Synthesise a peer-down error reply
NodeRpc.peer_down_error()   -- CallError
```

---

## Responder Side (NodeRpc)

Each node runs an RPC dispatcher that maps `(module, function)` keys to local stubs. The stubs decode MessagePack arguments, call the local function, and encode the result.

### Enrolling a function

```march
-- A stub: decode args, call the real function, encode the result
fn add_stub(args : List(Int)) : Result(List(Int), String) do
  match Msgpack.decode(args) do
    Err(e) -> Err(e)
    Ok(v)  ->
      match v do
        Msgpack.Array(Cons(Msgpack.Int(a), Cons(Msgpack.Int(b), Nil))) ->
          Ok(Msgpack.encode(Msgpack.int(a + b)))
        _ -> Err("add: bad args")
      end
  end
end

let targets = NodeRpc.empty()
let target  = { sig_hash: sig_hash, impl_hash: impl_hash, invoke: add_stub }
let targets = NodeRpc.enroll(targets, "Math", "add", target)
```

### Dispatching incoming frames

```march
-- Given raw bytes from the network:
match NodeRpc.handle_frame(targets, frame) do
  Some(reply) ->
    -- Encode the reply and send it back
    let reply_bytes = RemoteCall.encode_reply(reply)
    -- ... write reply_bytes to the peer's socket ...
  None ->
    -- Malformed frame — log and discard
    ()
end
```

`handle_frame` decodes the request, verifies `sig_hash` and `impl_hash` against the enrolled stub, invokes it (if both match), and returns a `CallReply`. The verification logic is:

1. No stub for `(module, fn)` → `NoTarget`
2. `sig_hash` mismatch → `TypeMismatch` (stub never called)
3. `impl_hash` mismatch → `VersionSkew` (stub never called)
4. Stub returns `Err(msg)` → `RemoteExit(msg)`
5. Stub returns `Ok(bytes)` → `Returned(bytes)`

---

## Remote actor messages: `NodeSend`

A `NodeCall` is a synchronous call to a *function*. To send a one-way
*message* to an actor on another node, the way `send(pid, msg)` does locally,
use `NodeSend`:

```march
-- sender: a frame on the peer connection, addressed by GlobalPid
let target = GlobalPid.make("node-b", their_local_pid, their_creation)
let _ = NodeSend.cast(conn_fd, seq, target, "App.Ping", payload_bytes)

-- receiver: decode one frame and hand it to a dispatch that knows which
-- local actor hosts which message type
let _ = NodeSend.serve_one(conn_fd, my_creation, fn d ->
  match d.type_tag do
    "App.Ping" -> let _ = send(ping_actor, Ping(d.payload))
                  Ok(())
    other      -> Err("unknown type " ++ other)
  end)
```

`cast` (not `send`, which is the local primitive's name) writes an
`ACTOR_MSG` frame `[9, seq, local_pid, creation, type_tag, payload]` and
returns once it is written. The receiving node checks the `creation` against
its own before dispatching, so a message addressed to a pid from before that
node restarted is refused rather than delivered to whatever now owns the
number. Any refusal — stale creation, a type the dispatch does not host, a
pid that is not alive, a payload it cannot decode — goes **back to the
sender** as a `DELIVERY_FAILED` frame `[10, seq, reason]`, read with
`NodeSend.recv_failure`. A remote send is not fire-and-forget.

Two things are the caller's, by design: the dispatch (a constructor is minted
by the actor that declares it, so a library cannot wrap the payload), and the
payload codec (encode the message with its `derive`d codec into bytes; the
frame carries bytes). Pids never travel: a message that must name an actor
carries a `GlobalPid`. `test/native/node_send_loopback.march` runs the whole
exchange over TCP loopback, including all three failure replies.

## Typed remote messages: `Node.send` and `@[remote]`

`NodeSend.cast` carries bytes under a string tag you keep in step by hand. The typed layer
checks and generates both halves.

**Sending.** `msg`'s type must `derive Json`; a missing codec is a compile error at the call.
The wire tag is the type's declared name, minted by the compiler. It is module-qualified
below the entry module (`Msgs.Ping` for `mod Msgs` inside the entry file), so the sender and
the receiver agree when both programs declare the type in the same module path.

```march
mod Msgs do
  type Ping = { n : Int, who : String }
  derive Json for Ping
end

let _ = Node.send(peer, target, ping)                       -- straight to the connection
let _ = Node.enqueue(q, target, ping, NodeQueue.DropNew)    -- through the peer's NodeQueue
```

`Node.send` writes the message to the connection immediately. `Node.enqueue` adds it to the
peer's credit-based `NodeQueue`. Both return `Ok(seq)`; a later `DELIVERY_FAILED` echoes
that seq. The queue's policy decides what happens when the peer's budget is full:
- `DropNew` refuses the new message with `Err(Backpressure)`.
- `DropOld` evicts the oldest queued messages to make room.
- `BlockSender(timeout_ms)` makes the caller wait for credit. Inside an actor's handler
  this is safe, but the actor handles nothing else while it waits: messages sent to it in
  the meantime stay in its mailbox, in order, and are handled after the handler returns.
- `Unbounded` never refuses and never waits: the message queues past the budget and goes out
  as credit arrives. The choreography runner sends this way.

A message larger than the whole budget is accepted when the queue is empty and sent on its
own, so no message is too big to send.

**Receiving.** Mark the actor `@[remote]`. Every handler that takes one parameter of a
declared type becomes a routing target, and the compiler generates `<Actor>_Remote.dispatch`:

```march
@[remote]
actor Inbox do
  state { n : Int }
  init  { n: 0 }
  on GotPing(p : Ping) do ... end
end

-- in the node's reader, per ACTOR_MSG delivery `d`:
match Inbox_Remote.dispatch(inbox_pid, d) do
  Ok(true)  -> ()                          -- decoded and sent to the actor's mailbox
  Ok(false) -> ...                         -- no handler of Inbox takes this type
  Err(e)    -> ...                         -- not JSON, or not the type its tag names
end
```

The dispatch compares the delivery's tag with the tag the sender's compiler minted for each
handler's type, so the two sides cannot drift. A handler whose type has no codec is a
compile error, and so is a `@[remote]` actor with no routable handler.

**Session protocols across nodes.** `SessionNode` is the `Session.Ops` transport for an
`@[endpoints]` protocol whose roles run on different nodes, over split peer connections
(`ClusterConn.connect_split` / `accept_split`). Two roles:

```march
let p = SessionNode.open(conn, "node-a", false, fn ep -> ())
let s = Session.attach(io, SessionNode.ops(p))
let _ = run_role(s, Stream_Prod.register(s, 0))
SessionNode.serve(p)
SessionNode.finish(p)
```

Three or more: start a party in your role, then add one connection per peer. The side
that ACCEPTS learns the peer's role from its hello (a listener does not know which role
connects next); the side that connects names it. Connect so that, for roles `i < j`, `i`
listens and `j` connects — then no configuration is needed and nothing deadlocks.

```march
let p0 = SessionNode.party(Relay_Msg.role_Server(), "node-b", fn ep -> ())
let p1 = SessionNode.accept_from(p0, conn_from_client)        -- role learned from its hello
let p  = SessionNode.connect_to(p1, Relay_Msg.role_Logger(), conn_to_logger)
```

`emit` picks the connection from the message's destination role, and `serve` reads every
peer at once. `SessionNode.require(p, Relay_Msg.peers_Server())` checks, before the session
starts, that the party has a connection to every role the projection says `Server`
exchanges messages with — the generated `peers_<Role>()` — and names the missing ones.
A wiring mistake fails at startup, not at the first message to an unreachable role. Messages from different peers race — each connection is FIFO, but two are
not ordered against each other — so a delivery that arrives before the continuation that
wants it is parked and replayed when that continuation is installed. The generated code
tells the transport which role each receive expects, so this needs nothing from you.

**The role runner.** `SessionNode.run` does all of the above from a role, its peer set and
a role→address table, in the one order that cannot deadlock (connect to every lower role,
ascending, then accept every higher one), and the generator emits its typed front,
`<P>_Run.run_<Role>(io, node_id, secret, addrs, body)`, where `body` takes the session
capability and the role's entry state — a body written for another role, or for another
point of this one, is a type error. A node is then its role's line and a match on the
result:

```march
fn main(c : Cap(IO)) do
  match Relay_Run.run_Server(c, "node-b", secret, Relay_Run.addrs_from_env(), fn (s, st) -> server(s, st)) do
    Ok(_) -> ()
    Err(SessionNode.Cancelled(role, _)) -> ...   -- this role was waiting on a role that failed
    Err(SessionNode.Protocol(role, why)) -> ...  -- a peer sent what the protocol cannot receive
    Err(e) -> panic(SessionNode.run_error_message(e))
  end
end
```

A message the generated code cannot decode, or one the current state does not receive, is
not a panic: the handler hands it to the transport (`Session.fail`), `SessionNode` ends the
session without a Bye, and `run` returns `Err(Protocol(role, why))` naming the sender. (A
same-thread transport panics there, as the handler itself used to.)

`Relay_Run.addrs_from_env()` reads `RELAY_<ROLE>_ADDR = host:port` for each role. Addresses
are a runtime value, but their shape is compile-time knowledge: a role needs its own entry
iff some peer is above it and an entry for every peer below it, and a missing one panics by
role at startup, before any socket opens. When a role fails it is cancelled, and a role
that was waiting on it with nothing from it still queued is cancelled in turn
(`Err(Cancelled(role, cause))`); a role that no longer needs it carries on and can finish.
A heartbeat catches a peer that stops without closing. A session is not resumable: what to
do next (`run` again, which is a fresh session) is the caller's decision. The rules, and the
`_or` receives that take a cancel handler, are in the choreography guide.

**A role hosted in an actor.** The same party can drive the event API instead of a body —
the session state in an actor's own state (`Parked_<Role>`), every step in a handler with
`state` in scope — through `<P>_Run.host_<Role>(io, node_id, secret, addrs, host, start,
deliver)`: `start` gets the session capability once the party is connected (send it to the
actor, whose start handler registers and parks), and `deliver` gets every delivery the
parked endpoint awaits, `(s, from, msg, ep)`, which is what its resume handler takes:

```march
let pc = spawn(ConsActor)
Stream_Run.host_Cons(c, "node-b", secret, Stream_Run.addrs_from_env(), pc,
  fn s -> send(pc, StartC(s)),
  fn (s, from, msg, ep) -> send(pc, DeliverC(s, from, msg, ep)))
```

Deliveries are one per suspension, in mailbox order; one that arrives before the actor has
re-parked is held for it. The host is monitored: its `Down` — a crash, a kill, a supervisor's
restart — cancels its role with `Err(HostGone(ep))`, and the peers are sent a Cancel;
`host_<Role>_or` also tells the actor itself. A restarted actor starts `Idle` and cannot continue a
session its predecessor parked; run again for a new one. (That is the event API's trade,
the same as in-process: the step can read the actor's state because the session state *is*
actor state, and actor state does not survive a restart.)

## Putting It Together

> **This is a layered API-reference skeleton, not a runnable program.** It shows how the pieces connect (identity, listen/connect, handshake, then a `RemoteCall`) but elides two things you must supply for real: (1) the actual byte transport over the socket `fd`, and (2) concrete `sig_hash` / `impl_hash` values, which the compiler bakes into your binary for the specific functions you enroll. The send/recv framing is `NetFrame`'s job (length-prefixed frames); see the *Wiring up the transport* note after the skeleton for how to close the loop.

A minimal two-node cluster:

**Node A (listener)**

```march
mod NodeA do
  fn main() do
    let my_id = NodeIdentity.make("a@127.0.0.1", "node-a-pubkey", 1)
    let secret = Crypto.random_hex(32)
    let reg    = PeerRegistry.empty()

    match ClusterConn.listen(9000) do
      Err(e) -> Env.exit(1)
      Ok(listen_fd) ->
        -- Accept one peer (in practice, loop in an actor)
        match ClusterConn.accept_one(reg, listen_fd, my_id, secret) do
          Ok(peer_id) -> run_rpc_loop(peer_id)
          Err(e)      -> Env.exit(1)
        end
    end
  end
end
```

**Node B (connector)**

```march
mod NodeB do
  fn main() do
    let my_id = NodeIdentity.make("b@127.0.0.1", "node-b-pubkey", 1)
    let secret = -- same secret as Node A

    match Socket.connect("127.0.0.1", 9000) do
      Err(e) -> Env.exit(1)
      Ok(fd) ->
        let nonce = NetKernel.fresh_nonce()
        match NetKernel.handshake(fd, my_id, secret, nonce) do
          Err(e)       -> Env.exit(1)
          Ok(peer_id)  ->
            -- Now call Math.add on Node A
            let fref = RemoteCall.remote_ref("Math", "add", sig_hash, impl_hash)
            let args = Msgpack.encode(
              Msgpack.array(Cons(Msgpack.int(2), Cons(Msgpack.int(3), Nil))))
            let reply_pid = GlobalPid.make(my_id.node_id, 1, 1)
            let req  = RemoteCall.request(fref, args, reply_pid, 5000, 1)
            -- send RemoteCall.encode_request(req) over fd, read reply ...
        end
    end
  end
end
```

### Wiring up the transport

To turn the skeleton into a running program, close the two gaps the note above flagged:

1. **Framing.** `RemoteCall.encode_request(req)` gives you a `List(Int)` of bytes. Wrap it in a length prefix with `NetFrame` and write it to the socket `fd`; on the other end, read a length-prefixed frame back and hand the bytes to `RemoteCall.decode_reply` (caller side) or `NodeRpc.handle_frame` (responder side). The accept/recv loop is the same shape as the `ClusterConn.listen` example in [Starting the listener](#starting-the-listener): receive a frame, dispatch, write the reply.
2. **Hashes.** `sig_hash` and `impl_hash` are produced by the compiler for the enrolled function (`Image.resize`, `Math.add`, …) and recorded in the binary; you reference the compiler-provided values rather than inventing them. A mismatch is caught *before* the remote body runs (`TypeMismatch` / `VersionSkew`), which is the whole point of the type-safe call path.

For a complete, executing example, see the cluster integration tests under the project's `test/` tree (search with `forge search` for `ClusterConn`, `NodeRpc`, and `GlobalRegistry`), which exercise the full accept → handshake → enroll → call → reply loop end to end.

---

## Conformance status

This stack splits into two conformance planes (widening slice 10; reference
in `core-march.md` §4.15, typing in `core-march-types.md` §2.12; the
distributed surface adds no new typing rules, it's ordinary ADTs).

**Single-process, mechanically tested.** The CRDT / lattice core (`CRDT`
with GCounter/PNCounter/LWWRegister/ORSet, `Membership`, `GlobalRegistry.merge`,
`VectorClock` causality, `Merkle`, `ConsistentHash`, `RingBuf`) plus the wire
codecs (`NetFrame`, `NodeIdentity`, `GlobalPid`, `Handshake`, `RemoteCall`,
`SwimDriver`) and `ClusterAuth`/`RemoteCall.verify` are pure functions over
data structures, evaluated identically on both backends. Golden
`g44_crdt_convergence` witnesses the GCounter/PNCounter/ORSet merge laws
(commutative, associative, idempotent) and `VectorClock.happens_before` on
causally-ordered clocks.

**Live-network layers stay prose-only.** The actual socket handshake
(`NetKernel.handshake`, `ClusterConn`), synchronous RPC transport
(`NodeCall.call`/`serve_loop`), SWIM gossip *dispatch* to peer fds, and
cross-node monitor firing require two real nodes and are exercised only by
the native TCP-loopback tests under `test/native/`, never by a
single-process golden. True multi-*process* failure semantics are exercised
by `scripts/two-node.sh` (two compiled binaries as two OS processes, a fault
script applied from outside, per-node sorted goldens under
`test/two_node/<scenario>/`): the `restart` scenario SIGKILLs a node holding
an actor, restarts it with a new creation at the same local pid, and pins
that a send to the held `GlobalPid` is refused as stale while a send to the
re-announced one is delivered; the `stream` scenario runs the Stream
session protocol's two endpoints on the two nodes over the `Session.Ops`
network transport, each node's trace its projection of the in-process
one; the `stall` scenario SIGSTOPs a node running SWIM and pins
Suspect → Dead on the observer and the incarnation refutation on resume;
the `skew` scenario runs one node 30 s ahead and pins that its load report is
aged on the receiver's clock (a received `NodeLoad`'s `sampled_at` is its
receipt time, so peer clocks need not agree for `SwimDriver.peer_load`'s
10 s staleness). `VectorClock` ordering takes no wall-clock input and is
unaffected by skew by construction; the `partition` scenario drops every
packet between two nodes running SWIM until each marks the other Dead, lets
each bind the same `GlobalRegistry` name in its own half, and pins that the
post-heal sync picks the same winner on both sides (a `REGISTRY_SYNC_RESP`
leaf carries the entry's `VectorClock`; the merge orders by it). `partition`
needs Linux and root for iptables; `scripts/two-node-docker.sh` runs it from
any host (`specs/progress/2026-09-14-two-node-failure-semantics-harness.md`).
Node certificates are covered by `cert_ok` (two certificate-mode nodes link, see
each other's certificates and carry actor messages over sealed connections),
`cert_wrong_operator`, `cert_expired` and `cert_revoked` (each refusal or drop
and its reason), and `frame_tampered` (a proxy flips one byte of one sealed data
frame; the receiver drops and counts that frame and keeps the link). All of
these run on one host over loopback; failure semantics across real
machines and networks aren't covered by an automated test, so treat them as
less battle-tested than the single-process core.

**A compiled memory-safety gap, FIXED (finding C1, `specs/todos/`, 2026-07-11).**
`VectorClock.compare` (and, transitively, `.concurrent`/`.happens_before` on
clocks with disjoint or partial actor-id sets) used to **crash when compiled**
(a use-after-free freeing a `String` map key, SIGSEGV) while running
correctly interpreted. The root cause was the read-then-update idiom
`Map.insert(m, k, f(Map.get_or(m, k, ...)), cmp)`, which both
`VectorClock.increment` and the `CRDT` counter updates use: a compiler
Perceus/borrow refcount bug (`lib/tir/llvm_case.ml`'s `strip_scrut_decrc`
only recognized a match arm's own scrutinee-dying dec_rc as the literal head
of the branch body, missing it, and silently skipping the shared-path field
refcount protection, whenever another cross-branch-dead variable's dec_rc
was emitted first), not a bug in this module's logic. Comparing vector
clocks built by different actors in compiled code is now safe; `g44`
includes the disjoint-key case unconditionally.

---

## See also

- [Actors]({{ site.baseurl }}/docs/actors/): `spawn` / `send` and the mailbox model the cluster layers on; `GlobalRegistry` is the distributed counterpart of registering a `Pid` under a name.
- [Supervision Trees]({{ site.baseurl }}/docs/supervision/): start from a supervised actor app on one node, then register its workers in the cluster as shown in [From one node to a cluster](#from-one-node-to-a-cluster).
- [Session Types]({{ site.baseurl }}/docs/session-types/): typed two-party protocols, the in-process analogue of a type-safe `RemoteCall`.
