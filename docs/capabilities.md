---
layout: docs
title: Capabilities
nav_order: 18
permalink: /docs/capabilities/
---

# Capabilities

March makes side effects **visible in your types** — zero runtime overhead, enforced at compile time. This guide explains what capabilities are, when to reach for each kind, when to leave them alone, and how they compose.

---

## The problem they solve

In most languages, a function's signature tells you what data flows in and out. It says nothing about what the function *does to the world*:

```python
# Does this read a file? Call the network? Write to a database?
# You have to read the implementation to find out.
def compute_price(product_id: str) -> float:
    ...
```

That invisibility causes three recurring problems:

**Accidental effects.** A function you thought was pure secretly calls a logger, which opens a file, which fails in a read-only sandbox. You find out at runtime.

**Unclear contracts.** "Does this library ever write files?" requires reading all the source. No amount of documentation fully substitutes for a machine-checked declaration.

**Audit blind spots.** Answering "which modules talk to the network?" in a large codebase means grepping and hoping — unless the compiler tracks it.

March's capability system addresses all three. Effects appear in the type, the compiler traces them transitively through the call graph, and the *absence* of a capability declaration is a machine-verified guarantee of purity:

```march
mod Price do
  -- No `needs`. The compiler verifies this module is completely pure.
  fn compute(base : Float, discount : Float) : Float do
    base * (1.0 - discount)
  end
end
```

---

## Which tool do I need?

| Problem | Tool |
|---------|------|
| Control what external resources a module may touch | IO caps (`needs` / `Cap(X)`) |
| Guarantee a function is pure | Declare nothing — absence enforces it |
| Prove initialization ran before dependent code | Proof caps (`proof cap`) |
| Prove a specific value has been processed | Opaque refined type (`ptype`) |
| Track a resource's open/closed/consumed lifecycle | Typestate (`always_linear type` + `transitions`) |
| Exclude allocation/IO from a realtime callback | Specialization tag (`Tagged(X, Realtime)`) |
| Thread many capabilities without parameter explosion | Capability environment record |

---

## IO permission caps

Every module that touches external resources declares `needs`:

```march
mod Server do
  needs IO.Network

  fn listen(cap : Cap(IO.Network), port : Int) : () do
    ...
  end
end
```

The compiler enforces this transitively. If your module calls `Server.listen`, you must also declare `needs IO.Network` — or the build fails with a clear message telling you which call requires which cap.

### Capability hierarchy

`Cap(IO)` is the root. Sub-capabilities narrow what is allowed:

```
IO
├── IO.Console          — stdout/stderr (println, print)
├── IO.FileSystem
│   ├── IO.FileRead     — read files, list directories
│   └── IO.FileWrite    — write, delete, rename files/dirs
├── IO.Network
│   ├── IO.NetConnect   — outbound TCP, WebSocket
│   │   ├── IO.NetConnect.TLS  — encrypted transport (tls_connect, tls_accept, …)
│   │   └── IO.Database — database connections (declaration-only; child of NetConnect)
│   └── IO.NetListen    — bind + listen on a port
├── IO.Process          — env vars, child processes, process exit
├── IO.Clock            — wall clock, monotonic time
├── IO.Random           — CSPRNG (random_bytes, uuid_v4)
├── IO.Spawn            — task spawning (task_spawn, task_spawn_link, …)
├── IO.Mut              — shared mutable state (Vault tables)
├── IO.Telemetry        — telemetry/observability emission (declaration-only)
└── IO.Foreign          — calling unverified C (extern blocks)
    └── IO.Foreign.Blocking — blocking extern (spawns OS thread)
```

A module that declares `needs IO` can pass `Cap(IO)` to any function that requires a narrower cap. Use `cap_narrow` to produce a sub-capability — it's free, compile-time only:

