# Hot Code Reloading — Design Spec

**Date:** 2026-06-18
**Status:** Draft (early — see § The Central Tension before committing to any phase)
**Depends on:** LLVM codegen (`lib/tir/llvm_emit.ml`), JIT (`lib/jit/`), interpreter (`lib/eval/eval.ml`), CAS cache, Perceus RC + borrow inference (`lib/tir/perceus.ml`, `lib/tir/borrow.ml`), defunctionalization (`lib/tir/defun.ml`), epochs (`specs/epochs-design.md`), C runtime scheduler, `BastionHotDeploy`

---

## Motivation

March's `BastionHotDeploy` module handles zero-downtime *process* restarts: drain in-flight connections, swap the binary, resume. This is adequate for infrastructure changes (runtime upgrades, binary ABI changes) but heavy for the common case: a developer fixes a handler bug or updates a business rule and wants it live in under a second with no connection drops, no drain, no process restart.

Erlang solved this in 1989. A running BEAM VM loads new module code while existing processes finish their current invocation in old code, with new dispatches going to the new version. The reason BEAM can do this cheaply is that **its modules are independently-compiled, dynamically-dispatched units** — there is no cross-module inlining or whole-program specialization to undo.

March is the opposite. Its performance comes from *whole-program* optimization: monomorphization, defunctionalization, Perceus reference counting, borrow inference, and LTO all operate across module boundaries. **That is exactly the property hot reload must give up.** This spec is therefore not "add a dispatch table" — it is a study of how much whole-program optimization March can forfeit at a chosen boundary, and what execution mechanism is actually sound given the rest of the compiler.

The honest conclusion, developed below: the **interpreter-trampoline** approach is correct and shippable in the near term; the **native-JIT dispatch-table** approach is a research project that fights the compiler's core model and must be de-risked by a spike before any production phase is planned.

---

## The Central Tension: Whole-Program Optimization vs. Module Isolation

Hot reload requires that a module be (re)compiled and swapped *independently* of the code that calls it. Four whole-program passes make this unsound if done naively. Every later design decision in this document is downstream of these four facts.

### 1. Monomorphization

Generic functions are specialized per concrete type at call sites, across modules. A cross-module call that can be hot-swapped cannot be specialized into the caller — the boundary must use a fixed (boxed or dictionary-passing) calling convention. Tolerable for app handlers, which are almost always concrete (`Router.handle(conn : Conn) : Conn`), but it forfeits specialization for any genuinely polymorphic exported function on the boundary.

### 2. Defunctionalization (the unsolved one)

Defun (`lib/tir/defun.ml`) replaces all closures with a global tag → `apply` dispatch function. The set of tags is closed at whole-program compile time. **If a hot-reloaded module introduces a new lambda shape that flows into a defunctionalized call site, the new tag has no arm in the already-running binary's global `apply`.** You cannot add a `match` case to loaded native code. There is no clean fix in the native path short of:

- forbidding new closure shapes in reloaded modules (unenforceable and surprising), or
- giving each hot-reloadable module its own *local* apply function for closures it constructs, and never letting a closure constructed in a reloadable module be applied by code outside it (hard to guarantee given closures flow through `HttpServer.plug`, `List.map`, etc.), or
- not defunctionalizing across the boundary at all (closures stay heap objects with a real function pointer — which the dispatch table can then version).

The third option is the only tractable one and it is itself a deoptimization. This is the single biggest reason the native path is "research, not engineering."

### 3. Perceus RC + borrow inference (soundness, not just speed)

Perceus decides *at each call site* whether caller or callee owns/drops a value and whether an argument is borrowed. These decisions are made by whole-program borrow inference (`lib/tir/borrow.ml`). If the new module version's borrow signature differs from what the still-running caller was compiled against, the RC protocol mismatches → **double-free or leak**. Therefore the RC/borrow ABI must be *frozen* at every hot-reload boundary: borrowed-ness of each exported function's parameters and return becomes part of the ABI contract and may not change across a reload.

