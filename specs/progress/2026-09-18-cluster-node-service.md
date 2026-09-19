# DONE 2026-09-18 — Cluster node service (the design; all four phases shipped)

**Shipped 2026-09-18**, one progress record per phase:
[[2026-09-18-cluster-node-service-phase-0]] (the data model),
[[2026-09-18-cluster-node-service-phase-1]] (a running node: joining, SWIM,
failure notifications), [[2026-09-18-cluster-node-service-phase-2]] (the
registry), [[2026-09-18-cluster-node-service-phase-3]] (the shared data plane),
[[2026-09-18-cluster-node-service-phase-4]] (sessions over the node). Three
compiler bugs were found and fixed on the way:
[[2026-09-18-perceus-three-deep-field-projection]],
[[2026-09-18-trmc-reuse-hole-shared-scrutinee]], and the stdlib-diagnostic trap
recorded in phase 3. What is left, including the open questions below, is
[[2026-09-18-cluster-node-service-follow-ups]]. Deviations from the design as
written here are recorded in the phase files (notably: no `peer()`; `monitor`
is `monitor_remote`; the C monitor registry needed no runtime change, since
watchers register with fd -1 and fires are resent through the control writer;
cluster session frames use `DropNew`, not `BlockSender`).

The design as filed follows.

---

# `[P1]` Cluster node service: one running node that joins, detects failure, and names things

Filed 2026-09-18. A design spec, not an implementation. It is the prerequisite for phase 4 of
[[2026-09-18-choreography-failure-handling]], which is filed as
[[2026-09-18-choreography-access-points]]: an access point is found **by name**, and the name
lives in `GlobalRegistry`. That was decided before this spec and is not reopened here. Nothing
in the stdlib assembles the parts below into a node that stays up, so this spec designs that node.

## Why

Choreography phase 4 needs four things the stdlib cannot yet provide:

1. **Discovery by name.** A node hosting a role registers an access point under a name. Any
   node resolves that name to a `GlobalPid` and from there to an address it can dial.
2. **One connection per peer, shared.** Sessions will multiplex over the node's persistent
   peer connections, each frame carrying a session id. Today `SessionNode.run` opens two new
   connections per role pair per session.
3. **A cluster failure detector.** In cluster mode SWIM replaces the per-connection heartbeat
   of phase 3: when SWIM declares a node dead, all of that node's roles in every session are
   cancelled.
4. **A binding that can be lost.** The registry is eventually consistent. After a partition
   heals, two nodes may both think they hold an access point's name. One binding wins
   everywhere, and the losing node has to find out.

The standalone runner stays unchanged as the no-cluster mode: `SessionNode.run` with
`<P>_<ROLE>_ADDR` addresses and the per-connection heartbeat.

## Survey: what exists (verified 2026-09-18 against `origin/main` at b4252d39b)

Each module is a correct piece. None of them runs continuously, and no two of them share a
connection except in hand-written test programs.

