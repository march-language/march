---
layout: docs
title: Safety by Construction
nav_order: 5.7
permalink: /docs/safety-by-construction/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Safety by Construction

March has three compile-time safety layers, and each one answers a different
question about the same call. **Capabilities** answer *what resources may this code
touch?* **Linearity and typestate** answer *how many times, and in what order, is
this resource used?* **Refinements** answer *with what values is it called?* They
compose on one function without interfering, and a real bug usually lives on exactly
one of the three axes.

This page walks one realistic function through all three layers at once, shows what
each layer rejects, and maps each layer to the bug class it removes. The three
chapters it draws on are [Capabilities]({{ site.baseurl }}/docs/capabilities/),
[Linear Types]({{ site.baseurl }}/docs/linear-types/) and
[Refinement Types]({{ site.baseurl }}/docs/refinement-types/); read this page first
if you want to know which of them you need.

## On this page

- [Which layer do I need?](#which-layer-do-i-need)
- [The whole function, all layers on](#the-whole-function-all-layers-on)
- [What the capability layer rejects](#what-the-capability-layer-rejects)
- [What the typestate layer rejects](#what-the-typestate-layer-rejects)
- [What the refinement layer rejects](#what-the-refinement-layer-rejects)
- [One bug class per layer](#one-bug-class-per-layer)
- [Three orthogonal axes](#three-orthogonal-axes)
- [See also](#see-also)

## Which layer do I need?

| The bug you want to make impossible | Layer | What you write |
|---|---|---|
| Code reads a file, opens a socket or spawns a process it was never granted | Capability | `needs IO.FileRead` on the module; `Cap(IO.FileRead)` as a parameter |
| A handle is used after it is closed, closed twice, or never closed | Linearity / typestate | `always_linear type File(s)`, with `File(Open)` and `File(Closed)` states |
| Operations on a resource run in the wrong order | Typestate | A state parameter on the handle, so `read_chunk` demands `File(Open)` |
| A negative offset, an oversized buffer, an index out of range | Refinement | `{Int \| _ >= 0}`, `{Int \| _ > 0 && _ <= 4096}` |
| A function is called before the thing it depends on has happened | Capability (proof cap) | `proof cap Migrated`; see [Capabilities]({{ site.baseurl }}/docs/capabilities/#proof-caps-encoding-initialization-order) |
| A two-party conversation sends out of turn or uses a closed channel | Linearity (session types) | A `protocol` and the `Chan` API; see [Session Types]({{ site.baseurl }}/docs/session-types/) |

The layers are independent, so you can add them one at a time. A function can be
capability-gated today, gain a refined argument tomorrow, and grow a typestate handle
later, with each new constraint checked on top of the others.

---

## The whole function, all layers on

The example is a **bounded file-chunk reader**. It must (1) only run in code allowed
to read files, (2) use its file handle in the right order and exactly once, and (3)
only be asked, at any point, for a non-negative offset and a page-sized chunk. Each
of those is a separate layer.

```march
mod ChunkReader do
  needs IO.FileRead                      -- (1) capability: may read files

  -- (2) typestate: a linear handle that tracks Open vs Closed
  always_linear type File(s) = File(Int)

  -- `tag` declares a zero-arg type used purely as a state label: Open and
  -- Closed carry no data, they just fill the `s` slot in `File(s)` above.
  tag Open
  tag Closed

  -- Opening yields a handle in the `Open` state.
  fn open(cap : Cap(IO.FileRead), path : String) : File(Open) do ... end

  -- (3) refinements: offset must be non-negative; size must be a sane page.
  -- The handle must be `Open`, and is returned still `Open` for the next read.
  fn read_chunk(
    f      : File(Open),
    offset : {Int | _ >= 0},
    size   : {Int | _ > 0 && _ <= 4096}
  ) : (String, File(Open)) do ... end

  -- Closing consumes the `Open` handle and returns it `Closed`.
  fn close(f : File(Open)) : File(Closed) do ... end

  -- A correct caller, accepted by the compiler:
  fn read_first(cap : Cap(IO.FileRead), path : String) : String do
    let f0          = open(cap, path)
    let (bytes, f1) = read_chunk(f0, 0, 4096)   -- 0 >= 0 ✓ , 0 < 4096 ≤ 4096 ✓
    let f2          = close(f1)                  -- handle consumed exactly once
    match f2 do File(_) -> bytes end
  end
end
```

Every line of `read_first` is checked against all three layers at once. The next
three sections show what each layer rejects.

### What the capability layer rejects

A module that never declares `needs IO.FileRead` cannot call `open` at all; the
build fails and names the missing cap. And because `open` *takes* a
`Cap(IO.FileRead)`, you cannot conjure one: it has to be threaded down from
`main`'s root capability. There is no ambient "just read a file"; the
permission is a value you must be given.

### What the typestate layer rejects

```march
let f0 = open(cap, path)
let (bytes, f1) = read_chunk(f0, 0, 4096)
let again = read_chunk(f0, 0, 4096)   -- ERROR: `f0` was already consumed
```

`File` is `always_linear`, so each handle is used **exactly once**. Reusing
`f0` after `read_chunk` consumed it is a compile error; so is dropping a handle
without closing it. And reordering (calling `close` before `read_chunk`, or
`read_chunk` on a `File(Closed)`) fails because the *state* is in the type:
`read_chunk` demands `File(Open)`. `Open` and `Closed` are declared with
`tag`, March's shorthand for a zero-argument type that exists only to be a
label; see [Capabilities: `tag`]({{ site.baseurl }}/docs/capabilities/#tag--zero-arg-phantom-label-types)
for the full typestate picture, including how `transitions` blocks declare
which functions move a handle between states.

### What the refinement layer rejects

```march
read_chunk(f0, -1, 8192)
-- ERROR: refinement violation: argument does not satisfy `_ >= 0`
-- ERROR: refinement violation: argument does not satisfy `_ > 0 && _ <= 4096`
```

A negative offset and an over-large chunk are both rejected **at compile time**,
with the failing predicate quoted back. The SMT solver proves these arguments
can *never* satisfy the contract; no test run required.

---

## One bug class per layer

Each layer removes a distinct category of bug, and all of them fire at compile time:

| Layer | Syntax | Bug class it removes | Caught when |
|-------|--------|--------------------|-------------|
| **Capability** | `needs IO.FileRead`, `Cap(IO.FileRead)` | Ambient authority: code touching a resource it was never granted (surprise file/network access) | Compile time |
| **Linearity / typestate** | `always_linear type` + `File(Open)` / `File(Closed)` states | Use-after-close, double-close, leaked (never-closed) handle, operations in the wrong order | Compile time |
| **Refinement** | `{Int \| _ >= 0}`, `{Int \| _ > 0 && _ <= 4096}` | Out-of-range values: negative offsets, oversized/zero chunk sizes, bad indices | Compile time |

The layers never overlap. The capability layer does not care *which* offset you
pass; the refinement layer does not care whether you have permission; the
typestate layer does not care about values at all, only the order and count of
handle uses.

---

## Three orthogonal axes

Each layer answers a different question about the same call:

- **Capability**: *what resources* may this code touch?
- **Linearity / typestate**: *how many times*, and *in what order*, is this
  resource used?
- **Refinement**: *with what values* is it called?

Because the axes are independent, you can add them incrementally and they never
fight. Safety by construction means the *only* programs that compile are the ones
that satisfy every axis at once.

---

## See also

- [Capabilities]({{ site.baseurl }}/docs/capabilities/): the `needs` / `Cap(X)`
  system, proof caps, and typestate handles in full.
- [Capability Enforcement]({{ site.baseurl }}/docs/capability-enforcement/):
  turning a declared capability set into an OS-level sandbox and a hot-deploy
  admission gate.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/): `linear` / `affine`
  ownership and why `always_linear` handles cannot be dropped.
- [Session Types]({{ site.baseurl }}/docs/session-types/): the linearity
  discipline applied to two-party communication protocols.
- [Refinement Types]({{ site.baseurl }}/docs/refinement-types/): value
  predicates, the SMT checker, and its definite-failure semantics.
- [Memory Model]({{ site.baseurl }}/docs/memory-model/): how the same ownership
  facts drive in-place reuse (FBIP) with no tracing garbage collector.
- [Type System]({{ site.baseurl }}/docs/types/): the "which safety tool for
  which job" table that indexes all of these.
