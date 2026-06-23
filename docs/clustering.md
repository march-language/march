---
layout: docs
title: Clustering & RPC
nav_order: 10.5
permalink: /docs/clustering/
---

# Clustering & RPC

March's distributed layer lets multiple nodes form a cluster, discover each other, detect failures, and call functions across node boundaries with type-safety guarantees. The full stack is built from composable pure modules layered on top of the actor runtime.

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
let id = NodeIdentity.make("alice@192.168.1.10", 9000, "v1.2.0")
-- { node_id: "alice@192.168.1.10", port: 9000, version: "v1.2.0" }
```

`node_id` is a `host@address` string that must be unique across the cluster. It is the primary key used in every distributed data structure.

### Serialisation

Node identities are serialised to MessagePack for transport:

```march
let bytes = NodeIdentity.to_bytes(id)   -- List(Int)
match NodeIdentity.of_bytes(bytes) do
  Ok(id2) -> id2
  Err(e)  -> ...
end
```

---

## Authentication & Handshake

Before any cluster traffic flows, nodes exchange a challenge-response handshake using a shared secret.

### Generating a secret

```march
let secret = ClusterAuth.gen_secret()   -- 32-byte random key (List(Int))
```

All nodes in a cluster must share the same secret (distribute it via environment variable or a secrets manager).

### Performing the handshake

`Handshake` is a pure state machine — call it once per new connection:

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
    Nil
  Err(e) -> ...
end
```

---

## Membership & Failure Detection

### Membership CRDT

`Membership` maintains the set of known cluster members as a last-write-wins CRDT. Each member carries a `MemberStatus` (`Alive`, `Suspect`, or `Dead`) and a vector clock for causal ordering.

```march
let members = Membership.empty()
let members = Membership.join(members, "alice@192.168.1.10", 9000, now_ms)
let members = Membership.leave(members, "bob@192.168.1.11", now_ms)

-- Merge two views (safe to call repeatedly — idempotent)
let merged = Membership.merge(local_view, remote_view)

-- Query
let alive = Membership.alive_nodes(members)   -- List(String)
let status = Membership.status_of(members, "alice@192.168.1.10")
```

### SWIM failure detection

`Swim` implements the SWIM gossip protocol as a pure state machine. It produces `Action` values that tell the runtime what to send — no sockets inside.

```march
let cfg   = { ack_timeout_ms: 200, suspect_timeout_ms: 2000, indirect_k: 3 }
let state = Swim.make("alice@192.168.1.10", members, cfg)

-- Tick: begin a probe period
let (state, actions) = Swim.begin_period(state, now_ms, random_index)
-- actions may contain SendPing / SendPingReq

-- Process an incoming ack
let state = Swim.on_ack(state, "bob@192.168.1.11", now_ms)

-- Check for overdue probes
let (state, actions) = Swim.ack_overdue(state, now_ms)

-- Advance suspect timeouts
let (state, dead_nodes) = Swim.expire_suspects(state, now_ms)
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

-- Look up a name
match GlobalRegistry.lookup(reg, "worker-1") do
  Some(entry) -> entry.pid      -- Int (local pid on entry.node_id)
  None        -> ...
end

-- Remove a name (tombstone — converges with concurrent registrations)
let reg = GlobalRegistry.unregister(reg, "worker-1", "alice@192.168.1.10", my_clock)

-- Merge two registry views (idempotent)
let reg = GlobalRegistry.merge(local_reg, remote_reg)

-- Enumerate
let names = GlobalRegistry.names(reg)   -- List(String)
let n     = GlobalRegistry.size(reg)
```

Merge is idempotent: applying the same remote view twice produces the same result. This makes gossip-based propagation safe — broadcast to all peers and let them forward.

---

## Remote Calls

### GlobalPid — cluster-wide process identifiers

A `GlobalPid` uniquely identifies a process across the cluster:

```march
let pid = GlobalPid.make("alice@192.168.1.10", 42, 1)
-- { node_id: "alice@192.168.1.10", local_pid: 42, creation: 1 }

-- Serialise / deserialise (for inclusion in RPC messages)
let v    = GlobalPid.to_value(pid)
let pid2 = GlobalPid.of_value(v)   -- Result(GlobalPid.Pid, String)
```

The `creation` counter lets the runtime distinguish a new process at the same local pid from a restarted one.

### RemoteRef — type-safe function references

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
| `TypeMismatch` | `sig_hash` did not match — type API changed |
| `VersionSkew` | `sig_hash` matched but `impl_hash` did not — different body version |
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

A minimal two-node cluster:

**Node A (listener)**

```march
mod NodeA do
  fn main() do
    let my_id = NodeIdentity.make("a@127.0.0.1", 9000, "1.0")
    let secret = ClusterAuth.gen_secret()
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
    let my_id = NodeIdentity.make("b@127.0.0.1", 9001, "1.0")
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

---

## Status

The distributed layer is **pure-module complete**: all protocols compile and are tested end-to-end in the evaluator (44 distributed tests). The remaining pieces needed for a production cluster are:

- **Runtime driver**: an actor that ticks the SWIM state machine and drives the CRDT gossip loop
- **Compiler stubs**: automatic generation of the `invoke` stub and `sig_hash`/`impl_hash` values at compile time
- **Net-kernel wiring**: routing `handle_frame` calls to the live socket layer

These are tracked in `specs/todos.md` under the P2–P3 distributed roadmap items.
