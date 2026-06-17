# Expanded Capability System Design (Phase 2)

**Date:** 2026-06-15
**Status:** Draft — reviewed and decisions recorded
**Depends on:** Capability system Phase 1 (implemented), linear/affine types (implemented), type-level naturals `TNat` (implemented), session types (implemented), monomorphization `lib/tir/mono.ml` (implemented)

---

## Overview

March's Phase 1 capability system enforces IO permissions: modules declare `needs X`, functions accept `Cap(X)` parameters, and the compiler verifies the declarations transitively. This is correct and working — `check_module_needs` (`lib/typecheck/typecheck.ml:4435`) runs five checks (one warning, one hint, three errors), `root_cap` / `cap_narrow` are builtins, and an IO capability hierarchy (`io_cap_hierarchy`, `cap_ancestors`, `cap_subsumes`, ~`typecheck.ml:858–894`) supports hierarchical narrowing.

This spec extends capabilities into new dimensions:

1. **Proof tokens** — capabilities as unforgeable evidence that something has happened
2. **Typestate** — capabilities encoding resource lifecycle protocols via `Handle(R, S)`
3. **Specialization tags** — phantom capability parameters driving monomorphization via `Tagged(X, T)`
4. **Environment records** — bundling/narrowing capabilities as first-class values
5. **Panic as a capability** — structural no-abort guarantees (realtime-exclusion narrowing in scope; full retrofit deferred)
6. **Tooling surface** — capability graph as a first-class information source for error messages, LSP, and forge

All of Phase 2 is purely additive with **no runtime changes**. Permission caps (`root_cap`/`cap_narrow`) are runtime-erased (`null` pointer in LLVM, `VUnit` in the interpreter); `Handle` and `Tagged` are built on the same erased model. Phantom state/tag parameters vanish at monomorphization.

> **Terminology note.** "Capability" here means object/permission capabilities (unforgeable tokens authorizing an effect). This is not Pony-style reference capabilities (`iso`/`val`/`ref`/`box`/`tag` aliasing modes). `specs/progress.md` records "Pony-style capabilities: No — linear/affine is the ceiling"; that decision is about aliasing modes and is unaffected by this proposal.

> **Three type constructors, three distinct concepts.**
> - `Cap(X)` — permission capability (Phase 1 and this spec); runtime-erased
> - `Handle(R, S)` — typestate handle for resource lifecycle (§2); runtime-erased
> - `Tagged(X, T)` — specialization tag for monomorphization policy (§3); runtime-erased
> - `Cap(A, e : Epoch)` — actor-messaging capability (`specs/epochs-design.md`); a real runtime heap value; **unrelated to this spec**

---

## 1. Proof Tokens

### Motivation

Many functions require not just permission to act, but evidence that a prior step succeeded. Currently this is enforced by convention: "call `validate()` before `save()`." Proof tokens make this a compile-time guarantee.

### Scope: ambient facts only

Proof caps are the right tool for **payload-independent, ambient facts** — things that are true about the system state rather than about a specific value:

- `Cap(Migrated)` — database migrations have run
- `Cap(Authenticated)` — the current request has a verified user identity
- `Cap(AppStarted)` — application initialization has completed

For **data-bound proofs** (this string is sanitized, this input is parsed), a proof cap is the wrong model — a detached cap proves "a validation happened" but doesn't bind to the specific value. Use **opaque refined types** instead (see below). Phase 2a implements proof caps for ambient facts only.

### Proof cap design

A proof cap is declared with the `proof cap` syntax. **Only public (`fn`) functions in the declaring module can mint a proof cap.** Private (`pfn`) functions face the same forgery restriction as external modules — they may pass a cap through, but cannot produce one from nothing. This makes the module's public API the complete, auditable minting surface.

The declaring module implicitly satisfies its own `needs` for any proof cap it declares — no explicit `needs Db.Migrated` is required inside `mod Db`.

