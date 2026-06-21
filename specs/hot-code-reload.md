# Hot Code Reloading — Design Spec

**Date:** 2026-06-18
**Status:** Draft (early — see § The Central Tension and § Phase 0 before committing to any production phase)
**Depends on:** the content-addressed store (`lib/cas/` — `cas.ml`, `pipeline.ml`, `scc.ml`, `hash.ml`, `serialize.ml`), LLVM codegen (`lib/tir/llvm_emit.ml`), JIT (`lib/jit/`), interpreter (`lib/eval/eval.ml`), Perceus RC + borrow inference (`lib/tir/perceus.ml`, `lib/tir/borrow.ml`), defunctionalization (`lib/tir/defun.ml`), epochs (`specs/epochs-design.md`), C runtime scheduler, `BastionHotDeploy`

---

## Motivation

March's `BastionHotDeploy` module handles zero-downtime *process* restarts: drain in-flight connections, swap the binary, resume. That is heavy for the common case — a developer fixes a handler bug or a business rule and wants it live in under a second with no connection drops, no drain, no restart.

Erlang has done this since 1989. The reason BEAM can do it cheaply is that **its modules are independently-compiled, dynamically-dispatched units** — there is no cross-module inlining or whole-program specialization to undo. March is the opposite: its performance comes from *whole-program* optimization (monomorphization, defunctionalization, Perceus RC, borrow inference, LTO), all of which cross module boundaries. That is exactly the property hot reload must give up at the boundary.

But March already has the machinery to do this *well*, in a place the first draft of this spec under-used: the **content-addressed store** (`lib/cas/`). The CAS is not a cache directory. It is a per-SCC, dual-hash, two-tier, content-addressed build store. Designed correctly, it is the natural substrate for hot reload — it already answers "what is the minimal unit of change," "is this change interface-compatible," "what exactly changed since the running version," "where do I get the artifact," and "how do I roll back." This rewrite makes the CAS the spine of the design instead of a side cache.

The honest conclusion is unchanged from the first draft: the **interpreter-trampoline** path is correct and shippable near-term; the **native-JIT** path is a research project gated on a spike (§ Phase 0). What changes is that *both* paths now ride the CAS for everything except the actual code-execution mechanism.

---

## The Central Tension: Whole-Program Optimization vs. Module Isolation

Hot reload requires (re)compiling and swapping a unit of code *independently* of its callers. Four whole-program passes make that unsound if done naively. Every decision below is downstream of these.

### 1. Monomorphization
Generics are specialized per concrete type across modules. A swappable boundary call cannot be specialized into the caller — the boundary needs a fixed (boxed / dictionary-passing) convention. Tolerable: app handlers are almost always concrete (`Router.handle(conn : Conn) : Conn`).

### 2. Defunctionalization (the unsolved one)
Defun (`lib/tir/defun.ml`) lowers all closures to a global tag → `apply` dispatch with a closed tag set. **A reloaded unit that introduces a new lambda shape flowing into a defunctionalized call site has no arm in the already-running `apply`.** You cannot add a `match` case to live native code. The only tractable native option is to not defunctionalize across the boundary (closures stay heap objects with a real, versionable function pointer) — itself a deoptimization. This is why the native path is "research, not engineering," and the CAS does **not** fix it (it tells you cheaply *what* changed; it does not make a new-closure native swap safe).

### 3. Perceus RC + borrow inference (soundness, not just speed)
Borrow inference (`lib/tir/borrow.ml`) decides per call site whether caller or callee drops a value and whether an argument is borrowed. If the new version's borrow signature differs from what the running caller compiled against, the RC protocol mismatches → **double-free or leak**. So the borrow/RC contract must be *frozen* at the boundary. Cost: per [todos.md](todos.md) borrow elision "eliminates 100% of RC overhead for read-only middlewares (HTTP `Conn` pattern)" — exactly the boundary. **Enabling reload across that boundary forfeits the single most important RC optimization for web handlers.** (As § Part 1 shows, the CAS's Merkle `impl_hash` makes this contract *checkable* rather than something to bolt on — but the cost is real and must be measured, not assumed.)

### 4. Global type namespace + structural record layout
App types are global; records are laid out with fields sorted alphabetically (`get_record_fields` in `lib/tir/llvm_emit.ml`; see [actor-lowering.md](actor-lowering.md)). Changing a record type's fields changes its GEP layout for **every** module using it, including non-recompiled callers. So "add a field" is only sound for a type *private* to the reloaded unit. The CAS can enforce this mechanically **iff** type definitions are nodes in the dependency graph (§ Part 1, prerequisite).

### Consequence
A binary that *can* reload across a boundary is permanently slower across that boundary than one that cannot — regardless of whether a reload ever happens — because the boundary forfeits inlining, specialization, defun, and borrow elision. The user's goal is hot reload *in production*, which means running the slower boundary in production. The design owns that tradeoff; it does not hide it.

---

## Two Execution Models

