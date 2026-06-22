---
layout: docs
title: Capabilities
nav_order: 18
permalink: /docs/capabilities/
---

# Capabilities

March makes side effects **visible in your types**. A module that reads files, opens network connections, or writes to shared mutable state must declare those effects — and the compiler verifies every claim, transitively, at compile time with no runtime overhead.

## Why this matters

Most languages treat side effects as invisible. A function call might read environment variables, spawn threads, or make network requests, and none of that appears in its type. Three problems follow:

**Accidental effects.** A utility function you thought was pure turns out to call a logger, which opens a file handle, which fails in a sandbox. You find out at runtime, not at the call site.

**Unclear contracts.** A function's signature tells you what data flows in and out, but not what it *does to the world*. That knowledge lives in the implementation, the docs (if they exist), or institutional memory.

**Audit scope.** In a large codebase it becomes hard to answer "does this library ever write files?" or "which modules talk to the network?" without reading everything.

March's capability system addresses all three. A module that needs to read files must declare `needs IO.FileRead`. A function that must remain pure declares nothing — and the compiler verifies it stays that way. Effects flow upward through the call graph automatically: if your code calls something effectful, the compiler tells you to acknowledge it.

---

## Phase 1: IO permission caps (`needs` / `Cap(X)`)

Every module that touches external resources declares its requirements with `needs`:

```march
mod Server do
  needs IO.Network

  fn listen(cap : Cap(IO.Network), port : Int) : () do
    -- only reachable with a real network capability
    ...
  end
end
```

The compiler enforces this transitively: if your module calls `Server.listen`, you must also declare `needs IO.Network`.

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
│   └── IO.NetListen    — bind + listen on a port (tcp_listen, tcp_accept)
├── IO.Process          — env vars, child processes, process exit
├── IO.Clock            — wall clock, monotonic time
├── IO.Random           — CSPRNG (random_bytes, uuid_v4)
├── IO.Spawn            — task spawning (task_spawn, task_spawn_link, …)
├── IO.Mut              — shared mutable state (Vault tables)
├── IO.Telemetry        — telemetry/observability emission (declaration-only)
└── IO.Foreign          — calling unverified C (extern blocks)
    └── IO.Foreign.Blocking — blocking extern (spawns OS thread)
```

A module that declares `needs IO` can pass `Cap(IO)` to any function that requires a narrower cap. Use `cap_narrow` to produce a sub-capability:

```march
fn restricted(cap : Cap(IO)) : () do
  let net_cap = cap_narrow(cap)  -- Cap(IO) → Cap(IO.Network)
  Server.listen(net_cap, 8080)
end
```

`cap_narrow` is free — it reinterprets the type at compile time only.

### Choosing the right level

Use the **narrowest capability that accurately describes what the code actually does**. Narrower declarations make more precise claims, and the compiler verifies them.

| What the code does | Declare |
|--------------------|---------|
| No external state, no I/O | *(nothing — pure functions need no `needs`)* |
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

**In libraries, prefer narrow caps.** A library that only reads files should declare `needs IO.FileRead`, not `needs IO`. Callers can hand it a read-only view, statically proving the library cannot secretly write.

**In entry points, `needs IO` is fine.** Top-level application modules that compose everything don't need to obsess over narrowing. The interesting claims live in the libraries being called.

### When not to declare IO caps

**Pure functions need nothing.** If a function computes a hash, parses JSON, sorts a list, or formats a string, write no `needs`. The *absence* of `needs` is the documentation — it tells a reader (and the compiler) that no external state is involved.

**Don't over-narrow to look principled.** Declaring `needs IO.FileRead` when your function also writes is a lie the compiler will catch. If a function reads and writes, `needs IO.FileSystem` is correct even if it feels "less precise." Accurate beats narrow-but-wrong.

**Don't use capabilities for pure concepts.** A function that validates an email address or checks a regex needs no `needs` — capabilities exist for external state. Pure computation is already proven pure by having no declaration.

### IO.Mut — shared mutable state

`IO.Mut` covers any access to Vault tables, which are process-global shared mutable hash tables. A module that touches Vault (read or write) must declare `needs IO.Mut`:

```march
mod Cache do
  needs IO.Mut

  fn store(key : String, val : Int) : () do
    let tbl = vault_new("app_cache")
    vault_set(tbl, key, val)
  end