```march
mod Db do
  -- Proof cap: only public functions in this module can mint Cap(Db.Migrated)
  proof cap Migrated

  -- Public factory — the only way callers can obtain Cap(Db.Migrated)
  fn run_migrations(cap : Cap(Db.Raw)) : Cap(Db.Migrated) do
    execute_pending_migrations(cap)
    ()   -- Cap is runtime-erased; the type is what enforces the invariant
  end

  fn start_app(cap : Cap(Db.Migrated)) : () do
    -- Cannot be called without migration proof
    ...
  end

  -- Private pass-through is fine; private minting is not
  pfn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end   -- OK
  -- pfn forge() : Cap(Db.Migrated) do () end                   -- ERROR
end
```

`Cap(Db.Migrated)` cannot be forged: `cap_narrow` cannot produce it, `root_cap` cannot produce it, no `pfn` in `mod Db` can produce it from nothing, and no external module can produce it. The only route is through a public function of `mod Db`.

```march
mod Auth do
  proof cap Authenticated

  fn authenticate(session : Session) : Option((Cap(Auth.Authenticated), UserId)) do
    match verify_session(session) do
      Ok(uid) -> Some(((), uid))   -- () is the runtime rep; type system enforces soundness
      Err(_)  -> None
    end
  end

  fn read_profile(cap : Cap(Auth.Authenticated), id : UserId) : Profile do
    ...
  end
end
```

**Design rationale.** Since proof cap values are always `()` at runtime (fully erased), any private "factory" function is always just `pfn mk() : Cap(X) do () end` — there is no real computation to encapsulate. Inlining `()` in each public minting function costs nothing and keeps the minting surface explicit. The restriction on `pfn` is therefore zero-cost in practice while providing the auditability property.

**Principle carried forward.** This same rule applies to Phase 2b `Handle(R, S)`: only public functions of the declaring module produce the initial handle state. The declaring module's public API is the exclusive entry point for any capability or handle creation across all of Phase 2.

### Data-bound proofs: use refined types, not caps

When the proof must travel with specific data, use an opaque wrapper type instead:

```march
mod Sanitize do
  -- Opaque: constructor private to this module
  type Sanitized = Sanitized(String)

  fn sanitize(raw : String) : Sanitized do
    Sanitized(clean(raw))
  end

  fn value(s : Sanitized) : String do
    let Sanitized(inner) = s
    inner
  end
end

-- XSS impossible: render_html requires Sanitized, not String
fn render_html(content : Sanitize.Sanitized) : Html do ... end
```

`Sanitized` cannot be forged because its constructor is private. This is standard module opacity — no new mechanism needed. The type *is* the proof; it cannot be separated from the data.

### Implementation notes

- `proof cap Name` is a new declaration form (`lexer.mll`, `parser.mly`, `ast.ml`)
- The type checker populates a **producer registry** (`env.proof_caps : (string * string) list`, proof cap full path → declaring module) during `check_decl`
- Proof caps cannot be constructed by `cap_narrow` or `root_cap` — enforced in `typecheck.ml`
- **Check 1 (needs gate):** any module using `Cap(X)` where X is a proof cap must declare `needs X`; the declaring module is implicitly exempt (the `proof cap` declaration satisfies its own needs)
- **Check 6 (forgery ban):** applies to *all* functions whose current module is not the declaring module, AND to `pfn` functions inside the declaring module; only public `fn` in the declaring module can mint freely
- Error messages consult the registry to name the declaring module when a proof cap is missing or forged (§6)

**Estimated scope:** ~300 lines across `lexer.mll`, `parser.mly`, `ast.ml`, `typecheck.ml`. No eval, TIR, codegen, or runtime changes.

---

## 2. Typestate Capabilities via `Handle(R, S)`

### Motivation

Resources have lifecycles: open before read, read before close, begin before commit. Currently these are enforced by runtime errors (use-after-close, double-close). The `Handle(R, S)` type moves this enforcement to compile time.