```march
fn start(cap : Cap(IO)) : () do
  let net_cap  : Cap(IO.NetListen)      = cap_narrow(cap)
  let tls_cap  : Cap(IO.NetConnect.TLS) = cap_narrow(cap)
  Server.listen(net_cap, 8080)
end
```

### Choosing the right level

Use the **narrowest capability that accurately describes what the code actually does**. Narrower declarations make stronger claims; the compiler verifies them.

| What the code does | Declare |
|--------------------|---------|
| No external state, no I/O | *(nothing — pure by declaration)* |
| Print to stdout/stderr | `needs IO.Console` |
| Read files or directories | `needs IO.FileRead` |
| Write, delete, or rename files | `needs IO.FileWrite` |
| Read **and** write files | `needs IO.FileSystem` |
| Outbound TCP or WebSocket | `needs IO.NetConnect` |
| Outbound HTTPS only — no plaintext TCP | `needs IO.NetConnect.TLS` |
| Accept inbound connections | `needs IO.NetListen` |
| Vault tables (shared mutable state) | `needs IO.Mut` |
| Spawn green tasks | `needs IO.Spawn` |
| Wall clock or sleep | `needs IO.Clock` |
| Random number generation | `needs IO.Random` |
| Environment variables, child processes | `needs IO.Process` |
| Calling C via `extern` | `needs IO.Foreign` |
| Blocking C calls (OS threads) | `needs IO.Foreign` + `needs IO.Foreign.Blocking` |
| Application entry point or top-level composition | `needs IO` |

**In libraries, prefer narrow caps.** A library that only reads config files should declare `needs IO.FileRead`, not `needs IO`. Callers can then hand it a read-only view, statically proving it cannot secretly write.

**In entry points, `needs IO` is fine.** The interesting precision lives in the libraries. Application main modules compose everything; they don't need to obsess over narrowing.

### What the compiler tells you

When you call something effectful without declaring the matching cap, the compiler is specific:

```
Warning: Config.load uses IO.FileRead but mod App does not declare `needs IO.FileRead`.
hint: add `needs IO.FileRead` to the module body.
```

There are no false positives. Follow the hint, build again. The compiler traces the full call graph so it catches transitive effects too.

### When *not* to use IO caps

**Pure functions need nothing.** If a function hashes a string, parses JSON, sorts a list, or formats a number, write no `needs`. The absence of `needs` is itself a machine-verified guarantee.

**Don't over-narrow to look principled.** Declaring `needs IO.FileRead` when your function also writes is a lie the compiler will catch. If a function reads and writes, `needs IO.FileSystem` is correct even if it feels "less precise." Accurate beats narrow-but-wrong.

**Don't use IO caps for pure domain concepts.** A function that validates an email address or checks a constraint has no business with capabilities. Capabilities exist for external state, not for logic.

**Don't use capabilities for per-value guarantees.** `Cap(IO.FileRead)` proves a module is *allowed* to read files; it says nothing about whether a specific string value came from a trusted source. For per-value guarantees, use an opaque refined type.

**Small scripts: just use `needs IO`.** For a 50-line script you'll run once, fine-grained capability declarations add more friction than value. Use `needs IO` at the top and move on. The value of narrow caps emerges in larger codebases with multiple contributors over time.

---

## Specific IO capabilities

### IO.Mut — shared mutable state

`IO.Mut` covers Vault tables — process-global shared mutable hash maps. A module with no `needs IO.Mut` is statically proven never to touch shared mutable state:

```march
mod Cache do
  needs IO.Mut

  fn store(key : String, val : Int) : () do
    let tbl = vault_new("app_cache")
    vault_set(tbl, key, val)
  end
end
```

This is especially useful for library code that should have no hidden state.

### IO.NetConnect.TLS — encrypted transport only

`IO.NetConnect.TLS` is a child of `IO.NetConnect`. Declaring it (without `IO.NetConnect`) proves the module uses *only* encrypted connections — no plaintext TCP. Declaring `needs IO.NetConnect` covers both.

