# Distributed OTP — P4 Work Distribution + P5 Full OTP Completion

**Date:** 2026-06-25
**Status:** Draft
**Depends on:** Distributed OTP P1–L4 complete (transport, SWIM, RPC, enroll/stub, two-host TCP verified). `GlobalPid` codec done. `ConsistentHash`, `Merkle`, `VectorClock`, `CRDT` stdlib modules done.
**Spec parent:** `specs/2026-06-21-distributed-otp-design.md` §§ P4, P5

---

## What's Done, What's Left

| Layer | Status | Gap |
|-------|--------|-----|
| L1/L2 Transport + auth | ✅ | — |
| L3 SWIM + driver | ✅ | — |
| L4 RPC (enroll/stub, two-host TCP) | ✅ | Load gossip not wired to peer state |
| L4 Serializable `GlobalPid` | ✅ | `creation` reconciliation on reconnect not enforced |
| L5 `GlobalRegistry` CRDT | ✅ | No Merkle anti-entropy; no ConsistentHash ownership routing |
| L6 Work dispatch | ❌ | Entire layer missing |
| P5 Cross-node links/monitors | ❌ | Entire layer missing |
| P5 Distributed supervisors | ❌ | Entire layer missing |

This spec covers two independent deliverables that can be implemented in either order:
- **P4** — L6 load-aware work dispatch (the "headline" feature)
- **P5** — Registry anti-entropy + cross-node links/monitors + distributed supervisors

---

## P4 — L6 Work Distribution

### Goal

`NodeCall.dispatch(fn_ref, args)` routes `fn_ref(args)` to the cluster node with the most spare capacity. The call is type-safe (same CAS admission check as `NodeCall.call`), homogeneous (the remote node runs its own AOT binary, no code shipping), and falls back to local execution if no healthier peer is found.

### Load Gossip

**Current state:** `ClusterLoad.local()` reads CPU/mem on the local node. `NodeLoad` can be encoded with `to_ints`/`from_ints`. But no node ever sends its load to peers.

**Change:** Piggyback `NodeLoad` on SWIM gossip frames. In `SwimDriver.step`, when encoding a `SwimGossip` frame, append the local node's load as a MessagePack array using `ClusterLoad.to_ints`. Receivers call `ClusterLoad.from_ints` and update a `PeerLoadTable` (a `Map(String, NodeLoad)` keyed by `node_id`).

**Staleness:** Load readings decay. Each `NodeLoad` gains a `sampled_at: Int` (unix ms from `System.time_ms()`). Readings older than `LOAD_STALE_MS = 10_000` are treated as unknown — the node is excluded from dispatch routing but not from membership.

### New `stdlib/work_dispatch.march`

```march
mod WorkDispatch do

  -- Power-of-two-choices: pick the better of two random members.
  -- Returns None if the member list has fewer than 2 live nodes
  -- or all load readings are stale.
  fn pick_dispatch_target(
    members: List(NodeLoad),
    scorer: NodeLoad -> Int,
    now_ms: Int
  ) : Option(NodeLoad)

  -- Route fn_ref to the best available node.
  -- Falls back to local execution if no remote node wins.
  fn dispatch(
    peers: List(NodeLoad),
    now_ms: Int,
    fn_ref: RemoteRef,
    args: List(Int),
    local_pid: Pid,
    timeout_ms: Int
  ) : Result(List(Int), CallError)

end
```

**`pick_dispatch_target` algorithm:**

1. Filter `members` to those with `sampled_at >= now_ms - LOAD_STALE_MS`.
2. If fewer than 2 candidates: return `None`.
3. Pick 2 candidates uniformly at random (without replacement).
4. Return `Some` of whichever has the higher `scorer` value (e.g. `ClusterLoad.spare_cpu_milli`).

**`dispatch` algorithm:**

1. Call `pick_dispatch_target`. If `None`: execute locally via normal function call (not RPC).
2. If `Some(target)` and `target.spare_cpu_milli > local_spare + DISPATCH_THRESHOLD_MILLI`: call `NodeCall.call` on `target`.
3. If remote call returns `Err(NoConnection)` or `Err(DeadlineExceeded)`: fall back to local.
4. All other errors propagate.