| Module | What it is | Gap for a running node |
|---|---|---|
| `global_registry.march` | Pure CRDT. `Names = Map(name, Entry)`, `Entry = {node_id, pid, clock : VectorClock, present}`. `observe` keeps the winner per name: causally After wins, Concurrent falls to `tiebreak` (higher `node_id`, then higher `pid`). Tombstones via `present = false`. `root_hash` (Merkle over sorted entries), `diff_entries`, `all_entries`. | `Entry` has **no creation**, so a binding from before a restart points at whatever process now has that local pid. `entry_to_bytes` hashes name, node, pid and present, **not the clock**. Two replicas that differ only in clocks compare equal and never exchange them. `unregister` tombstones whatever binding is present, including somebody else's. The caller supplies the clock, and nothing says which clock that should be. |
| `vector_clock.march` | `increment` / `merge` / `compare` / `advance`. | None. |
| `membership.march` | `Member = {node_id, status, incarnation}`. Merge is the lexicographic max over (incarnation, severity). | **No address, name or creation.** A `node_id` cannot be turned into host:port. A restarted node is the same member as its dead predecessor. |
| `swim.march` | Pure probe loop: `begin_period`, `on_ack`, `escalate_indirect`, `end_period`, `expire_suspects`, `on_gossip`, `refute`. Emits `SendPing` / `SendPingReq` / `Gossip`. | Probes only Alive members (via `SwimDriver.alive_others`), so nothing ever contacts a Dead member again. A two-node cluster that closes its connection on Dead never heals. |
| `swim_driver.march` | Owns the RNG and period timer. `step(state, now, events)`. Wire tags 0–3 (tag 3 is overloaded by element count for load gossip). `dispatch` writes straight to `peer.fd`. Has an anti-entropy timer (`anti_entropy_peers`, 30 s). | **`PeerDown` goes straight to Dead** and gossips it, so a reset connection evicts a healthy node cluster-wide. Nothing handles `SwimPingReq` (the fixtures drop it). `dispatch` writes to the fd directly, bypassing any writer. |
| `net_kernel.march` | Framing (`send_frame`, `recv_frame`, `recv_frame_exact`), the symmetric handshake (`handshake_role`), codecs for REGISTRY_SYNC_REQ/RESP (5/6, leaves carry the clock since the partition fix) and MONITOR_REQ/FIRE (7/8). | The handshake reads have **no deadline**. A peer that is SIGSTOPped still gets its SYN-ACK from the kernel's listen backlog, so the dialer then waits forever for the peer's hello. |
| `handshake.march`, `node_identity.march` | `Hello = {identity, nonce, role}`, extended by element count (the `role` field was added that way). `Identity = {name, node_id = sha256(pubkey), incarnation}`, where `incarnation` counts restarts, i.e. it is the **creation**. | No advertised listen address. |
| `cluster_conn.march` | `connect_split` / `accept_split`: two authenticated connections per peer, control then data. | One-shot. `accept_split` assumes the next two accepts are one peer's control and data, in that order. With several peers dialling at once, that assumption fails. |
| `peer_registry.march` | `node_id -> Peer {fd = control, data_fd}`. `add` replaces, so the newer connection wins. | Two nodes that dial each other at the same moment each keep a different connection. |
| `peer_reader.march` | One reader per connection, dispatch by tag through an injected `on_frame`. Tag table: 0–3 SWIM, 5–6 registry, 7–8 monitor, 9–10 ACTOR_MSG / DELIVERY_FAILED. | Does not list 11 (CREDIT, `node_queue.march`) or 12 (MONITOR_ACK, `dist_link.march`). RPC frames are untagged and keep their own connection. |
| `node_queue.march` | Per-peer `Writer` actor: credit flow control over the data connection, byte budget, `DropNew` / `DropOld` / `BlockSender`. | None; it is the right writer. |
| `node_send.march`, `node.march` | ACTOR_MSG `[9, seq, to_local_pid, to_creation, type_tag, payload]`, DELIVERY_FAILED, a stale-creation refusal. `Node.send(peer, …)` takes a `PeerRegistry.Peer`. | The caller must already hold a `Peer`. |
| `dist_link.march`, `runtime/march_monitor_registry.c` | Cross-node monitors. **The C runtime writes MONITOR_FIRE directly to the fd the watcher registered** (`write_nosigpipe`). | That makes it a second writer on the control socket. Phase 3 of the failure-handling work showed that two writers on one socket interleave frames. |
| `cluster.march` | Parses `MARCH_CLUSTER_NODES=host:port,…`. | Nothing else. |
| `session_node.march` | Transport for `Session.Ops`. One `Endpoint` actor per party. Readers are tasks that `send` to the endpoint in stream order. Heartbeat per data connection. Frames are ACTOR_MSG addressed to the peer's endpoint `GlobalPid`, with `type_tag` `SessionNode.{Deliver,Bye,Cancel,Ping}`. The node identity is `NodeIdentity.make(name, "pk-" ++ name, 1)`. | Opens its own connections per session. The connect rule is "role i < j: i listens, j connects". |

The two-node scenarios that combine these parts wire everything by hand over **one raw
socket, without the handshake**:

- `stall`, `skew` and `partition` each carry a copy of the same 50 ms read-step-perform loop.
- They use plain names ("node-a") as SWIM ids.
- `partition` keeps the TCP connection open across the partition. That is the only reason it
  heals: `drop_link` drops packets, the Dead gossip is buffered, and after `heal` the gossip
  arrives and the peer refutes it.

A service that closes the connection on Dead, which it must do (see "Connections" below),
needs a different way to heal. The `partition` port in phase 2 is designed to exercise that.

`scripts/two-node.sh` supplies what the witnesses need: three nodes (`MARCH_PORT_A/B/C`),
`start_node <x> [creation]` for restarts, `kill_node`, `stop_node` / `cont_node`, and
`drop_link` / `heal`. `drop_link` and `heal` need Linux iptables; on macOS they run through
`scripts/two-node-docker.sh`.

## Design

### Shape: a pure core plus a thin actor

The repo already splits pure logic from I/O (`Swim` / `SwimDriver`, `Handshake` /
`NetKernel`), and the node follows the same split:

