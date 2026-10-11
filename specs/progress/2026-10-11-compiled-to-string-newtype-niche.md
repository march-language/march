`[P3]` - [x] **Compiled `to_string` prints a newtype's payload and a niche's nullary constructor as `nil`.**

Filed 2026-10-11 while working on
`specs/todos/2026-10-07-module-type-layouts.md`. Landed the same day.

## What was wrong

A type declared directly in the entry module gets the Milestone-2 newtype or
niche layout. Its values have no heap cell, so `march_value_to_string` has no
constructor tag to read and prints the raw payload:

```march
mod Main do
  needs IO.Console
  type Meters = Meters(Int)
  type MaybeName = NoName | Named(String)
  fn main(_c : Cap(IO.Console)) do
    println(to_string(Meters(7)))          -- interpreted Meters(7), compiled 7
    println(to_string(MaybeName.Named("x")))  -- interpreted Named("x"), compiled x
    println(to_string(MaybeName.NoName))      -- interpreted NoName, compiled nil
  end
end
```

## The change

The constructor-name descriptor (`lib/tir/llvm_ctor_desc.ml`, parsed and
rendered by `ctor_render` in `runtime/march_extras.c`) describes two more
kinds of type, decided by `Llvm_ctor_desc.desc_kind`:

- `N`, a newtype. The value is its one constructor's payload, so the
  renderer prints that constructor around the payload without reading any
  header.
- `X`, a non-generic niche. The nullary constructor is raw 0 and the other
  is the payload, so the renderer picks the constructor from the word.

Both are rendered before `ctor_render` looks at the word as a heap cell. A
payload row uses the new tokens `I` and `B` for a tagged Int or Bool, since
the allocator stores a scalar payload as `(v<<1)|1`
(`Kind.payload_needs_tag`). A niche-shaped type whose payload is not
niche-safe (`NoF | SomeF(Float)`) is a boxed cell and is now described as an
ordinary variant. N and X types are not registered in the header-id map,
since no cell carries their id.

This is the static route: the call site's type picks the row. It covers
every place the static type reaches the renderer:

- a top-level `to_string`, `inspect`, and string interpolation;
- elements of `List`, `Option`, `Result` and tuples, whose Show impls
  monomorphise to an element `to_string` with the element's static type;
- a field of a boxed constructor or of a declared record, through the field
  token `A<id>`;
- a `~H` hole (`Llvm_emit_html` uses the same descriptor id).

`derive Json` was already right: the derived code matches on constructors.
`Actor.inspect_state` renders state with the compiler's typed `to_string`
(`lower_actor.ml`), so it takes the same path; not tested here.

Found and fixed alongside: `Some(NoName)` was encoded as `None`
(`specs/progress/2026-10-11-nested-niche-option-payload.md`).

## Test

`test/native/to_string_newtype_niche.march` runs interpreted and compiled
against one `.expected` (32 lines: top-level and nested newtypes and niches,
a boxed niche-shaped type, interpolation, `inspect`, `~H`).

## Left open

`specs/todos/2026-10-11-to-string-newtype-in-generic-slot.md`: a newtype or
niche value in a type-variable slot of a user generic type (`Box(Meters(9))`
prints `Box(9)`), or reaching `to_string` with an erased type, still prints
its payload. The descriptor is per declaration, not per instance, so such a
slot has no static type to read.

## Benchmarks

Compiled `--opt 2`, this branch against the train branch's compiler
(`merge-train/groups-abcd`), same box, alternating, first round discarded as
warm-up, 4 rounds: `bench/tree_transform.march` 573-579 ms on both;
`bench/binary_trees.march` 63-67 ms on both. Nothing on these paths
changed: the fix only adds descriptor rows and a branch in the renderer.