`DISPATCH_THRESHOLD_MILLI = 200` (20% of a core — don't dispatch for tiny gains).

### ConsistentHash Affinity (optional override)

For data-local work (e.g. every call for key `K` should go to the same node regardless of load):

```march
fn dispatch_affine(
  ring: ConsistentHash.Ring,
  fn_ref: RemoteRef,
  key: String,
  args: List(Int),
  local_pid: Pid,
  timeout_ms: Int
) : Result(List(Int), CallError)
```

Routes to `ConsistentHash.get(ring, key)` (the consistent-hash owner) regardless of load, unless that node is down (then falls back to load-aware dispatch). Useful for cache-locality and shard-affinity patterns.

### Cross-Node Work-Stealing (P4b — deferred)

Pull-based stealing is materially harder than push dispatch: it requires exposing a work queue protocol (`STEAL_PEEK` / `STEAL_CLAIM`) and steal-victim selection. Keep as a follow-on phase after push dispatch (above) ships and is measured.

---

## P5 — Full Distributed OTP

### 5a — `GlobalRegistry` Merkle Anti-Entropy

**Why:** `GlobalRegistry.merge` is a CRDT join (correct, order-insensitive), but two nodes that never exchange a full state will diverge silently if gossip drops a registration event. Merkle anti-entropy detects divergence cheaply (compare root hashes) and repairs it efficiently (`diff()` returns only the divergent leaves).

**Protocol extension in net_kernel:**

New frame type `REGISTRY_SYNC` (frame tag `0x05`):
```
→ REGISTRY_SYNC_REQ  root_hash:String
← REGISTRY_SYNC_RESP root_hash:String leaves:[{name, entry}]  -- empty if hashes match
```

**`GlobalRegistry` changes:**

```march
fn root_hash(registry: Names) : String
-- Builds a Merkle tree over sorted (name, entry) pairs.
-- Uses Merkle.build with serializer: fn (name, entry) -> msgpack_encode({name, entry}).
-- Returns the hex root hash.

fn diff_entries(local: Names, remote_root: String, remote_leaves: List((String, Entry))) : Names
-- Merges remote_leaves into local (CRDT join per entry).
-- Only called when root_hash(local) != remote_root.
```

**Anti-entropy loop (in `SwimDriver` or a dedicated green thread):**

Every `ANTI_ENTROPY_PERIOD_MS = 30_000`:
1. For each live peer: send `REGISTRY_SYNC_REQ(root_hash(local_registry))`.
2. If peer replies with non-empty `leaves`: call `diff_entries` and update local.
3. If root hashes match: nothing to do.

This piggybacks on the existing net-kernel connection. No new connection needed.

### 5b — ConsistentHash Name-Partitioning

**Authoritative ownership:** the node that `ConsistentHash.get(ring, name)` returns is the authoritative registrar for that name.

**Current `GlobalRegistry.register` behavior:** any node can register any name locally; CRDT merge resolves conflicts via VectorClock + tiebreak.

**Phase 5b change:** `register(registry, name, ...)` on a non-authoritative node proxies through the authoritative node (via `NodeCall.call` to the owner's `GlobalRegistry.remote_register` stub). The authoritative node writes the registration and gossips it out. Non-authoritative nodes can still read locally (eventual consistency).

**Why defer this to 5b:** routing via the owner is a behavioral change (adds network round-trip for writes). The pure-CRDT path (5a) gives correctness without the latency. Ownership routing adds determinism for concurrent same-name registrations.

**Same-name conflict policy (from Risk 4 in parent spec):** when two nodes concurrently register the same name, VectorClock says `Concurrent` and the deterministic `(node_id, pid)` tiebreak in `GlobalRegistry.wins` resolves it. With ownership routing this becomes: first write to the authoritative node wins; concurrent writes arrive serially at the owner (TCP FIFO).

### 5c — Cross-Node Links and Monitors

**New `stdlib/dist_link.march`:**

```march
mod DistLink do

  -- Monitor a remote process. Returns a ref for demonitoring.
  -- When the remote process dies, the local process receives:
  --   Down(ref, Pid, reason)
  -- where reason is one of: Normal | Killed | Crash(msg) | NodeDown
  fn monitor(pid: GlobalPid, timeout_ms: Int) : Result(MonitorRef, CallError)

  -- Bidirectional link. If either side dies, the other gets EXIT.
  fn link(pid: GlobalPid, timeout_ms: Int) : Result((), CallError)
  fn unlink(pid: GlobalPid) : ()
  fn demonitor(ref: MonitorRef) : ()

end
```

**Implementation:**

Monitoring is a two-step protocol:
1. Local node sends `MONITOR_REQ(watcher_pid, target_pid)` to the node that hosts `target_pid`.
2. Remote node adds `(watcher_node, watcher_pid)` to a per-pid monitor table in a new C-side registry `march_monitor_registry.c`.
3. When the monitored process dies (normal exit, crash, or its node disconnects), the remote node sends `MONITOR_FIRE(target_pid, reason)` back.
4. Local node's net-kernel delivers `Down(ref, pid, reason)` to the watcher's mailbox.

**Node-down fires all monitors:** when a peer connection drops, sweep all monitors whose `target.node_id == peer` and fire `Down(..., NodeDown)` locally. This is the same signal as Erlang's `nodedown`.

**Links** build on monitors: both sides call `monitor` on each other. When either fires a `Down`, the linked process receives `EXIT` and propagates (unless trapping exits).

**New `march_monitor_registry.c`:**
- `march_monitor_register(target_pid_int, watcher_node_id, watcher_pid_int)` — called from net-kernel frame handler.
- `march_monitor_fire_all(target_pid_int, reason_tag)` — called from `actor_green_thread` on exit + from net-kernel on peer-down.
- Sends `MONITOR_FIRE` frames back via the net-kernel connection.

### 5d — Distributed Supervisors

A supervisor that can spawn and monitor children on remote nodes, using the same restart strategies as the local supervisor.

**`stdlib/dist_supervisor.march`:**

```march
mod DistSupervisor do

  type RemoteChild = {
    fn_ref: RemoteRef,        -- the child actor module's init fn
    node_id: String,          -- which node to run it on
    restart: RestartStrategy  -- same as local: Permanent | Transient | Temporary
  }

  -- Start a supervisor managing remote children.
  -- Returns the supervisor's local Pid.
  fn start_link(children: List(RemoteChild), strategy: SupervisionStrategy) : Pid

end
```

**Implementation:** a local supervisor actor that:
1. For each `RemoteChild`, calls `NodeCall.call` to spawn the child actor on the remote node and gets back a `GlobalPid`.
2. Calls `DistLink.monitor` on each remote child.
3. On `Down(ref, pid, reason)`: applies the restart strategy — if `Permanent` or `Transient+Crash`, re-spawns via `NodeCall.call`.

This reuses all existing supervision logic; the only new pieces are the remote spawn call and the cross-node monitor.

---

## Integration Test Plan

### P4 tests

1. **`test/native/work_dispatch_local.march`** — 1 node: `dispatch` falls back to local when no peers; verifies result is correct.
2. **`test/native/work_dispatch_two_nodes.march`** — 2 processes (green threads), one saturated: `dispatch` routes to the idle one; wall-clock assert (call on busy local > call via dispatch to idle).
3. **`test/native/dispatch_affine.march`** — same key always routes to the same virtual node; verify 100 calls with different args all land on the same node_id.

### P5 tests

1. **`test/native/registry_anti_entropy.march`** — 2 nodes start with divergent registries; anti-entropy loop runs; verify they converge within 2 rounds.
2. **`test/native/cross_node_monitor.march`** — node A monitors actor on node B; kill actor on B; verify node A gets `Down` message within 500ms.
3. **`test/native/dist_supervisor.march`** — dist supervisor spawns 2 remote actors; kill one; verify supervisor restarts it; verify registered name resolves to new pid.

---

## File Map

| New file | Purpose |
|----------|---------|
| `stdlib/work_dispatch.march` | P4 dispatch API (pick_dispatch_target, dispatch, dispatch_affine) |
| `stdlib/dist_link.march` | P5 cross-node monitor/link API |
| `stdlib/dist_supervisor.march` | P5 distributed supervisor |
| `runtime/march_monitor_registry.c` | P5 per-pid monitor table + fire-on-exit |
| `runtime/march_monitor_registry.h` | P5 header |

**Modified files:**

| File | Change |
|------|--------|
| `stdlib/swim_driver.march` | Piggyback `NodeLoad` on gossip frames (P4) |
| `stdlib/global_registry.march` | Add `root_hash`, `diff_entries` (P5a) |
| `stdlib/net_kernel.march` | Handle `REGISTRY_SYNC_REQ/RESP`, `MONITOR_REQ/FIRE` frames |
| `runtime/march_runtime.c` | Call `march_monitor_fire_all` on actor exit |
| `runtime/march_reload.c` | Call `march_monitor_fire_all(NodeDown)` on peer-disconnect |

---

## Implementation Order

These can be done in two independent streams:

**Stream A (P4):**
1. Add `sampled_at` to `NodeLoad`; gossip load via SWIM gossip frames.
2. `stdlib/work_dispatch.march` — `pick_dispatch_target` + `dispatch`.
3. Integration test: two-node dispatch.
4. `dispatch_affine` with `ConsistentHash`.

**Stream B (P5):**
1. `GlobalRegistry.root_hash` + `diff_entries` using `Merkle.build`/`diff`.
2. Anti-entropy loop in `SwimDriver` (or standalone green thread).
3. Integration test: registry convergence.
4. `march_monitor_registry.c` + `actor_green_thread` exit hook.
5. `stdlib/dist_link.march`.
6. Integration test: cross-node monitor fires on death.
7. `stdlib/dist_supervisor.march`.
8. Integration test: dist supervisor restarts remote child.
9. ConsistentHash name-partitioning with ownership proxy (5b, last — behavioral change).

---

## Open Questions

1. **Load gossip frequency vs SWIM period.** SWIM probes fire every ~1–5s per member. Piggybacking load there is fine for small clusters (N≤50). For larger clusters, consider a dedicated `LOAD_GOSSIP` frame on the bulk lane.

2. **Dispatch fallback on RPC error.** Current spec falls back to local on `NoConnection` and `DeadlineExceeded`. Should `TypeMismatch` also fall back? No — a type mismatch is a programming error, not a routing error. Propagate it.

3. **Monitor table persistence across node restart.** Today: if a node restarts, it loses its monitor registrations. Peers that had monitors on the restarted node's actors get `NodeDown` (which is correct); but a restarted node has no memory of monitors it had placed on peers. Document as known limitation; proper solution requires a durable monitor log (out of scope).

4. **Dist supervisor + HCR.** If a remote child's function is hot-reloaded (state migrated), should the supervisor re-link? The dist monitor fires `Down` when the actor restarts during migration — a supervisor would incorrectly restart it. Need a `MigratedDown` reason so the supervisor can distinguish migration from crash. Defer to a HCR+OTP integration phase.