```march
mod HttpsClient do
  needs IO.NetConnect.TLS  -- plaintext TCP is statically excluded

  fn fetch(fd, h, host) do
    tls_connect(fd, h, host)
  end
end
```

### IO.Telemetry — observability annotation

`IO.Telemetry` is declaration-only: the compiler accepts it as a semantic annotation but does not scan for specific builtins. Use it to make telemetry visible in a module's surface contract so callers know this module emits observability data:

```march
mod Metrics do
  needs IO.Telemetry

  fn record_request(duration : Int) : () do
    ...
  end
end
```

### IO.Foreign — calling unverified C

`IO.Foreign` is a meta-capability triggered by the **presence of an `extern` block** — not by any specific builtin call. C code bypasses every March type guarantee, so the compiler requires you to acknowledge this explicitly.

```march
mod Bindings do
  needs IO.Foreign
  needs IO.FileSystem  -- the specific cap the C code uses

  extern "libc": Cap(IO.FileSystem) do
    fn read(fd : Int, buf : String, n : Int) : Int
  end
end
```

The `blocking` modifier spawns an OS thread. Declare both caps when any extern function is blocking:

```march
mod Bindings do
  needs IO.Foreign
  needs IO.Foreign.Blocking
  needs IO.FileSystem

  extern "libc": Cap(IO.FileSystem) do
    blocking fn slow_read(fd : Int) : Int
  end
end
```

`needs IO.Foreign` alone subsumes `IO.Foreign.Blocking` (parent covers child), so one declaration suppresses both warnings if you prefer coarser annotations.

---

## Behavioral module caps — `cap no_panic` and `cap no_alloc`

Beyond IO permission caps and proof caps, March has two *behavioral* capability declarations that trigger static analysis passes rather than type-system enforcement. They live in the module body alongside `needs` declarations.

### `cap no_panic` — guaranteed panic-free

```march
mod SafeMath do
  cap no_panic

  fn divide(a : {v : Int | v >= 0}, d : {v : Int | v > 0}) : Int do
    a / d
  end
end
```

A module with `cap no_panic` must not contain any expression that can panic at runtime. The compiler enforces this with two sub-checks:

1. **Panic-surface ban** — `refine_check.ml` flags calls to functions that can panic (`assert`, `error`, etc.) when reachable without a proof of non-panic.
2. **Division safety** — `division_safety.ml` proves every integer divisor is non-zero via the Z3 SMT solver. Both literal divisors (`a / 0` → immediate error) and variable divisors are handled:
   - Variable with an Int refinement `{v | pred}`: Z3 discharges `pred ⊢ v ≠ 0`; fast syntactic short-circuit for common patterns (`v > 0`, `v >= 1`, `v != 0`, `v < 0`).
   - Let-bound variable: Z3 discharges `var = rhs ⊢ var ≠ 0` with param assumptions injected.
   - No refinement or unsupported expression: conservative error.

When Z3 is absent, `cap no_panic` is still conservatively enforced — `Unverified` outcomes are treated as errors.

**Use `Math.checked_div` / `Math.checked_mod`** when you cannot prove the divisor non-zero statically; they return `Option(Int)` instead of panicking.

### `cap no_alloc` — no heap allocation

```march
mod RealTimeDSP do
  cap no_alloc

  fn mix(a : Float, b : Float, gain : Float) : Float do
    (a + b) * gain
  end
end
```

`no_alloc.ml` walks every function body and flags heap-allocating expressions:

| Allocating expression | Error |
|-----------------------|-------|
| `ETuple` with ≥1 items | tuple construction allocates |
| `ERecord` | record construction allocates |
| `ECon` with ≥1 args (e.g. `Some(x)`) | boxed constructor allocates |
| `ELam` | lambda/closure allocates |

Nullary constructors (`None`, `True`, `False`, custom zero-arg tags) and unit `()` are safe — they compile to immediate integer tags with no heap allocation.