- **`ClusterNode.Core`**, pure: `step(core, event) -> (core, List(Effect))`. It holds the
  SWIM driver state, the extended member view, connection states, the registry replica,
  local registrations, watches and subscribers. It is unit-testable under the eval harness,
  which cannot run sockets, and every rule in this spec is a case in its tests.
- **`ClusterNode`**, the I/O layer. It consists of one actor and a few tasks:

| Runs as | Does |
|---|---|
| `Node` actor (one per process) | Owns `Core`. Every event goes through its mailbox and every effect is performed in its turn, so the node's state has one writer and needs no locks. |
| Acceptor task | Blocking `tcp_accept` loop. Runs the handshake with a deadline, then sends `Accepted(conn)` to the actor. It takes roles from the hello, never from accept order (fixes the `accept_split` assumption). |
| Dialer task (one per attempt) | `Socket.connect_timeout` + handshake, then `Dialed(result)`. |
| Reader task (one per connection) | `PeerReader.serve`. Control-plane frames go to the actor. Data frames go straight to their route (see "Frame routing"), so the actor is never on the data path. On end of stream it sends `ConnClosed(node_id, gen)`. |
| Ticker task | `sleep_ms(tick)`, then `Tick(unix_time_ms())`. `tick` is 100 ms by default. The SWIM period, anti-entropy timer and redial backoff all run off it. |
| Writers (per peer) | Data: the existing `NodeQueue.Writer`. Control: a `ControlWriter` actor with no credit (control frames are small and must not wait for data credit). **Every write to a socket goes through its writer.** That includes SWIM dispatch, which today writes the fd directly, and MONITOR_FIRE (see phase 3). |

Readers for the registry need no round trip. The actor mirrors the effective bindings into a
`Vault` (`"cluster_names"`), so `lookup` is a Vault read: concurrent and needing no
capability, the same arrangement as `Actor.whereis`. All writes go through the actor.

### Configuration and start

```march
type Config = { name : String, listen_port : Int, advertise : String,     -- "host:port" peers dial
                seeds : List(Cluster.NodeAddr), secret : String, creation : Int,
                swim : Swim.Config, period_ms : Int, tick_ms : Int,
                redial_min_ms : Int, redial_max_ms : Int, handshake_timeout_ms : Int }

ClusterNode.config_from_env() : Result(Config, String)
ClusterNode.start(io : Cap(IO), cfg : Config) : Result(Node, String)   -- Node is the handle
ClusterNode.stop(node : Node) : ()
```

`config_from_env` reads these variables:

| Variable | Meaning |
|---|---|
| `MARCH_NODE_NAME` | Node name. |
| `MARCH_NODE_PORT` | Listen port; already set for node-b by the harness. |
| `MARCH_NODE_ADVERTISE` | Advertised address. Default `127.0.0.1:<port>`. Mandatory in practice for any multi-host setup, so the docs must say so. |
| `MARCH_CLUSTER_NODES` | Seed addresses, parsed by the existing `Cluster.from_env`. |
| `MARCH_CLUSTER_SECRET` | Cluster secret. |
| `MARCH_NODE_CREATION` | Creation; already set by the harness. Default: `unix_time_ms()` at start, which is monotone across restarts on one host without needing persistent state. |

The node's `node_id` is `NodeIdentity.derive_id` of its public key. Today every caller passes
`"pk-" ++ name`, and that stays until real keys exist. It is filed as an open question, not
designed here.

**Capabilities.** `ClusterNode` declares `needs IO.NetListen`, `IO.NetConnect`, `IO.Spawn`,
`IO.Mut`, `IO.Clock` (SWIM's timers) and `IO.Random` (the driver's seed). `start` takes
`Cap(IO)`, as `SessionNode.run` does, so a program that starts a node must hold those
capabilities under its cap ceiling. The returned `Node` handle is itself the authority to
act as the node: only code given the handle can `register`, `unregister`, `watch` or
`subscribe`. `lookup` needs neither the handle's net capabilities nor a Vault capability.
Library code such as `SessionNode` takes a `Node` argument and declares no new `needs`.

### Membership: addresses and creation

`Member` gains three fields: `{node_id, name, addr, creation, status, incarnation}`.

- **The merge order becomes (creation, incarnation, severity), lexicographic.** It is still a
  max, so still a join. A node that restarts outranks every verdict about its previous life,
  whatever that verdict's incarnation. `addr` and `name` travel with the winning observation.
  An address can only change with a new creation, since a node that moves has restarted.
