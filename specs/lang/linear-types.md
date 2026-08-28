---
layout: docs
title: Linear Types
nav_order: 5.4
permalink: /docs/linear-types/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Linear and Affine Types

March's type system tracks ownership through **linear** and **affine** qualifiers. These let the compiler catch resource leaks and use-after-free bugs **at compile time**, not at runtime, and not by relying on a garbage collector.

---

## The Problem They Solve

Consider a file handle or database connection. These resources must be:
1. **Used**: you shouldn't open a file and forget to read or close it
2. **Closed exactly once**: closing twice is a bug
3. **Not shared**: concurrent access through the same raw handle leads to data corruption

In most languages, these are programmer responsibilities enforced by convention and code review. In March, the type system enforces them.

---

## Linear vs Affine

| Qualifier | Usage count | Meaning |
|-----------|-------------|---------|
| `linear` | **Exactly once** | Must be used; dropping it is a compile error |
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
  ()
end
```

```
The linear value `h` was never used.
Linear values must be consumed exactly once — did you mean to pass it somewhere?
```

If you try to use it twice:

```march
fn also_bad(linear h : Handle) : () do
  close(h)
  close(h)
end
```

```
The linear value `h` is used more than once here.
Linear values must be consumed exactly once — they cannot be copied or ignored.
```

(Both verified live, 2026-07-10; these are the exact diagnostics; corpus
witnesses `specs/lang/types/reject/t58` and `t60`. Caveat for the name
`Handle` specifically: because the stdlib declares `always_linear type
Handle`, a user type NAMED `Handle` inherits linearity even without the
`linear` keyword; see "always_linear types" below.)

### Linear Let Bindings

```march
fn read_file(path : String) : String do
  linear let handle : Handle = open_file(path)
  let content = read_all(handle)     -- consumes handle
  content
end
```

The `linear let` annotation tells the compiler this binding has linear semantics. **The qualifier must appear at the binding site**: either the `linear let` keyword form, or a type annotation on the binding (`let h : linear Handle = ...`). A `linear` qualifier on the *callee's return type* by itself does NOT currently propagate to a plain `let` binding of the result (verified 2026-07-10: a dropped `let h = open_file(p)` with `open_file : ... -> linear Handle` is silently accepted; finding L8, `specs/todos/`). Earlier versions of this chapter claimed the return type was enough.

---

## Affine Values

An affine type may be used zero or one times. This is useful for values that have a cleanup operation but where "not using" is acceptable (e.g., an optional connection).

**Spelling matters:** `affine` is a *type modifier* only; write it inside the
type annotation. Unlike `linear`, there is no `affine` parameter keyword (the
form `fn f(affine cap : T)` is a **parse error**) and no `affine let`
(finding L1, `specs/todos/`):

```march
fn maybe_connect(cap : affine NetworkCap, should_connect : Bool) : () do
  if should_connect do
    connect(cap)
  else
    ()    -- OK: no error when cap goes unused on this path
  end
end
```

The key property: you still cannot use an affine value twice. The second use
rejects with:

```
The affine value `cap` is used more than once here.
Affine values may be used at most once.
```

(Verified live; corpus witnesses `accept/t66` (affine drop accepted) and
`reject/t64` (affine double-use rejected).)

---

## Linear Record Fields

Individual fields of a record can be linear:

```march
type Resource = {
  linear fd   : FileDesc,
  metadata    : String
}
```

The compiler tracks each linear field independently. Accessing `r.fd` consumes that field; a second access rejects with `` The linear value `r.fd` is used more than once here. ``

Two candid caveats (both live-verified, 2026-07-10):

- **Field tracking only engages for locally-`let`-bound records.** If the
  record arrives as a *function parameter*, the tracker has no sentinel for it
  and a double field access degrades to a warning (`Field `fd` has a linear
  type but linearity tracking is not available for `r` at this binding
  site.`); finding L3, open in `specs/todos/`. Bind the record with a
  `let` first to get real enforcement. Corpus witness: `reject/t63`.
- **Arithmetic on linear primitive fields works** (e.g. `r.count + 1` for a
  `linear count : Int` field), but only since 2026-07-10: previously the
  linearity wrapper leaked into `Num` resolution and rejected even a single,
  correct use (finding L2, fixed). Corpus witness: `accept/t67`.

---

## always_linear Types

The per-site qualifiers above have a whole-type sibling: `always_linear type`
declares a type where **every** binding is automatically tracked as linear;
no `linear` keyword needed at any use site. This is the primary mechanism for
typestate resource handles (the stdlib's `Handle` in `stdlib/handle.march` is
the canonical example, combined with `tag` phantom states):

```march
always_linear type Token = Token(Int)

