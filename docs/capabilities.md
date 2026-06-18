---
layout: docs
title: Capabilities
nav_order: 18
permalink: /docs/capabilities/
---

# Capabilities

March has a two-layer capability system that enforces *what your code is allowed to do* at compile time, with no runtime overhead.

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
├── IO.Console
├── IO.FileRead
├── IO.FileWrite
├── IO.FileSystem
├── IO.Network
│   ├── IO.Network.Client
│   └── IO.Network.Server
├── IO.Process
└── IO.Clock
```

A module that declares `needs IO` can pass `Cap(IO)` to any function that requires a narrower cap. Use `cap_narrow` to produce a sub-capability:

```march
fn restricted(cap : Cap(IO)) : () do
  let net_cap = cap_narrow(cap)  -- Cap(IO) → Cap(IO.Network)
  Server.listen(net_cap, 8080)
end
```

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

Proof caps suit **ambient, payload-independent facts** — things that are true about the system rather than a specific value:

| Proof cap | Meaning |
|-----------|---------|
| `Cap(Db.Migrated)` | Database migrations have run |
| `Cap(Auth.Authenticated)` | The current request has a verified identity |
| `Cap(App.Initialized)` | Application startup has completed |
| `Cap(Config.Loaded)` | Configuration has been validated |

### When *not* to use proof caps

If the proof must be tied to a specific value ("this `String` has been sanitized"), use an **opaque refined type** instead:

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

A detached `Cap(Sanitized)` would prove "some string was sanitized" without binding it to the specific string you're about to render. The opaque type approach ties proof and data together.

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
