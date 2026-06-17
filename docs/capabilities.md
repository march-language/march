---
layout: page
title: Capabilities
nav_order: 18
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

```march
mod Db do
  proof cap Migrated

  fn run_migrations(raw : Cap(Db.Raw)) : Cap(Db.Migrated) do
    execute_pending_migrations(raw)
    mk_migrated_cap()   -- private factory, not exported
  end

  fn start_app(m : Cap(Db.Migrated)) : () do
    -- cannot be called without migration proof
    ...
  end
end
```

`Cap(Db.Migrated)` is unforgeable:

- `cap_narrow` cannot produce it (it's not in the IO hierarchy)
- `root_cap` cannot produce it
- The only factory (`mk_migrated_cap`) is private to `mod Db`
- External code that receives `Cap(Db.Migrated)` can pass it through, but cannot create one

### Enforcement rules

**Check 1 — must declare `needs`:** Any module that accepts or returns `Cap(Db.Migrated)` must declare `needs Db.Migrated`. The error names the declaring module:

```
Cap(Db.Migrated) is a proof capability declared in module Db.
Add `needs Db.Migrated` to module App to acknowledge this dependency.
Only Db can mint Cap(Db.Migrated) — callers must receive it as a parameter.
```

**Check 6 — no forgery:** A function outside `Db` cannot have `Cap(Db.Migrated)` in its return type unless it received that cap as a parameter:

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

## Planned: Phase 2b — Typestate via `Handle(R, S)`

The next capability phase adds `Handle(R, S)` for resource lifecycle protocols. A database connection that starts `Closed` and must be `Open` before reading is expressed as:

```march
fn connect(cap : Cap(IO.Network)) : Handle(Conn, Closed)
fn open(h : Handle(Conn, Closed)) : Handle(Conn, Open)
fn query(h : Handle(Conn, Open), sql : String) : List(Row)
fn close(h : Handle(Conn, Open)) : Handle(Conn, Closed)
```

The compiler rejects calls in the wrong state at compile time. See `specs/capability-system-design.md §2` for the full design.