fn main() : () do
  let t = Token(1)
  ()    -- error: The linear value `t` was never used.
end
```

See `surface-syntax.md`'s always_linear/`tag` section for the full typestate
pattern, and `core-march-types.md` §2.9.1 for the promotion rule.

> **Name-collision warning (finding L4, `specs/todos/`):** the
> `always_linear` registry is keyed by the bare type NAME, globally. If your
> program declares a plain type with the same name as any `always_linear`
> type, including the stdlib's `Handle`, your type silently inherits
> linearity, and its constructors confuse exhaustiveness checking. Until
> this is fixed, avoid reusing such names.

---

## Linearity and Memory

Linearity isn't only about correctness; it also feeds March's in-place
memory model. A `linear` value has a single owner by construction, which the
compiled backend exploits as an **optimization**: the linearity flag on a TIR
variable (`v_lin`) lets Perceus elide reference-count traffic where uniqueness
is guaranteed, and a `send` of a linear message compiles to a zero-copy
**ownership-transfer move** (`march_send_linear`) instead of a byte copy.
These are performance facts, not semantic ones: linearity is
**compile-time-erased**, and neither backend re-checks it at runtime (see
`core-march.md` §4.12; golden witness `g41_linear_annotations_erased`). See
[Perceus]({{ site.baseurl }}/docs/memory-model/) for the memory model.

---

## Linear Types and Actors

Sending a linear value to an actor **is allowed, and the send is the
consuming use**:

```march
linear let r : Res = R(7)
send(pid, StoreRes(r))   -- consumes r
take(r)                   -- error: The linear value `r` is used more than once here.
```

(Verified live; corpus witnesses `accept/t68` + `reject/t66`. Earlier
versions of this chapter claimed a linear value "cannot be sent as a message
directly"; that was never true, and it contradicted the zero-copy-move
paragraph above; finding L6, `specs/todos/`.) On the compiled backend the
transfer is a zero-copy move; interpreted, it is an ordinary handoff; either
way the type system prevents you from touching the value after the send.

For richer typed interaction patterns, the channel system below layers
session types on top of the same linearity infrastructure.

---

## Session Types

Session types use binary typed channels: the two endpoints have **dual** types. If one end sends, the other must receive.

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

The channel endpoints are linear: each `Chan.send`/`Chan.recv` operation
consumes the old endpoint and returns a new one representing the next step of
the protocol.

> **What session types catch, and the current enforcement scope:** sending
> when you should receive, receiving the wrong type, and reusing a consumed
> `let`-bound endpoint are compile errors. But enforcement runs on the same
> generic linear tracker described in this chapter, applied to `let`-threaded
> continuations **in one scope**; two shapes currently slip through
> (finding F7, `specs/todos/`): reusing a linear *parameter* endpoint at a
> state that coincidentally still matches, and abandoning an unclosed channel
> (never calling `Chan.close`) both typecheck and run cleanly today. See
> `core-march-types.md` §2.7.8 for the precise account, and
> [Session Types]({{ site.baseurl }}/docs/session-types/) for the full
> protocol syntax and duality rules.

---

## Capabilities as Linear Types

`Cap(X)` is, by default, an **ordinary unrestricted type**: `cap_narrow` is
free and side-effect-free, and a plain `Cap(X)` value can be passed to as
many callees as you like (see `core-march-types.md` §2.8, and
[Capabilities]({{ site.baseurl }}/docs/capabilities/)). Preventing a
capability from being *forged* is a separate mechanism: proof capabilities
are created only through the gated `mint_cap` primitive, not through
linearity (see `core-march-types.md` §2.8.13). What you *can* do is apply the
ordinary `linear` qualifier to a capability parameter, exactly as to any
other value, when a function should force its caller to give up the
capability for good:

```march
fn narrow_once(linear cap : Cap(IO)) : Cap(IO.FileRead) do
  cap_narrow(cap)   -- consumes cap; the caller cannot reuse it afterward