end
```

A module with no `needs IO.Mut` declaration is statically guaranteed never to touch shared mutable state — useful for proving that library code is side-effect-free.

### IO.NetConnect.TLS — encrypted transport

`IO.NetConnect.TLS` is a child of `IO.NetConnect`. It covers all TLS operations: establishing sessions (`tls_connect`, `tls_accept`), reading/writing (`tls_read`, `tls_write`), and querying session metadata (`tls_peer_cn`, `tls_negotiated_alpn`).

Declaring `needs IO.NetConnect.TLS` (without `IO.NetConnect`) proves the module only uses encrypted connections — no plaintext TCP. Declaring `needs IO.NetConnect` covers both plain TCP and TLS.

```march
mod HttpsClient do
  needs IO.NetConnect.TLS  -- no plaintext TCP allowed in this module

  fn fetch(fd, h, host) do
    tls_connect(fd, h, host)
  end
end
```

### IO.Telemetry — observability (declaration-only)

`IO.Telemetry` is a declaration-only capability: the compiler accepts `needs IO.Telemetry` as a semantic annotation but does not (yet) enforce it via body scanning. Use it to make telemetry emission visible in a module's surface contract:

```march
mod Metrics do
  needs IO.Telemetry

  fn record_request(duration : Int) : () do
    -- emit telemetry event via your telemetry module
    ...
  end
end
```

Applications that import `Metrics` will see `IO.Telemetry` in their transitive `needs` set, making observability a visible architectural concern.

### IO.Foreign — calling unverified C

`IO.Foreign` is a meta-capability that must be declared by any module containing an `extern` block. Unlike other IO caps, it is not triggered by specific builtin calls — it is triggered by the **presence of an `extern` block itself**, because C code can bypass every March type guarantee regardless of the declared `Cap(X)`.

Declaring `needs IO.Foreign` makes FFI usage grep-auditable: any module that reaches outside the type system is visible in its `needs` set.

```march
mod Bindings do
  needs IO.Foreign
  needs IO.FileSystem  -- the specific cap the C code uses

  extern "libc": Cap(IO.FileSystem) do
    fn read(fd : Int, buf : String, n : Int) : Int
  end
end
```

The `blocking` modifier on an extern function spawns an OS thread for the call. This is a distinct and stronger side effect than `IO.Spawn` (which spawns green tasks). A module with blocking externs should also declare `needs IO.Foreign.Blocking`:

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

`needs IO.Foreign` subsumes `needs IO.Foreign.Blocking` (parent covers child), so `needs IO.Foreign` alone suppresses both warnings if you prefer a coarser declaration.

### `extern` blocks

FFI bindings declare the capability they require:

```march
extern "libc": Cap(IO.FileSystem) do
  fn open(path : String, flags : Int) : Int
  fn read(fd : Int, buf : Ptr(Byte), n : Int) : Int
  fn close(fd : Int) : ()
end
```

---

## Putting it together

Here's how capability declarations compose across a small web application:

```march
mod Config do
  needs IO.FileRead          -- reads one config file, nothing else

  fn load(path : String) : Config do ... end
end

mod Metrics do
  needs IO.Telemetry         -- semantic annotation: this module emits telemetry

  fn record(event : String, duration : Int) : () do ... end
end

mod Api do
  needs IO.NetListen         -- binds a port
  needs IO.NetConnect.TLS    -- makes outbound HTTPS calls only (no plaintext)
  needs IO.Mut               -- session vault

  fn start(io : Cap(IO.NetListen), tls : Cap(IO.NetConnect.TLS),
           mut : Cap(IO.Mut)) : () do
    let session = Session.new(mut)
    HttpServer.new()
    |> HttpServer.plug(fn conn -> handle(conn, tls, session))
    |> HttpServer.run(io, 8080)
  end
end

mod Main do
  needs IO

  fn main() : () do
    let config  = Config.load("/etc/myapp/config.toml")
    let io_cap  : Cap(IO.NetListen)      = cap_narrow(root_cap())
    let tls_cap : Cap(IO.NetConnect.TLS) = cap_narrow(root_cap())
    let mut_cap : Cap(IO.Mut)            = cap_narrow(root_cap())
    Api.start(io_cap, tls_cap, mut_cap)
  end
