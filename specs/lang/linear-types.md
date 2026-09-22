---
layout: docs
title: Linear Types
nav_order: 5.4
permalink: /docs/linear-types/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Linear and Affine Types

March's type system tracks ownership through **linear** and **affine** qualifiers. These let the compiler catch resource leaks and use-after-free bugs **at compile time**, not at runtime, and not by relying on a garbage collector.

Think of a **linear** value as a claim ticket: you're given it once, and the
compiler requires you to hand it in exactly once: not zero times, not twice. An
**affine** value is a looser cousin: you're allowed to lose it, but you still can't use
it twice. Both are checked entirely by the compiler, with no runtime cost and no
runtime tracking.

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
witnesses `specs/lang/types/reject/t58` and `t60`.) The stdlib's own
`Handle` type (`stdlib/handle.march`) is always linear, even without the
`linear` keyword; a plain type of your own that happens to be called `Handle`
is not. See [`always_linear` types](#always_linear-types) below.

### Linear Let Bindings

```march
fn read_file(path : String) : String do
  linear let handle : Handle = open_file(path)
  let content = read_all(handle)     -- consumes handle
  content
end
```

The `linear let` annotation tells the compiler this binding has linear semantics. You can also get it from a type annotation on the binding (`let h : linear Handle = ...`) or from the callee: a plain `let h = open_file(p)` with `open_file : ... -> linear Handle` is tracked as linear too, so dropping `h` rejects with `` The linear value `h` was never used. `` (finding L8, fixed; corpus witness `reject/t78`).

---

## Affine Values

An affine type may be used zero or one times. This is useful for values that have a cleanup operation but where "not using" is acceptable (e.g., an optional connection).

**Spelling:** `affine` works as a type modifier inside the annotation
(`cap : affine NetworkCap`, below) and as a parameter keyword
(`fn f(affine cap : NetworkCap)`, finding L1, fixed; corpus witness
`accept/t80`). There is no `affine let`:

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

The compiler tracks each linear field independently, and the record **owns**
its linear fields. A field whose type is an `always_linear` type is a linear
field too, with no qualifier needed. The rules:

1. **Accessing a field moves it out.** `r.fd` consumes that field; a second
   access rejects with `` The linear value `r.fd` is used more than once here. ``
2. **Using the whole record moves every field it still holds.** Passing `r` to
   a function, returning it, or storing it hands its linear fields on too. So
   consuming `r.fd` and then passing `r` along, or passing `r` along twice, is
   a double use of `r.fd`.
3. **`{ r with … }` keeps every field it doesn't replace.** After consuming
   `r.fd`, write `{ r with fd: new_fd }`; `{ r with metadata: "x" }` would carry
   the consumed `fd` into the new record, and is rejected with a note saying so.
4. **Every linear field must be consumed by the end of the record's scope**,
   by one of the three moves above. Otherwise it leaks: `` The linear value
   `r.fd` was never used. ``
5. **Reading an ordinary field moves nothing.** `r.metadata` never consumes
   `r.fd`.

This works the same for `let`-bound and parameter-bound records (a double
field access on a parameter was once only a warning; finding L3, fixed), and
for an actor's `state`; see [Linear Types and Actors](#linear-types-and-actors).
Corpus witnesses: `reject/t63`, `reject/t77`, `reject/t216`–`t222`,
`accept/t223`.

One more note: **arithmetic on linear primitive fields works** (e.g.
`r.count + 1` for a `linear count : Int` field), but only since 2026-07-10:
previously the linearity wrapper leaked into `Num` resolution and rejected even
a single, correct use (finding L2, fixed). Corpus witness: `accept/t67`.

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

> **Same-named types don't inherit linearity.** Whether a type is
> `always_linear` is resolved against the type the name actually refers to,
> so a plain type of your own called `Handle` is an ordinary type, even though
> the stdlib's `Handle` is linear (finding L4, fixed; corpus witnesses
> `accept/t81`, `accept/t194`).

---

## Linearity and Memory

