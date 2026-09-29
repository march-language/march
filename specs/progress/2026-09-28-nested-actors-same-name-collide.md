# Same-named nested actors stay distinct (fixed 2026-09-28)

**Scope was wider than the TIR glue.** On origin/main (216f45fba) every backend
keyed an actor by its bare name: the typechecker's constructor table (`Box` and
the `Box_Msg` type), the interpreter's `actor_defs_tbl`, and the TIR glue
(`Box_spawn`, `Box_dispatch`, `Box_Msg`, `Box_Actor`). With a root `Box` and
two nested `Box`es (`test/native/nested_actor_same_name.march`):

- interpreted: `A.Box n = <none>`, `Box root = <none>` (one definition spawned
  for all three);
- compiled: `panic: record field access: no field "root" in record`;
- with distinct message constructors per actor, `--compile` died with an ICE,
  `actor-message tag table has no row for Box_Msg.Scale`.

Two actors of one name in the SAME module were silently accepted.

**Fix: rename only on collision, before anything keys the name.** A new desugar
pass, `lib/desugar/desugar_actor_names.ml`, runs first in `desugar_module`. It
collects every actor with its module path. For a bare name declared more than
once, each NESTED declaration is renamed to its module path joined with `__`
(`A.Box` -> `A__Box`, `A.C.Box` -> `A__C__Box`); a root-level actor keeps its
name. References are resolved lexically (innermost enclosing module that
declares the name wins) and only the last segment is replaced, so `spawn(Box)`
in `A` becomes `spawn(A__Box)` and `spawn(A.Box)` from the parent becomes
`spawn(A.A__Box)`: the backends' existing qualified-reference paths are
untouched. Rewritten positions: the `spawn` target (pre-desugar `ECon`, `EVar`
or `EField` chain), a supervise child's type, and `<Actor>.Msg` in any type
annotation. A reference the pass misses names an actor that no longer exists
under that spelling, so it fails to typecheck instead of binding to the wrong
actor. Two same-named actors in one module are now a desugar error.

**HCR / manifest spelling.** When no name collides the pass returns the
declarations unchanged, so a unique nested actor and every root-level actor
keep their glue names, dispatch-table entries and `.schemas.json` spelling byte
for byte. Only actors that collided (which never worked) get a new spelling.
`Tir_names.actor_decl_name` stays: it still strips the qualifier from
`A.A__Box`.

**Visible in diagnostics.** A renamed actor appears under its new name in
messages, e.g. a capability chain `Safe.run → Safe.Safe__Worker →
Safe.Safe__Worker_Go` (`test_same_named_actors_spawned_one_still_rejected`
now asserts that spelling; before, it read `Safe.Worker_Go` and was only
right because the capability attribution happened to pick the spawned one).

**Not covered.** A cross-FILE collision (two separately loaded files each
declaring a nested `Box`) is not seen by a per-file pass, and a reference from
another file to a renamed actor (`spawn(Lib.A.Box)`) now fails to typecheck
rather than resolving. Hot-reload `<actor>_migrate_msg` / `_migrate_state`
functions are named after the actor; for a renamed actor they would need the
new name. `spawn(Outer.B.Box)` spelled with the entry module's own name fails
to typecheck with or without this change (pre-existing).

**Message constructors.** Same-named actors may also share message constructor
names (`Poke` in each). The typechecker resolves an unqualified `Poke` in each
module to that module's actor (a HINT lists the candidates); the fixture checks
each actor applies its own `Poke` to its own state.

**Verification.** `test/native/nested_actor_same_name.march` (root `Box`,
`A.Box`, `B.Box`, all with a `Poke` handler and different state) prints each
actor's state; compiled (`native_nested_actor_same_name`) and interpreted
(`interp_nested_actor_same_name`) dune rules diff it against one `.expected`.
With the pass disabled it prints `<none>` interpreted and panics compiled, as
above. `test/test_compiler.ml` "desugar" group: a unique nested actor keeps its
name, colliding ones are renamed (including a doubly nested one), and a
same-module duplicate is an error.

---

Original report:

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