- **SWIM ids stay `node_id`s.** Events and logs report `name` alongside.
- **Wire:**
  - New tag **13 MEMBER_GOSSIP** `[13, node_id, name, addr, creation, status, incarnation, load?]`
    replaces tag 3 between service nodes. Tag 3 is already overloaded by element count, and
    one more overload would make the fixtures that decode it guess.
  - New tag **14 MEMBERS_SYNC** carries the whole view (a list of tag-13 bodies). It is
    exchanged in both directions on every new connection: SWIM's push-pull join, and the
    heal path.
  - Tags 0–2 (ping, ack, ping-req) are unchanged.
- **Hello** gains a sixth element, the advertised address. It extends by element count the
  way `role` did, so a hello without it decodes as before. The acceptor then learns the
  dialer's address at handshake time, before any gossip arrives.

`node_id -> address` is `Membership.get(view, id).addr`. The node exposes it as
`ClusterNode.addr_of(node, node_id) : Option(String)` and, more usefully,
`ClusterNode.peer(node, node_id) : Option(PeerRegistry.Peer)`, which is what `Node.send`
already takes.

### Joining and staying joined

- **Start:** listen, add self as `Alive(creation, incarnation = 1)`, and dial every seed. A
  seed that is also this node's own advertised address is skipped. After a successful
  handshake both sides exchange MEMBERS_SYNC. The node then dials every Alive member it
  learned about that it has no connection to. This gives a **full mesh**; see the limits
  below.
- **No seed reachable is not a failure.** The node runs as a cluster of one and keeps
  redialling seeds with backoff (`redial_min_ms` 200 ms doubling to `redial_max_ms` 5 s).
  `start` returns without waiting for a seed. A program that needs a peer before it
  proceeds uses `subscribe` or `await_members(node, n, timeout_ms)`.
- **SWIM runs continuously.** On each `Tick`, `SwimDriver.step` is called, and its actions
  go to the per-peer control writers. `SwimPingReq` gets a handler: the helper pings the
  target on its own connection and relays the ack. Every fixture drops this frame today.
- **Registry anti-entropy** runs on the driver's existing 30 s timer, and also immediately
  on every new connection.

### Connections

- **One control and one data connection per peer, reused by everything**: SWIM, registry,
  monitors, credit, DELIVERY_FAILED and every session. The data connection's writer is the
  peer's single `NodeQueue`.
- **Duplicate rule.** If two nodes dial each other at the same time, each side ends up with
  two connection pairs. Both sides keep the pair **dialled by the lower `node_id`** and close
  the other once its handshake completes. The rule is deterministic and symmetric, so no
  message is needed to agree on it. `PeerRegistry.add`'s "newer wins" is right only after
  this filter.
- **Generations.** Each connection gets a generation number, and `ConnClosed(node_id, gen)`
  for a generation that is no longer current is ignored. Without this, the close of a
  replaced connection would take down its successor.
- **A closed connection is a hint, not a verdict.** This changes `PeerDown`:
  - On `ConnClosed`, the member becomes **Suspect** (not Dead) and the node redials at once.
  - `ECONNREFUSED` on the redial means nothing is listening at that address, which is
    definite for a crashed process. The member goes straight to **Dead** and the verdict is
    gossiped. This keeps crash detection as fast as the per-connection readers are today:
    the failure-handling work measured a parked reader waking 201 ms after SIGKILL.
  - A redial that succeeds with the **same creation** puts the member back to Alive
    locally. A redial that finds a **new creation** marks the old creation Dead and the new
    one Alive (a rejoin).
  - A connect or handshake timeout is not a verdict. SWIM's own suspect timer decides.
- **When SWIM declares a node Dead, the node shuts down both of its connections**, the way
  the session heartbeat does. This does three things:
  - Frames still queued for it are dropped. The `NodeQueue` writer's `dead` path reports
    them, which is consistent with Cancel semantics.
  - Every reader ends, which is how sessions hear about the death in the correct order (see
    "Failure notifications").
  - The other side, if it is alive and partitioned, sees the close when the partition heals.
- **Healing.** SWIM never probes a Dead member, so the service does it. Every Dead member
  whose `addr` is known is redialled on the backoff schedule, and each seed is redialled
  while the node has no peers. When a redial succeeds, MEMBERS_SYNC tells each side what
  the other believed. A node that finds itself Suspect or Dead in the other's view refutes
  (`Swim.refute`) with a higher incarnation, and both sides mark each other Alive. A
  *Rejoined* event is fired and registry anti-entropy runs.

  Behind an iptables DROP, a redial's SYN is never answered. That is why
  **`Socket.connect_timeout` is a prerequisite** (a runtime non-blocking connect plus poll;
  `Socket.connect` has no timeout today). Handshake reads also get a deadline
  (`handshake_timeout_ms`, default 2 s). Without that, a SIGSTOPped peer, whose kernel still
  completes the TCP connect, keeps a dialer waiting forever.