### Design

`Handle(R, S)` is a linear, state-indexed resource handle. `R` is the resource tag; `S` is a phantom state type. Operations consume the old state and produce the new one. Because the handle is linear, you cannot skip steps or use a stale state.

```march
-- Phantom state types — declared in the same module as the Handle
type ConnState = Closed | Open | Errored

fn connect(addr : String) : linear Handle(Conn, Closed)
fn open(linear h : Handle(Conn, Closed)) : linear Handle(Conn, Open)
fn query(h : Handle(Conn, Open), sql : String) : (Result(Rows, DbError), Handle(Conn, Open))
fn close(linear h : Handle(Conn, Open)) : Handle(Conn, Closed)
fn disconnect(linear h : Handle(Conn, Closed)) : ()
```

The compiler enforces:

- `query` on a closed connection — type error
- `disconnect` on an open connection — type error
- Forgetting to `close` — linearity error (handle unused)
- Calling `close` twice — linearity error (handle already consumed)

The phantom state parameter has no runtime representation; it is erased at monomorphization.

### Transaction protocol

```march
type DbState = Ready | InTx

fn begin_tx(h : Handle(Db, Ready)) : linear Handle(Db, InTx)
fn commit(linear h : Handle(Db, InTx)) : Handle(Db, Ready)
fn rollback(linear h : Handle(Db, InTx)) : Handle(Db, Ready)

fn transfer(db : Handle(Db, Ready), from : AccountId, to : AccountId, amount : Decimal) do
  let tx = begin_tx(db)
  match do_transfer(tx, from, to, amount) do
    Ok(tx2)  -> commit(tx2)
    Err(tx2) -> rollback(tx2)
  end
end
-- tx cannot escape uncommitted — linearity guarantees it
```

### State type syntax

State parameters use the existing implicit type variable mechanism — `S` in `Handle(Conn, S)` is an ordinary type variable resolved by the signatures of transition functions. No new explicit bounded type-parameter syntax is introduced in Phase 2; state variables are inferred from use. Explicit bounded type parameters (`fn f[S : ConnState](...)`) are deferred to Phase 3.

### Relationship to session types

Session types handle *branching* protocols — two-party, with branching responses that both sides must handle. `Handle` covers *single-party state machines* — fixed sequences you control on both ends. They are complementary:

- Use session types for two-party protocols with external branching
- Use `Handle` for resource lifecycle (files, connections, transactions, device handles)

### Pattern match refinement: deferred

Refining a `Handle`'s state type inside a match arm (getting `Handle(Conn, Open)` in the `Open` branch of a match on connection state) requires GADT-style type refinement — not in the type checker today. Deferred to a future type system extension. The transition-function model covers the vast majority of resource lifecycle cases without refinement.

### Implementation notes

- New `Handle(R, S)` type constructor (parser/AST/typecheck) — distinct from `Cap` to avoid colliding with the epoch parameter in `Cap(A, e)` from `specs/epochs-design.md`
- State transition declarations: new surface syntax (`transition open : Handle(Conn, Closed) -> Handle(Conn, Open)`) populating a transition graph in `typecheck.ml`
- Enforcement: state-parameterized handles checked at each call site against expected state
- Error messages show the protocol sequence when a state mismatch occurs (§6)
- No eval, codegen, or runtime changes — `Handle` is runtime-erased like permission caps

**Estimated scope:** 400–800 lines. Main complexity: transition graph representation and the error renderer.

---

## 3. Specialization Tags via `Tagged(X, T)`

### Motivation

Several March design goals require compile-time specialization: `@noalloc`/`@realtime` contracts, SIMD width selection, platform targeting. The `Tagged(X, T)` constructor unifies these into a single mechanism over the existing monomorphization pipeline.

### Two distinct cases

**Type-indexed (low cost, nearly free):** The tag is a real `TNat` or enum type that appears in actual data types. Monomorphization already specializes on type parameters — this comes at no extra cost.

