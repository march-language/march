# Distributed OTP — Node Discovery, Distribution & Cross-Node Work

**Date:** 2026-06-21
**Status:** Draft — design approved in brainstorm, pending implementation plans per phase
**Depends on:**
- CAS (`lib/cas/` — `cas.ml`, `pipeline.ml`, `scc.ml`, `hash.ml`, `serialize.ml`)
- Hot Code Reloading (`specs/hot-code-reload.md`) — **shares the CAS prerequisite (HCR Part 1) and the mixed-version schema-evolution machinery (HCR Part 6)**
- Distributed-algorithms stdlib (`specs/2026-06-20-distributed-algorithms-design.md` — `vector_clock`, `crdt`, `merkle`, `consistent_hash`, `deque`; the `CRDT(t)` and `Hashable(a)` interfaces)
- Actor/task runtime (`stdlib/actor.march`, `stdlib/task.march`; `runtime/march_runtime.c`, `march_scheduler.c`, `march_message.c`)
- Networking (`runtime/march_http.c`, `stdlib/socket.march`, TLS)
- Serialization (`stdlib/msgpack.march`, `stdlib/json.march`)
- Capability system Phase 1 (`specs/capability-system-design.md`; `needs X` / `Cap(X)`, `root_cap`/`cap_narrow`)

---

## Motivation

March already has most of the OTP *substrate*: green-thread actors with `cast`/`call`, MPSC mailboxes with selective receive, links/monitors, supervisor strategies (`one_for_one`/`one_for_all`/`rest_for_one`), a work-stealing M:N scheduler, TCP/TLS/WebSocket, and MessagePack. What it lacks is the layer that turns *one node* into *a cluster*: node discovery, location-transparent messaging, and the ability to call a module function on another node — safely, and as a way to move work off a busy machine onto an idle one.

The recently-added `vector_clock`, `crdt`, `merkle`, and `consistent_hash` modules are the missing coordination primitives, but they are currently pure-functional and wired to nothing. This spec makes them the coordination layer of a distributed runtime, and reuses the CAS — exactly as the HCR spec does — as the source of truth for *what a function is*, *whether two nodes agree on it*, and *where to get its code*.

The headline use case: **Node A is on a busy machine, Node B has spare capacity. `dispatch(MyApp.expensive, args)` routes the call to B, which runs its own fully-optimized native copy at full speed and returns the result.** No code shipped, no interpreter, no deopt — the CAS hashes only *verify* that A and B mean the same function.

---

## The Central Relationship to Hot Code Reload

This design and HCR are two projections of one idea: **the CAS is the spine.** They share substrate and must not fork it. Four reconciliations are load-bearing:

1. **Shared prerequisite — Merkle `did_hash` (HCR Part 1).** Today `ADefRef.did_hash` is *not* populated with real callee hashes, so `impl_hash` is not yet a true Merkle root (`serialize.ml:166` already writes only `did_hash` for content-addressing, but nothing fills it). Cross-node type safety has the *same* dependency as HCR: until a bottom-up pass sets `ADefRef.did_hash = callee.impl_hash` over the topo-sorted SCCs, an `impl_hash` match does not prove transitive agreement. **This design inherits HCR Phase 1 as a hard prerequisite (P0), not a parallel effort.**

2. **One distribution model, two transports.** HCR Part 1 establishes "distribution is CAS tiers, not a bespoke protocol," adding a remote registry tier (`s3://`/`https://`) above the global `~/.march/cas/` tier with read-through warming. This design adds a **peer CAS tier** reachable over the net-kernel connection (§L2). Deploy-time artifact distribution pulls from the registry tier; runtime peer code-shipping (P6) fetches from a sibling node's CAS. Same content-addressed `lookup_artifact` abstraction, same immutability, same ed25519 signing — no new shipping protocol.

3. **Mixed-version wire safety defers to HCR Part 6.** HCR Part 6 already specifies the distributed case: old and new nodes coexisting and exchanging messages require **forward** compatibility (old code reads new data), and it provides the machinery — the forward/backward-compat classification table, the *added-variant-requires-a-catch-all-arm* rule, `@compat(forward|full)` checked against the CAS prior type, row polymorphism for unknown-field tolerance, and session-subtyping for protocol evolution. This design **does not reinvent any of it**; it makes "mixed-version cluster" a *permanent* first-class state rather than HCR's transient rolling-upgrade window.