- **Limits.** The design is a full mesh with SWIM on top: n·(n−1) connection pairs.
  Membership is small and every node talks to every other. That covers the target (tens of
  nodes). A partial view (HyParView-style) is out of scope. With a full mesh SWIM is partly
  redundant, but it is kept because it is what decides Dead *without* a connection closing:
  a stall or a partition.

### Frame routing, and room for multiplexed sessions

A connection has one reader, and the reader dispatches by tag. This table replaces the one
in `peer_reader.march`'s header:

| Tag | Frame | Connection | Goes to |
|---|---|---|---|
| 0, 1, 2 | SWIM ping / ack / ping-req | control | node actor |
| 3 | legacy SWIM gossip | control | node actor (decoded, for interop with the fixtures) |
| 5, 6 | REGISTRY_SYNC_REQ / RESP | control | node actor |
| 7, 8, 12 | MONITOR_REQ / FIRE / ACK | control | `DistLink` (phase 3) |
| 9 | ACTOR_MSG | data | **route table**, from the reader task |
| 10 | DELIVERY_FAILED | control | `NodeSend.on_failure` |
| 11 | CREDIT | control | that peer's `NodeQueue` writer |
| 13, 14 | MEMBER_GOSSIP / MEMBERS_SYNC | control | node actor |

**ACTOR_MSG routing.** An ACTOR_MSG already carries `to_local_pid` and `to_creation`. The
node keeps a route table in a `Vault`, from a local pid to a delivery closure:

```march
ClusterNode.route(node, pid_int : Int, deliver : NodeSend.Delivery -> Result((), String)) : RouteRef
ClusterNode.unroute(node, r : RouteRef) : ()
ClusterNode.route_type(node, type_tag : String, deliver) : RouteRef   -- fallback by type, for Node.send's typed receivers
```

- The reader task looks the destination up and calls the closure in its own turn. The
  closure normally does a single `send` to a local actor. The data path never passes
  through the node actor.
- A stale creation, or a message with no route, is answered with DELIVERY_FAILED, the rules
  `NodeSend.handle_frame` already has.
- Consumption is announced by CREDIT as today.
- Closures are the only option: a library cannot name another actor's message constructors.
  `SessionNode.run_hosted` stores its forwarders in Vaults the same way.

**This is what makes session multiplexing possible, and the session id rides on top of it.**

- In cluster mode a session's frames go to the peer's per-session `Endpoint` pid. That is
  what `SessionNode` already addresses (`l.peer` from the session hello). So one connection
  carries any number of sessions, each routed by destination pid.
- The **session id** goes in the `SessionNode.*` payloads, as the access-points item
  requires. The endpoint drops a frame whose id is not its own session's. That covers pid
  reuse within one creation and a node rejoining an old session.
- The session id does not choose the route. The route is the destination pid, which the
  wire already carries.
- In cluster mode, `Bye` or `Cancel` ends a *session* and never closes the connection. The
  connection ends only when the node is Dead or when `stop` is called.

Fairness between sessions on one peer's queue is not designed here. `NodeQueue` is FIFO
across all of a peer's traffic, and "consumed" means "in the mailbox", so a slow endpoint
actor does not hold back another session's frames. It is recorded as a watch item.

### Registry replica and API

```march
type RegisterError = Taken(GlobalPid.Pid) | NotLocal | Stopped
type NameEvent = Bound(String, GlobalPid.Pid) | Unbound(String) | Lost(String, GlobalPid.Pid)

ClusterNode.register(node, name : String, pid) : Result((), RegisterError)
ClusterNode.unregister(node, name : String) : Result((), String)
ClusterNode.lookup(name : String) : Option(GlobalPid.Pid)          -- Vault read, no handle needed
ClusterNode.watch(node, name : String, on_event : NameEvent -> Unit) : WatchRef
ClusterNode.unwatch(node, w : WatchRef) : ()
```

**`Entry` gains `creation`.**

- `lookup` returns a full `GlobalPid`.
- A binding whose `(node_id, creation)` belongs to a node that has since restarted is stale.
  Every replica hides it, and **the owner tombstones it** when it learns of it through sync.
  The owner may do this because it is the only node that writes bindings for its own
  `node_id`.
- REGISTRY_SYNC_RESP leaves gain a sixth element (by element count again). A leaf without
  it reads as creation 0, which is always stale for a service node.
- `root_hash` includes the clock and the creation, so replicas that differ only in those
  exchange them.

**Clocks, per name.**