**Policy tags (medium-high cost):** The tag selects whether certain code is *present* in the binary (no alloc calls, no IO, no panic). Monomorphization clones bodies under a type substitution; it does not prune code based on a phantom tag value. Making `NoAlloc` genuinely contain no allocation sites requires a new **conditional-lowering/DCE pass** in `lib/tir/`. This is real work; the "free monomorphization" claim applies only to type-indexed cases.

### Type-indexed case: SIMD width

```march
-- N is a real TNat in a real type — monomorphization specializes this for free
fn fft(cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)

-- Monomorphization produces fft_256 for N=256, fft_1024 for N=1024, etc.
```

No new mechanism — `TNat` is already in the type system (`typecheck.ml:93`), monomorphization already handles it.

### Policy tags: allocation policy

```march
type AllocPolicy = WithAlloc | NoAlloc

fn process(cap : Tagged(Alloc, P), buf : Buffer(Byte)) : Buffer(Byte)
-- P is resolved at call sites; NoAlloc variant omits allocation sites (requires DCE pass)
```

For `NoAlloc` to genuinely contain no allocation call sites, the lowering pass must prune them when `P = NoAlloc`. This is beyond current monomorphization and is the main implementation cost of policy tags.

### Realtime contract

```march
type RealtimePolicy = Realtime | Standard

fn dsp_callback(cap : Tagged(DSP, R), buf : Buffer(Float32, N)) : Buffer(Float32, N)
```

`Tagged(DSP, Realtime)` does not subsume `Cap(Alloc)`, `Cap(IO)`, or `Cap(Panic)` — this is a narrowing rule added to `cap_subsumes`. A realtime function is therefore **statically proven not to allocate, do IO, or abort**. This narrowing rule is the in-scope part of §5 for Phase 2; it requires only an addition to `cap_subsumes`, not the full panic retrofit.

### Platform targeting

```march
type Platform = Native | Wasm | Embedded

fn render(cap : Tagged(Platform, P), scene : Scene) : Output
```

Build target is a compile-time constant; the conditional-lowering pass eliminates dead branches. Same DCE work as the allocation policy case.

### Relation to `@noalloc`/`@realtime` today

The annotation system can remain for backward compatibility. The `Tagged` approach is preferred for new code and is semantically equivalent, but structurally enforced rather than audited after the fact.

### State type syntax

Same as §2: tag type variables are implicit and inferred from transition/narrowing rules. No explicit bounded type-parameter syntax in Phase 2. Explicit syntax (`fn f[P : AllocPolicy](...)`) deferred to Phase 3.

### Implementation notes

- `Tagged(X, T)` type constructor (parser/AST/typecheck)
- Narrowing rules: `Tagged(DSP, Realtime)` does not subsume `Cap(Alloc)`, `Cap(IO)`, `Cap(Panic)` — small addition to `cap_subsumes`
- Type-indexed specialization: no new work (uses existing `TNat` + mono)
- Policy-tag DCE: new conditional-lowering pass in `lib/tir/` — the main cost

**Estimated scope:** 300–500 lines in `typecheck.ml` for narrowing; additional `lib/tir/` work for the policy-tag DCE pass.

---

## 4. Capability-Parameterized Environment Records

### Design

Functions needing multiple capabilities receive them bundled as a record. Narrowing to a restricted set is **ordinary record construction** — not the `cap_narrow` builtin (which narrows `Cap(IO)` → `Cap(X)` along the hierarchy). These are two different operations.

```march
type RuntimeEnv = {
  alloc : Cap(Alloc),
  log   : Cap(Logger),
  clock : Cap(Clock),
  sched : Cap(Scheduler)
}

fn process(env : RuntimeEnv, data : Input) : Output

-- Give a plugin only what it needs — construct a smaller record type
fn run_plugin(env : RuntimeEnv, plugin : Plugin) do
  let restricted = { log = env.log, clock = env.clock }
  plugin.run(restricted)   -- plugin's type lacks alloc and sched fields
end
-- plugin structurally cannot allocate or spawn — not by policy, by type
```

