---
layout: docs
title: Safety by Construction
nav_order: 5.7
permalink: /docs/safety-by-construction/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Safety by Construction

March's safety features aren't a grab-bag: each one checks a *different,
orthogonal axis* of correctness, and they compose on the same function. This page
walks one realistic function through all four layers at once, then maps each
layer to the exact bug class it eliminates and when.

The example: a **bounded file-chunk reader**. It must (1) only run in code allowed
to read files, (2) use its file handle in the right order and exactly once, and
(3) only be asked, at any point, for a non-negative offset and a page-sized chunk. Each of
those is a separate layer.

---

## The whole function, all layers on

```march
mod ChunkReader do
  needs IO.FileRead                      -- (1) capability: may read files

  -- (2) typestate: a linear handle that tracks Open vs Closed
  always_linear type File(s) = File(Int)

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

Every line of `read_first` is checked against all four layers simultaneously.
Now watch what each layer *rejects*.

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
`read_chunk` demands `File(Open)`.

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

Each layer kills a distinct category of bug, and all of them fire at compile time:

| Layer | Syntax | Bug class it kills | Caught when |
|-------|--------|--------------------|-------------|
| **Capability** | `needs IO.FileRead`, `Cap(IO.FileRead)` | Ambient authority: code touching a resource it was never granted (surprise file/network access) | Compile time |
| **Linearity / typestate** | `always_linear type` + `File(Open)` / `File(Closed)` states | Use-after-close, double-close, leaked (never-closed) handle, operations in the wrong order | Compile time |
| **Refinement** | `{Int \| _ >= 0}`, `{Int \| _ > 0 && _ <= 4096}` | Out-of-range values: negative offsets, oversized/zero chunk sizes, bad indices | Compile time |

Note these never overlap. The capability layer doesn't care *which* offset you
pass; the refinement layer doesn't care whether you have permission; the
typestate layer doesn't care about values at all, only the order and count of
handle uses.

---

## The punchline: four orthogonal axes

That's the whole idea. Each layer answers a different question about the same
call, and a real bug usually lives on exactly one of these axes:

- **Capability**: *what resources* may this code touch?
- **Linearity / typestate**: *how many times*, and *in what order*, is this
  resource used?
- **Refinement**: *with what values* is it called?

Because the axes are independent, you can add them incrementally and they never
fight: a function can be capability-gated today, gain a refined argument
tomorrow, and grow a typestate handle later, with each new constraint checked on
top of the others. Safety by construction means the *only* programs that compile
are the ones that satisfy every axis at once.

---

## Next Steps

- [Capabilities]({{ site.baseurl }}/docs/capabilities/): the `needs` / `Cap(X)`
  system and typestate handles in full.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/): `linear` / `affine`
  ownership and why `always_linear` handles can't be dropped.
- [Refinement Types]({{ site.baseurl }}/docs/refinement-types/): value
  predicates, the SMT checker, and its definite-failure semantics.
- [Type System]({{ site.baseurl }}/docs/types/): the "which safety tool for
  which job" table that indexes all of these.