The check recurses into sub-expressions inside `if`, `match`, `let`, blocks, etc.

### Choosing between the two

| I want to… | Use |
|------------|-----|
| Prove no integer division can panic | `cap no_panic` + Int refinements on divisor params |
| Guarantee safe use in a realtime audio callback | `cap no_alloc` (+ `Tagged(DSP, Realtime)` for the calling site) |
| Both — pure, panic-free, zero-alloc | `cap no_panic` and `cap no_alloc` together |

Both declarations can coexist in the same module. Each is checked by its own independent pass.

---

## Capability inference hints

If you call a function that requires a `needs X` declaration but your module doesn't have one, the compiler emits a **hint** (not an error) pointing to the call site:

```
hint: this call uses IO.FileRead but mod Config does not declare `needs IO.FileRead`.
hint: add `needs IO.FileRead` to the module body.
```

This is informational — the type checker already enforces `needs` as an error. The hint pass (`cap_infer.ml`) runs after typechecking and gives an actionable fix message in addition to the type error.

---

## Putting it together

Here's how capability declarations compose across a small web application. Reading the `needs` list of each module answers "what does this module do to the world?" without opening the implementation:

```march
mod Config do
  needs IO.FileRead          -- reads one config file, nothing else

  fn load(path : String) : Config do ... end
end

mod Metrics do
  needs IO.Telemetry         -- makes observability a visible architectural concern

  fn record(event : String, duration : Int) : () do ... end
end

mod Api do
  needs IO.NetListen         -- binds a port
  needs IO.NetConnect.TLS    -- outbound HTTPS only — no plaintext TCP
  needs IO.Mut               -- session vault

  fn start(io : Cap(IO.NetListen), tls : Cap(IO.NetConnect.TLS),
           mut : Cap(IO.Mut)) : () do
    HttpServer.new()
    |> HttpServer.plug(fn conn -> handle(conn, tls, mut))
    |> HttpServer.run(io, 8080)
  end
end

mod Main do
  needs IO

  -- The initial Cap(IO) is provided implicitly by the runtime to `main()` —
  -- there is no `root_cap()` call in user code.
  fn main(cap : Cap(IO)) : () do
    let config  = Config.load("/etc/myapp/config.toml")
    let io_cap  : Cap(IO.NetListen)      = cap_narrow(cap)
    let tls_cap : Cap(IO.NetConnect.TLS) = cap_narrow(cap)
    let mut_cap : Cap(IO.Mut)            = cap_narrow(cap)
    Api.start(io_cap, tls_cap, mut_cap)
  end
end
```

`Config` is provably read-only. `Api` cannot read files and cannot use plaintext TCP. If `Config.load` ever called a network function, the build would fail until `needs IO.NetConnect` was added — no audit needed.

---

## Runtime behaviour

All `Cap(X)` values are **runtime-erased**. They compile to `null` in LLVM IR and to `VUnit` in the interpreter. No allocation, no indirection, no overhead. Enforcement is purely at compile time.

---

## Hot-deploy authorization — node-local admission control

When using `forge deploy hot` to upgrade a running application, the node has a second opportunity to enforce capability discipline at deployment time — after signature verification, before the new code is loaded.

### How it works

A hot deploy activates only the **functions that changed** (each is sent as a separate signed activation message). For **each activated function**, `forge deploy hot` embeds that function's own inferred IO capabilities — the capabilities its own body actually requires — in the message. Admission is checked per activated function, not over the whole artifact. (This granularity matters: `--hot-reload` links the entire standard library, so a *whole-artifact* capability set would be dominated by the stdlib's footprint and identical for every app — useless for a policy. Gating on the changed function's own caps is what makes the policy discriminating.) The trust boundary is: the **base server binary is trusted** — the operator built and started it, with a policy — and each **hot-patched function** is what the gate governs.