4. **Reuse loading + signing; no `dlopen`.** Shipped remote code (P6) loads via HCR's Model A (interpreter trampoline) / Model B (ORC JIT) — explicitly **not** `dlopen` (HCR Part 4). Shipped artifacts are ed25519-signed exactly like HCR activations (HCR Part 9).

### The performance insight that makes distribution cheaper than HCR

HCR's central tension is that hot-reloadable code is *permanently deoptimized at the boundary* (no inlining/defun/borrow-elision across a swappable edge). **Distribution mostly escapes this**, because **remote dispatch is independent of the hot-reload boundary** (design decision):

- **Homogeneous remote call (P1–P5):** Node B invokes its *own* fully-optimized AOT function, located by `impl_hash`. The wire carries only `{function identity, args}`. B pays **zero** boundary deopt — it runs its native O3+LTO copy. The CAS hashes are used *only* to verify A and B agree.
- **Code-shipped function (P6):** *only here* do you pay HCR's boundary cost, because shipped code runs as trampoline/JIT.

So the deopt tax is confined to heterogeneous code-shipping; the OTP work-dispatch headline runs at full native speed. Any function is a legal remote target — not just boundary functions.

---

## Architecture — The Layer Cake

Each layer depends only on those below it, so the system builds and tests bottom-up.

```
┌─────────────────────────────────────────────────────────────┐
│ L6  Work distribution    load-aware dispatch, power-of-two,  │
│                          cross-node work-stealing            │
│ L5  Distributed OTP      global registry (CRDT), dist        │
│                          supervisors, cross-node links/mon.  │
│ L4  Remote calls (RPC)   Node.call w/ CAS type-safety,       │
│                          location-transparent send/cast/call │
│ L3  Membership           SWIM failure detection, gossip,     │
│                          CRDT member set, Merkle anti-entropy│
│ L2  Net kernel           one persistent auth'd conn per peer,│
│                          multiplexed framed channels, CAS tier│
│ L1  Transport & identity TCP+TLS, length-framed MessagePack, │
│                          NodeId + handshake/auth             │
└─────────────────────────────────────────────────────────────┘
```

---

## Primitive Mapping (the core of the design)

| Primitive | Role(s) in this system |
|-----------|------------------------|
| **CAS** | (1) *Type/version safety on every remote call* — a remote function reference carries `sig_hash` + `impl_hash`; remote rejects on `sig_hash` mismatch (incompatible type) and applies policy on `impl_hash` mismatch (version skew). (2) *Peer code-shipping* (P6) — on `impl_hash` miss, fetch the `compilation_hash` artifact via the peer CAS tier and load it. (3) *Deterministic result memoization* — a pure call's result is cacheable cluster-wide keyed by `(impl_hash, BLAKE3(args))`. |
| **VectorClock** | Causally orders cluster events — membership transitions (join/suspect/alive/leave), registry updates, config changes — so gossip converges deterministically and "who won" is well-defined. (`LWWRegister` already embeds a `VectorClock`.) |
| **CRDT** | Holds all partition-tolerant replicated state: **OR-Set** member set, **LWW-Map / OR-Set** global name→pid registry, **G/PN-Counter** cluster metrics (aggregate load, distributed rate limits). The generic `CRDT(t)` interface drives a single sync loop that merges any peer's state without knowing the concrete type. |
| **Merkle** | Anti-entropy: two peers compare a root hash and `diff()` to sync only divergent membership/registry entries — no full-state shipping. Also verifies integrity of shipped CAS artifacts (P6). |
| **ConsistentHash** | Routing: partitions registry ownership (which node is authoritative for a name) and provides sticky/affinity work routing, overridden by load metrics in L6. |
| **Deque** | Local work queue at L6 — O(1) push/pop at both ends for cross-node work-stealing. |

---

## The Four Safety Guarantees

"Call module functions across nodes safely" was decomposed into four properties, all in scope:

