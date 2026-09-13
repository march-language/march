---
layout: docs
title: Linear Types
nav_order: 5.4
permalink: /docs/linear-types/
---

# Linear and Affine Types

Some values represent things that need to be handled with care: a file that must be
closed, a network connection that must be released, a lock that must be given back.
Forget to do it and you leak a resource; do it twice and you get a crash or corruption;
hand the same one to two different parts of your program and you get a race.

March's type system can enforce these rules for you, at compile time, with no runtime
cost. Think of a **linear** value as a claim ticket: you're given it once, and the
compiler requires you to hand it in exactly once: not zero times, not twice. An
**affine** value is a looser cousin: you're allowed to lose it, but you still can't use
it twice. Both are checked entirely by the compiler; there's no garbage collector or
runtime tracking involved.

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

**Note:** the stdlib's own `Handle` type (used for files and similar resources) is
always linear, even without writing the `linear` keyword; see [`always_linear`
types](#always_linear-types) below for how that works.

### Linear Let Bindings

```march
fn read_file(path : String) : String do
  linear let handle : Handle = open_file(path)
  let content = read_all(handle)     -- consumes handle
  content
end
```

The `linear let` annotation tells the compiler this binding has linear semantics. The
rule to remember: **the qualifier has to appear where you bind the value**, either as
`linear let` or as a type annotation (`let h : linear Handle = ...`). It also comes
from the *function you're calling*: if `open_file` returns a `linear Handle`, a plain
`let h = open_file(p)` is tracked as linear, and dropping `h` is an error.

---

## Affine Values

An affine type may be used zero or one times. This is useful for values that have a cleanup operation but where "not using" is acceptable (e.g., an optional connection).

**Spelling:** `affine` works as a type modifier inside the annotation
(`cap : affine NetworkCap`, below) and as a parameter keyword
(`fn f(affine cap : NetworkCap)`). There is no `affine let`:

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

---

## Linear Record Fields

Individual fields of a record can be linear:

```march
type Resource = {
  linear fd   : FileDesc,
  metadata    : String
}
```

The record **owns** its linear fields, and a field whose type is an
`always_linear` type counts as a linear field too:

1. **Accessing a field moves it out.** `r.fd` consumes that field; a second
   access rejects with `` The linear value `r.fd` is used more than once here. ``
2. **Using the whole record moves every field it still holds**: passing `r`
   along, returning it, storing it. Consume `r.fd` and then pass `r` along, and
   `fd` has been used twice.
3. **`{ r with … }` keeps every field you don't replace.** After consuming
   `r.fd`, write `{ r with fd: new_fd }`.
4. **Every linear field must be consumed by the end of the record's scope**, or
   the compiler reports it as never used.
5. **Reading an ordinary field moves nothing**: `r.metadata` leaves `r.fd` alone.

These rules apply to `let`-bound records, parameters, and an actor's `state`
alike.

One more note: **arithmetic on linear primitive fields works**: e.g.
`r.count + 1` for a `linear count : Int` field is a valid single use.

---

## always_linear Types

So far, `linear` has been something *you* write at each use site. `always_linear type`
is the alternative for when you're defining a type and want it to be linear
*everywhere*, automatically; no one who uses your type has to remember to write
`linear` themselves:

```march
always_linear type Token = Token(Int)

fn main() : () do
  let t = Token(1)
  ()    -- error: The linear value `t` was never used.
end
```

This is exactly how the stdlib guarantees you can't forget to close a file: `Handle` is
declared `always_linear`, so every `Handle` value, everywhere in your program, is
tracked as linear whether or not you write the word `linear` at all.

> **Same-named types don't inherit linearity.** A plain type of your own called
> `Handle` is an ordinary type, even though the stdlib's `Handle` is linear: the
> compiler resolves which `Handle` a name refers to before deciding.

---

## Why This Also Makes Programs Fast

*You don't need this section to use linear types correctly; skip ahead to [Linear
Types and Actors](#linear-types-and-actors) if you just want the safety picture.*

Linearity isn't only about correctness; it also feeds March's in-place memory model.
Normally, the compiler has to track "is anyone else still holding onto this value?"
before it can safely reuse or drop its memory. A `linear` value answers that question
for free: because the type system guarantees there's exactly one reference to it, the
compiler can skip that bookkeeping and reuse memory in place where a value would
otherwise need to be reference-counted or copied. Sending a linear value to an actor is
a real example: it compiles to a zero-copy **ownership-transfer move** instead of a byte
copy, because the type system already proves no one else can be looking at it.

These are performance facts, not semantic ones: linearity is **compile-time-erased**,
and no check repeats it at runtime. See [Memory Model]({{ site.baseurl }}/docs/memory-model/) for the full picture.

---

## Linear Types and Actors

If you haven't read [Actors]({{ site.baseurl }}/docs/actors/) yet, the short version:
`send(pid, msg)` delivers a message to another actor asynchronously. Sending a linear
value to an actor **is allowed, and the send itself is the consuming use**:

```march
linear let r : Res = R(7)
send(pid, StoreRes(r))   -- consumes r
take(r)                   -- error: The linear value `r` is used more than once here.
```

On the compiled backend the transfer is a zero-copy move; interpreted, it is an ordinary
handoff; either way the type system prevents you from touching the value after the send.

An actor's `state` holds linear values the way a record does: in a handler, `state`
owns the state's linear fields under the record rules above. So
`{ state with st: advance(state.st) }` is fine, while consuming `state.st` and then
returning `{ state with n: k }` is an error, because the update would keep the old
`st`. A handler that returns a brand-new record must consume the old linear fields
first.

---

## A Preview: Session Types

March also uses linearity to enforce **conversation protocols** between two parties: a
strict two-party "who sends what, in what order" agreement, checked at compile time. A
channel endpoint is a linear value: each send or receive consumes your current endpoint
and hands you back a new one representing "what's allowed next," so using a channel out
of order, or using it after it's closed, is a type error rather than a runtime surprise.

```march
protocol Transfer do
  Client -> Server : Int
  Server -> Client : Int
end

fn client_side(ch : Chan(Client, Transfer)) : Int do
  let ch2 = Chan.send(ch, 42)        -- send consumes ch, returns a new endpoint
  let (result, ch3) = Chan.recv(ch2) -- recv returns (value, new endpoint)
  Chan.close(ch3)
  result
end
```

This is really just linear types applied to a channel instead of a file handle, the
same "exactly once, in the right order" discipline you've already seen above. See
[Session Types]({{ site.baseurl }}/docs/session-types/) for the full protocol syntax,
branching, and the precise guarantees (and their current limits).

---

## Capabilities as Linear Types

*A quick reminder if you haven't read [Capabilities]({{ site.baseurl }}/docs/capabilities/)
yet: a `Cap(X)` value is proof that your code is allowed to perform the effect `X` (like
`Cap(IO.Network)` for opening sockets); it's how March makes permissions part of the
type system instead of a runtime check.*

`Cap(X)` is, by default, an **ordinary unrestricted type**: a plain `Cap(X)` value can
be passed to as many callees as you like. Preventing a capability from being *forged* is
a separate mechanism entirely (see the capabilities page). What you *can* do is apply
the ordinary `linear` qualifier to a capability parameter, exactly as to any other
value, when a function should force its caller to give up the capability for good:

```march
fn narrow_once(linear cap : Cap(IO)) : Cap(IO.FileRead) do
  cap_narrow(cap)   -- consumes cap; the caller cannot reuse it afterward
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

## FFI and Native Resources

*This section only matters if you're binding to a C library; skip ahead to [Practical
Rules](#practical-rules) otherwise.*

There is no `Ptr` type in March. The mechanism for safe manual memory management across
the FFI boundary is the `resource` declaration together with the `consume` parameter
mode. A `resource` type is an opaque native handle that is reference-counted like any
other value, invoking its destructor automatically when the last reference is dropped;
`consume` on an extern parameter transfers ownership into that call so the compiler does
not *also* auto-drop the binding afterward (which would double-free):

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

---

## Linear Values in Closures, Containers, and Generic Code

A linear value has to stay traceable wherever it goes:

- **Closures can't capture one.** A closure may run more than once, so an outer
  linear value can't be used inside one; pass it in as a parameter. And a
  lambda's own linear parameters must be consumed, just like a function's.
- **`_` can't discard one.** `let _ = token` or `fn _ -> …` receiving a linear value
  would drop it. Discarding a non-linear part (`Token(_)`) is fine.
- **A container holding one is linear itself.** `(token, 1)`, `Some(token)` and
  `[token]` must be used exactly once, like what they hold. Records are the exception:
  their fields are tracked one by one.
- **Generic functions must opt in.** A generic function may drop or duplicate a value
  of its type parameter, so it can only receive a linear value if it marks that
  parameter `linear`:

  ```march
  fn dup(x) do (x, x) end              -- dup(token): rejected, dup may duplicate
  fn id(linear x : a) : a do x end     -- id(token): fine, x is checked linear
  ```

  Constructors, operators, and functions that only *return* their type variable need
  nothing. Most stdlib generics haven't opted in, so `List.length([token])` is
  rejected: it would drop the token.

---

## Practical Rules

1. **Use `linear` for resources with mandatory cleanup**: file handles, database connections, exclusive locks, capabilities you must return.

2. **Use `affine` for optional-use tokens**: things you might or might not use, but definitely shouldn't use twice.

3. **Ordinary values need no qualifier**: the default is unrestricted (can be copied, dropped, used many times).

4. **Branches must agree.** A linear value that one branch of an `if`, `match` or `match do` consumes must be consumed by every branch that returns; a branch that ends in `panic(…)` never returns and doesn't count. The early `Err` return of `let?` is a branch too, so consume linear values before a `let?` that could skip them. Affine values and session-channel endpoints may still be dropped on a branch.

5. **Linear fields in records are owned by the record**: accessing one moves it out, using the record whole moves them all, `{ r with … }` keeps the ones it doesn't replace, and each must be consumed by the end of the record's scope.

6. **Closures, wildcards and generic code don't get a pass**: a closure can't capture a linear value, `_` can't discard one, a tuple/list/ADT holding one is linear too, and a generic function receives one only through a parameter marked `linear`.

---

## Why Both?

Many systems have only one kind of linear type. March has both because they solve different problems:

- `linear` ensures you can't **forget** to do something (close, release, respond)
- `affine` ensures you can't **duplicate** something, while allowing graceful abandonment

For example, a session channel is *meant* to be completed; it is linear by
construction (though the "can't abandon it midway" part isn't fully enforced today for
unclosed channels; see the caveat on the [Session Types]({{ site.baseurl }}/docs/session-types/)
page). An optional permission token might be affine: the operation is valid with or
without it.

---

## Next Steps

- [Type System](types.md): the broader type system context
- [Refinement Types](refinement-types.md): the other compile-time safety layer: value predicates checked by an SMT solver
- [Actors](actors.md): how linear types interact with actor message passing
- [Pattern Matching](pattern-matching.md): destructuring linear values