The receiving node, for each activated function:

1. **Recomputes the capability set** — normalizes the function's declared caps and hashes them with BLAKE3, reproducing the digest that was signed during the deploy.
2. **Tamper-checks** — compares its computed digest to the signed value; a mismatch (`ERR cap_tamper`) aborts before dlopen. The tamper check is **unconditional** even when the function declares no capabilities: a genuinely cap-free function has the fixed digest `blake3("")`, so a stripped capability field on a signed message is detected rather than silently admitted.
3. **Applies the deployment policy** — if `MARCH_DEPLOY_POLICY` is set (a file path), the node verifies that every capability the activated function declares is subsumed by a capability listed in the policy; a capability outside policy (`ERR cap_policy <cap>`) aborts.

### Configuring the policy

Set the `MARCH_DEPLOY_POLICY` environment variable to a file path:

```bash
export MARCH_DEPLOY_POLICY=/etc/march/deploy-policy.txt
```

The policy file is line-delimited. Each non-empty, non-comment line is a permitted capability path:

```
# /etc/march/deploy-policy.txt
IO
IO.FileRead
IO.NetConnect.TLS
IO.Clock
```

An empty policy file or absent `MARCH_DEPLOY_POLICY` ⇒ permissive (all activations admitted). This is the default for backward compatibility. A policy constrains what *hot-patched* functions may do; it does not retroactively constrain the trusted base binary the operator already deployed.

### Threat model and scope

The policy is **authorization on a self-reported manifest** — a defense-in-depth layer, not a sandbox. A party with the signing key can lie about what capabilities the code uses. The node admission gate proves:

- The artifact was signed by the expected entity (Phase 4 ed25519 signature).
- The declared capability set has not been tampered with in transit (BLAKE3 tamper-check).
- The declared capabilities are within a static policy envelope (subsumption check).

It does **not** prove that the code actually *uses* only those capabilities — only that the manifest claims it does, and the claim is signed and untampered. Runtime enforcement via `cap no_panic`, `cap no_alloc`, FFI sandboxing, or OS-level confinement can provide stronger guarantees. For most deployments, the combination of compile-time capability verification + signed manifests + policy gates is sufficient.

---

## Proof caps — encoding initialization order

IO caps control *which resources* a module may touch. Proof caps control *when* dependent code may run. They're separate concerns.

### The problem they solve

Some operations must happen before others:

```march
-- What stops someone calling this before run_migrations?
fn query(sql : String) : List(Row) do ... end
```

A proof cap makes "migrations have run" part of the type:

```march
mod Db do
  proof cap Migrated

  fn run_migrations(raw : Cap(Db.Raw)) : Cap(Db.Migrated) do
    execute_pending_migrations(raw)
    ()   -- Cap is runtime-erased; () is the actual runtime value
  end

  fn query(m : Cap(Db.Migrated), sql : String) : List(Row) do
    -- cannot be called without migration proof
    ...
  end
end
```

