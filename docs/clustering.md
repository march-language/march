---
layout: docs
title: Clustering & RPC
nav_order: 10.5
permalink: /docs/clustering/
---

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

> `GlobalRegistry.lookup` returns `Option((String, Int))`: the holder's `node_id` and its **local** `pid` on that node. You address remote calls with a `GlobalPid` (node + local pid + creation counter), which is what persists across a restart unambiguously.

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

Before any cluster traffic flows, nodes exchange a challenge-response handshake using a shared secret.

### Generating a secret

```march
let secret = Crypto.random_hex(32)   -- random hex String shared by all nodes
```

The secret is just a `String`; `ClusterAuth.prove(secret, nonce)` signs a challenge with `HMAC-SHA256(secret, nonce)` and the secret itself never goes on the wire. All nodes in a cluster must share the same secret (distribute it via environment variable or a secrets manager).

### Performing the handshake

`Handshake` is a pure state machine; call it once per new connection:

```march
-- Initiator side
let nonce  = NetKernel.fresh_nonce()
let result = NetKernel.handshake(fd, my_id, secret, nonce)

match result do
  Ok(peer_id) -> -- connection authenticated; peer_id is their NodeIdentity
  Err(e)      -> -- reject and close fd
end
```

`ClusterConn.accept_one` wraps the accept → handshake → enroll flow for the listening side:

```march
match ClusterConn.accept_one(registry, listen_fd, my_id, secret) do
  Ok(peer_id) -> -- new peer enrolled
  Err(e)      -> -- handshake failed
end
```

### Starting the listener

```march
match ClusterConn.listen(9000) do
  Ok(listen_fd) ->
    -- accept loop
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

## Membership & Failure Detection

### Membership CRDT

`Membership` maintains the set of known cluster members as a last-write-wins CRDT. Each member stores a `MemberStatus` (`Alive`, `Suspect`, or `Dead`) and an `incarnation` counter for causal ordering. You build a `Member` value with `alive`/`suspect`/`dead`, then fold it into the view with `observe`.

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

## Maturity of this stack

The distributed layer splits into two tiers of confidence:

**Single-process logic, well-tested.** The CRDT / lattice core (`CRDT`, `Membership`,
`GlobalRegistry.merge`, `VectorClock` causality, `Merkle`, `ConsistentHash`, `RingBuf`)
plus the wire codecs (`NetFrame`, `NodeIdentity`, `GlobalPid`, `Handshake`, `RemoteCall`,
`SwimDriver`) and `ClusterAuth`/`RemoteCall.verify` are pure functions over data
structures, evaluated identically on both backends, and exercised by an automated
conformance suite covering the CRDT merge laws (commutative, associative, idempotent) and
`VectorClock` causal ordering.

**Live-network layers are exercised, but less exhaustively.** The actual socket
handshake, synchronous RPC transport, SWIM gossip dispatch to peer file descriptors, and
cross-node monitor firing require two real nodes and are covered by native multi-process
integration tests rather than the same conformance corpus as the pure logic above. True
multi-*machine* failure semantics (netsplit, node restart/incarnation, clock skew across
hosts) aren't yet covered by an automated test at all; treat them as less battle-tested
than the single-process core.

---

## See also

- [Actors]({{ site.baseurl }}/docs/actors/): `spawn` / `send` and the mailbox model the cluster layers on; `GlobalRegistry` is the distributed counterpart of registering a `Pid` under a name.
- [Supervision Trees]({{ site.baseurl }}/docs/supervision/): start from a supervised actor app on one node, then register its workers in the cluster as shown in [From one node to a cluster](#from-one-node-to-a-cluster).
- [Session Types]({{ site.baseurl }}/docs/session-types/): typed two-party protocols, the in-process analogue of a type-safe `RemoteCall`.