- `register` computes `clock = increment(existing_entry.clock or new(), my_node_id)`. A
  registration made after seeing another binding is therefore causally **After** that
  binding and wins over it. It never falls to the tiebreak.
- `unregister` works the same way from the local entry's clock.
- The fixtures use one node-wide clock that never absorbs remote observations. With that
  clock a deliberate takeover would be Concurrent and could lose to the tiebreak.

**Preconditions.**

- `register` fails with `Taken(holder)` if the local replica shows a *visible* binding held
  by another pid. It fails with `NotLocal` if `pid` is not on this node.
- A binding whose holder node is Dead, or whose creation is stale, is not visible, so it
  can be taken over. That is exactly the case after a partition or a crash.
- `unregister` acts only if the current winner is this node's own binding. This is a
  compare-and-delete. `GlobalRegistry.unregister` itself tombstones whatever binding is
  present and must not be called on another node's binding.

  **A stale unregister cannot erase the winner.** Suppose a node's replica still shows its
  own binding and it unregisters. The tombstone carries its own `(node_id, pid)` and a clock
  concurrent with the winner's, so the tiebreak that picked the winner picks it again. This
  is a property worth a unit test.

**Visibility filter.** The CRDT winner for a name is the same on every replica once they have
exchanged state. `lookup`, and the Vault mirror, additionally hide a winner whose holder node
is Dead in the local view or whose creation is stale. The binding is hidden, not
tombstoned, so it reappears if the holder rejoins with the same creation.

- Choreography wants this: a name whose holder is unreachable resolves to nothing, rather
  than to a pid that no message will reach.
- It also makes takeover automatic. A node that sees a name hidden may claim it.

**Local holder death.** The node actor monitors every pid registered through it. On `Down`
it unregisters that pid's names. This mirrors `Actor.register`, whose names are retired on
death before any `Down` fires.

**Dissemination.** A change made locally is pushed at once to every connected peer as a
REGISTRY_SYNC_RESP carrying only the changed leaves. `diff_entries` merges any leaf set, so
no new frame is needed. Anti-entropy (REQ with the root hash, answered with every leaf if
the hashes differ) repairs whatever the push missed. Over a full mesh on TCP, the push
reaches every live peer directly, so piggybacking on SWIM gossip is unnecessary.

**Watch.** `on_event` runs in the node actor's turn and must only `send`, the same contract
as `run_hosted`'s forwarders. It fires on every change to the *visible* binding of `name` on
this replica:

- `Bound(name, pid)` when the name gains a new visible holder.
- `Unbound(name)` when it loses one (unregistered, holder dead, or stale).
- `Lost(name, winner)` instead of `Bound` when the binding it replaces was registered **from
  this node** and was not unregistered here.

A watcher added while the name is bound gets `Bound` at once, so it cannot miss the current
state.

### Partition and heal: what happens to a name held on both sides

1. **Before the partition**, A holds `ap` with clock `{A:1}`.
2. **During the partition**, B's view marks A Dead, which hides A's binding. B registers
   `ap` with clock `{A:1, B:1}`, and B's watchers see `Bound(ap, B.pid)`. A still sees its
   own binding, and A's view marks B Dead.
3. **On heal**, a redial succeeds, MEMBERS_SYNC refutes both Dead verdicts, and
   anti-entropy exchanges registries. B's entry is causally After A's, so **B wins
   everywhere**. If A also re-registered during the partition, the two claims are
   Concurrent and the tiebreak (higher `node_id`, then pid) picks the same winner on every
   replica. The `partition` scenario already pins that law over the wire.
4. **On A**, the watch sees its own binding replaced and fires `Lost(ap, B.pid)`.

**What the loser must do.** It must stop behaving as the holder:

- An access point stops forming new sessions under the name. Sessions already formed carry
  on: they were formed with specific peers under a fresh session id, and Maty's model does
  not require them to know which node held the name.
- It must **not** unregister. The name is not its own any more, and the compare-and-delete
  would refuse anyway.
- If it still wants the name, it waits for `Unbound` and registers again. It gets no
  priority.

Nothing makes a binding exclusive during a partition. **A global name is AP, not a lock.**
That is sufficient for access points (a duplicate access point costs one extra session, which
is affine and so safe to cancel). It is not sufficient for anything that needs mutual
exclusion. The docs must say so plainly, and must not describe `GlobalRegistry` as leader
election.

### Failure notifications

