# Distributed OTP — Node Discovery, Distribution & Cross-Node Work

**Date:** 2026-06-21
**Status:** Draft — design approved in brainstorm; **P1 (transport + net-kernel L1/L2) and L3 membership-CRDT implemented** (see `specs/progress.md` and `specs/todos.md` Done). Built as stdlib modules: `net_frame`, `node_identity`, `cluster_auth`, `handshake`, `net_kernel`, `peer_registry`, `cluster_conn`, `membership`; plus exposing `tcp_listen`/`tcp_accept` to the typechecker/eval. Pure logic eval-tested; socket I/O typecheck-clean + runtime-exercised. Remaining: SWIM probe loop, registry CRDT (L5), load-aware dispatch (L6), loopback integration test.
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

- **Homogeneous remote call (P1–P5):** Node B invokes its *own* fully-optimized AOT copy of the function. The function *body* runs at full O3+LTO speed — no inlining/defun/borrow-elision is sacrificed *inside* it, and the function may still be inlined into B's *local* callers (a remote call crosses no local call boundary). The CAS hashes are used *only* to verify A and B agree.
- **Code-shipped function (P6):** *only here* do you pay HCR's boundary cost, because shipped code runs as trampoline/JIT.

So the deopt tax is confined to heterogeneous code-shipping; the OTP work-dispatch headline runs at full native body speed.

**What "full speed" does *not* mean — the enrollment cost.** Being a remote *target* is not free for *every* function, because nothing in the runtime today can locate or invoke a function by content identity (there is no function-by-`impl_hash` registry in `runtime/`; the HCR dispatch table is *proposed*, not built). A remote-callable function needs two compiler-emitted artifacts: (1) a **registry entry** mapping its identity → a retained, addressable entry point (which also pins it against dead-code elimination), and (2) a **marshalling stub** that decodes MessagePack args into typed March values, invokes the function, and encodes the result. So the precise rule is: **any function the author names as a `remote_ref`/`dispatch` target, whose argument and return types are serializable, is a legal remote target.** That is still "any function the author refers to" — not a separate optimization boundary, and compatible with the *independent-of-reload-boundary* decision — but it is an *enrollment* (the compiler stubs + registers referenced targets), not a universal "every function is free." Non-serializable arg/return types (closures — see P6; linear/affine values — see Risk 5; resource handles; pid-capabilities) are excluded until the relevant phase provides a transport.

---

## Architecture — The Layer Cake

Each layer depends only on those below it, so the system builds and tests bottom-up.