1. **Version/type agreement (CAS).** Every remote call carries `{sig_hash, impl_hash}`. `sig_hash` mismatch → `TypeMismatch` (the two nodes do not share the function's type — reject before executing anything). `impl_hash` match → invoke the local optimized copy. `impl_hash` miss → policy: `VersionSkew` reject, or (P6) fetch+load. This is end-to-end type safety across the wire, from machinery the compiler already computes. **Soundness depends on P0** (Merkle `did_hash`).

2. **Authenticated transport (L1).** Only cluster members can join and issue calls — mutual TLS or a shared cluster secret with a signed challenge in the handshake. Prevents arbitrary remote code execution by outsiders. Identity = `NodeId = BLAKE3(node public key)`.

3. **Failure isolation (L4 + L3).** A remote call that crashes, times out, or hits a netsplit returns `Err(timeout | noconnection | exit(reason))` — never hangs the caller, never corrupts local state. Cross-node links/monitors synthesize `Down(noconnection)` when the failure detector declares a peer dead.

4. **Sandboxing untrusted code (L4, P6).** Shipped/foreign work runs under a narrowed capability token (built on the existing Phase-1 capability system): no `fs`/`net`/`spawn` unless explicitly granted. Heaviest property; only needed for mutually-distrusting (multi-tenant) clusters, so it lands with code-shipping in P6.

---

## L1 — Transport & Node Identity

- **Node identity.** A node is `name@host` plus a stable `NodeId = BLAKE3(node public key)`. The keypair backs both the cluster handshake (auth) and ed25519 artifact signing (P6, shared with HCR Part 9).
- **Wire.** Reuse `march_tcp_*` + TLS. Frames are length-prefixed; payloads are **MessagePack** (`stdlib/msgpack.march` — binary, compact). JSON stays for human/debug/health paths only.
- **Handshake.** Mutual auth (mTLS, or shared cluster secret + signed challenge), then exchange `{NodeId, name, incarnation, compiler_identity, runtime_identity}`. The `compiler_identity`/`runtime_identity` fields are lifted verbatim from the CAS (`cas.ml`); a mismatch tells the cluster *at join time* whether two nodes can share homogeneous calls (P1) or must fall back to code-shipping (P6).

## L2 — Net Kernel

- **One persistent authenticated connection per peer** (Erlang `dist` style), multiplexing every traffic class — process messages, RPC, monitor signals, gossip, CAS fetches — as tagged frames over a small set of logical channels.
- **Heartbeat/keepalive** on the connection feeds the L3 failure detector (cheap liveness signal between SWIM probes).
- This connection **is the peer CAS tier transport** (reconciliation #2): a `lookup_artifact` miss can be satisfied by fetching content-addressed bytes from a peer that has them, verified by `compilation_hash` (tamper-evident by construction).

## L3 — Membership (SWIM + CRDT + Merkle)

- **Failure detection — SWIM.** Periodic randomized direct ping; on miss, k-way indirect ping via random members; suspicion timeout → dead. Per-node **incarnation numbers** let a falsely-suspected node refute and rejoin.
- **State — CRDT.** The live-member set is an **OR-Set** (`NodeId → NodeMeta`); per-node status/incarnation is an **LWW-Register** (already `VectorClock`-backed). **Vector clocks** order join/suspect/alive/leave so concurrent transitions converge deterministically. The generic `CRDT(t)` interface lets one sync routine merge member-set, registry, and metric CRDTs uniformly.
- **Anti-entropy — gossip + Merkle.** Gossip piggybacks membership deltas on SWIM probes. Periodically two peers compare a **Merkle** root over their membership+registry state and `diff()` to reconcile only divergent entries — bounded bandwidth regardless of cluster size.
- **Discovery.** Config-provided **seed nodes** for bootstrap (P2 minimal); full gossip dissemination thereafter. (External registry/DNS discovery is a later, optional alternative, not a v1 requirement.)
- **Hook to L5.** When a node is declared dead, every cross-node link/monitor to it fires `Down(noconnection)`.

## L4 — Remote Calls (RPC) — the safety core

A **remote function reference** is `{module, name, sig_hash, impl_hash}`, stamped at compile time. `Node.call(node, fref, args, deadline)`:

1. Frame `{fref, msgpack(args), reply_ref, deadline}`; send over the net-kernel.
2. **Remote CAS check:** `sig_hash` mismatch → reply `TypeMismatch`. `impl_hash` match → invoke its own optimized native copy (zero deopt). `impl_hash` miss → `VersionSkew`, or (P6) fetch+load via the peer CAS tier.
3. Result/`Err` framed back. **Failure isolation:** deadline expiry, netsplit, or remote crash → `Err(timeout | noconnection | exit(reason))`; the caller never hangs.
4. **Sandboxing (P6):** foreign/shipped execution runs under a narrowed `Cap`.

- **Result memoization:** a pure call keyed by `(impl_hash, BLAKE3(args))` is cacheable cluster-wide (opt-in; pure functions only).
- **Location transparency:** `send`/`cast`/`call` ride the same path. A global `Pid = {NodeId, local_pid, creation}` (the `creation` counter prevents reuse ambiguity across restarts); local target → existing mailbox, remote target → net-kernel. `march_msg_copy` semantics are preserved by re-encoding through MessagePack on the wire.

## L5 — Distributed OTP

- **Global registry.** `name → {NodeId, Pid}` as an **LWW-Map / OR-Set CRDT**, gossip-replicated, conflicts resolved by incarnation (LWW). **ConsistentHash** partitions authoritative ownership of names; reconciliation rides the Merkle anti-entropy path.
- **Cross-node links/monitors.** Extend `march_link`/monitor over the net-kernel: remote process death → `Down(reason)`; failure-detector-declared node death → synthesized `Down(noconnection)` (standard OTP semantics).
- **Distributed supervisors.** A supervisor starts children on remote nodes via remote spawn, under the existing strategies (`one_for_one`/`one_for_all`/`rest_for_one`); restarts honor the registry + monitors across nodes.
- **Mixed-version messaging.** Every cross-node value carries `impl_hash`; wire-safety defers entirely to **HCR Part 6** (forward/backward compat, added-variant catch-all, `@compat`).

## L6 — Work Distribution (the headline)

- **Load publication.** Each node publishes load (run-queue depth from `march_scheduler`, reduction rate) as a gossiped **G/PN-Counter / LWW gauge** in the membership metadata.
- **`dispatch(fref, args)` target selection.** **ConsistentHash** for sticky/affinity routing, overridden by **power-of-two-choices** least-loaded selection over live members. The "Node A busy → Node B idle" case reads the gossiped load gauges and routes the `remote_call` to B, which runs its own native copy at full speed.
- **Cross-node work-stealing.** An idle node pulls from a busy node's queue; the local queue is a **Deque** (O(1) both ends). Stealing is bounded by the same load gauges to avoid thrashing.

---

## Compiler Touchpoints

Almost everything is stdlib + runtime, but three points touch the compiler — all **reuse HCR machinery**, none are net-new mechanisms:

1. **Remote function reference.** `remote_ref(Module.f)` (builtin/macro) lowers to `{module, name, sig_hash, impl_hash}`, reusing HCR Phase-2's `NAME_ID` interning and the Merkle `impl_hash`. The author gets a first-class, wire-stable, type-checked handle.
2. **Merkle `did_hash` (P0).** The shared prerequisite — identical to HCR Phase 1. Without it, `impl_hash` is not transitively sound and the type-safety guarantee is hollow.
3. **Dynamic artifact loading (P6 only).** Shipped code loads via HCR's Model A/B (trampoline/ORC), not `dlopen`. Not needed for the homogeneous path.

The capability sandbox (safety property 4) reuses the **existing Phase-1 capability system** (`needs X` / `Cap(X)`, `root_cap`/`cap_narrow`, runtime-erased) — `cap_narrow` produces the restricted token under which foreign work executes. No new capability mechanism.

---

## Phased Roadmap

Work distribution is pulled up: the vertical slice reaches the headline payoff after a *minimal* membership layer, with full CRDT registry / anti-entropy / distributed supervisors following. Each phase gets its own spec → implementation plan.

- **P0 — Shared CAS prerequisite** *(== HCR Phase 1; do once, both features depend on it).* Merkle-populate `ADefRef.did_hash` via a bottom-up pass over topo-sorted SCCs; add `TypeDef`s as graph nodes so type-layout changes propagate into dependents' hashes. Regression-test the cross-SCC-inlining stale-cache case. **Highest leverage; also fixes a latent stale-cache bug independent of distribution.**

- **P1 — Transport + net kernel (L1–L2).** Auth handshake, framed MessagePack, one-connection-per-peer multiplexing, identity exchange (incl. compiler/runtime digests). Test: two nodes handshake, exchange tagged frames, detect identity mismatch.

- **P2 — Minimal membership (L3, just enough).** Seed-node join, SWIM liveness (direct + indirect ping, incarnations), and load-gauge gossip. Defer the full CRDT registry, Merkle anti-entropy, and richer dissemination to P5. Goal: every node has a live, load-annotated member view.

- **P3 — Remote messaging + RPC (L4).** Global `Pid`, location-transparent `send`/`cast`/`call`, `Node.call` with `sig_hash`/`impl_hash` verification and failure isolation. *Homogeneous, full native speed.* Test: cross-node `call` returns correct result; `sig_hash` mismatch rejected; netsplit → `Err(noconnection)`.

- **P4 — Work distribution (L6) — the headline.** Load-aware `dispatch`, power-of-two-choices, ConsistentHash affinity, cross-node work-stealing over `Deque`. Test: with Node A saturated and Node B idle, `dispatch` runs the call on B and beats local execution wall-clock.

- **P5 — Full distributed OTP (L5).** Global registry CRDT, cross-node links/monitors, distributed supervisors, and the full CRDT member set + Merkle anti-entropy + vector-clock event ordering (upgrading P2's minimal membership). Test: registered name resolves cluster-wide; remote actor crash fires `Down`; supervisor restarts a remote child.

- **P6 — CAS code-shipping + sandboxing.** Peer CAS tier over the net-kernel; ship + load via HCR Model A/B (trampoline/ORC, **not dlopen**); ed25519-signed artifacts (shared with HCR Part 9); `cap_narrow` sandbox for foreign code; cluster-wide pure-call result memoization. Enables heterogeneous clusters and dispatch to nodes lacking the code.

---

## Non-Goals

- **Reinventing HCR's schema-evolution / mixed-version machinery** — reuse HCR Part 6 wholesale.
- **A bespoke code-distribution protocol** — code distribution is CAS tiers (registry tier + peer tier), per reconciliation #2.
- **`dlopen`-based loading** — shipped code uses HCR's ORC/trampoline path.
- **Hot-reloading the runtime/stdlib/deps across the cluster** — inherits HCR's non-goal; those are direct-called and require a restart.
- **Byzantine fault tolerance / consensus (Raft/Paxos)** — the model is CRDT/AP (available, partition-tolerant, eventually consistent), not CP. Strong-consistency coordination is out of scope; if needed later it is a separate layer.
- **Multi-datacenter / WAN topology optimization** — v1 targets a single LAN cluster; WAN gossip tuning is deferred.

---

## Risks & Open Problems

1. **P0 soundness (shared with HCR).** Merkle `did_hash` must hash in a canonical, deterministic order or the type-safety guarantee silently corrupts. Reuse `serialize.ml`'s canonical encoding; test against cross-SCC-inlining cases. *Without P0, the headline "type-safe cross-node call" claim is unsound.*
2. **Global `Pid` identity across restarts.** The `creation` counter must make a restarted node's old pids unambiguously stale, or a stray message could hit a reused local pid. Needs the same rigor as Erlang's node creation field.
3. **SWIM tuning.** False-positive failure detection under GC pauses / scheduler preemption (signal-based, 1 ms quantum) could evict healthy nodes; suspicion timeouts must account for `MARCH_QUANTUM_US` and GC stop-the-world windows.
4. **CRDT registry conflict semantics.** LWW-by-incarnation silently drops a concurrent registration of the same name; whether that is acceptable (vs. reject/error) is a policy decision to settle in P5.
5. **MessagePack ↔ March value fidelity.** Cross-node `send` must preserve everything `march_msg_copy` preserves; linear/affine values and closures need an explicit policy (likely: linear values cannot cross nodes without explicit move semantics; closures require P6 code-shipping of their function).
6. **Result memoization correctness.** Only sound for genuinely pure functions; the compiler's effect/capability information should gate which `fref`s are memoizable, else a cached impure result corrupts the cluster.
7. **Sandbox completeness (P6).** `cap_narrow` gates declared capabilities, but the C runtime FFI surface must have no un-gated escape hatch (raw socket/file builtins) reachable from foreign code.
8. **Interaction with epochs/atomic-RC under cross-node monitors.** Remote `Down` delivery vs. local epoch reclamation needs the rigor of `atomic-rc-design.md`.