Freezing it has a real cost. Per [todos.md](todos.md) (Borrow inference and elision, P7), borrow elision "eliminates 100% of RC overhead for read-only middlewares (HTTP `Conn` pattern)." That is precisely the `Conn` flowing router → controller → view, i.e. *the* hot-reload boundary. **Enabling hot reload across that boundary disables the most important RC optimization for web handlers.** The earlier "~1–4 ns per cross-module call" estimate ignored this and was wrong; see § Performance.

### 4. Global type namespace + structural record layout

March app types live in a global namespace (records are laid out with fields sorted alphabetically — see `get_record_fields` in `lib/tir/llvm_emit.ml` and [actor-lowering.md](actor-lowering.md)). Changing a record type's fields changes its memory layout (GEP indices) for **every** module that uses it, including non-recompiled callers. So "add a field to the actor's state record" is only sound if that type is private to the reloaded module — which the type system does not currently enforce. The migration story (§ Part 5) must restrict itself to types provably local to the reloaded module, and the ABI check (§ Part 7) must reject layout changes to any shared type. This is a soundness constraint, not a convenience.

### Consequence

A binary that *can* hot-reload across a boundary is permanently slower across that boundary than one that cannot — regardless of whether a reload ever happens — because the boundary forfeits inlining, specialization, defun, and borrow elision. This directly contradicts a naive "zero cost in production" pitch: **the user's goal is hot reload in production, which means running the slower boundary in production.** The design must own that tradeoff rather than hide it.

---

## Two Execution Models

Given the tension, there are two viable mechanisms. They share everything *above* the call boundary (boundary detection, `forge deploy hot`, signing, CAS, actor migration) and differ only in how reloaded code runs.

### Model A — Interpreter trampoline (near-term, correct)

The binary embeds the tree-walking interpreter (`lib/eval/eval.ml`), which it already contains for the REPL/eval paths. A dispatch slot can point either at native code (the AOT default) or at an **interpreter trampoline** that marshals the native ABI into eval values, runs the reloaded function in the interpreter, and marshals the result back.

Why this sidesteps the tension:

- **No defun problem.** The interpreter has its own closure representation; new lambda shapes are fine.
- **No RC/borrow ABI problem.** Marshalling copies across the boundary into interpreter-owned values; the native RC contract at the trampoline is fixed and trivial (the trampoline owns its inputs).
- **Migration is easier.** Interpreter values are dynamically typed, so `migrate_state` is a normal value transform.

Cost: reloaded functions run at interpreter speed (≈10–100× slower than native) until the next full `forge build`. For I/O-bound web handlers this is usually invisible; for a hot loop it is not. This is the correct default and the only model that should be planned for production before the spike below succeeds.

### Model B — Native JIT + dispatch table (research)