```march
type NodeInfo = { node_id : String, name : String, addr : String, creation : Int, incarnation : Int }
type NodeEvent = NodeUp(NodeInfo) | NodeSuspect(NodeInfo) | NodeDead(NodeInfo, String) | NodeRejoined(NodeInfo)

ClusterNode.subscribe(node, on_event : NodeEvent -> Unit) : SubRef
ClusterNode.unsubscribe(node, s : SubRef) : ()
ClusterNode.members(node) : List(NodeInfo)
```

- Events are derived in `Core` by comparing the member view before and after each step, so
  gossip, a timer and a refused connection all produce them the same way.
- `NodeRejoined` fires when a member goes from Dead to Alive with the same creation, or when
  a new creation replaces a Dead one. `NodeDead`'s string is the cause: "suspect timeout",
  "connection refused", "gossip from <name>", or "superseded by creation N".
- A subscriber added late receives `NodeUp` for every current Alive member.

**How `SessionNode` hears about a death (the ordering rule).**
[[2026-09-18-choreography-failure-handling]] names one way that design can fail. A peer's
cancellation must reach the endpoint actor *behind* every delivery that peer already sent.
A `NodeDead` from the node actor is a different sender than the reader that pushed those
deliveries, and mailbox order between two senders is not defined. So **a session does not
cancel on the `NodeDead` event**:

- When the node declares a node Dead, it shuts down that node's connections.
- The reader for the data connection reaches end of stream. It then, *from the reader
  task*, calls each route that received frames from that peer with a closing notice.
- `SessionNode` turns that notice into `PeerGone(role, "node <name> dead: <cause>")` for
  every role hosted on that node. It arrives in the same mailbox, from the same sender,
  behind the last `Deliver`.

The route API therefore gains an `on_peer_closed(node_id, cause)` alongside `deliver`.
`subscribe` is for everything else: the access point's own bookkeeping, logging, and
dropping registrations from dead nodes before a session forms.

A false Dead (a stall) cancels sessions that could have completed. That is safe for affine
sessions, as the failure-handling spec argues. In cluster mode the SWIM suspect timeout
replaces `MARCH_SESSION_TIMEOUT_MS` as the bound on "eventually".

### Where each piece lives

- **New:**
  - `stdlib/cluster_node.march`: `ClusterNode` and `ClusterNode.Core`. A second file is
    possible if one-mod-per-file requires it; `ClusterNodeCore` would be the pure part.
- **Changed:**
  - `membership.march`: fields and merge order.
  - `swim_driver.march`: `PeerDown` becomes Suspect; tag 13/14 codecs; dispatch through a
    writer function passed in instead of `peer.fd`.
  - `global_registry.march`: creation, clock in the hash, `unregister_own`.
  - `handshake.march`: addr.
  - `net_kernel.march`: deadlines, leaf creation.
  - `peer_reader.march`: the tag table.
  - `socket.march` plus the runtime: `connect_timeout`.
- **Unchanged:**
  - `SessionNode.run` and the standalone mode.
  - The fixtures' raw-socket loops, which keep decoding tags 0–3 and 6 as before.

## Phases, each with a witness

Every phase ships with its `specs/progress/` record, a CHANGELOG entry if user-visible, and
`docs/clustering.md` (plus the `specs/lang` twin if it has one) in the same change. Each
two-node witness must first be shown to **go red** on a deliberate breakage before its green
counts. The failure-handling work's first `fan_late_crash` passed vacuously, and it was the
old-runner run that exposed it.

**Phase 0: data model, all pure.**
- Member fields and the (creation, incarnation, severity) order.
- `Entry.creation`, the clock in `root_hash`, compare-and-delete `unregister`.
- Hello addr, tags 13/14, leaf creation, all extended by element count.

Witnesses:
- Stdlib unit tests: merge laws with creation; a stale unregister does not erase the winner;
  old-shape frames still decode.
- The existing `stall`, `skew` and `partition` goldens unchanged (they use the old codecs).

**Phase 1: the node, membership and notifications.**
- `ClusterNode.start` / `stop`, acceptor, dialer, readers, ticker, control writer.
- Seeds, MEMBERS_SYNC join, full-mesh dialling, the duplicate rule, generations.
- `PeerDown` as Suspect with the refused-means-Dead fast path, Dead closes connections, the
  redial heal path.
- Prerequisites: `Socket.connect_timeout` and handshake deadlines.
- `subscribe`, `members`, `peer`, `addr_of`.

Witnesses:
- **`cluster_join`** (three nodes). c's only seed is a. Every node prints its converged
  member list, by name and address. c must print b's address and a direct-connection line
  for b, which proves `node_id -> address` came from gossip, not configuration. Red check:
  drop the addr from MEMBER_GOSSIP and c never reaches b.