end
```

Reading each module's `needs` list answers "what does this module do to the world?" without opening the implementation. `Config` is provably read-only. `Api` can neither read files nor use plaintext TCP. The compiler verifies every claim: if `Config.load` ever called a network function, the build would fail until `needs IO.NetConnect` was added.

---

## Phase 2a: Proof capability tokens (`proof cap`)

Proof caps enforce **sequencing** — that a specific initialization step has run before dependent code is called.

### Declaring a proof cap

Only **public (`fn`) functions** in the declaring module can mint a proof cap. Private (`pfn`) functions face the same forgery restriction as external modules — they may pass a cap through, but cannot produce one from nothing. This makes the module's public API the complete minting surface.

The declaring module implicitly satisfies its own `needs` for any cap it declares — no explicit `needs Db.Migrated` is needed inside `mod Db`.

```march
mod Db do
  proof cap Migrated

  -- Public factory — the only way to obtain Cap(Db.Migrated)
  fn run_migrations(raw : Cap(Db.Raw)) : Cap(Db.Migrated) do
    execute_pending_migrations(raw)
    ()   -- Cap is runtime-erased; () is the actual runtime value
  end

  fn start_app(m : Cap(Db.Migrated)) : () do
    -- cannot be called without migration proof
    ...
  end

  -- Private pass-through OK; private minting is not
  pfn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end   -- fine
  -- pfn forge() : Cap(Db.Migrated) do () end                   -- ERROR
end
```

`Cap(Db.Migrated)` is unforgeable:

- `cap_narrow` cannot produce it (it's not in the IO hierarchy)
- `root_cap` cannot produce it
- No `pfn` inside `mod Db` can produce it from nothing
- External code that receives `Cap(Db.Migrated)` can pass it through, but cannot create one
- The minting surface is exactly the public API of `mod Db` — auditable at a glance

### Enforcement rules

**Check 1 — must declare `needs`:** Any module that accepts or returns `Cap(Db.Migrated)` must declare `needs Db.Migrated` (the declaring module is automatically exempt). The error names the declaring module:

```
Cap(Db.Migrated) is a proof capability declared in module Db.
Add `needs Db.Migrated` to module App to acknowledge this dependency.
Only public functions of Db can mint Cap(Db.Migrated) — callers must receive it as a parameter.
```

**Check 6 — no forgery:** A function outside `Db`, or a `pfn` inside `Db`, cannot have `Cap(Db.Migrated)` in its return type unless it received that cap as a parameter:

```march
mod App do
  needs Db.Migrated

  -- ERROR: App cannot produce Cap(Db.Migrated) from nothing
  fn bad() : Cap(Db.Migrated) do () end

  -- OK: pass-through is allowed
  fn relay(m : Cap(Db.Migrated)) : Cap(Db.Migrated) do m end
end
```

### Good use cases for proof caps

Proof caps suit **ambient, payload-independent facts** — things that are true about the system state, not about a specific value:

| Proof cap | Meaning |
|-----------|---------|
| `Cap(Db.Migrated)` | Database migrations have run |
| `Cap(Auth.Authenticated)` | The current request has a verified identity |
| `Cap(App.Initialized)` | Application startup has completed |
| `Cap(Config.Loaded)` | Configuration has been validated |

The key test: **is there a single, well-defined place in the codebase that produces this capability?** If yes, a proof cap works. If the initialization is diffuse, conditional, or happens in multiple places, a proof cap will feel awkward — use a runtime flag instead.

### When *not* to use proof caps

**Don't use proof caps for per-value facts.** If the proof must be tied to a specific value ("this `String` has been sanitized"), use an **opaque refined type** instead:

```march
mod Sanitize do
  -- Constructor is private — only this module can create Sanitized values
  ptype Sanitized = Sanitized(String)

  fn sanitize(raw : String) : Sanitized do
    Sanitized(escape_html(raw))
  end

  fn render(s : Sanitized) : String do
    let Sanitized(text) = s
    text
  end
