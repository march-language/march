# `[P2]` Two nested actors with the same name compile into one actor

Filed 2026-09-24, found while reviewing #611 (`spawn(Inner.Box)` from a parent
module, `specs/progress/2026-09-23-nested-actor-spawn-link.md`). Pre-existing:
reproduced with a compiler built from `origin/main` before #611 merged.

## Symptom

Two sibling modules each declare an actor called `Box`, with different state:

```march
mod Outer do
  needs IO.Console
  needs IO.Spawn
  mod A do
    needs IO.Spawn
    actor Box do
      state { n : Int }
      init  { n: 1 }
      on Get(r : Int) do
        { n: r + 1 }
      end
    end
    fn start(s : Cap(IO.Spawn)) do spawn(Box) end
  end
  mod B do
    needs IO.Spawn
    actor Box do
      state { s : String }
      init  { s: "b" }
      on Get(r : Int) do
        { s: "x" }
      end
    end
    fn start(s : Cap(IO.Spawn)) do spawn(Box) end
  end
  fn main(_c : Cap(IO.Console), s : Cap(IO.Spawn)) do
    let _a = A.start(s)
    let _b = B.start(s)
    println("spawned both")
  end
end
```

`--check` exits 0, `--compile` exits 0, and the binary runs and prints
`spawned both`. `--emit-llvm` contains exactly **one** `define void @Box_dispatch`,
and both spawns use it. So one of the two actors runs the other's handlers
against a state record of a different shape (`Int` where `String` is expected, or
the reverse): a silent miscompile, not a link error. After #611, spawning the
same actors from the parent (`spawn(A.Box)`, `spawn(B.Box)`) reaches the same
single definition.

This example only proves the collapse (one dispatch, two spawns). It does not yet
observe the wrong behaviour; a regression test should make the actors' state
visible (reply with it via `Actor.call`, or read it with `get_actor_field`) so the
test fails on wrong state, not only on a symbol count.

## Cause

An actor's generated glue (`<Name>_spawn`, `<Name>_dispatch`, `<Name>_Msg`, …) is
minted from its **bare** declared name, nested actors included. The `DMod`/`DActor`
arm in `lib/tir/lower.ml` documents this as intentional, and #611's progress note
("Cause") records it. Two same-named actors therefore mint the same symbols, and
whichever is lowered last or first wins.

## Fix direction

Module-qualify the glue names at definition time (for example `A.Box_dispatch`, or a
mangled equivalent), so that the definition and every reference agree without
stripping the qualifier. That retires the `Tir_names.actor_decl_name` helper #611
added, which maps `"Inner.Box"` back to `"Box"`. Two consumers assert the short
spelling today and must move with it:

- the hot-code-reload manifest (actor names in the dispatch table and
  `.schemas.json`), and
- the spawn symbol, including the C runtime's lookups and any golden or
  test that names `<Actor>_spawn`.

Check message constructors too (`Inner.Put(1)` is not visible from the parent,
`specs/todos/2026-09-23-nested-actor-msg-ctors-invisible-from-parent.md`), since
qualifying the glue may change that answer.

## Acceptance

- The program above emits two distinct dispatch functions, and a runtime test shows
  each actor handling its own messages against its own state, compiled and
  interpreted.
- Actors that are not nested, and nested actors with unique names, keep working,
  including hot-code-reload of an actor (the manifest spelling).
- Reject or accept, deliberately: if two same-named actors in one module are
  possible at all, decide whether that is an error.