*You don't need this section to use linear types correctly; skip ahead to [Linear
Types and Actors](#linear-types-and-actors) if you just want the safety picture.*

Linearity isn't only about correctness; it also feeds March's in-place
memory model. Normally the compiler has to track "is anyone else still holding
onto this value?" before it can safely reuse or drop its memory; a `linear`
value answers that question for free: it has a single owner by construction, which the
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

If you haven't read [Actors](actors.md) yet, the short version:
`send(pid, msg)` delivers a message to another actor asynchronously. Sending a
linear value to an actor **is allowed, and the send is the consuming use**:

```march
linear let r : Res = R(7)
send(pid, StoreRes(r))   -- consumes r
take(r)                   -- error: The linear value `r` is used more than once here.
```

(Verified live; corpus witnesses `accept/t68` + `reject/t66`. Earlier
versions of this chapter claimed a linear value "cannot be sent as a message
directly"; that was never true, and it contradicted the zero-copy-move
paragraph above; finding L6, resolved as this doc fix.) On the compiled backend the
transfer is a zero-copy move; interpreted, it is an ordinary handoff; either
way the type system prevents you from touching the value after the send.

**An actor's state holds linear values the same way a record does.** A
handler's `state` owns the state's linear fields (an `always_linear`-typed
field, or one written `linear`) for the turn, under the record rules above.
The two shapes to know:

```march
actor Ep do
  state { st : Token, n : Int }        -- Token is always_linear
  init  { st: new_token(), n: 0 }
  on Step() do
    { state with st: advance(state.st) }    -- OK: consumed and replaced
  end
  on Oops() do
    let k = spend(state.st)
    { state with n: k }                     -- error: the update keeps the old `st`
  end
end
```

A handler that returns a brand-new record must consume the old linear fields
first, or they leak. A linear value arriving as a handler **parameter** is
tracked too: it must be consumed, or stored into the returned state. Corpus
witnesses: `reject/t195`–`t196`, `reject/t216`, `reject/t217`, `reject/t222`,
`accept/t197`, `accept/t223`.

For richer typed interaction patterns, the channel system below layers
session types on top of the same linearity infrastructure.

---

## Session Types

March also uses linearity to enforce **conversation protocols** between two
parties: a strict two-party "who sends what, in what order" agreement, checked
at compile time. This is linear types applied to a channel instead of a file
handle.

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
> endpoint (a `let`-bound continuation *or* a channel parameter) are compile
> errors, and so is dropping an endpoint that has reached `End` without
> calling `Chan.close` (`` Session channel `ch3` reached `End` but was never
> closed. ``). One shape still slips through (the F7 residual, logged in
> `specs/todos/`): abandoning a channel *mid*-protocol, before it reaches
> `End`, typechecks and runs cleanly. An endpoint is tracked as affine plus
> that must-close-at-`End` rule, not as fully linear. See
> [Session Types]({{ site.baseurl }}/docs/session-types/) for the full protocol syntax, duality
> rules and the precise guarantees.

---

## Capabilities as Linear Types

*A quick reminder if you haven't read [Capabilities](capabilities.md) yet: a
`Cap(X)` value is proof that your code is allowed to perform the effect `X`
(like `Cap(IO.Network)` for opening sockets); it's how March makes permissions
part of the type system instead of a runtime check.*

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

*This section only matters if you're binding to a C library; skip ahead to
[Practical Rules](#practical-rules) otherwise.*

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

## Linear Values in Closures, Containers, and Generic Code

A linear value has to stay traceable wherever it goes, so four more places
enforce the rule:

- **Closures can't capture one.** A closure may run any number of times, so
  `run(fn () -> sink(s))` with an outer linear `s` is rejected (`` The linear
  value `s` cannot be captured by a closure ``), whether the closure is bound
  with `let`, passed straight to a function, or written as a local
  `fn … end`. Pass the value in as a parameter instead. A lambda's or local
  fn's own linear parameters must be consumed by the end of its body, just like
  a top-level function's (`reject/t198`–`t201`, `t208`–`t210`).
- **`_` can't discard one.** `let _ = token`, `let (a, _) = pair_of_tokens`,
  a `_ ->` arm on a linear value, or `fn _ -> …` receiving one all drop a
  value that must be consumed, and so does a `_` over something that *holds*
  one (`let (_, n) = (Some(token), 1)`). Discarding a non-linear part
  (`Token(_)`) is fine, and so is a `_` arm that ends in `panic(…)`
  (`reject/t203`–`t206`, `t256`). This holds however the value became linear:
  not only when its *type* says so, but also when only its *binding* does —
  a `linear x : a` parameter or a `linear let` local, whose type stays a plain
  type variable or `Int`. `let _ = x` on one of those is rejected too
  (`` This `_` discards the linear value `x` ``), so no generic function can
  launder a linear value away by binding it to a wildcard (`reject/t281`).
  The one exception is a session endpoint: a `Chan` has its own, narrower
  must-close rule (only an endpoint at `End` must be closed — see
  [session-types.md](session-types.md)), so dropping one mid-protocol stays
  legal (`accept/t282`).
- **A container holding one is linear itself.** A tuple, list or ADT value
  with a linear value inside (`(token, 1)`, `Some(token)`, `[token]`) must be
  used exactly once, like the value it holds. Records are the exception: their
  fields are tracked one by one, as above (`reject/t233`–`t234`). Taking the
  container apart consumes it, and each part is then judged by its own type:
  in `let (n, t) = (1, token)`, `t` is linear and `n` is an ordinary `Int`
  (`accept/t257`).
- **Generic functions must opt in.** A type variable is unrestricted: a generic
  function may drop or duplicate a value of that type. So passing a linear
  value to one is an error unless the function marks that parameter
  `linear`, which makes the body use it exactly once:

  ```march
  fn dup(x) do (x, x) end              -- dup(token): rejected, dup may duplicate
  fn id(linear x : a) : a do x end     -- id(token): fine, x is checked linear
  ```

  Constructors (`Some`, tuples, your own ADTs) store each argument once and need
  nothing; neither do operators, nor functions whose type variable appears only
  in what they return. Most stdlib generics have not opted in, so
  `List.length([token])` is rejected: it would drop the token
  (`reject/t229`–`t231`, `accept/t232`).

An unannotated parameter is tracked as soon as its body fixes its type to a
linear one: `fn g(st) do sink(st) + sink(st) end` is rejected just like the
annotated form (`reject/t212`–`t214`).

---

## Keyed Collections of Linear Values: `LinearMap`

`Map` can't hold a linear value: `Map.get` copies the value out while the map
keeps it, and `Map.insert` over an existing key drops the old one, so
`Map.insert(m, k, token)` is rejected. The stdlib's `LinearMap(k, v)` is the
map for values that must be used exactly once, such as the per-session state an
actor hosting several sessions keeps (one `Parked_<Role>` per session id).

- **Every operation consumes the map and hands it back.** `put(m, k, v)`
  returns `(Option(v), LinearMap)`, where the option is the value it displaced
  (the caller must consume it); `take(m, k)` is the only way a value comes out;
  `size`, `member` and `keys` return their answer beside the map.
- **`LinearMap` is `always_linear`.** Every binding must be consumed, even an
  empty map's. It ends in `drain(m, acc, f)` (each value goes through `f`,
  which must consume it), `to_list(m)`, or `dispose(m)`, which returns `Ok(())`
  for an empty map and hands a non-empty one back in `Err`. Nothing is lost and
  nothing panics.
- **Slots for the take-and-put-back turn.** `take_slot(m, k)` returns the
  value and a `LinearSlot`: the map with a hole at `k`. `fill(slot, v)` puts a
  value back (it cannot displace one) and `vacate(slot)` leaves the key empty.
- **Keys are ordinary values.** They are hashed, compared and copied, so a
  linear key type is rejected. Equality comes from the comparator given to
  `empty(cmp)` (`empty_int()` and `empty_string()` supply one), stored in the
  map.

In actor state the map is a linear field, so every handler that reads it must
store one back:

```march
actor Host do
  state { sessions : LinearMap(Int, Session) }
  init  { sessions: LinearMap.empty_int() }
  on Step(sid : Int) do
    match LinearMap.take_slot(state.sessions, sid) do
      (None, slot) -> { state with sessions: LinearMap.vacate(slot) }
      (Some(s), slot) -> { state with sessions: LinearMap.fill(slot, advance(s)) }
    end
  end
end
```

The checks are at every use site (`accept/t247`–`t248`, `reject/t249`–`t255`).
The module's own function bodies are a small reviewed kernel over `Map`: they
carry `@[trusted_linear(v)]`, which lets callers pass linear values for `v`
without the body being checked to use each one once. That attribute is
reserved for the standard library (`reject/t259`); user code opts a parameter
in with `linear x : a`, whose body is checked.

---

## Practical Rules

1. **Use `linear` for resources with mandatory cleanup**: file handles, database connections, exclusive locks, capabilities you must return.

2. **Use `affine` for optional-use tokens**: things you might or might not use, but definitely shouldn't use twice.

3. **Ordinary values need no qualifier**: the default is unrestricted (can be copied, dropped, used many times).

4. **Branches must agree.** A linear value that one branch of an `if`, `match` or `match do` consumes must be consumed by every branch that returns; a branch that ends in `panic(…)` never returns and doesn't count. The early `Err` return of `let?` is a branch too, so consume linear values before a `let?` that could skip them. Affine values and session-channel endpoints may still be dropped on a branch.

5. **Linear fields in records are owned by the record**: accessing one moves it out, using the record whole moves them all, `{ r with … }` keeps the ones it doesn't replace, and each must be consumed by the end of the record's scope.

6. **Closures, wildcards and generic code don't get a pass**: a closure can't capture a linear value, `_` can't discard one, a tuple/list/ADT holding one is linear too, and a generic function receives one only through a parameter marked `linear`.

7. **Keep many linear values in a `LinearMap`**, not a `Map`: take a value out, use it, put the next one back.

---

## Why Both?

Many systems have only one kind of linear type. March has both because they solve different problems:

- `linear` ensures you can't **forget** to do something (close, release, respond)
- `affine` ensures you can't **duplicate** something, while allowing graceful abandonment

For example, a session channel is *meant* to be completed; it is linear by
construction (though note the F7 residual above: an endpoint must be closed
once it reaches `End`, but abandoning a channel midway is not rejected today). An optional permission token
might be affine: the operation is valid with or without it.

---

## Next Steps

- [Type System](../../docs/types.md): the broader type system context
- `core-march-types.md` §2.9: the rule-by-rule static-semantics account of everything in this chapter (with `typecheck.ml` citations and the conformance corpus)
- `core-march.md` §4.12: linearity at runtime (there is none: annotations are compile-time-erased; golden witness `g41`)
- [Refinement Types](refinement-types.md): the other compile-time safety layer: value predicates checked by an SMT solver
- [Actors](actors.md): how linear types interact with actor message passing
- [Pattern Matching](pattern-matching.md): destructuring linear values