Convention: each env type's module should provide named narrowing functions:

```march
mod RuntimeEnv do
  fn read_only(env : RuntimeEnv) : { log : Cap(Logger), clock : Cap(Clock) } do
    { log = env.log, clock = env.clock }
  end
end
```

This gives ergonomic narrowing without new language mechanism.

### Testing

Permission caps are runtime-erased (null/VUnit) and carry no behavior, so mock-cap substitution is not possible. Instead, inject behavior through **function fields** in the env record, keeping the cap as the compile-time permission gate:

```march
type LogEnv = {
  log_cap : Cap(Logger),   -- erased permission token — compile-time gate
  write   : (String) -> () -- runtime behavior — swappable in tests
}

fn test_process() do
  let captured = Ref.new([])
  let env : LogEnv = {
    log_cap = test_logger_cap(),
    write   = fn line -> Ref.update(captured, fn xs -> [line, ...xs])
  }
  let result = process(env, test_input)
  assert_contains(Ref.get(captured), "expected message")
end
```

The cap gates permission at compile time; the function field provides swappable behavior at runtime. No new mechanism required — ordinary first-class functions.

Note: allocation counting specifically cannot be done this way (no allocator function to swap). Use TIR/Perceus allocation insights or a runtime allocation flag for that use case.

---

## 5. Panic as a Capability

### Phase 2 scope: realtime-exclusion narrowing only

The full vision — requiring `Cap(Panic)` for `/`, `%`, array indexing, and `assert` throughout all code — is **deferred to its own sub-spec**. The blast radius is too high for Phase 2: it touches essentially all arithmetic and indexing in the stdlib, requires non-aborting primitive variants (`checked_div` etc.), needs an implicit-cap threading mechanism for expressions that don't take cap parameters today, and requires a migration plan.

**Phase 2 ships one rule only:** `Tagged(DSP, Realtime)` does not subsume `Cap(Panic)`.

This already delivers the headline guarantee: **realtime functions are statically proven not to abort** (no panic, no alloc, no IO — all excluded via narrowing). It requires only an addition to `cap_subsumes`, reusing the existing hierarchy machinery.

### Future vision (deferred sub-spec)

The full capability hierarchy:

```
Cap(Panic)
  Cap(Panic.Arithmetic)    -- integer overflow, division by zero
  Cap(Panic.Bounds)        -- array/string out-of-bounds
  Cap(Panic.Assert)        -- assert/invariant failures
  Cap(Panic.Ffi)           -- undefined behavior from C FFI
```

This is a second hierarchy rooted at `Panic` (parallel to `io_cap_hierarchy`). The small part; the large part is the language-wide retrofit. Write the sub-spec when a concrete realtime/embedded need arrives.

---

## 6. Capability-Aware Error Messages

### Current state

`check_module_needs` produces five categories of diagnostics with Elm-style message parts (`MPCode`, `MPText`, `MPBreak`). This is good but limited to permission errors.

### Extensions

**Missing capability — suggest the source:**

```
Error: `greet` requires Cap(IO.Console) but this function does not have it.

This module declares `needs IO` — you can narrow it:

  let console_cap = cap_narrow(cap)   ← add this line
  greet(console_cap, name)

Or add Cap(IO.Console) to this function's parameters.
```

**Missing proof cap — show the factory function** (uses the producer registry from §1):

```
Error: `start_app` requires Cap(Db.Migrated) but this capability has not been obtained.

Cap(Db.Migrated) is produced by:
  Db.run_migrations(cap : Cap(Db.Raw)) : Cap(Db.Migrated)

Typical usage:
  let migrated_cap = Db.run_migrations(db_cap)
  start_app(migrated_cap)
```

**Typestate violation — show the protocol sequence** (uses the transition graph from §2):