```
┌─────────────────────────────────────────────────────────────┐
│ L6  Work distribution    load-aware dispatch, power-of-two,  │
│                          cross-node work-stealing            │
│ L5  Distributed OTP      global registry (CRDT + Merkle      │
│                          anti-entropy), dist supervisors,    │
│                          cross-node links/monitors           │
│ L4  Remote calls (RPC)   Node.call w/ CAS type-safety,       │
│                          location-transparent send/cast/call │
│ L3  Membership           SWIM failure detection, gossip,     │
│                          CRDT member set (full-state sync)   │
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
| **CAS** | (1) *Type/version safety on every remote call* — a remote function reference carries `sig_hash` + `impl_hash`; remote rejects on `sig_hash` mismatch (incompatible type) and applies policy on `impl_hash` mismatch (version skew). (2) *Peer code-shipping* (P6) — on `impl_hash` miss, fetch the `compilation_hash` artifact via the peer CAS tier and load it. (3) *Deterministic result memoization* (P6, opt-in) — a *provably* pure call's result is cacheable keyed by `(impl_hash, canonical_encode(args))`; requires a canonical encoding and an effect-system purity proof (see Risk 6 and Open Mechanism Questions). |
| **VectorClock** | Causally orders updates to the **registry and replicated config** — concurrent register/unregister/config-set on the same key — so convergence is deterministic and "who won" is well-defined. (`LWWRegister` already embeds a `VectorClock`.) *Not* used for membership: SWIM's per-node **incarnation** counter already orders join/suspect/alive/leave, and a full vector clock there would be redundant (see W2 in the review / Open Mechanism Questions). |
| **CRDT** | Holds all partition-tolerant replicated state: **OR-Set** member set, a **name→`{NodeId,Pid}` registry** and **per-node load gauges**. Note the registry-map and gauge are *composite CRDTs to be built* on the existing primitives (a map of `LWWRegister`s keyed by name, or an `ORSet` of entries; a gauge as an `LWWRegister(Int)` or `PNCounter`) — they are **not** existing modules (the stdlib ships only `GCounter`/`PNCounter`/`LWWRegister`/`ORSet`). The generic `CRDT(t)` interface drives a single sync loop that merges any peer's state without knowing the concrete type. |
| **Merkle** | Anti-entropy for the **registry** (potentially many names): two peers compare a root hash and `diff()` to reconcile only divergent entries — bandwidth independent of registry size. The **member set is small (O(N))**, so it uses plain full-state gossip, *not* Merkle — building a tree per round there would cost more than it saves. Merkle also verifies integrity of shipped CAS artifacts (P6). |
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
- **Handshake.** Mutual auth (mTLS, or shared cluster secret + signed challenge), then exchange `{NodeId, name, incarnation, compiler_identity, runtime_identity}`. The `compiler_identity`/`runtime_identity` fields are lifted verbatim from the CAS (`cas.ml`). A match is a **coarse precondition** for homogeneous calls — necessary but not sufficient: it does not establish that any *particular* function exists or agrees on both sides (that remains the per-call `impl_hash`/`sig_hash` check at L4), and a runtime mismatch does not strictly forbid an ABI-compatible call. Its real use is to flag *up front* that two nodes are likely to need code-shipping (P6) rather than discovering it per call.

## L2 — Net Kernel

- **One persistent authenticated connection per peer** (Erlang `dist` style), multiplexing every traffic class — process messages, RPC, monitor signals, gossip, CAS fetches — as tagged frames over a small set of logical channels.
- **Liveness must not be starved by payload (backpressure & head-of-line).** A single FIFO connection carrying both bulk `dispatch`/RPC payloads and gossip/heartbeats can head-of-line-block: a burst of large frames delays heartbeats, SWIM declares a *healthy but busy* node dead, and spurious failover cascades — and heavy dispatch is *exactly* when this happens. Mitigations, all in scope for P1:
  - **Prioritized lanes.** Heartbeat/gossip/monitor-signal frames travel on a high-priority lane that preempts bulk RPC/CAS-fetch frames (per-lane queues drained by priority, or a separate lightweight liveness connection/UDP path so a saturated bulk stream cannot delay a ping).
  - **Flow control.** Bounded per-peer send queues with credit-based backpressure; when a peer's bulk lane is full, `dispatch` to it fails fast (`Err(overloaded)`) and the L6 router re-selects — rather than buffering unboundedly.
  - **Frame-size cap + chunking** so one giant payload cannot monopolize the socket between heartbeats.
- This connection **is the peer CAS tier transport** (reconciliation #2): a `lookup_artifact` miss can be satisfied by fetching content-addressed bytes from a peer that has them, verified by `compilation_hash` (tamper-evident by construction). CAS fetches ride the bulk lane, never the liveness lane.

## L3 — Membership (SWIM + CRDT)

- **Failure detection — SWIM.** Periodic randomized direct ping; on miss, k-way indirect ping via random members; suspicion timeout → dead. Per-node **incarnation numbers** let a falsely-suspected node refute and rejoin.
- **State — CRDT (incarnation-ordered, *not* vector-clock-ordered).** The member view is a map `NodeId → {status, incarnation, load_gauge, meta}`. Merge is the standard SWIM rule — **higher incarnation wins; within the same incarnation, `dead > suspect > alive`** — which is associative/commutative/idempotent, i.e. a CRDT, and is the merge the generic `CRDT(t)` sync loop uses. Vector clocks are deliberately *not* used here: the single per-node incarnation counter already totally-orders that node's own state transitions, so a vector clock would be redundant weight. (Vector clocks earn their place one layer up, in the L5 registry, where independent keys genuinely need causal ordering.)
- **Anti-entropy — full-state gossip (no Merkle).** Gossip piggybacks member deltas on SWIM probes; periodic full-state push-pull reconciles stragglers. The member set is O(N) and small, so full-state exchange is cheaper than building a Merkle tree per round — **Merkle anti-entropy lives at L5 for the registry**, which can be large. The `CRDT(t)` merge makes reconciliation order-insensitive.
- **Tuning caveat (Risk 3).** Suspicion timeouts must be sized above worst-case GC stop-the-world and scheduler-preemption windows (`MARCH_QUANTUM_US`, signal-based 1 ms) or a paused-but-healthy node is falsely evicted.
- **Discovery.** Config-provided **seed nodes** for bootstrap (P2 minimal); full gossip dissemination thereafter. (External registry/DNS discovery is a later, optional alternative, not a v1 requirement.)
- **Hook to L5.** When a node is declared dead, every cross-node link/monitor to it fires `Down(noconnection)`.

## L4 — Remote Calls (RPC) — the safety core

A **remote function reference** is `{module, name, sig_hash, impl_hash}`, stamped at compile time, for a function the author has *enrolled* as a remote target (compiler emits its registry entry + marshalling stub — see the performance-insight section). `Node.call(node, fref, args, deadline)`:

1. Frame `{fref, msgpack(args), reply_ref, deadline}`; send over the net-kernel.
2. **Remote CAS check:** `sig_hash` mismatch → reply `TypeMismatch`. `impl_hash` match → the marshalling stub decodes args and invokes the local optimized native copy. `impl_hash` miss → `VersionSkew`, or (P6) fetch+load via the peer CAS tier.
3. Result/`Err` framed back. **Failure isolation:** deadline expiry, netsplit, or remote crash → `Err(timeout | noconnection | exit(reason))`; the caller never hangs.
4. **Sandboxing (P6):** foreign/shipped execution runs under a narrowed `Cap`.

- **Serializable arg/return types only.** Args and results round-trip through MessagePack, so a remote target's parameter and return types must be serializable. Closures are excluded until P6 (the closure's *function* must be shippable); linear/affine values need explicit move semantics (Risk 5); resource handles and pid-capabilities do not cross nodes. The compiler rejects an `enroll`/`remote_ref` on a function with a non-serializable signature.
- **Ordering guarantee — pairwise FIFO, nothing stronger.** Messages between a fixed (sender, receiver) pair over the single dist connection are delivered in send order (matching Erlang's pairwise guarantee). The design promises *only* this: `dispatch`/work-stealing may route equivalent work via different nodes, and concurrent `call` replies interleave, so users must not assume any global or cross-pair ordering. Stated explicitly so OTP habits don't import a guarantee that isn't here.
- **Result memoization (P6, opt-in, pure only).** Keyed by `(impl_hash, canonical_encode(args))` — note **canonical** encoding (default MessagePack is *not* canonical: map-key order and integer width vary), so the stub uses a canonicalizing encoder for memoizable targets. Soundness requires the function be *provably* pure (gated by the effect/capability system, not author assertion), and the cache store / eviction / coherence model is specified in P6 — until then this is a future item, not a P1–P5 guarantee.
- **Location transparency.** `send`/`cast`/`call` ride the same path. A global `Pid = {NodeId, local_pid, creation}` — where `local_pid` is the runtime's integer scheduler PID (`march_sched_find`) and `creation` distinguishes a restarted node's reused PIDs. **Prerequisite to validate (Risk/Open Question):** the surface actor handle must expose (or be convertible to) a serializable `{local_pid, creation}` — today actor handles may be heap references, so a serializable-pid representation is a P3 prerequisite, not an established fact. `march_msg_copy` semantics are preserved by re-encoding through MessagePack on the wire.

## L5 — Distributed OTP

- **Global registry.** `name → {NodeId, Pid}` as a **composite CRDT built for this purpose** — a map of `LWWRegister`s (each entry carrying a `VectorClock` for causal conflict resolution), or an `ORSet` of entries — gossip-replicated. Concurrent registrations of the *same* name are a genuine conflict; the resolution policy (LWW-by-incarnation vs. reject/error) is a P5 decision (Risk 4). **ConsistentHash** partitions authoritative ownership of names. Because the registry can hold many names, reconciliation uses the **Merkle anti-entropy** path (root-hash compare + `diff()`) — this is the layer where Merkle earns its keep.
- **Cross-node links/monitors.** Extend `march_link`/monitor over the net-kernel: remote process death → `Down(reason)`; failure-detector-declared node death → synthesized `Down(noconnection)` (standard OTP semantics).
- **Distributed supervisors.** A supervisor starts children on remote nodes via remote spawn, under the existing strategies (`one_for_one`/`one_for_all`/`rest_for_one`); restarts honor the registry + monitors across nodes.
- **Mixed-version messaging.** Every cross-node value carries `impl_hash`; wire-safety defers entirely to **HCR Part 6** (forward/backward compat, added-variant catch-all, `@compat`).

## L6 — Work Distribution (the headline)

- **Load publication.** Each node publishes load (run-queue depth from `march_scheduler`, reduction rate) as a gossiped **G/PN-Counter / LWW gauge** in the membership metadata.
- **`dispatch(fref, args)` target selection.** **ConsistentHash** for sticky/affinity routing, overridden by **power-of-two-choices** least-loaded selection over live members. The "Node A busy → Node B idle" case routes the `remote_call` to B, which runs its own native copy at full body speed.
- **Stale-load hazard (W5).** Gossiped load gauges lag reality by gossip-propagation delay, and power-of-two-choices on stale samples *herds* — every dispatcher piles onto whichever node looked idle several rounds ago. Counters, in scope for P4: (a) **decay/age** the gauge and treat older samples as more loaded; (b) the chosen node returns its *current* run-queue depth on the call (cheap piggyback) so the next decision is fresh; (c) the bounded send-queue backpressure from L2 makes an over-chosen node reject (`Err(overloaded)`) and the router re-selects. P2C is the policy; freshness is the thing that makes it correct.
- **Cross-node work-stealing.** An idle node pulls from a busy node's queue; the local queue is a **Deque** (O(1) both ends). Stealing is bounded by the same load gauges to avoid thrashing. *Note:* pull-based stealing is materially more complex than push-based `dispatch` (it needs a queue-exposure protocol and steal-victim selection); it may split into its own phase after the `dispatch` slice lands (see roadmap note on P4).

---

## Compiler Touchpoints

Almost everything is stdlib + runtime, but these points touch the compiler:

1. **Remote function reference + enrollment.** `remote_ref(Module.f)` (builtin/macro) lowers to `{module, name, sig_hash, impl_hash}`, reusing HCR Phase-2's `NAME_ID` interning and the Merkle `impl_hash`. *Enrolling* a target additionally emits (a) a **runtime registry entry** mapping the identity → a retained, DCE-pinned entry point, and (b) a **marshalling stub** (decode MessagePack args → typed values → invoke → encode result), with a compile-time check that the signature is serializable. This is the one genuinely net-new runtime mechanism — there is no function-by-identity registry today (confirmed: `runtime/` has none; HCR's dispatch table is proposed, not built).
2. **Merkle `did_hash` (P0).** The shared prerequisite — identical to HCR Phase 1. **Sharpened (M1):** `ADefRef` is currently *never constructed* in the pipeline (grep finds only consumers — `lower.ml:605`, `scc.ml:27`, `join_points.ml:43`), so populating `did_hash` may first require *emitting* `ADefRef` for cross-definition references, not merely setting a field on existing nodes. The P0 plan must verify the actual state of CAS call-graph integration before depending on it. Without this, `impl_hash` is not transitively sound and the type-safety guarantee is hollow.
3. **Dynamic artifact loading (P6 only).** Shipped code loads via HCR's Model A/B (trampoline/ORC), not `dlopen`. Not needed for the homogeneous path.

The capability sandbox (safety property 4) reuses the **existing Phase-1 capability system** (`needs X` / `Cap(X)`, `root_cap`/`cap_narrow`, runtime-erased) — `cap_narrow` produces the restricted token under which foreign work executes. No new capability mechanism.

---

## Phased Roadmap

Work distribution is pulled up: the vertical slice reaches the headline payoff after a *minimal* membership layer, with full CRDT registry / anti-entropy / distributed supervisors following. Each phase gets its own spec → implementation plan.

- **P0 — Shared CAS prerequisite** *(== HCR Phase 1; do once, both features depend on it).* Make `impl_hash` a true Merkle root: populate `ADefRef.did_hash` with callee `impl_hash`es over the topo-sorted SCCs — **first verifying whether `ADefRef` is even emitted today (it is not — see Compiler Touchpoint 2), which may enlarge this from "set a field" to "emit the cross-def references."** Add `TypeDef`s as graph nodes so type-layout changes propagate into dependents' hashes. Regression-test the cross-SCC-inlining stale-cache case. **Highest leverage; also fixes a latent stale-cache bug independent of distribution.**

- **P1 — Transport + net kernel (L1–L2).** Auth handshake, framed MessagePack, one-connection-per-peer multiplexing, identity exchange (incl. compiler/runtime digests), **prioritized liveness lanes + credit-based flow control + frame-size cap** (H3 — not deferrable, it gates correct failure detection under load). Test: two nodes handshake, exchange tagged frames, detect identity mismatch; a saturated bulk lane does not delay heartbeats.

- **P2 — Minimal membership (L3, just enough).** Seed-node join, SWIM liveness (direct + indirect ping, incarnations, incarnation-ordered CRDT merge), full-state member gossip, and load-gauge gossip. Defer the registry, Merkle anti-entropy, and distributed OTP to P5. Goal: every node has a live, load-annotated member view.

- **P3 — Remote messaging + RPC (L4).** **Serializable-pid representation (H5 prerequisite)**, global `Pid`, location-transparent `send`/`cast`/`call`, the **enroll/stub/registry mechanism (H1)**, `Node.call` with `sig_hash`/`impl_hash` verification, pairwise-FIFO delivery, and failure isolation. *Homogeneous, full native body speed.* Test: cross-node `call` returns correct result; `sig_hash` mismatch rejected; netsplit → `Err(noconnection)`; non-serializable signature rejected at compile time.

- **P4 — Work distribution (L6) — the headline.** Load-aware `dispatch`, power-of-two-choices with **freshness/decay + on-call load piggyback (W5)**, ConsistentHash affinity. **Cross-node work-stealing may split into P4b** (pull protocol is materially harder than push `dispatch`). Test: with Node A saturated and Node B idle, `dispatch` runs the call on B and beats local execution wall-clock; no herding under stale gauges.

- **P5 — Full distributed OTP (L5).** Composite registry CRDT (vector-clock-ordered per key) + **Merkle anti-entropy for the registry**, cross-node links/monitors, distributed supervisors, ConsistentHash name-partitioning, and the same-name conflict policy (Risk 4). Test: registered name resolves cluster-wide; concurrent same-name registration resolves per policy; remote actor crash fires `Down`; supervisor restarts a remote child.

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

1. **P0 soundness (shared with HCR).** Merkle `did_hash` must hash in a canonical, deterministic order or the type-safety guarantee silently corrupts. Reuse `serialize.ml`'s canonical encoding; test against cross-SCC-inlining cases. *Without P0, the headline "type-safe cross-node call" claim is unsound.* Also see M1: `ADefRef` may need to be *emitted*, not just populated.
2. **Liveness starvation under load (H3).** Without prioritized lanes + flow control, bulk `dispatch`/CAS traffic delays heartbeats and triggers false failover — worst exactly when the cluster is busiest. Addressed in P1, not deferrable.
3. **Global `Pid` identity & serializability (H5).** Two sub-risks: (a) the surface actor handle must be reducible to a serializable `{local_pid, creation}` at all (a P3 prerequisite, currently unverified); (b) the `creation` counter must make a restarted node's reused pids unambiguously stale — including how a peer learns the new `creation` on reconnect and rejects stale-stamped messages. Needs the rigor of Erlang's node-creation field.
4. **SWIM tuning.** False-positive detection under GC pauses / scheduler preemption (signal-based, 1 ms quantum) could evict healthy nodes; suspicion timeouts must account for `MARCH_QUANTUM_US` and GC stop-the-world windows.
5. **Registry same-name conflict semantics.** Concurrent registration of one name is a real conflict; LWW-by-incarnation silently drops a registrant, reject/error surfaces it. Policy decision for P5.
6. **MessagePack ↔ March value fidelity & canonical encoding.** Cross-node `send` must preserve everything `march_msg_copy` preserves; linear/affine values and closures need an explicit policy (linear values: explicit move only; closures: P6 code-shipping). Separately, *memoization* keys need a **canonical** encoding (default MessagePack is not canonical), or equal values hash differently.
7. **Result memoization correctness.** Only sound for *provably* pure functions; the effect/capability system — not author assertion — must gate which `fref`s are memoizable, else a cached impure result corrupts the cluster. Cache store/eviction/coherence is itself unspecified until P6.
8. **Message-ordering expectations (H4).** The design guarantees only pairwise FIFO; OTP code that assumes stronger ordering will be subtly wrong. Must be documented prominently, not just in the spec.
9. **Sandbox completeness (P6).** `cap_narrow` gates declared capabilities, but the C runtime FFI surface must have no un-gated escape hatch (raw socket/file builtins) reachable from foreign code.
10. **Interaction with epochs/atomic-RC under cross-node monitors.** Remote `Down` delivery vs. local epoch reclamation needs the rigor of `atomic-rc-design.md`.

---

## Open Mechanism Questions (resolve at plan time, before the dependent phase)

These are decisions the design deliberately leaves open; each blocks a specific phase, not the whole effort.

1. **Enrollment surface (P3).** Is a remote target opted in explicitly (`enroll`/`@remote` annotation) or implicitly by appearing in a `remote_ref`/`dispatch` site? The latter keeps the headline "any function the author names" promise; the former is more auditable. Either way it is *not* universal registration of every function.
2. **Serializable pid representation (P3).** What is the wire form of a `Pid`, and does the surface actor handle expose it? (Risk 3a.) Blocks location-transparent `send`.
3. **VectorClock vs. incarnation at the registry (P5).** Confirm vector clocks earn their place for per-key registry causality, or whether a simpler per-entry incarnation suffices there too (it does for membership — W2). Avoid using the primitive merely because it exists.
4. **Same-name registry conflict policy (P5).** LWW-drop vs. reject/error vs. multi-bind. (Risk 5.)
5. **Memoization purity oracle + cache substrate (P6).** Which effect/capability signal proves purity, and where does the cluster cache live (peer CAS tier? a dedicated CRDT?) with what eviction? (Risk 7.)
6. **Work-stealing protocol (P4/P4b).** Queue-exposure + steal-victim selection, or drop pull-stealing in favor of push-only `dispatch`?
