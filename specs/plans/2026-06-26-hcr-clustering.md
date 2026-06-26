# HCR Phase 10 — Cluster-Aware Hot Deploy

**Status:** Design. Prerequisites: Phase 9 complete (`f86f9b66`), dlclose GC (`26ddc4e4`).

**Motivation:** `forge deploy hot` currently deploys to a single server. A production cluster runs N nodes behind a load balancer. Today you must script N separate `forge deploy hot` invocations, each with a different SSH host, and manage ordering, health checks, and partial failures yourself. Epoch routing (Phase 9) already makes partial rollouts *safe* — old callers on un-updated nodes keep working — but forge has no first-class concept of a node set, shared epoch assignment across nodes, or cross-node observability.

---

## What Clustering Adds

1. **`[[hot-reload.nodes]]` in forge.toml** — declare the cluster as a named node list.
2. **Shared epoch per batch** — forge calls `GET_EPOCH` on one node and uses the same epoch for all ACTIVATEs across all nodes in a single deploy run. Cross-node epoch comparisons become meaningful.
3. **Rolling deploy** (default) — one node at a time, with an optional health check between.
4. **Simultaneous deploy** (`--simultaneous`) — all nodes in parallel, for fast low-traffic windows.
5. **`forge deploy hot status`** — connect to all nodes and print a per-node / per-function version + epoch table, highlighting drift.
6. **`VERSIONS_DETAIL` epoch field** — add epoch to the server response so `forge status` can read it.
7. **Partial failure semantics** — clearly defined, exploiting epoch routing.

---

## forge.toml Schema

Single-node config is unchanged (backward compat):

```toml
[hot-reload]
ssh_host   = "my-server"
socket     = "/tmp/my_app.sock"
public_key = "base64encodedkey="
```

Multi-node config adds `[[hot-reload.nodes]]`. The top-level `public_key` (ed25519 signing key) is shared across all nodes — the same compiled binary runs everywhere, so the embedded pubkey is the same.

```toml
[hot-reload]
public_key = "base64encodedkey="

[[hot-reload.nodes]]
name     = "web-1"
ssh_host = "web-1.prod"
socket   = "/tmp/my_app.sock"

[[hot-reload.nodes]]
name     = "web-2"
ssh_host = "web-2.prod"
socket   = "/tmp/my_app.sock"

[[hot-reload.nodes]]
name     = "web-3"
ssh_host = "web-3.prod"
socket   = "/tmp/my_app.sock"
```

If `[[hot-reload.nodes]]` is present, `[hot-reload].ssh_host` and `[hot-reload].socket` are ignored. If absent, forge falls back to the single-node path (existing behavior, no changes).

Optional per-node and cluster-level settings:

```toml
[hot-reload]
public_key  = "base64encodedkey="
strategy    = "rolling"        # "rolling" (default) | "simultaneous"
health_check_url   = "http://localhost:8080/healthz"  # checked after each rolling step
health_check_delay = 5         # seconds to wait even without a URL (default 0)
health_check_timeout = 10      # HTTP timeout in seconds (default 5)
```

---

## Epoch Coordination Across Nodes

**Goal:** all ACTIVATEs in a single `forge deploy hot` run carry the same epoch N, regardless of how many nodes are in the cluster. This makes epoch a deploy-batch identifier, not a per-node counter.

**Protocol:**

```
1. Connect to all nodes (open SSH tunnels in parallel).
2. Call GET_EPOCH on node[0] (the epoch master — first node in the list).
   → EPOCH <N>
3. Use epoch N for all ACTIVATE commands on all nodes.
4. If node[0] is unreachable, try node[1], etc. (first reachable wins).
5. If all nodes respond ERR unknown_command (old servers), epoch = 0 (Phase 8 behavior).
```

This means nodes' local `next_epoch` counters may drift (node A's counter is ahead of node B's if A was the epoch master more often). That is fine — the counter is only used to generate the epoch value for a batch; the actual epoch handed to each ACTIVATE is forge-supplied, not derived from the local counter at activation time.