Reloaded modules are JIT-compiled to native code and swapped in. This is the fast path, but only works if the four problems above are solved — most critically defun (#2) and the frozen RC/borrow ABI (#3). **Model B must not be scheduled past a spike until a prototype demonstrates a cross-boundary swap with (a) a new closure shape and (b) a `Conn`-style borrowed parameter, with no double-free under ASan and no defun tag fault.** See § Phase 0.

The two models can coexist: a reloaded module runs as a trampoline immediately (Model A, instant, correct, slow), and is *upgraded* to JIT-native in the background (Model B) once it compiles cleanly. If the JIT path is disabled or fails, the trampoline remains. This hybrid is the long-term target; Model A alone is the shippable milestone.

---

## Non-Goals

- **Hot-reloading the runtime** (`runtime/*.c`), the **stdlib**, or **dependencies**. These are never on the boundary; always direct-called and fully optimized. Runtime/stdlib changes require a full restart via `BastionHotDeploy`.
- **Type-incompatible interface changes.** Changing an exported function's arity or signature, removing an export, or changing the layout of a *shared* type is rejected; a restart handles it.
- **Persisting hot reloads across a process restart.** A crash/restart reverts to the AOT baseline binary (see § Crash-Restart Reconciliation for how this is surfaced and reconciled, not hidden).
- **WASM target.** No hot reload.
- **Model B in production before Phase 0 succeeds.**

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  forge deploy hot                                                    │
│  1. diff modules vs last deploy   2. compile changed (boundary ABI)  │
│  3. sign (ed25519)                4. ship to server CAS              │
│  5. connect reload socket         6. send per-module reload request  │
│  7. await per-module ack          8. report + record deploy-state    │
└─────────────────────────┬────────────────────────────────────────────┘
                          │  Unix socket (local) / SSH-tunneled
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Runtime reload server (background fiber, pinned thread)             │
│  recv (module, artifact, sig) → verify sig → verify compiler id      │
│  → verify ABI (boundary signatures + shared-type layouts)           │
│  Model A: install interpreter trampoline for the module's fns        │
│  Model B (if enabled & spike-proven): JIT compile → load → version   │
│  atomic-publish new version into per-version dispatch slot           │
│  old version retired via epoch reclamation + purge policy            │
└─────────────────────────┬────────────────────────────────────────────┘
                          │  versioned dispatch
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Running application                                                 │
│  Requests in flight: pinned to the version they entered             │
│  New requests: see the new version                                   │
│  Actors: per-actor versioned handler; migrate_state runs BEFORE      │
│          any new-version handler executes (see § Part 5)            │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: The Boundary and the Dispatch Table

### The flag

Hot reload is opt-in at compile time; a binary either has the dispatch infrastructure or it does not.

```bash
forge build                    # direct calls, full LTO/O3 — no hot reload, fastest
forge build --hot-reload       # dispatch table on the boundary — reloadable, slower boundary
forge bastion server           # implies --hot-reload (dev)
```

**Honesty about `--release`:** `forge build --release` produces a fully-optimized, *non-reloadable* binary. If you want hot reload in production you must ship `--hot-reload`, and you accept the boundary deoptimization from § The Central Tension. There is no "reloadable and also maximally optimized across the boundary" build — that is a contradiction in this language. The spike (Phase 0) exists partly to measure how large that gap actually is.

### What changes in LLVM emit

Without `--hot-reload`, cross-module calls are direct and inlinable. With `--hot-reload`, a call from one boundary module to another is emitted as a versioned indirect call:

```llvm
; Boundary call under --hot-reload:
;   resolve the current version's fn pointer for (module, fn),
;   pinning this caller to that version for the duration of the call.
%fn = call ptr @march_dispatch_enter(i32 MOD_ID, i32 FN_ID)   ; bumps per-version refcount
%r  = call i64 %fn(ptr %conn)
       call void @march_dispatch_leave(i32 MOD_ID, i32 FN_ID)  ; drops per-version refcount
```

`enter`/`leave` (not a bare pointer load) are required so that version reclamation is correct — see § Versioning & Reclamation, which replaces the earlier single-`in_flight`-counter sketch that was racy.

Module/function IDs are **not** source-order integers (that shifts on edit). They are assigned by a stable, name-based index built at startup from a symbol table emitted into the binary; `forge deploy hot` resolves names → IDs via an `abi_query` handshake before sending any reload (see § Part 7). New modules/functions register additively; existing ones never change ID within a binary's lifetime.

### Boundary detection (auto, with overrides)

The dispatch table covers only the project's own source — never stdlib or deps.

**Default:** every `.march` under `src/` is reloadable; the module prefix is derived from `[package] name` (e.g. `my_app` → `MyApp.*`), reusing the multi-file convention (`module_name_to_filename` in `bin/main.ml`). No config required.

```bash
forge hot-reload modules     # print the computed boundary + why each module is in/out
```

**Override** via optional `[hot-reload]` in `forge.toml`: `include = [...]` replaces the auto set; `exclude = [...]` subtracts from it. Excluded modules are direct-called and fully optimized.

**`forge hot-reload init`** analyzes git change-frequency and *suggests* excluding rarely-changed modules (so they keep full optimization). Advisory only.

**Call-direction rules:** boundary→stdlib, boundary→excluded-app-module, and intra-module calls are all **direct**. Only boundary→boundary calls are indirect. stdlib→app already goes through closures (`HttpServer.plug`), needing no table entry — but note this closure path interacts with defun (§ The Central Tension #2) and is part of what Phase 0 must validate.

### Polymorphic exports on the boundary

A genuinely polymorphic exported function on the boundary cannot be monomorphized into callers. The compiler emits a warning and uses dictionary-passing for that call site, or the author marks the function module-private. Most app handlers are concrete and unaffected.

---

## Part 2: Versioning & Reclamation

This section replaces the naive single `in_flight` counter, which could not distinguish versions and was racy.

### Per-version slots

Each dispatch slot holds a small ring of **versions**, each with its own code pointer and refcount:

```c
typedef struct {
    _Atomic(void *)   fn_ptr;     // code for this version (native or trampoline thunk)
    _Atomic(uint64_t) refs;       // callers currently pinned to THIS version
    uint32_t          version;
    uint8_t           kind;       // MARCH_NATIVE | MARCH_TRAMPOLINE
} MarchFnVersion;

typedef struct {
    _Atomic(uint32_t) current;        // index of the live version
    MarchFnVersion    ring[MARCH_MAX_LIVE_VERSIONS];  // small, e.g. 4
} MarchDispatchSlot;
```

`march_dispatch_enter` reads `current`, increments *that* version's `refs`, and returns its `fn_ptr` — the increment and the read of `current` must be ordered so a caller is always pinned to the version it actually runs (acquire on `current`, then RMW on the chosen version's `refs`; publication of a new version uses release ordering). `march_dispatch_leave` decrements the same version's `refs`.

### Reclamation

Tie reclamation to the existing **epoch** mechanism ([epochs-design.md](epochs-design.md)) rather than a bespoke counter. A retired version is freed only after (a) its `refs` reaches zero **and** (b) a grace epoch has elapsed in which no thread holds a pointer into it. Closures captured from old-version code keep that version pinned via the same `refs` accounting (the closure carries its version), so a captured callback cannot outlive its code.

### Purge policy and version cap (Erlang's lesson)

Long-lived connections (WebSockets, SSE, streaming responses) can pin an old version for hours. Without a bound, a day of deploys accumulates unbounded code versions and never reclaims. Therefore:

- **At most `MARCH_MAX_LIVE_VERSIONS` (default 2, like BEAM "old + current") versions per function.** A reload that would exceed the cap triggers a **purge**: any fiber/actor/connection still pinned to the *oldest* version is forcibly terminated (connection closed, actor restarted via its supervisor) so the version can be freed. This is surfaced loudly in the reload report (`forge deploy hot` prints "purge: 3 long-lived connections on MyApp.WS will be closed — proceed? [y/N]").
- The purge boundary is the reason connections must be cancellable; this reuses `BastionHotDeploy` drain machinery for the affected sockets only, not the whole process.

---

## Part 3: The Reload Server

A background fiber, started when `MARCH_HOT_RELOAD_SOCKET` is set (auto for `forge bastion server` and during deploys). It is **pinned to a single OS thread** — required on macOS because `pthread_jit_write_protect_np` toggles thread-local W^X state and the M3 worker pool migrates fibers across threads ([atomic-rc-design.md](atomic-rc-design.md)); a migrating reload fiber would corrupt the W^X state. Pin the reload fiber (and any JIT codegen it performs) to a dedicated thread.

### Protocol (length-prefixed binary, Unix socket / SSH-tunneled)

Request carries: magic, protocol version, **compiler-identity digest**, module name, artifact (Model A: nothing to compile — the bitcode is still sent so it can be upgraded to native later; Model B: LLVM bitcode), and an ed25519 signature over the whole payload. Response carries status (`ok | bad_signature | compiler_mismatch | abi_mismatch | compile_error | purge_required`), the new version, and a message.

### Preconditions checked in order (all hard gates)

1. **Signature** verifies against the embedded public key. The socket executes code; unsigned/!verified is rejected before anything is loaded.
2. **Compiler identity** matches. The artifact must be produced by the exact compiler embedded in the running binary (reuse the CAS compiler digest from CLAUDE.md). A mismatch can silently break ABI/JIT assumptions, so it is rejected, not warned.
3. **ABI compatibility** (§ Part 7): boundary signatures unchanged for existing exports; no layout change to any shared type; frozen RC/borrow signature for existing exports.
4. **Version cap / purge** consent if the reload would exceed `MARCH_MAX_LIVE_VERSIONS`.

### Loading mechanism — pick ONE per platform (the earlier draft conflated dlopen and ORC)

LLVM ORC JIT produces in-memory compiled symbols; it does **not** produce an ELF `.so`. So you either use ORC end-to-end (its own mmap + symbol resolution; **no `dlopen`**) or you compile bitcode → `.o` → link → `.so` and `dlopen` that. This spec chooses **ORC JIT on both platforms** for Model B, because it avoids a linker on the server and unifies the path:

- **Linux & macOS (Model B):** feed bitcode to ORC (reuse `lib/jit/`), which allocates executable memory itself (on macOS via `MAP_JIT` with the toggle, on the pinned thread). Resolve the module's exported symbols from ORC, then publish their pointers into the dispatch ring. External references (the dispatch table, runtime functions, stdlib) are resolved against the main image's symbols — so the main binary must be built with dynamic export of those symbols (`-rdynamic` / `--export-dynamic` on Linux; keep the relevant symbols un-stripped on macOS). This is a change to the **main** build, not just the reload path, and must be in Phase 1.
- **macOS hardened runtime:** ORC's JIT memory requires the `com.apple.security.cs.allow-jit` entitlement. Server binaries are typically un-notarized so this is usually moot, but it must be documented for anyone shipping a hardened/sandboxed build.
- **Model A (trampoline):** no executable memory at all — the slot points at a static native thunk that calls into the interpreter with the module's freshly parsed+typechecked AST. This is why Model A is the safe default: it touches none of the platform JIT machinery.

### Compilation timing

Model A install is parse + typecheck + publish: a few ms, no codegen. Model B JIT of one app module is ~20–200 ms on the pinned thread; serving is unaffected (old version stays live until publish). The optimization level for Model B is O2 (fast); the gap vs the AOT O3+LTO build is **to be measured by Phase 0**, not assumed — and is on top of the permanent boundary deoptimization, so do not quote a single tidy percentage.

---

## Part 4: CAS Integration

The CAS (`.march/cas/artifacts/`) caches compiled artifacts keyed by hash of (source + compiler digest + runtime sources) per CLAUDE.md. Hot reload adds per-module entries:

```
.march/cas/artifacts/hot/<sha256(module_source + compiler_digest)>/
  module.bc          # LLVM bitcode (Model B input; also kept under Model A for later upgrade)
  module.sig         # ed25519 signature over module.bc
  module.meta.json   # { module_name, fn_names[], abi_hash, shared_type_layout_hash, compiler_digest }
```

The compiler digest is part of the key *and* recorded in meta, so the precondition check in § Part 3 is a lookup, not a guess. `forge deploy hot` sends only the content hash to each server; a server that already has the artifact (from a prior deploy) skips the transfer. For large fleets, an optional content-addressed `registry` (`s3://…` or `https://…`) in `[hot-reload]` lets servers pull independently.

---

## Part 5: Actor State Migration (ordering corrected)

### The problem and the race the earlier draft had

A reloaded module may change the type of an actor's state. The earlier design did a **global** dispatch swap and *then* delivered an async `{:hot_reload}` message — which means between the swap and the actor draining that message, the actor runs **new handler code against old-typed state**: exactly the corruption migration was meant to prevent.

### Fix: per-actor versioned handler, migrate-before-run

Actor handler dispatch is **not** the global function table. Each actor carries the code version it is currently running. The reload does not change a running actor's version. Instead:

1. The new version is published for *new* actors and for explicit migration.
2. Each live actor of the reloaded module is sent a migration step that the runtime executes **as the actor's next turn, before any new-version handler runs**: it calls `migrate_state(old_state) : NewState`, atomically swaps *that actor's* handler version to the new one together with its migrated state, then resumes the mailbox.

Because the version swap and the state migration happen in the same uninterrupted turn, a new-version handler never sees old-typed state. Actors that haven't migrated yet keep running old code against old state — consistent, just not yet upgraded.

### Soundness constraint (from § The Central Tension #4)

`migrate_state` may only change types that are **private to the reloaded module**. The ABI check rejects the reload if the state type — or any type reachable from it — is shared with a non-reloaded module and its layout changed. `migrate_state` reads the old value through a runtime type-erased `RawRecord` accessor (constructable only by the runtime, panics on missing/mistyped fields) and returns a fully-typed new state.

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

### When `migrate_state` is absent

Stateless modules: nothing to migrate. Stateful actors without `migrate_state`: `forge deploy hot` detects this at deploy time and requires an explicit choice — restart affected actors via their supervisor (state lost, serving uninterrupted) or abort the reload for that module. If migration panics, the supervisor restarts that actor from `init()`; other actors continue.

---

## Part 6: `forge deploy hot`

```bash
forge deploy hot [target] [--env <name>] [--dry-run] [--no-migrate]
                 [--force] [--canary <n>] [--timeout <ms>]
```

Workflow: diff modules vs `.march/deploy-state.json` → compile changed modules with `--hot-reload` (boundary ABI) → sign → transfer to server CAS (skip if hash present) → `abi_query` handshake (resolve IDs, fetch ABI + compiler digest) → send per-module reload, sequentially in dependency order → await acks → record new hashes. Falls back to `forge deploy` (graceful full restart via `BastionHotDeploy`) whenever a precondition rejects the reload.

`--canary <n>` reloads `n` servers first, watches health for a window, then rolls out or rolls back. Rollback is itself a hot reload back to the previous artifact (still in CAS).

---

## Part 7: ABI Compatibility

Before compiling, `forge deploy hot` fetches the running binary's ABI via `abi_query`: per-module `abi_hash`, exported `fn_signatures` (including **borrow/ownership annotations**), `shared_type_layout_hash`, and `compiler_digest`. The new module is accepted only if:

| Change | Allowed | Why |
|--------|---------|-----|
| Function body change, same signature **and same borrow/RC annotations** | ✓ | boundary ABI unchanged |
| Add a new exported function | ✓ | additive — new ID/slot |
| Add a private function / change private body | ✓ | not on the boundary |
| Change a **module-private** type's layout | ✓ | not shared; migrate via `migrate_state` if it's actor state |
| Change an exported function's borrow/ownership annotation | ✗ | RC ABI mismatch → double-free/leak (§ Central Tension #3) |
| Change exported arity or type signature | ✗ | caller mismatch |
| Remove an exported function | ✗ | callers hold the ID |
| Change layout of a **shared** type | ✗ | re-laid-out for non-reloaded callers (§ Central Tension #4) |
| Introduce a new closure shape crossing a defunctionalized boundary (Model B only) | ✗ until Phase 0 proves the local-apply scheme | defun tag fault (§ Central Tension #2) |

The borrow-annotation and shared-type-layout rows are new and load-bearing; they are the difference between "looks fine" and "corrupts memory."

---

## Part 8: Crash-Restart Reconciliation

Hot-reloaded code lives only in process memory. A crash, OOM-kill, or scheduled restart brings the process back on the **AOT baseline binary**, silently dropping every hot patch. The earlier draft ignored this; it is an operational landmine and must be surfaced, not hidden:

- The running process exposes its **effective module versions** (baseline vs hot-reloaded, with artifact hashes) on the reload socket and on the `BastionDev`/health endpoint. "What is actually running on this box" is queryable.
- `deploy-state.json` records the *intended* hot set per server. On reconnect after a restart, `forge deploy hot` detects baseline-vs-intended drift and re-applies the pending hot reloads (or reports the drift in `--dry-run`).
- For durability, the recommended operational pattern is: **hot reload is for the gap between deploys, not a substitute for them.** A hot-reloaded change should be promoted to a real `forge build --release` + `forge deploy` within the same cycle, so a restart converges to a binary that already contains the change. This guidance belongs in the user docs, prominently.

---

## Part 9: Security

The reload socket executes code; treat it as the highest-value attack surface in the system.

1. **Mandatory ed25519 signing.** Public key embedded at build time; private key only on the build/CI machine. Unsigned or unverified artifacts are rejected before load.
2. **Compiler-identity gate** (§ Part 3) doubles as a downgrade/confusion defense.
3. **Socket exposure.** Default Unix socket, mode `0600`, owner-only; remote access only via SSH tunnel. Optional mTLS TCP bound to localhost/private interface, never `0.0.0.0`. mTLS certs are distinct from the signing key.
4. **Operational risk, stated plainly.** This is a *larger* RCE surface than ordinary deploy: there is no process restart and possibly no orchestrator audit trail, so a CI/signing-key compromise yields silent, persistent code injection on every reloadable server. Mitigations to document: keep the signing key in an HSM/KMS, require signed+reviewed artifacts, log every accepted reload (module, hash, signer, time) to an append-only audit sink, and provide a kill switch (`MARCH_HOT_RELOAD_SOCKET` unset / `forge hot-reload disable`) that drops the feature without redeploying. A "when NOT to enable this" section belongs in the docs.

---

## Part 10: Performance (corrected)

The earlier numbers ("1–4 ns/call", "5–15% O2 vs O3") were fabricated and, given § The Central Tension, optimistic. Replace with measured-by-spike and the honest structure of the cost:

- **Non-reloadable build (`forge build` / `--release`):** unchanged from today. The dispatch table does not exist.
- **Reloadable build, boundary calls, even with no reload ever performed:** pays (a) an indirect, non-inlinable call, (b) loss of cross-module specialization, (c) loss of defun across the boundary if Model B's local-apply scheme is used, and (d) **loss of borrow/RC elision** — which for the `Conn` middleware path is the dominant cost, not the pointer chase. The aggregate is **TBD, to be measured by Phase 0** on `bench/list_ops.march` (HOF/closure) and a Bastion request benchmark. Do not quote a single number until measured.
- **Reloaded function, Model A (trampoline):** interpreter speed, ≈10–100× slower than native. Acceptable for I/O-bound handlers; unacceptable for hot loops — which is why the trampoline targets handlers and the JIT upgrade (Model B) exists.
- **Reloaded function, Model B (JIT, O2):** near-native but below the AOT O3+LTO baseline, *and* still inside the deoptimized boundary. Magnitude TBD by Phase 0.
- **Memory:** bounded by `MARCH_MAX_LIVE_VERSIONS` per function (default 2) plus the purge policy (§ Part 2). A typical app module is 50–500 KB of code; with the cap, worst case is a small constant multiple, not unbounded.

---

## Part 11: Failure Modes

| Situation | Behavior |
|-----------|----------|
| Signature invalid | reject pre-load, log WARNING, running binary untouched |
| Compiler-identity mismatch | reject, instruct to rebuild with matching toolchain |
| ABI/borrow/shared-layout mismatch | reject at deploy or reload; suggest `forge deploy` |
| Compile/typecheck error (Model B JIT or Model A typecheck) | reject, old version keeps running |
| Reload exceeds version cap | `purge_required`; prompt to close long-lived connections, else abort |
| `migrate_state` panics | supervisor restarts that actor from `init()`; others continue |
| Long-lived connection pins old version | kept alive until cap forces a purge (§ Part 2) |
| Process restart after hot reloads | reverts to baseline; drift detected and re-applied (§ Part 8) |
| Socket unreachable | clear error; fall back to `forge deploy` |

---

## Phase 0 (MANDATORY before any production phase): the spike

A throwaway prototype that answers the only question that matters: *can March swap native code across a boundary without corrupting memory or faulting defun?* Until this passes, Models B's later phases are unschedulable.

1. Two hand-written app modules with a boundary call passing a `Conn`-style **borrowed** record.
2. Freeze the RC/borrow ABI at the boundary; hot-swap the callee; run under ASan/leak detector across thousands of requests → **zero double-frees, zero leaks**.
3. Introduce a **new closure shape** in the swapped module that flows through the boundary (`HttpServer.plug`-style) → demonstrate the per-module local-apply scheme handles it with **no defun tag fault**, or conclude that Model B requires not-defunctionalizing the boundary and measure that cost.
4. Measure the boundary deoptimization (§ Part 10) on `bench/list_ops.march` and a Bastion request bench.

Deliverable: a go/no-go on Model B with real numbers. Model A does not need this spike and can proceed in parallel.

---

## Implementation Plan (re-sequenced: trampoline first)

### Phase 1 — Boundary + dispatch infrastructure (compiler + main-build changes)

- `hot_reload : bool` in the `Llvm_emit` context; boundary detection from `src/` + `[hot-reload]`.
- Emit versioned `enter`/`leave` dispatch for boundary→boundary calls; per-version slot ring (§ Part 2).
- Emit the name-based module/fn symbol index + `abi_query` data (signatures **with borrow annotations**, shared-type-layout hashes, compiler digest).
- **Main-build change:** `-rdynamic`/`--export-dynamic` (Linux) and keep needed symbols un-stripped (macOS) so later JIT can resolve against the image.
- `forge build --hot-reload`; `forge hot-reload modules`.
- Test: reloadable binary is behavior-identical to non-reloadable (only dispatch differs); measure the boundary cost and record it.

### Phase 2 — Model A: interpreter trampoline (the shippable milestone)

- Reload server fiber, pinned thread, `MARCH_HOT_RELOAD_SOCKET` gate, protocol with signature + compiler-identity + ABI gates.
- Trampoline thunks: native ABI ↔ eval values; install per (module, fn); version published into the slot ring.
- Epoch-based reclamation + version cap + purge (§ Part 2), reusing `BastionHotDeploy` drain for purged connections only.
- End-to-end: hot-reload a handler in a running Bastion app, interpreted, zero dropped connections.

### Phase 3 — `forge deploy hot` + CAS + signing

- `deploy-state.json`, module diff, per-module compile, CAS `hot/` entries, ed25519 keygen/sign, SSH-tunneled socket, `abi_query` handshake, crash-restart drift detection (§ Part 8).

### Phase 4 — Actor state migration

- Per-actor versioned handler dispatch (§ Part 5), migrate-before-run ordering, `RawRecord`, supervisor-restart fallback, shared-type-layout rejection.

### Phase 0/5 — Model B JIT upgrade (gated on the spike)

- Only after Phase 0 returns go: ORC JIT path (both platforms, pinned thread, macOS `MAP_JIT` + entitlement note), background upgrade of trampolined modules to native, defun local-apply scheme (or boundary-no-defun), measured perf.

### Phase 6 — Fleet, registry, tooling

- `--env`, parallel + `--canary`, content-addressed registry, `forge hot-reload init` (git-frequency suggestions), `forge hot-reload keygen --rotate`, effective-version + audit-log endpoints (§ Part 8/9).

---

## Risks & Open Problems

1. **Defun across the boundary (§ Central Tension #2)** is the highest risk and may force "do not defunctionalize boundary closures," whose cost is unknown until Phase 0. If that cost is too high, Model B may be infeasible and Model A (trampoline, possibly with a cheaper bytecode compile instead of pure tree-walking) is the ceiling. That is an acceptable outcome and should not be treated as failure.
2. **Frozen borrow/RC ABI (§ #3)** permanently deoptimizes the `Conn` path — the most common web hot path. The whole feature's production value depends on that cost being tolerable; Phase 0 must quantify it before anyone ships `--hot-reload` to production.
3. **Shared-type layout (§ #4)** means "add a field" is only safe for module-private types; the type system does not yet *enforce* privacy, so the ABI check is the only guard. A future language feature (module-private types with enforced non-export) would make this safer.
4. **Version reclamation + purge** correctness under the M3 work-stealing scheduler and epochs needs the same rigor as `atomic-rc-design.md`; getting `enter`/`leave` ordering wrong is a use-after-free.
5. **macOS W^X + fiber migration** requires hard thread-pinning of all JIT codegen; easy to regress.
6. **Operational drift (§ Part 8)** — hot reloads vanishing on restart — is a footgun even when the mechanism is perfect; the docs must push "hot reload bridges to a real deploy, it doesn't replace one."
7. **REPL convergence.** The REPL JIT already does incremental redefinition; once Model B exists, unifying them is attractive but out of scope until Phase 5 lands.
8. **DAP debugging** of trampolined (interpreted) and JIT-native reloaded code needs source-mapping work; deferred.
