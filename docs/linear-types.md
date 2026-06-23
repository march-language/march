---
layout: docs
title: Linear Types
nav_order: 6
permalink: /docs/linear-types/
---

# Linear and Affine Types

March's type system tracks ownership through **linear** and **affine** qualifiers. These let the compiler catch resource leaks and use-after-free bugs **at compile time** — not at runtime, and not by relying on a garbage collector.

---

## The Problem They Solve

Consider a file handle or database connection. These resources must be:
1. **Used** — you shouldn't open a file and forget to read or close it
2. **Closed exactly once** — closing twice is a bug
3. **Not shared** — concurrent access through the same raw handle leads to data corruption

In most languages, these are programmer responsibilities enforced by convention and code review. In March, the type system enforces them.

---

## Linear vs Affine

| Qualifier | Usage count | Meaning |
|-----------|-------------|---------|
| `linear` | **Exactly once** | Must be used — dropping it is a compile error |
| `affine` | **At most once** | May be dropped (unused), but cannot be used twice |

Both prevent **duplicating** (using twice). Linear additionally prevents **discarding** (never using).

---

## Linear Values

A linear type must be used exactly once:

```march
fn consume(linear h : Handle) : () do
  -- h must be used here — the compiler tracks this
  close(h)
end
```

If you forget to use a linear value, the compiler reports an error:

```march
fn bad(linear h : Handle) : () do
  ()    -- error: linear value `h` must be used
end
```

If you try to use it twice:

```march
fn also_bad(linear h : Handle) : () do
  close(h)
  close(h)   -- error: linear value `h` used more than once
end
```

### Linear Let Bindings

```march
fn read_file(path : String) : String do
  linear let handle : Handle = open_file(path)
  let content = read_all(handle)     -- consumes handle
  content
end
```

The `linear let` annotation tells the compiler this binding has linear semantics. You don't need to annotate everything — the type of `open_file` already carries the linear constraint.

---

## Affine Values

An affine type may be used zero or one times. This is useful for values that have a cleanup operation but where "not using" is acceptable (e.g., an optional connection):

```march
fn maybe_connect(affine cap : NetworkCap) : () do
  -- OK to drop cap without using it
  if should_connect do
    connect(cap)
  end
  -- No error if we fall through without using cap
end
```

The key property: you still cannot use an affine value twice.

---

## Linear Record Fields

Individual fields of a record can be linear:

```march
type Resource = {
  linear fd   : FileDesc,
  metadata    : String
}
```

The compiler tracks each linear field independently. Accessing `r.fd` consumes that field — you cannot access it again.

---

## Linearity and Memory

Linearity isn't only about correctness — it's the strongest case for March's
in-place memory model. A `linear` value has **reference count 1 by
construction**: the type system guarantees exactly one owner, so the compiler
never has to emit a single reference-count adjustment for it. At the value's last
use, it is simply freed — no scan, no count to check. This is the cleanest
[Perceus]({{ site.baseurl }}/docs/memory-model/) case there is.

The same guarantee makes actor message passing **zero-copy**. Sending an ordinary
value to another actor copies its bytes (so the two heaps stay disjoint). A
`linear` value can't be aliased, so sending it *transfers ownership* instead:
the runtime hands the pointer over and adjusts bookkeeping, with no bytes copied.
Uniqueness turns "send" from a copy into a move.

---

## Linear Types and Actors

Actors communicate by message passing. For safety, a linear value cannot be sent as a message directly — sending would require copying, and copying a linear value violates the uniqueness guarantee.

The actor system uses session types (see below) for typed communication channels where linear values can be transferred safely via `Send`/`Recv` channel handles.

---

## Session Types

Session types use binary typed channels — the two endpoints have **dual** types. If one end sends, the other must receive.

Define a protocol:

```march
protocol Transfer do
  Client -> Server : Int
  Server -> Client : Int
end
```

A channel endpoint is typed `Chan(Role, Protocol)`. Each operation consumes
the current endpoint and returns a continuation typed at the next protocol
step:

```march
fn client_side(ch : Chan(Client, Transfer)) : Int do
  let ch2 = Chan.send(ch, 42)        -- send consumes ch, returns continuation
  let (result, ch3) = Chan.recv(ch2) -- recv returns (value, continuation)
  Chan.close(ch3)
  result
end
```

The server side mirrors this with the dual sequence (`recv` then `send`):

```march
fn server_side(ch : Chan(Server, Transfer)) : () do
  let (n, ch2) = Chan.recv(ch)
  let ch3 = Chan.send(ch2, n * 2)
  Chan.close(ch3)
end
```

The channel endpoints are linear — each `Chan.send`/`Chan.recv` operation
consumes the old endpoint and returns a new one representing the next step of
the protocol. The compiler verifies the full protocol is followed.

> **What session types catch:** sending when you should receive, receiving the
> wrong type, abandoning a conversation half-finished, or letting the two ends
> drift out of step — all become compile errors. See
> [Session Types]({{ site.baseurl }}/docs/session-types/) for the full protocol
> syntax and duality rules.

---

## Capabilities as Linear Types

Capabilities (see [capabilities]({{ site.baseurl }}/docs/capabilities/)) use linear types to ensure a capability token cannot be forged or duplicated:

```march
fn read_secret(linear cap : Cap(Vault)) : String do
  Vault.read(cap, "secret_key")
  -- cap is consumed; caller must obtain a new one for further operations
end
```

Capability narrowing attenuates a capability to a sub-capability:

```march
fn restricted_op(cap : Cap(IO)) : () do
  let console_cap = cap_narrow(cap)   -- Cap(IO) -> Cap(IO.Console)
  greet(console_cap, "Alice")
end
```

---

## FFI and Linear Pointers

When calling C code, raw pointers are typed as `linear Ptr(a)`:

```march
extern "libc": Cap(LibC) do
  fn malloc(n : Int) : linear Ptr(a)
  fn free(linear ptr : Ptr(a)) : ()
end
```

This makes memory management explicit in the type — you cannot forget to `free` a `linear Ptr`, and you cannot `free` it twice.

---

## Practical Rules

1. **Use `linear` for resources with mandatory cleanup** — file handles, database connections, exclusive locks, capabilities you must return.

2. **Use `affine` for optional-use tokens** — things you might or might not use, but definitely shouldn't use twice.

3. **Ordinary values need no qualifier** — the default is unrestricted (can be copied, dropped, used many times).

4. **Pattern matching on a linear value consumes it** — each branch must use it in a compatible way.

5. **Linear fields in records** — accessing the field consumes it; you must use or explicitly drop each linear field.

---

## Why Both?

Many systems have only one kind of linear type. March has both because they solve different problems:

- `linear` ensures you can't **forget** to do something (close, release, respond)
- `affine` ensures you can't **duplicate** something, while allowing graceful abandonment

For example, a session channel must be completed (linear — you can't just drop it midway through a protocol). But an optional permission token might be affine — the operation is valid with or without it.

---

## Next Steps

- [Type System](types.md) — the broader type system context
- [Refinement Types](refinement-types.md) — the other compile-time safety layer: value predicates checked by an SMT solver
- [Actors](actors.md) — how linear types interact with actor message passing
- [Pattern Matching](pattern-matching.md) — destructuring linear values