```
Error: `query` requires Handle(Conn, Open) but you have Handle(Conn, Closed).

Connection lifecycle:
  connect(addr)  →  Handle(Conn, Closed)
  open(h)        →  Handle(Conn, Open)      ← you need to call this first
  query(h, sql)
  close(h)       →  Handle(Conn, Closed)
  disconnect(h)
```

**Realtime tag mismatch:**

```
Error: this call site provides Tagged(Alloc, WithAlloc) but the realtime
       context requires Tagged(Alloc, NoAlloc).

The surrounding function was called with Tagged(DSP, Realtime), which
excludes allocation. To allocate, move this call outside the realtime
callback or pre-allocate the buffer before entering the callback.
```

### Implementation path

`check_module_needs` and the unification error paths gain access to:
- `env.mod_needs` — declared needs for the current module (already available, `typecheck.ml:435`)
- `io_cap_hierarchy` / `cap_ancestors` / `cap_subsumes` — capability hierarchy (already present, ~`typecheck.ml:858–894`)
- The proof token producer registry (new — §1)
- The `Handle` state transition graph (new — §2)

Error message enhancements are incremental and can be added alongside each phase.

---

## 7. LSP Integration

### Capability-filtered autocomplete

When the cursor is inside a function scope, the LSP knows the available capabilities. Completions are filtered and annotated:

```
-- Inside a function with Cap(IO.Console), Cap(DB.Read):

IO.Console.println   ✓ available
IO.Console.print     ✓ available
DB.read              ✓ available
DB.write             ✗ requires Cap(DB.Write) — not in scope
Http.get             ✗ requires Cap(IO.Network) — not in scope
```

Functions requiring unavailable capabilities appear grayed with a tooltip explaining what cap is needed and how to obtain it.

### Hover — capability requirements

Hovering a function name shows its full capability requirements and what it does *not* require:

```
fn process_payment(cap: Cap(Payment.Gateway), ...)

Requires:
  Cap(Payment.Gateway)  — communicates with external payment processor
  Cap(Alloc)            — allocates intermediate structures

Does NOT require:
  Cap(IO.File)          — does not read or write files
  Cap(DB.Write)         — does not write to the database
  Cap(Panic)            — all errors returned as Result
```

The "does not require" section is as important as the "requires" section for auditing what a function can do.

### Capability graph navigation

Go-to-definition on a `Cap(X)` navigates to the `needs X` declaration or the proof cap factory. Find-references on a capability shows all functions that require it, all modules that declare it, and all narrowing operations that produce it.

---

## 8. Forge Integration

### Capability diff in PR review

```
$ forge cap diff main..feature/payments

Capability changes:
  + needs Payment.Gateway    (new — talks to external payment processor)
  + needs IO.Network         (via Payment.Gateway — transitive)
  ~ needs DB.Write           (was: module X only; now: modules X, Y)
  - needs IO.File            (removed — no longer reads config from disk)
```

Computation is a graph traversal over capability declarations the compiler already has.

### Capability coverage in test reports

```
$ forge test --cap-coverage

Test results: 47 passed, 0 failed

Capability coverage:
  Cap(IO.Console)        ✓  covered by 12 tests
  Cap(DB.Read)           ✓  covered by 8 tests
  Cap(DB.Write)          ✓  covered by 3 tests
  Cap(Payment.Gateway)   ✗  not covered — 0 tests exercise this path
  Cap(IO.Network)        ~  covered indirectly via Payment.Gateway
  Cap(Panic.Arithmetic)  ✓  covered by 2 tests
```

A higher-level coverage metric than line coverage — which *behaviors* are untested, not which lines.

### Capability audit query

```
$ forge cap query --needs IO.Network

Modules requiring Cap(IO.Network):
  stdlib/http_client.march      (direct)
  stdlib/websocket.march        (direct)
  stdlib/payment_gateway.march  (direct)
  app/billing.march             (via payment_gateway)
  app/webhooks.march            (via http_client)
```