Both share everything in this spec *above the call boundary* — CAS substrate, reload unit, deploy flow, signing, actor migration — and differ only in how reloaded code runs.

- **Model A — interpreter trampoline (near-term, correct).** A dispatch slot points either at native code (AOT default) or at a trampoline that marshals the native ABI into interpreter values, runs the reloaded definition in `lib/eval/eval.ml`, and marshals back. Sidesteps defun (#2), the borrow ABI (#3 — marshalling copies into interpreter-owned values), and eases migration (#4 — dynamic values). Cost: interpreter speed (≈10–100× slower) until the next full build. Correct and shippable; the production default until Phase 0 succeeds.
- **Model B — native JIT (research).** Reloaded SCCs are JIT-compiled and swapped. Fast, but only sound if #2 and #3 are solved. **Not scheduled past § Phase 0** until a prototype demonstrates a cross-boundary swap with (a) a new closure shape and (b) a borrowed `Conn` parameter, with zero double-frees under ASan and no defun fault.

The hybrid target: a changed unit runs as a trampoline immediately (instant, correct, slow) and is *upgraded* to JIT-native in the background once it compiles cleanly — both keyed in the CAS by the same `impl_hash`.

---

## Non-Goals

- Hot-reloading the **runtime** (`runtime/*.c`), **stdlib**, or **dependencies** — never on the boundary; always direct-called and fully optimized; changes require a restart.
- **Interface-incompatible changes** that escape the reloadable boundary (a changed `sig_hash` reaching stdlib or a frozen export) — rejected; restart handles them.
- **Persisting hot reloads across a process restart** — a crash/restart reverts to the AOT baseline (surfaced and reconciled, § Part 8, not hidden).
- **WASM target.**
- **Model B in production before § Phase 0 succeeds.**

---

## Architecture (CAS-native)

```
┌──────────────────────────────────────────────────────────────────────┐
│  forge deploy hot                                                    │
│  1. build → hash SCCs (Merkle impl_hash, types in graph)            │
│  2. reload set = {new impl_hashes} \ {running impl_hashes}          │
│  3. safety gate = per-changed-def sig_hash comparison               │
│  4. ensure artifacts reachable in server CAS chain (tiers)          │
│  5. sign activation request   6. send (name, impl_hash) activations │
│  7. await acks                8. record active set                   │
└─────────────────────────┬────────────────────────────────────────────┘
                          │  Unix socket (local) / SSH-tunneled
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Reload server (background fiber, pinned thread)                     │
│  resolve artifact by compilation_hash from CAS (local→global→remote)│
│  verify signature + compiler identity (already in the CAS key)      │
│  verify sig_hash compatibility for the changed SCC(s)               │
│  Model A: install interpreter trampoline   Model B: load JIT native │
│  publish new version (= impl_hash) into the dispatch slot           │
│  retire old version via epoch reclamation; Cas.gc bounds retention  │
└─────────────────────────┬────────────────────────────────────────────┘
                          │  dispatch slot: name → active impl_hash → code
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Running application                                                 │
│  In-flight calls pinned to the version they entered                 │
│  New calls see the new version; rollback = re-activate prior hash    │
│  Actors: per-actor versioned handler; migrate_state runs BEFORE      │
│          any new-version handler executes (§ Part 5)               │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: The CAS as the HCR Substrate

This is the spine. Read it before the parts that project from it.

### What exists today (`lib/cas/`)

- **Per-SCC granularity, topological order.** `pipeline.ml` groups TIR functions into strongly-connected components (`scc.ml`, Tarjan), hashes each, and on a cache hit skips `mono → defun → llvm` entirely. SCCs are returned dependencies-first.
- **Dual hash per definition** (`hash.ml`): `sig_hash = BLAKE3(signature)` and `impl_hash = BLAKE3(sig_hash ++ full body)`. A body change moves `impl_hash` while leaving `sig_hash` stable.
- **Artifact key carries identity** (`cas.ml`): `compilation_hash = BLAKE3(impl_hash ++ target ++ compiler_identity ++ runtime_identity ++ flags)`. Compiler and runtime digests are *already* mixed in — a cache hit cannot cross compiler or runtime versions.
- **Two-tier store with read-through warming**: project-local `.march/cas/` over global `~/.march/cas/`; `lookup_def` warms local from global.
- **Persistent `name → def_id` index** and **`gc` with keep-sets** (`cas.ml`).

### The reload unit is the SCC, not the module

A module has many SCCs; an SCC is the *minimal* sound reload unit. Consequences:

- **Surgical reloads.** Change one function → reload one `Single` SCC, not the whole module.
- **Mutual recursion is atomic by construction.** Mutually-recursive functions live in one `Group` SCC and reload together; there is no partial-update window.
- **Cross-SCC order is a DAG.** `compute_sccs` already yields topological order, so multi-SCC reloads have a well-defined sequence. *This dissolves the first draft's "cyclic hot-reload dependencies" open question entirely.*

### Version identity is the `impl_hash`

A function's running version *is* its `impl_hash`. The runtime dispatch slot (§ Part 2) is keyed by name and tagged by `impl_hash`; the CAS `name → def_id` index is its source of truth. This eliminates the first draft's fragile source-order integer IDs: content hashes never shift when unrelated code is edited.

### The safety gate is a `sig_hash` comparison

Per changed definition:

- **`sig_hash` unchanged, `impl_hash` changed** → body-only change → **hot-swappable in place** (the calling convention callers compiled against is unchanged).
- **`sig_hash` changed** → interface change → it must propagate to dependents. If the propagation stays within the reloadable boundary, reload the affected SCCs together (topological order). If it reaches a non-reloadable boundary (stdlib, a frozen export, the runtime), **reject** → fall back to `forge deploy`.

This replaces the first draft's hand-written, per-module "allowed/rejected" ABI table (old Part 7) with a mechanical, per-definition rule the compiler already has the hashes for.

### "What changed" is an `impl_hash` set-diff

The running process knows its active `impl_hash` set (those are the CAS keys it loaded) and can report it on the reload socket. The deploy diff is then:

```
reload_set = { impl_hash of each SCC in the new build } \ { active impl_hashes in the process }
```

No source-text diffing, so no false positives from reformatting or line moves — a function whose bytes are unchanged produces the same `impl_hash` and is not reloaded.

### Distribution is CAS tiers, not a bespoke protocol

The two-tier store *is* content-addressed dedup distribution. A fleet adds a third, remote tier (a content-addressed registry — `s3://…` / `https://…`) above global; each server read-through-warms on demand. `forge deploy hot` does not invent a shipping protocol — it ensures the needed `compilation_hash`es are reachable in the server's CAS chain, then sends activations. A server that already has the artifact (from a prior deploy) transfers nothing.

### Versioning, rollback, and GC are inherent

Artifacts are immutable and content-addressed, so **every version ever built remains addressable**. Rollback = re-activate the prior `impl_hash` (still in the CAS). Retention is bounded by `Cas.gc` keep-sets: `keep_artifacts = active impl_hashes ∪ versions pinned by in-flight calls` (§ Part 3).

### PREREQUISITE (highest-leverage work in the codebase): Merkle `did_hash` + types in the graph

The serializer is already built for this: `serialize.ml:166` writes **only `did.did_hash`** for an `ADefRef` ("name excluded for content-addressing"), and `tir.ml:30` documents `did_hash` as the callee's BLAKE3 `impl_hash`. **But nothing populates `did_hash` with a real callee hash** (only type decls and comparisons reference it). Two problems follow, and both must be fixed before the CAS can carry HCR:

1. **Latent stale-cache bug, independent of HCR.** `compile_scc` keys on the SCC's *local* `impl_hash`. The optimizer inlines across SCCs (`known_call`, inline threshold 50), so changing callee B does not change inliner A's hash → a cache hit can serve A with an old inlined B.
2. **HCR cannot compute a correct blast radius** without transitive hashing.

**Fix:** add a bottom-up pass over the already-topo-sorted SCCs that sets each `ADefRef.did_hash = callee.impl_hash` before hashing, making `impl_hash` a true Merkle root. Then:

- A change's reload set is **exactly** the defs whose Merkle `impl_hash` moved — minimal and correct.
- **Borrow/RC ABI stability (Central Tension #3) is subsumed.** Borrow inference is deterministic in (own impl + callee sigs); Merkle-`impl_hash` stable ⟹ borrow output stable. The separate "frozen borrow ABI hash" the first draft proposed is unnecessary.
- **Shared-type layout (Central Tension #4) becomes a hash comparison** *iff* `TypeDef`s are added as nodes in the dependency graph (they are already a `def_kind` in `cas.ml`; `compute_sccs` currently walks `tm_fns` only). With types in the graph, a layout change flips dependents' Merkle hashes automatically, turning the "reject if a shared type changed layout" gate into the same `sig_hash`/`impl_hash` machinery as everything else.

Without this prerequisite, HCR safety claims are unsound. With it, the CAS *is* the ABI checker, the diff engine, the distribution layer, and the version store.

---

## Part 2: The Boundary & Dispatch Table

### The flag

```bash
forge build                    # direct calls, full LTO/O3 — not reloadable, fastest
forge build --hot-reload       # versioned dispatch on the boundary — reloadable, slower boundary
forge bastion server           # implies --hot-reload (dev)
```

**Honesty about `--release`:** a fully-optimized binary is *not* reloadable. Hot reload in production means shipping `--hot-reload` and accepting the boundary deoptimization (§ Central Tension). There is no "reloadable and maximally optimized across the boundary" build; § Phase 0 measures how large the gap is.

### Boundary detection (auto, with overrides)

Default: every `.march` under `src/` is reloadable; module prefix derives from `[package] name` (e.g. `my_app` → `MyApp.*`), reusing `module_name_to_filename` in `bin/main.ml`. Stdlib, deps, and runtime are never reloadable. `forge hot-reload modules` prints the computed boundary and the reason each module is in/out. Optional `[hot-reload]` `include`/`exclude` in `forge.toml` overrides; `forge hot-reload init` suggests excluding rarely-changed modules (which keep full optimization) from git history.

### What changes in LLVM emit

A boundary→boundary call resolves the active version through the dispatch slot, pinning the caller to that version for the call:

```llvm
%fn = call ptr @march_dispatch_enter(i32 NAME_ID)   ; reads active version, pins it (refcount++)
%r  = call i64 %fn(ptr %conn)
       call void @march_dispatch_leave(i32 NAME_ID)  ; unpins (refcount--)
```

`NAME_ID` is a stable, name-interned index (resolved at startup from the CAS index), **not** a source-order integer. The *version* a slot points at is identified by `impl_hash`. `enter`/`leave` (not a bare load) are required for correct reclamation (§ Part 3).

Direct (non-indirect, inlinable) calls: boundary→stdlib, boundary→excluded module, and intra-SCC. Only boundary→boundary crosses the table. **Boundary→boundary must be a no-inline edge** — otherwise inlining would defeat independent swap; this is the runtime counterpart of the Merkle requirement in Part 1.

### Polymorphic exports on the boundary

A genuinely polymorphic exported function on the boundary cannot be monomorphized into callers; the compiler warns and uses dictionary-passing, or the author marks it module-private. Most handlers are concrete and unaffected.

---

## Part 3: Versioning, Reclamation & Rollback

### Per-version slots

Each dispatch slot holds a small ring of versions, each tagged by `impl_hash`, each with its own refcount:

```c
typedef struct {
    _Atomic(void *)   fn_ptr;     // native code or trampoline thunk
    _Atomic(uint64_t) refs;       // callers currently pinned to THIS version
    char              impl_hash[64];
    uint8_t           kind;       // MARCH_NATIVE | MARCH_TRAMPOLINE
} MarchFnVersion;

typedef struct {
    _Atomic(uint32_t) current;                          // live version index
    MarchFnVersion    ring[MARCH_MAX_LIVE_VERSIONS];    // small, e.g. 2 (BEAM-style old+current)
} MarchDispatchSlot;
```

`march_dispatch_enter` reads `current` (acquire), increments that version's `refs` (RMW), returns its `fn_ptr`; publication of a new version uses release ordering so a caller is always pinned to the version it actually runs. `leave` decrements the same version.

### Reclamation via epochs + Cas.gc

A retired version is freed only after its `refs` hits zero **and** a grace epoch has elapsed with no thread holding a pointer into it (reuse [epochs-design.md](epochs-design.md)). Closures captured from old-version code carry their version and keep it pinned, so a captured callback cannot outlive its code. On-disk retention is bounded by `Cas.gc` with `keep_artifacts = active ∪ in-flight-pinned impl_hashes`.

### Version cap + purge (Erlang's lesson)

Long-lived connections (WebSocket/SSE/streaming) can pin an old version for hours; unbounded, a day of deploys never reclaims. So: **at most `MARCH_MAX_LIVE_VERSIONS` per slot (default 2).** A reload that would exceed the cap triggers a **purge** — fibers/actors/connections still pinned to the oldest version are terminated (connection closed, actor restarted via supervisor) so it can be freed. Surfaced loudly: `forge deploy hot` prints `purge: 3 long-lived connections on MyApp.WS will be closed — proceed? [y/N]` and reuses `BastionHotDeploy` drain for the affected sockets only.

### Rollback

Because the prior artifact is still content-addressed in the CAS, rollback (manual or `--canary` health-triggered) is a hot reload that re-activates the previous `impl_hash`. No rebuild, no separate artifact store.

---

## Part 4: The Reload Server

A background fiber, started when `MARCH_HOT_RELOAD_SOCKET` is set (auto for `forge bastion server` and during deploys), **pinned to one OS thread** — required on macOS because `pthread_jit_write_protect_np` toggles thread-local W^X state and the M3 worker pool migrates fibers across threads ([atomic-rc-design.md](atomic-rc-design.md)); a migrating reload fiber would corrupt W^X. Pin the fiber and all JIT codegen to a dedicated thread.

### Protocol (length-prefixed binary; Unix socket / SSH-tunneled)

An **activation** request carries: magic, protocol version, definition name, target `impl_hash`, and an ed25519 signature over the payload. The artifact itself usually does **not** travel on this socket — it is already reachable in the server's CAS chain (§ Part 1 distribution); the request just names which content to activate. (For a cold server, the artifact can be streamed as a fallback.) Response: status (`ok | bad_signature | compiler_mismatch | sig_incompatible | missing_artifact | purge_required`), the activated `impl_hash`, and a message. The socket also answers `abi_query` (active `impl_hash`/`sig_hash` set, compiler digest) and `versions` (effective baseline-vs-hot map for § Part 8).

### Preconditions (hard gates, in order)

1. **Signature** verifies against the embedded public key.
2. **Compiler identity** matches — and this is *free*: the artifact's `compilation_hash` already includes `compiler_identity` + `runtime_identity` (`cas.ml`), so a mismatched build simply has no matching artifact in the CAS.
3. **`sig_hash` compatibility** for the changed SCC(s) per Part 1 (body-only, or interface change contained within the boundary).
4. **Version cap / purge** consent if needed.

### Loading mechanism — pick ONE per platform

LLVM ORC JIT produces in-memory symbols, **not** an ELF `.so` — so do not mix ORC with `dlopen` (the first draft conflated them). This spec uses **ORC end-to-end** for Model B on both platforms: feed the CAS bitcode to ORC (reuse `lib/jit/`), which allocates executable memory itself (macOS via `MAP_JIT` + the toggle, on the pinned thread), resolve the SCC's symbols, publish their pointers into the version ring. External references (dispatch table, runtime, stdlib) resolve against the main image, so the **main build** must export those symbols (`-rdynamic` / `--export-dynamic` on Linux; keep them un-stripped on macOS) — a Phase-1 main-build change. macOS hardened runtime needs the `com.apple.security.cs.allow-jit` entitlement (usually moot for un-notarized servers; documented regardless).

**Model A (trampoline)** uses no executable memory: the slot points at a static native thunk that calls the interpreter with the SCC's freshly parsed+typechecked AST. This is why Model A is the safe default — it touches none of the JIT/W^X machinery.

### Timing

Model A install = parse + typecheck + publish (a few ms, no codegen). Model B JIT of one SCC ≈ 20–200 ms on the pinned thread; serving is unaffected (old version stays live until publish). Model B uses O2; the gap vs the AOT O3+LTO baseline is measured by § Phase 0, on top of the permanent boundary deoptimization — no single tidy percentage is quoted.

---

## Part 5: Actor State Migration (ordering corrected)

### The race the first draft had

A reloaded SCC may change an actor's state type. A *global* dispatch swap followed by an *async* `{:hot_reload}` message means that, between swap and the actor draining that message, the actor runs **new handler code against old-typed state** — exactly the corruption migration exists to prevent.

### Fix: per-actor versioned handler, migrate-before-run

Actor handler dispatch is **not** the global table; each actor carries the code version it runs. A reload does not change a running actor's version. Instead the runtime schedules a migration step that executes **as the actor's next turn, before any new-version handler runs**: it calls `migrate_state(old_state) : NewState`, atomically swaps *that actor's* handler version together with its migrated state, then resumes the mailbox. Because version swap and state migration happen in one uninterrupted turn, a new-version handler never sees old-typed state. Un-migrated actors keep running old code against old state — consistent, just not yet upgraded.

### Soundness gate (from Central Tension #4, now CAS-checked)

`migrate_state` may only change types **private** to the reloaded unit. With `TypeDef`s in the Merkle graph (§ Part 1 prerequisite), a layout change to a *shared* type flips the `impl_hash`/`sig_hash` of every dependent, including non-reloadable ones — so the standard `sig_hash` gate rejects the reload automatically. No special case.

```march
mod MyApp.Counter do
  type State = { count : Int, history : List(Int) }   -- v2 added `history`; State is module-private

  fn migrate_state(old : RawRecord) : State do
    { count = RawRecord.get_int(old, "count"), history = Nil }
  end

  fn init() : State do { count = 0, history = Nil } end
  fn handle(state : State, msg : Msg) : State do … end
end
```

`RawRecord` is a runtime-only, type-erased accessor (constructable only by the runtime, panics on missing/mistyped fields). Absent `migrate_state`: `forge deploy hot` requires an explicit choice — restart affected actors via supervisor (state lost, serving uninterrupted) or abort the reload for that unit. A migration panic → supervisor restarts that actor from `init()`; others continue.

---

## Part 6: Type-Level Migration Guardrails

Everything so far makes a reload *safe at the boundary* via frozen contracts and runtime gates (`sig_hash` comparison, purge, migrate-before-run). The type system can go further and prove, *before* deploy, that a data-structure or protocol change is safe to put on the wire — including the hardest case you raised: a value produced by new code reaching a node still running old code.

### The name for this

This is **schema evolution**, and the property "a record only adds fields, safe to pass to nodes running old code" is **forward compatibility** (old code reads new data). Its dual is **backward compatibility** (new code reads old data); both together is **full compatibility** (Avro/Protobuf terminology). The type-theoretic machinery is **record width subtyping** / **row polymorphism**; the protocol analogue is **session-type subtyping** (Gay–Hole); and the overall discipline of a compiler giving static guarantees about live update is **type-safe Dynamic Software Updating (DSU)** (Stoyle et al., *Mutatis Mutandis*; Neamtiu/Hicks, *Ginseng*), whose core notions are **version consistency** and **con-freeness**.

### Two regimes (they need different guarantees)

- **Intra-node reload.** After `migrate_state`, only new code runs → only **backward** compatibility is required (the migration is total over the old value), checkable directly against the prior type in the CAS.
- **Mixed-version cluster (rolling upgrade).** Old and new nodes coexist and exchange messages → **forward** compatibility is *also* required, because an old node receives a new-shaped value. This is the regime the "pass to nodes running old code" question targets, and the one that needs the subtyping story.

### The variance duality (what makes this mechanizable in March)

Because March is built on ADTs + exhaustive `match`, records and variants evolve with *opposite* variance, and the compiler can check both:

| Edit | Old node reading the new value (forward) | Why |
|---|---|---|
| Add a record field | ✅ safe | width subtyping: old reader ignores the extra |
| Remove a record field | ❌ | old reader still expects it |
| Change a field's type | ❌ unless widening | not a subtype |
| **Add a variant case** | ❌ *unless every deployed matcher has a `_` arm* | a sum with more cases is a *supertype*; consumers are contravariant |
| Remove a variant case | ✅ for old readers | they simply never receive it |

The "added constructor ⇒ all live matchers must tolerate the unknown case" rule is something only a language with compiler-checked exhaustiveness can enforce, and it is precisely a hot-reload guardrail for actor *messages*.

### The mechanism: the CAS is the schema oracle

Once `TypeDef`s are nodes in the Merkle graph (§ Part 1 prerequisite), the compiler has the **previously deployed version of every type**. So at `forge deploy hot`:

1. **Diff + classify.** Structurally diff each boundary / message / actor-state type against its prior CAS version; classify every change by the table above; reject forward-incompatible edits with a targeted error, e.g.
   > `MyApp.Msg`: added constructor `Archive`, but receivers `Inbox.handle` (v7, still running) have no fallback arm — add `_ -> …` or restart. *(forward-incompatible)*
2. **Declared policy, enforced.** Protobuf-`reserved`-style intent, type-checked against the CAS prior version:
   ```march
   @compat(forward) type Msg   = ...    -- reject any edit unreadable by old nodes
   @compat(full)    type State = ...    -- both directions
   ```
3. **Structural forward-safety for free, via row polymorphism.** If message handlers are typed over open rows `{ known | ρ }`, "add a field" is forward-safe *by construction* with no annotation — the principled form of Protobuf's "ignore unknown fields." (Row polymorphism is already on the backlog; this is a strong motivating use case.)
4. **Protocol evolution via session subtyping.** For actor *calls*, the conversation is itself a type (`Send`/`Recv`/`SRec`). Checking that the new actor's session type is a **subtype** of the deployed one (accepts ≥ messages, emits ≤) proves it can be dropped into a live exchange — the protocol-level analogue of width subtyping.

### Sums: named fields in variants would complete the story

The forward-safe "add a field" guarantee is a *record* (product) property. March variant payloads are **positional** (`Circle(Float)`), and anonymous records inside variants are not yet supported (see the HTTP library spec), so today a constructor's payload cannot evolve field-by-field — adding an argument to an existing constructor is breaking. **Adding named fields in variant payloads (a planned language feature, sibling to row polymorphism) would extend the safe-evolution story to sums:** a constructor `Circle { radius : Float }` could then gain `Circle { radius : Float, stroke : Option(Color) }` under the same width-subtyping rule that makes record field additions forward-safe, instead of forcing a new constructor (which, per the table above, is forward-*incompatible* for old matchers). Until then the guardrails cover record evolution field-precisely and variant evolution only at constructor granularity (add/remove case).

### Honest limits

- **Width subtyping is a wire guarantee only if serialization preserves unknown fields** (Protobuf unknown-field retention). If an old node deserializes a new record, drops the field it doesn't know, and re-emits, a round-trip silently loses data. The type rule must be paired with a retain-unknowns serialization discipline.
- The compiler can *force* a catch-all arm for an added variant case but cannot supply the semantics for the unknown case — that stays the author's job.
- These guardrails shrink the *blast radius* a reload may legally have; they do not remove the § Central Tension costs of the boundary itself.

---

## Part 7: `forge deploy hot`

```bash
forge deploy hot [target] [--env <name>] [--dry-run] [--no-migrate]
                 [--force] [--canary <n>] [--timeout <ms>]
```

CAS-native workflow:

1. **Build** the project with `--hot-reload`; the CAS hashes all SCCs (Merkle `impl_hash`, types in graph).
2. **Diff**: `abi_query` the running process for its active `impl_hash` set; `reload_set = new \ active` (§ Part 1).
3. **Gate**: for each changed def compare `sig_hash` (§ Part 1); anything escaping the boundary → fall back to `forge deploy`.
4. **Distribute**: ensure each reload-set `compilation_hash` is reachable in the server's CAS chain (local → global → registry); transfer only what's missing.
5. **Sign + activate**: send `(name, impl_hash)` activations, sequentially in topological SCC order; await acks.
6. **Record** the new active set; detect drift on reconnect (§ Part 8).

`--canary <n>` activates on `n` servers first, watches health, then rolls out or rolls back (rollback = re-activate the previous `impl_hash`, already in CAS).

---

## Part 8: Crash-Restart Reconciliation

Hot-reloaded code lives only in process memory; a crash/OOM/restart returns on the **AOT baseline binary**, silently dropping every hot patch. This is surfaced, not hidden:

- The process answers `versions` on the reload socket and on the `BastionDev`/health endpoint with its effective per-name map (baseline `impl_hash` vs hot-reloaded `impl_hash`). "What is actually running here" is queryable.
- `forge deploy hot` records the *intended* hot set per server. On reconnect after a restart it detects baseline-vs-intended drift and re-applies pending activations (or reports them under `--dry-run`).
- Operational guidance for the docs, prominently: **hot reload bridges the gap between deploys; it does not replace one.** Promote a hot fix to a real `forge build --release` + `forge deploy` within the same cycle so a restart converges to a binary that already contains the change.

---

## Part 9: Security

The reload socket activates executable code; treat it as the highest-value attack surface.

1. **Mandatory ed25519 signing.** Public key embedded at build time; private key only on the build/CI machine. Unsigned/unverified activations are rejected before anything loads.
2. **Compiler-identity gate, free via the CAS key** (§ Part 4) — doubles as downgrade/confusion defense.
3. **Content integrity, free via content addressing.** An activation names an `impl_hash`/`compilation_hash`; a tampered artifact does not match its CAS path, so it cannot be activated.
4. **Socket exposure.** Default Unix socket, mode `0600`, owner-only; remote only via SSH tunnel. Optional mTLS TCP bound to localhost/private interface, never `0.0.0.0`; mTLS certs distinct from the signing key.
5. **Operational risk, stated plainly.** Larger RCE surface than ordinary deploy — no restart, possibly no orchestrator audit trail; a CI/signing-key compromise yields silent, persistent injection. Mitigations to document: signing key in HSM/KMS; signed+reviewed artifacts; append-only audit log of every activation (name, `impl_hash`, signer, time); a kill switch (`forge hot-reload disable` / unset `MARCH_HOT_RELOAD_SOCKET`). Include a "when NOT to enable this."

---

## Part 10: Performance

The first draft's "1–4 ns/call" and "5–15% O2 vs O3" were fabricated and, given § Central Tension, optimistic. The honest structure:

- **Non-reloadable build (`forge build` / `--release`):** unchanged from today; no dispatch table.
- **Reloadable build, boundary calls, even with no reload performed:** pays (a) an indirect, non-inlinable call, (b) lost cross-module specialization, (c) lost defun across the boundary if Model B's no-defun scheme is used, and (d) **lost borrow/RC elision** — for the `Conn` middleware path, (d) dominates, not the pointer chase. Aggregate is **TBD, measured by § Phase 0** on `bench/list_ops.march` and a Bastion request bench. No single number until measured.
- **Reloaded function, Model A:** interpreter speed (≈10–100× slower); fine for I/O-bound handlers, not for hot loops — hence the JIT upgrade.
- **Reloaded function, Model B (O2):** near-native but below AOT O3+LTO, and still inside the deoptimized boundary; magnitude TBD by Phase 0.
- **Memory:** bounded by `MARCH_MAX_LIVE_VERSIONS` (default 2) + purge (§ Part 3) + `Cas.gc`. A typical SCC artifact is small; worst case is a small constant multiple, not unbounded.

---

## Part 11: Failure Modes

| Situation | Behavior |
|-----------|----------|
| Signature invalid | reject pre-activation, log WARNING, process untouched |
| Compiler-identity mismatch | no matching CAS artifact; reject, instruct to rebuild |
| `sig_hash` change escapes the boundary | reject at deploy or activation; suggest `forge deploy` |
| Artifact missing from server CAS chain | `missing_artifact`; transfer then retry (or stream fallback) |
| Compile/typecheck error | reject; old version keeps running |
| Reload exceeds version cap | `purge_required`; prompt to close long-lived connections, else abort |
| `migrate_state` panics | supervisor restarts that actor from `init()`; others continue |
| Long-lived connection pins old version | kept alive until the cap forces a purge (§ Part 3) |
| Process restart after hot reloads | reverts to baseline; drift detected and re-applied (§ Part 8) |
| Socket unreachable | clear error; fall back to `forge deploy` |

---

## Phase 0 (MANDATORY before any Model B production work)

A throwaway spike answering the only question that matters: *can March swap native code across a boundary without corrupting memory or faulting defun?*

1. Two app modules with a boundary call passing a `Conn`-style **borrowed** record.
2. Freeze the borrow/RC ABI at the boundary (validated by stable Merkle `impl_hash` per § Part 1); hot-swap the callee; run under ASan across thousands of requests → **zero double-frees, zero leaks**.
3. Introduce a **new closure shape** in the swapped module flowing through the boundary (`HttpServer.plug`-style) → show the per-module local-apply / no-defun scheme handles it with **no defun fault**, or conclude Model B must not defunctionalize the boundary and measure that cost.
4. Measure the boundary deoptimization (§ Part 10).

Deliverable: a go/no-go on Model B with real numbers. Model A needs no spike and proceeds in parallel.

---

## Implementation Plan (CAS-native, trampoline-first)

### Phase 1 — CAS prerequisite (highest leverage; also fixes a real stale-cache bug)
- Merkle-populate `ADefRef.did_hash` via a bottom-up pass over the topo-sorted SCCs (`pipeline.ml`/`scc.ml`), so `impl_hash` is a true Merkle root.
- Add `TypeDef`s as nodes in the dependency graph so type-layout changes propagate into dependents' hashes.
- Regression test the cross-SCC-inlining stale-cache case directly (independent of HCR).

### Phase 2 — Boundary + versioned dispatch (compiler + main-build)
- `--hot-reload` in `Llvm_emit`; boundary detection (`src/` + `[hot-reload]`).
- `march_dispatch_enter`/`leave` with the per-version ring (§ Part 3); name-interned `NAME_ID`; version = `impl_hash`; boundary→boundary as a no-inline edge.
- Main-build symbol export (`-rdynamic` / un-stripped) for later JIT resolution.
- `forge hot-reload modules`; test: reloadable binary behavior-identical to non-reloadable; record the boundary cost.

### Phase 3 — Model A: interpreter trampoline (shippable milestone)
- Reload-server fiber (pinned thread), `MARCH_HOT_RELOAD_SOCKET` gate, signed activation protocol, `abi_query`/`versions`.
- Trampoline thunks: native ABI ↔ eval values, installed per SCC; published into the version ring.
- Epoch reclamation + version cap + purge, tied to `Cas.gc` keep-sets.
- End-to-end: hot-reload a Bastion handler, interpreted, zero dropped connections.

### Phase 4 — `forge deploy hot` (CAS-native)
- `impl_hash` set-diff against the running process; `sig_hash` safety gate; distribution via CAS tiers (local→global→registry); topological activation; ed25519 keygen/sign; crash-restart drift detection (§ Part 8); fall back to `forge deploy` on any rejection.

### Phase 5 — Actor state migration + type-level guardrails
- Per-actor versioned handler dispatch, migrate-before-run ordering (§ Part 5); `RawRecord`; shared-type rejection via the Merkle gate; supervisor-restart fallback.
- Type-level migration guardrails (§ Part 6): schema diff + forward/backward-compat classification against the CAS prior type, the added-variant-needs-catch-all check, and `@compat(forward|full)` enforcement. Row-polymorphic handlers and session-subtyping checks are follow-ons (depend on those language features landing).

### Phase 6 — Model B: native JIT upgrade (gated on § Phase 0 go)
- ORC JIT both platforms (pinned thread; macOS `MAP_JIT` + entitlement note); **ORC end-to-end, no `dlopen`**; background upgrade of trampolined SCCs to native O2; defun no-boundary scheme (or per the spike); measured perf.

### Phase 7 — Fleet, registry, tooling
- `--env`, parallel + `--canary <n>`; content-addressed registry as the third CAS tier; `forge hot-reload init` (git-frequency exclude suggestions); `forge hot-reload keygen --rotate`; effective-version + append-only audit-log endpoints.

---

## Risks & Open Problems

1. **Defun across the boundary (Central Tension #2)** — highest risk; may force no-defun-at-boundary at unknown cost, or cap the design at Model A. The CAS does not help here. § Phase 0 decides.
2. **Frozen borrow/RC ABI (Central Tension #3)** — permanently deoptimizes the `Conn` hot path. Now *checkable* via Merkle `impl_hash`, but the cost must be quantified by § Phase 0 before shipping `--hot-reload` to production.
3. **Merkle correctness** — the prerequisite pass must hash in a canonical, deterministic order; getting it wrong silently corrupts the cache (and HCR). Reuse `serialize.ml`'s canonical encoding; test against known cross-SCC-inlining cases.
4. **Reclamation under the M3 scheduler** — `enter`/`leave` ordering vs epochs needs the rigor of `atomic-rc-design.md`; a mistake is use-after-free.
5. **macOS W^X + fiber migration** — hard thread-pinning of all JIT codegen; easy to regress.
6. **Operational drift (§ Part 8)** — hot reloads vanishing on restart is a footgun even when the mechanism is perfect; the docs must push "bridge to a real deploy."
7. **REPL convergence** — the REPL JIT already does incremental redefinition and shares the global CAS tier; unifying it with Model B is attractive but out of scope until Phase 6.
8. **DAP debugging** of trampolined (interpreted) and JIT-native reloaded code needs source-mapping work; deferred.