**ACTIVATE change:** the server's ACTIVATE handler already parses `epoch:<N>` and calls `march_dispatch_publish_epoch`. No server-side change needed for this to work — one `GET_EPOCH` call to the master is enough.

---

## Deploy Flows

### Rolling (default)

```
Build .so  →  Upload to all nodes (CAS_PUT in parallel)
    ↓
For each node[i]:
    ACTIVATE all changed functions on node[i]
    Wait for health check (URL or delay)
    ↓ continue to node[i+1]
```

Old callers on un-updated nodes (i+1 … N) continue routing to the previous ring slot via epoch dispatch. No ABI mismatch, no dropped requests.

If node[i] fails to activate (any function returns `ERR`), the rolling deploy **stops**:
- Nodes 0 … i-1: running new code (epoch N)
- Node i: partially activated or unchanged (see below)
- Nodes i+1 … N: still on old code

This is safe. Epoch routing means the mixed-version cluster is correct. The operator can either retry the deploy (forge will skip functions already at the new impl_hash) or let the cluster stabilize on old code until the next planned deploy.

### Simultaneous (`--simultaneous`)

```
Build .so  →  Upload to all nodes (CAS_PUT in parallel)
           →  ACTIVATE all changed functions on all nodes in parallel
```

Faster, but all-or-nothing per node. Use during low-traffic windows or for stateless services where brief mixed-version operation is acceptable. Still uses the shared epoch N.

### Single-node targeting (`--node <name>`)

```
forge deploy hot --node web-2
```

Deploys only to the named node. `GET_EPOCH` is called on that node. Useful for canary deploys or debugging a specific node.

---

## Partial Failure Semantics

When a rolling deploy stops at node[i], the cluster is in a split state:

| Nodes | Code | Epoch |
|-------|------|-------|
| 0 … i-1 | new B.foo (slot 1, epoch N) | N |
| i … N   | old B.foo (slot 0, epoch N-1) | N-1 |

Old callers (.so files at epoch N-1) on nodes i … N route to old B.foo. New callers (.so files at epoch N) on nodes 0 … i-1 route to new B.foo. Cross-node calls (actors sending messages to actors on other nodes) are safe because message dispatch goes through the local ring, not the remote ring.

**No automatic rollback.** Rollback of already-activated nodes would require publishing the old impl_hash again, which forge can do (`forge deploy hot --rollback` — out of scope for this phase). Manual rollback: redeploy the previous `.so` from the CAS.

---

## `VERSIONS_DETAIL` Epoch Field

Currently:

```
SLOT <id> <name> <impl_hash> <activated_at_ms> <signer_hex>
```

Extended:

```
SLOT <id> <name> <impl_hash> <activated_at_ms> <signer_hex> <epoch>
```

The epoch field is 0 for baseline / pre-Phase-9 slots. `forge status` reads it to detect cross-node epoch drift.

**Server change:** `VERSIONS_DETAIL` handler in `march_reload.c` adds `ring[cur].epoch` to the snprintf format. One line change.

**Forge change:** `parse_versions_detail` in `cmd_deploy_hot.ml` parses the 6th token as epoch (optional; defaults to 0 for old servers).

---

## `forge deploy hot status`

```
$ forge deploy hot status

Node       Function              impl_hash   epoch  activated_at
---------  --------------------  ----------  -----  -------------------------
web-1      B.compute_delta       a3f7c2...   5      2026-06-26T14:01:00Z   ✓
web-2      B.compute_delta       a3f7c2...   5      2026-06-26T14:01:12Z   ✓
web-3      B.compute_delta       9e21ab...   4      2026-06-26T13:55:44Z   ← drift

web-1      Counter_dispatch      cc8812...   5      2026-06-26T14:01:00Z   ✓
web-2      Counter_dispatch      cc8812...   5      2026-06-26T14:01:12Z   ✓
web-3      Counter_dispatch      cc8812...   5      2026-06-26T14:01:13Z   ✓
```

`←` flags functions where impl_hash or epoch differs from the majority. Exit code 0 if all nodes agree, 1 if any drift is detected (makes this usable in CI post-deploy checks).