Useful for security audits, compliance reviews, and blast-radius analysis.

---

## 9. Implementation Roadmap

### Phase 2a — Proof tokens (low cost)

- `proof cap Name` declaration form (lexer/parser/AST) ✅
- Producer registry in `typecheck.ml` (`env.proof_caps`) ✅
- Enforcement: proof caps cannot be produced by `cap_narrow` or `root_cap` ✅
- Check 1 (needs gate): must declare `needs X` to use `Cap(X)` where X is a proof cap ✅
- Check 6 (forgery ban): external modules and `pfn` within declaring module cannot mint ✅ (external); **`pfn`-in-declaring-module restriction** — in progress
- Implicit `needs` for declaring module: `proof cap X` in `mod M` auto-satisfies `needs M.X` — in progress
- Error message: name the declaring module in forgery/missing-needs errors ✅
- **Scope:** ambient-fact caps only; data-bound proofs use opaque refined types (existing module opacity)
- 6 tests (capabilities 19–24) ✅

Estimated: ~300 lines across `lexer.mll`, `parser.mly`, `ast.ml`, `typecheck.ml`. No runtime changes.

### Phase 2b — Typestate via `Handle(R, S)` (medium cost)

- `Handle(R, S)` type constructor (parser/AST/typecheck)
- State transition declarations (new surface syntax); transition graph in `typecheck.ml`
- Call-site enforcement: handle state matches expected state
- Error messages: protocol sequence display
- State type variables implicit and inferred (no explicit bounded syntax until Phase 3)

Estimated: 400–800 lines. No runtime changes.

### Phase 2c — Specialization tags via `Tagged(X, T)` (split cost)

- `Tagged(X, T)` type constructor (parser/AST/typecheck)
- Narrowing rules: `Tagged(DSP, Realtime)` does not subsume `Cap(Alloc)` / `Cap(IO)` / `Cap(Panic)`
- **Type-indexed (SIMD width, sized buffers): low** — existing `TNat` + mono; no new work
- **Policy tags (AllocPolicy, Platform, RealtimePolicy): medium-high** — conditional-lowering/DCE pass in `lib/tir/`; not plain monomorphization
- Realtime exclusion (the one §5 item in scope): small addition to `cap_subsumes`

Estimated: 300–500 lines in `typecheck.ml` + `lib/tir/` work for DCE pass.

### Phase 2d — Environment records (low cost)

- No new type system work; records of caps are already expressible
- Library convention: env modules provide named narrowing functions
- Testing: function-field injection (ordinary first-class functions — no new mechanism)

### Phase 2e — Panic capability (deferred)

Out of scope for Phase 2. Deferred to its own sub-spec. Phase 2 ships only the realtime-exclusion narrowing rule (already in 2c). Write the sub-spec when a concrete embedded/realtime use case requires the full retrofit.

### Phase 2f — Tooling (ongoing)

- Capability hover info: low (hierarchy already queryable)
- `forge cap diff` / `forge cap query`: medium (extract declarations from compile artifacts)
- Capability-filtered completions: medium (LSP queries available caps at cursor)
- Capability coverage: high (test runner tracks exercised caps — needs design; static analysis of executed paths is simpler, dynamic instrumentation is more precise)

### Phase 2g — Error message enhancements (ongoing)

Incremental, added alongside each phase. The `MPCode`/`MPText`/`MPBreak` infrastructure is already in place.

---

## 10. What This Does Not Change

- **Phase 1 enforcement** — all five existing checks in `check_module_needs` remain unchanged
- **`root_cap` and `cap_narrow`** — the existing narrowing model is preserved; proof caps simply cannot be produced by narrowing
- **Session types** — `Handle` complements session types; it does not replace them. Session types remain the right tool for two-party protocols with external branching
- **Linear/affine types** — `Handle` uses linearity but does not change the linear type system
- **The runtime** — no runtime changes in Phase 2. All new types (`Handle`, `Tagged`, proof caps) are runtime-erased