end
```

A detached `Cap(Sanitized)` would prove "some string was sanitized" without binding it to the specific string you're about to render. The opaque type approach ties proof and data together — you physically cannot pass an unsanitized string to `render`.

**Don't use proof caps when there's no single mint point.** If the initialization logic is spread across multiple code paths, the cap becomes meaningless. The value of unforgeability comes from there being one clear entry point that does the work.

---

## Runtime behaviour

All `Cap(X)` values — IO permission caps and proof caps alike — are **runtime-erased**. They compile to `null` in LLVM IR and to `VUnit` in the interpreter. There is no allocation, no indirection, and no overhead. The enforcement is purely at compile time.

---

## Phase 2b/2c: Typestate handles (`always_linear type` + `transitions`)
{: #typestate-handles}

March has first-class support for **typestate** — compile-time tracking of a
resource's lifecycle state, encoded directly in the type.

### `Handle(R, S)` from the standard library

`stdlib/handle.march` ships the canonical typestate handle:

```march
always_linear type Handle(r, s) = Handle(Int)
```

The `r` parameter is a phantom *resource tag* and `s` is the current *state*.
Because `Handle` is declared `always_linear`, every binding of it is
automatically tracked as linear by the compiler — no `linear` annotation needed
at call sites. Dropping a handle without consuming it, or consuming it twice,
are both compile-time errors.

A database connection modelled with `Handle`:

```march
tag ConnTag    -- phantom resource label
tag Closed     -- state labels (zero-arg phantom types)
tag Open

fn connect(cap : Cap(IO.Network)) : Handle(ConnTag, Closed) do ... end
fn open(h : Handle(ConnTag, Closed)) : Handle(ConnTag, Open) do ... end
fn query(h : Handle(ConnTag, Open), sql : String) : (List(Row), Handle(ConnTag, Open)) do ... end
fn close(h : Handle(ConnTag, Open)) : Handle(ConnTag, Closed) do ... end
```

The type system rejects any call in the wrong state at compile time:

```march
let h0 = connect(net_cap)
let h1 = query(h0, "SELECT 1")  -- ERROR: expected Handle(ConnTag, Open), got Handle(ConnTag, Closed)
let h2 = open(h0)               -- OK
let (rows, h3) = query(h2, "SELECT 1")
let h4 = close(h3)
-- h4 : Handle(ConnTag, Closed) -- must eventually be released
```

### Declaring state-machine transitions with `transitions`

A `transitions` block names every valid state transition for a handle type. The
compiler checks:

1. Each `via` function exists in the module and has the right signature.
2. Functions in the same module that *look* like transitions but aren't declared
   produce a warning with the suggested declaration text.

```march
mod Db do
  transitions Handle do
    ConnTag: Closed -> Open   via open
    ConnTag: Open   -> Open   via query
    ConnTag: Open   -> Closed via close
  end
end
```

Syntax: `ResourceTag: FromState -> ToState via function_name`. Multiple arms in
one block; one block per handle type per module.

### `always_linear type` for your own handles

You can declare your own always-linear handle:

```march
always_linear type FileHandle(s) = FileHandle(Int)

tag FileClosed
tag FileOpen

fn open_file(path : String) : FileHandle(FileClosed) do ... end
fn read_file(h : FileHandle(FileOpen)) : (String, FileHandle(FileOpen)) do ... end
fn close_file(h : FileHandle(FileOpen)) : FileHandle(FileClosed) do ... end
```

Any type declared `always_linear` gets the same compile-time enforcement as
`Handle`: automatic linear promotion at every binding site (let, parameter,
lambda parameter), and a compile error on drop or double-use.

### `tag` — zero-arg phantom label types

`tag Foo` is shorthand for `type Foo = Foo`. It declares a zero-argument type
used as a phantom label (state name or resource tag) without constructor boilerplate:

```march
tag ConnTag
tag Closed
tag Open
-- equivalent to:
-- type ConnTag = ConnTag
-- type Closed  = Closed
-- type Open    = Open
```

### Tooling

The LSP provides **typestate hover** — hovering any `Handle(R, S)` expression
shows the current state and all declared transitions from it (see
[LSP]({{ site.baseurl }}/docs/lsp/#typestate-and-capability-intelligence)).

`forge cap query` prints a project-wide capability and typestate summary (see
[Tooling]({{ site.baseurl }}/docs/tooling/#forge-cap--capability-and-typestate-inspection)).

---

## Phase 2c: Specialization tags (`Tagged(X, T)`)
{: #specialization-tags}

`Tagged(X, T)` is a two-argument phantom type constructor that annotates a
capability with a specialization policy. The tag `T` drives compile-time
behaviour without carrying any runtime value.

### Syntax

```march
fn dsp_callback(cap : Tagged(DSP, Realtime), buf : Buffer(Float32, 256)) : Buffer(Float32, 256)
```

`DSP` is the *tag kind* (a phantom type you declare) and `Realtime` is the
*policy value* (another phantom type).

### Realtime exclusion

The key narrowing rule: a function that takes `Tagged(_, Realtime)` is in a
**realtime context** and cannot also hold `Cap(Alloc)`, `Cap(IO)`, or
`Cap(Panic)`. The compiler rejects mixed signatures at compile time:

```march
type DSP = DSP
type Realtime = Realtime