`Cap(Db.Migrated)` is **unforgeable**:
- `cap_narrow` cannot produce it (it's not in the IO hierarchy)
- The runtime-provided `Cap(IO)` in `main()` cannot produce it
- Only public (`fn`) functions of `mod Db` can mint it — private (`pfn`) functions may pass it through but cannot create one from nothing
- External code can pass it through, but cannot create one

Any module that accepts `Cap(Db.Migrated)` must declare `needs Db.Migrated`. Forgery is a compile error:

```march
mod App do
  needs Db.Migrated

  -- ERROR: App cannot produce Cap(Db.Migrated) from nothing
  fn bad() : Cap(Db.Migrated) do () end

  -- OK: pass-through is allowed
  fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
end
```

### When to use proof caps

Proof caps suit **ambient, payload-independent facts** — things true about the *system*, not about a specific value:

| Proof cap | Meaning |
|-----------|---------|
| `Cap(Db.Migrated)` | Database migrations have run |
| `Cap(Auth.Authenticated)` | The current request has a verified identity |
| `Cap(App.Initialized)` | Application startup has completed |
| `Cap(Config.Loaded)` | Configuration has been validated |

The key test: **is there a single, well-defined place in the codebase that produces this capability?** If yes, a proof cap works cleanly. If initialization is diffuse, conditional, or happens in multiple places, a proof cap will feel awkward — use a runtime flag instead.

### When *not* to use proof caps

**Don't use proof caps for per-value facts.** If the guarantee must be tied to a specific value ("this `String` has been sanitized"), use an opaque refined type:

```march
mod Sanitize do
  ptype Sanitized = Sanitized(String)   -- private constructor

  fn sanitize(raw : String) : Sanitized do
    Sanitized(escape_html(raw))
  end

  fn render(s : Sanitized) : String do
    let Sanitized(text) = s
    text
  end
end
```

A `Cap(Sanitized)` would prove "some string was sanitized somewhere," but not that the string you're about to render *is* the one that was sanitized. The opaque type ties proof and data together — you physically cannot pass an unsanitized string to `render`.

**Don't use proof caps when there's no single mint point.** Unforgeability is only meaningful when the minting surface is small and auditable. If the initialization is spread across many code paths, the cap gives a false sense of safety.

---

## Typestate — tracking resource lifecycle

IO caps answer "is this module allowed to open a file?" Typestate answers "is *this specific handle* currently open or closed?"

### `Handle(R, S)` from the standard library

`stdlib/handle.march` ships a canonical typestate handle:

```march
always_linear type Handle(r, s) = Handle(Int)
```

The `r` parameter is a phantom *resource tag* and `s` is the current *state*. Because `Handle` is `always_linear`, dropping it without consuming it — or consuming it twice — are both compile-time errors.

```march
tag ConnTag
tag Closed
tag Open

fn connect(cap : Cap(IO.Network)) : Handle(ConnTag, Closed) do ... end
fn open(h : Handle(ConnTag, Closed)) : Handle(ConnTag, Open) do ... end
fn query(h : Handle(ConnTag, Open), sql : String) : (List(Row), Handle(ConnTag, Open)) do ... end
fn close(h : Handle(ConnTag, Open)) : Handle(ConnTag, Closed) do ... end
```

The wrong call order is a type error:

```march
let h0 = connect(net_cap)
let h1 = query(h0, "SELECT 1")  -- ERROR: expected Handle(ConnTag, Open), got Handle(ConnTag, Closed)
let h2 = open(h0)               -- OK
let (rows, h3) = query(h2, "SELECT 1")
let h4 = close(h3)
```

### Declaring transitions

A `transitions` block names every valid state transition. The compiler verifies each `via` function exists with the right signature, and warns about functions that look like transitions but aren't declared:

```march
mod Db do
  transitions Handle do
    ConnTag: Closed -> Open   via open
    ConnTag: Open   -> Open   via query
    ConnTag: Open   -> Closed via close
  end
end
```

### `always_linear type` for your own handles

```march
always_linear type FileHandle(s) = FileHandle(Int)

tag FileClosed
tag FileOpen

fn open_file(path : String) : FileHandle(FileClosed) do ... end
fn read_file(h : FileHandle(FileOpen)) : (String, FileHandle(FileOpen)) do ... end
fn close_file(h : FileHandle(FileOpen)) : FileHandle(FileClosed) do ... end
```

### `tag` — zero-arg phantom label types

`tag Foo` is shorthand for `type Foo = Foo` — a zero-argument phantom type for state labels and resource tags:

```march
tag ConnTag
tag Closed
tag Open
```

### When to use typestate

Use typestate when:
- A resource has a finite, well-defined lifecycle (closed → open → consumed)
- Calling operations in the wrong order is a programmer error worth preventing statically
- The resource must not be dropped without being explicitly released

Don't use it for:
- Simple flags or booleans that change frequently at runtime — the type parameter overhead isn't worth it
- Cases where the lifecycle state is dynamic and not known until runtime

The LSP shows typestate hover — hovering any `Handle(R, S)` expression displays the current state and all declared transitions from it.

---

## Advanced patterns

### Specialization tags — realtime exclusion

`Tagged(X, T)` annotates a capability with a policy. The key narrowing rule: a function taking `Tagged(_, Realtime)` is in a realtime context and cannot also hold `Cap(Alloc)`, `Cap(IO)`, or `Cap(Panic)`. The compiler rejects mixed signatures:

```march
type DSP = DSP
type Realtime = Realtime

-- ERROR: realtime functions cannot take Cap(IO)
fn bad(cap : Tagged(DSP, Realtime), io : Cap(IO)) : () do () end

-- OK: statically proven — no allocation, no IO, no panic
fn process(cap : Tagged(DSP, Realtime), buf : Buffer(Float32, 256)) : Buffer(Float32, 256) do
  ...
end
```

`Tagged` also covers type-indexed specialization (SIMD widths, buffer sizes) — monomorphization handles these for free:

```march
fn fft(cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)
-- monomorphization produces fft_256, fft_1024, etc.
```

### Capability environment records — reducing parameter count

When many functions need the same bundle of capabilities, threading individual `Cap(X)` parameters everywhere is tedious. Bundle them into a record instead:

```march
type RuntimeEnv = {
  io    : Cap(IO),
  clock : Cap(IO.Clock),
  net   : Cap(IO.Network)
}

fn run(env : RuntimeEnv, data : Input) : Output do ... end
```

Narrow to a restricted set by constructing a smaller record — the type system enforces what the callee can do structurally:

```march
type PluginEnv = { clock : Cap(IO.Clock) }

fn run_plugin(env : RuntimeEnv, plugin : Plugin) do
  plugin.run({ clock: env.clock })  -- plugin structurally cannot use IO or network
end
```

Each env module should provide named narrowing functions:

```march
mod RuntimeEnv do
  fn narrow_for_plugin(env : RuntimeEnv) : PluginEnv do
    { clock: env.clock }
  end
end
```

### Testing with capability environment records

`Cap(X)` values are runtime-erased, so you cannot swap them in tests. Pair the cap with a function field for swappable runtime behaviour:

```march
type LogEnv = {
  log_cap : Cap(IO.Console),  -- compile-time gate, erased at runtime
  write   : (String) -> ()    -- runtime behaviour — swappable in tests
}

fn test_process() do
  let captured = Ref.new([])
  let env : LogEnv = {
    log_cap: test_logger_cap(),
    write:   fn line -> Ref.update(captured, fn xs -> Cons(line, xs))
  }
  let result = process(env, test_input)
  assert_contains(Ref.get(captured), "expected message")
end
```

---

## Quick decision guide

| I want to… | Use |
|------------|-----|
| Prove a module never touches the network | Declare only non-network caps — compiler enforces absence |
| Guarantee a function is completely pure | Declare no `needs` — the compiler verifies it |
| Let a plugin only read the clock | `cap_narrow` to `Cap(IO.Clock)` at the call site |
| Guarantee migrations run before any query | `proof cap Migrated` in `mod Db` |
| Prove a specific string has been sanitized | Opaque refined type (`ptype`), not a proof cap |
| Track that a file handle is open vs closed | `always_linear type` + `transitions` (typestate) |
| Exclude allocation/IO from a realtime callback | `Tagged(DSP, Realtime)` |
| Thread many caps without adding parameters | Capability environment record |
| Prove integer division can never panic | `cap no_panic` + Int refinements on divisor params |
| Guarantee zero heap allocation (realtime/embedded) | `cap no_alloc` |
| Small script, just want it to work | `needs IO` — don't overthink it |