**Implementation:** open tunnels to all nodes in parallel, send `VERSIONS_DETAIL` to each, parse responses, join by function name, compare impl_hash and epoch, print table.

---

## Implementation Pieces

### 1. `forge/lib/project.ml`

Add `hr_nodes : (string * string * string) list` to `hot_reload_config` (name, ssh_host, socket triples). Parse `[[hot-reload.nodes]]` in `parse_hot_reload`. Backward compat: if `nodes` is empty, fall back to `hr_ssh_host` / `hr_socket`.

### 2. `forge/lib/cmd_deploy_hot.ml`

- `run_cluster` function: open N tunnels in parallel, CAS_PUT to all, GET_EPOCH from node[0], ACTIVATE per strategy (rolling / simultaneous).
- `run_status` function: open N tunnels, send VERSIONS_DETAIL, parse and join results, print table.
- Dispatch in `deploy`: if `hr.hr_nodes <> []`, call `run_cluster`; else call existing `run` (single-node).
- `parse_versions_detail`: new parser for VERSIONS_DETAIL responses (analogous to `parse_abi_query`).

### 3. `runtime/march_reload.c`

- `VERSIONS_DETAIL` handler: append ` %u` (epoch) to the snprintf — one field, backward-incompatible addition (old forge ignores extra tokens; new forge handles missing token by defaulting to 0).

### 4. `forge/bin/main.ml`

- Add `status` subcommand routing to `Cmd_deploy_hot.run_status`.
- Add `--simultaneous` / `--node <name>` flags to the `deploy hot` subcommand.

---

## What This Does NOT Include

- **Cross-node consensus on deploy state.** Nodes don't gossip about what versions their peers are running. Forge is the source of truth during a deploy run; after that, `forge status` reads it on demand.
- **Automatic canary analysis.** Error-rate monitoring / automatic promotion or rollback based on metrics. That's an operator concern; forge provides the primitive (`--node web-1` for canary, then `--node web-2,web-3` for promotion).
- **Leader election for epoch master.** The first reachable node in the list wins. No Raft, no ZooKeeper.
- **Actor migration coordination across nodes.** Actors are pinned to a node. Each node runs its own actor migration independently at ACTIVATE time. No cross-node actor migration.

---

## Compatibility Table

| forge version | server version | Result |
|---|---|---|
| pre-clustering | any | single-node deploy (existing behavior) |
| clustering | pre-Phase-9 | rolling deploy, epoch 0 (Phase 8 gate only) |
| clustering | Phase 9+ | rolling deploy, shared epoch, full routing |
| clustering | any | `forge status` works if VERSIONS_DETAIL is supported; epoch column shows 0 for pre-Phase-9 servers |

---

## Open Questions

1. **CAS_PUT to all nodes before rolling start, or on-demand per node?** Uploading to all nodes before the first ACTIVATE means a node failure mid-upload doesn't leave some nodes with the artifact and some without. Recommended: parallel CAS_PUT to all nodes upfront, then begin rolling ACTIVATEs.

2. **Health check failure handling.** If the health check URL returns non-200 after deploying node[i], should forge (a) stop and leave i+1…N on old code, (b) attempt to continue anyway, or (c) surface an actionable error message and let the operator decide? Recommended: (a) stop + error message. Health check failure is evidence the deploy is bad; don't spread a bad deploy to remaining nodes.

3. **Epoch master failure.** If node[0] (epoch master) fails between GET_EPOCH and the ACTIVATEs, forge should retry GET_EPOCH on node[1]. The increment on node[0] is lost (next_epoch on node[0] is now N+1, but N was never used). This is fine — a gap in epoch sequence doesn't break routing (ring selection is "newest slot ≤ caller_epoch", so gaps are transparent).

4. **Forge.toml `[[hot-reload.nodes]]` TOML parsing.** The forge TOML parser may or may not support array-of-tables. Verify before implementing; if not, add support or use an alternative schema (`[hot-reload.nodes.web-1]`, etc.).