-- ERROR: realtime functions cannot take Cap(IO)
fn bad(cap : Tagged(DSP, Realtime), io : Cap(IO)) : () do () end
```

```
Error: function `bad` takes Tagged(_, Realtime) but also takes Cap(IO).
Realtime functions cannot hold Cap(IO) — allocation, IO, and panic are excluded
from realtime contexts.
```

A correct realtime function signature takes only the `Tagged(DSP, Realtime)` cap:

```march
fn process(cap : Tagged(DSP, Realtime), buf : Buffer(Float32, 256)) : Buffer(Float32, 256) do
  -- statically proven: no allocation, no IO, no panic
  ...
end
```

Functions tagged with a non-`Realtime` policy (e.g. `Tagged(DSP, Standard)`) are
not restricted and may hold other capabilities alongside the tag.

### Type-indexed specialization

`Tagged` also covers type-indexed specialization (SIMD width, buffer sizes). In
this case the tag is a real `TNat` or type parameter that monomorphization already
handles for free — no new mechanism is needed:

```march
fn fft(cap : Tagged(SIMD, N), buf : Buffer(Float32, N)) : Buffer(Complex32, N)
-- monomorphization produces fft_256, fft_1024, etc. for each call site
```

---

## Phase 2d: Capability-parameterized environment records
{: #environment-records}

Instead of threading individual `Cap(X)` parameters through every function,
bundle related capabilities into a record. Narrowing to a restricted set is
**ordinary record construction** — the type system enforces what the callee can
do, not by policy, but by type.

### Bundling capabilities

```march
type RuntimeEnv = {
  io    : Cap(IO),
  clock : Cap(IO.Clock),
  net   : Cap(IO.Network)
}

fn run(env : RuntimeEnv, data : Input) : Output do
  -- pass env.io, env.clock, env.net to callees as needed
  ...
end
```

### Narrowing via record construction

Give a plugin only what it needs by constructing a smaller record:

```march
type PluginEnv = {
  clock : Cap(IO.Clock)
}

fn run_plugin(env : RuntimeEnv, plugin : Plugin) do
  let restricted = { clock = env.clock }
  plugin.run(restricted)   -- plugin's type lacks io and net fields
end
```

The plugin structurally cannot use IO or network — not by policy, but because
`PluginEnv` has no `io` or `net` field.

### Naming convention

Each env type's module should provide named narrowing functions:

```march
mod RuntimeEnv do
  fn narrow_for_plugin(env : RuntimeEnv) : PluginEnv do
    { clock = env.clock }
  end
end
```

### Testing with function fields

Since `Cap(X)` values are runtime-erased, you cannot swap them out in tests.
Instead, pair the cap with a function field that provides swappable runtime
behaviour:

```march
type LogEnv = {
  log_cap : Cap(IO.Console),   -- erased permission gate — compile-time only
  write   : (String) -> ()     -- runtime behaviour — swappable in tests
}

fn test_process() do
  let captured = Ref.new([])
  let env : LogEnv = {
    log_cap = test_logger_cap(),
    write   = fn line -> Ref.update(captured, fn xs -> Cons(line, xs))
  }
  let result = process(env, test_input)
  assert_contains(Ref.get(captured), "expected message")
end
```

The cap gates permission at compile time; the function field provides swappable
behaviour at runtime. No new mechanism required — ordinary first-class functions.

---

## Quick decision guide

| I want to… | Use |
|------------|-----|
| Prove a module never touches the network | Declare only non-network caps; absence enforced at compile time |
| Guarantee a function is completely pure | Declare no `needs`; the compiler verifies it |
| Let a plugin only read the clock | `cap_narrow` to `Cap(IO.Clock)` at the call site |
| Guarantee migrations run before any query | `proof cap Migrated` in `mod Db` |
| Prove a specific string has been sanitized | Opaque refined type (`ptype`), not a proof cap |
| Track that a file handle is open vs closed | `always_linear type` + `transitions` (typestate) |
| Exclude allocation/IO from a realtime callback | `Tagged(DSP, Realtime)` |
| Thread many caps without adding parameters | Bundle into a capability-parameterized env record |