end
```

(Verified live, 2026-07-22. An earlier version of this section used a
`Cap(Vault)`/`Vault.read` example and claimed linearity is what stops
capability forging; neither held up: `Vault` is a stdlib module, not a
capability namespace, `Vault`'s real API is `Vault.get`/`Vault.set`, not
`read`, and `Cap(Vault)` is rejected with `` `Cap(Vault)` used in module
`Main` but `Vault` is not declared in `needs` ``.)

Capability narrowing attenuates a capability to a sub-capability:

```march
fn restricted_op(cap : Cap(IO)) : () do
  let console_cap = cap_narrow(cap)   -- Cap(IO) -> Cap(IO.Console)
  greet(console_cap, "Alice")
end
```

---

## FFI and Native Resources

There is no `Ptr` type in March, and no `linear Ptr(a)` spelling. The actual
mechanism for safe manual memory management across the FFI boundary is the
`resource` declaration together with the `consume` parameter mode. A
`resource` type is an opaque native handle that Perceus reference-counts like
any other value, invoking its destructor automatically when the last
reference is dropped; `consume` on an extern parameter transfers ownership
into that call so the compiler does not *also* auto-drop the binding
afterward (which would double-free):

```march
mod Bindings do
  needs IO.Foreign
  needs IO.FileSystem

  resource Buffer

  extern "libc": Cap(IO.FileSystem) do
    fn buffer_alloc(n : Int) : Buffer
    fn buffer_free(consume buf : Buffer) : ()
  end
end
```

This makes the ownership transfer explicit in the type: `buffer_free`
consumes `buf`, so a later use of `buf` in the same scope is a compile
error, the same double-use rejection this chapter has covered throughout.
(Verified live, 2026-07-22; corrects an earlier sketch that used a
fictitious `Ptr(a)` type and a `Cap(LibC)` capability namespace; neither
exists. See `test/native/ffi_resource.march` for a full worked example with
the `consume` mode.)

---

## Practical Rules

1. **Use `linear` for resources with mandatory cleanup**: file handles, database connections, exclusive locks, capabilities you must return.

2. **Use `affine` for optional-use tokens**: things you might or might not use, but definitely shouldn't use twice.

3. **Ordinary values need no qualifier**: the default is unrestricted (can be copied, dropped, used many times).

4. **Pattern matching on a linear value consumes it**: each branch must use it in a compatible way.

5. **Linear fields in records**: accessing the field consumes it. Enforcement engages for `let`-bound records; for parameter-bound records tracking currently degrades to a warning (finding L3 above).

6. **Avoid type names that collide with stdlib `always_linear` types** (like `Handle`) until finding L4 is fixed; the collision silently makes your type linear.

---

## Why Both?

Many systems have only one kind of linear type. March has both because they solve different problems:

- `linear` ensures you can't **forget** to do something (close, release, respond)
- `affine` ensures you can't **duplicate** something, while allowing graceful abandonment

For example, a session channel is *meant* to be completed; it is linear by
construction (though note F7 above: the "can't abandon it midway" part is not
fully enforced today for unclosed channels). An optional permission token
might be affine: the operation is valid with or without it.

---

## Next Steps

- [Type System](types.md): the broader type system context
- `core-march-types.md` §2.9: the rule-by-rule static-semantics account of everything in this chapter (with `typecheck.ml` citations and the conformance corpus)
- `core-march.md` §4.12: linearity at runtime (there is none: annotations are compile-time-erased; golden witness `g41`)
- [Refinement Types](refinement-types.md): the other compile-time safety layer: value predicates checked by an SMT solver
- [Actors](actors.md): how linear types interact with actor message passing
- [Pattern Matching](pattern-matching.md): destructuring linear values