---

## 11. Design Decisions Recorded

### §11.1 — `Cap` second-parameter collision (RESOLVED)

`Cap(A, e : Epoch)` from `specs/epochs-design.md` already uses `Cap`'s second parameter for epoch tracking and is a real runtime value (heap-allocated, ~80 bytes). The typestate and specialization-tag proposals originally wanted that same second slot. **Decision: distinct constructors** — `Handle(R, S)` for typestate, `Tagged(X, T)` for specialization. Keeps the three systems independently evolvable. `Cap(X)` stays the permission capability.

### §11.2 — Proof caps are not ordinary ADTs

Phase 1 cap arguments are capability paths (`IO`, `IO.Console` → `TCon("IO", [])`), not arbitrary user ADTs. `type Validated = Validated` declares an ADT constructor, not a capability. The `proof cap Name` form registers `Name` as a user-declared capability in the capability namespace, not the type namespace.

### §11.3 — Proof tokens don't bind payload (RESOLVED via decision A)

A non-linear `Cap(Validated)` proves "validate was called," not "*this* value is validated." `save(validatedCap, unvalidatedData)` would typecheck. **Decision:** restrict proof caps to payload-independent ambient facts; use opaque refined types for data-bound proofs. Applied throughout §1.

### §11.4 — "Specialization is free" only for type-indexed cases

Monomorphization substitutes types and clones bodies; it does not prune code based on phantom tag values. SIMD width (a real `TNat`) specializes for free. Policy tags (AllocPolicy / RealtimePolicy / Platform) that select whether code is *present* require a conditional-lowering/DCE pass — new work in `lib/tir/`. Roadmap (2c) reflects this.

### §11.5 — Cap runtime representation (RESOLVED)

Investigated against the compiler:
- `root_cap` → `null` pointer literal in LLVM (`llvm_emit.ml:1225`), `VUnit` in interpreter (`eval.ml:7048`)
- `cap_narrow` → identity pass-through in C runtime (`march_runtime.c:2757`), no-op in interpreter (`eval.ml:7049`)
- `Cap(A, e)` from `get_cap` → real heap object: rc, actor ptr, pid_index, epoch (`march_runtime.c:2993`)

**Consequence:** permission caps carry no runtime data; mock-cap substitution is impossible. §4's testing story redesigned around function-field injection. `Handle` and `Tagged` are zero-overhead (same erased model).

### §11.6 — Panic-as-capability is a language-wide retrofit (RESOLVED via decision re scope)

Requiring `Cap(Panic)` for `/`, `%`, indexing, and `assert` touches essentially all arithmetic/indexing in stdlib and user code. **Decision:** defer the full retrofit. Phase 2 ships only the realtime-exclusion narrowing rule (a small addition to `cap_subsumes`), which delivers the headline guarantee without the migration cost.

---

## Open Questions

**Q1 — Proof cap constructors:** Resolved — module-scoped only. No language-level builtin. The declaring module is the mint; it controls issuance.

**Q2 — Typestate pattern match refinement:** Deferred. The transition-function model is sufficient for Phase 2b. GADT-style refinement is a future type system extension.

**Q3 — Environment records as first-class construct:** Plain records plus module-convention narrowing functions. No language-level construct in Phase 2.

**Q4 — `Cap(Panic)` granularity:** Deferred with the full panic retrofit.

**Q5 — Forge capability coverage implementation:** To be decided at implementation time. Static analysis of executed paths (simpler, less precise) vs. call-site instrumentation (more precise, more work).

**Q6 — Explicit bounded type-parameter syntax:** Deferred to Phase 3. Phase 2 uses implicit state/tag type variables inferred from transition/narrowing rules.

**Q7 — Allocation count assertions in tests:** Open. TIR/Perceus allocation insights (already exist) can surface per-function allocation data; a runtime allocation counter behind a test flag is the alternative.