- **`cluster_stall`** (port of `stall`). node-a's subscriber prints Suspect, then Dead, then
  Rejoined. Since the service closes the connection on Dead, the Rejoined line requires the
  redial heal path; this is where it is proved.
- **`cluster_crash`**. `kill_node b`: node-a prints `NodeDead(b, "connection refused")`, well
  before the suspect timeout would have fired.
- Core unit tests for every transition rule above.

**Phase 2: the registry.**
- Live replica, Vault mirror, `register` / `unregister` / `lookup` / `watch`, local-holder
  monitors, delta push plus anti-entropy, the visibility filter, owner tombstoning of stale
  creations.

Witnesses:
- **`cluster_partition`**, the natural first witness and a port of `partition` onto the
  service. The connection is closed on Dead, so healing goes through redial behind
  `drop_link` (connect timeouts), not a connection kept open. Both nodes claim `leader` in
  their halves. After heal, both print the same winner *by name*: `node_id` is a hash, so
  the golden records whichever name the hash order picks, and the test is that the two
  sides agree. The loser prints `Lost(leader, …)`. It needs root, so it runs via the Docker
  runner on macOS and in the CI loop on Linux.
- **`cluster_takeover`** (no root, so it runs everywhere).
  - a registers `leader`; `kill_node a`; b's watch prints `Unbound`; b registers and prints
    `Bound`.
  - `start_node a 2` (a new creation): a's `lookup(leader)` prints b.
  - a's stale creation-1 binding is tombstoned by a itself, which a prints.
  - Red check: remove the creation from `Entry`, and the restarted a resolves `leader` to its
    own reused pid.

**Phase 3: the shared data plane.**
- The route table, `route` / `route_type`, `on_peer_closed`.
- `Node.send` via `ClusterNode.peer`.
- DistLink's frames through the control writer. This needs a runtime change:
  `march_monitor_registry.c`'s direct `write_nosigpipe` must either hand the frame to the
  writer or write whole frames under a per-fd lock shared with it.
- Until that change lands, a monitor fire and a SWIM frame can interleave on one socket.

Witness: **`cluster_mux`**. Two independent actor-message streams and a SWIM ping share one
connection pair under load, and every message arrives in order per stream. A MONITOR_FIRE
from a killed actor on b reaches its watcher on a without a torn frame. Run it 20 times;
torn frames are load-dependent (see `recv_frame_exact`'s history).

**Phase 4: `SessionNode` in cluster mode** (the handoff to
[[2026-09-18-choreography-access-points]]).
- `SessionNode.run_cluster(node, …)` uses the node's connections, routes by endpoint pid,
  carries the session id, and drops the per-connection heartbeat in favour of SWIM.
- This spec fixes only the contract: routes, `on_peer_closed`, `lookup`, `watch`, and
  `subscribe`.
- How an access point pairs registrations when a role has many instances is that item's
  open question. It stays open here.

Witnesses:
- **`cluster_session_silent`**. `stop_node` a peer mid-session: the survivors return
  `Cancelled(…, "node … dead: suspect timeout")` from SWIM, with no session heartbeat
  running.
- **`cluster_fan_late_crash`**. The drain rule holds when the death arrives via the node
  service.
- Two concurrent sessions between the same two nodes, over one connection pair.

## Out of scope

- A partial-view overlay for large clusters (HyParView); consensus or locks on names;
  multi-cluster federation.
- Real node keys: the `"pk-" ++ name` placeholder stays. Transport encryption beyond the
  existing HMAC handshake.
- Moving RPC (`NodeRpc` / `RemoteCall`, untagged frames) onto the shared connections. It
  needs a tagged envelope first, as `peer_reader.march` notes, and nothing in choreography
  depends on it.
- Forgetting Dead members (tombstone GC for the member view). Keep them for now. A restart
  already supersedes them by creation.

## Open questions

- **A new creation from wall-clock time** is monotone on one host but not across a clock
  step backwards. The alternative is a persisted counter (`~/.march/node/<name>/creation`).
  The harness passes an explicit creation either way.
- **Registering a local name instead of a pid**: `register_name(global, local_name)`,
  resolved through `Actor.whereis` on the holder. A supervisor restart would then keep the
  global binding valid without re-registering. It is attractive for access points, but
  resolution becomes two steps. Decide in phase 2.
- **Whether `ECONNREFUSED` should go straight to Dead** on multi-host deployments, where a
  refused connection can come from a firewall rather than a dead process. The rule might
  apply only when the advertised host is local. Measure it in phase 1 before generalising.
- **The tick interval versus SWIM period granularity**, and whether the ticker should be
  replaced by the node actor sending itself delayed messages if the runtime gains a timer
  primitive.
