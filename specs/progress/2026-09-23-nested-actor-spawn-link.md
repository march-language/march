# `spawn(Inner.Actor)` from the parent module links (fixed 2026-09-23)

**Cause.** An actor's glue (`Name_spawn`, `Name_dispatch`, `Name_Msg`, ...) is
minted from its BARE declared name, nested actors included: lower.ml's `DMod`
`DActor` arm documents that the spawn symbol and the HCR manifest assert the short
spelling. `Lower_state._actor_mailboxes` is keyed the same way
(`collect_actor_mailboxes` recurses through `DMod` with `name.txt`). The `ESpawn`
arm in `lib/tir/lower_expr.ml` built the callee as `actor_name ^ "_spawn"` straight
from the reference's spelling. From inside `Inner` that is `Box`, which matches.
From the parent it is `Inner.Box`, which gives `Inner.Box_spawn`, a symbol no
definition provides. `--check` passes (the typechecker resolves the qualified
name), the interpreter already ran it,
and `--compile` dies in the linker. The TIR showed it already
(`--dump-tir`: `Inner.Box_spawn()`), so codegen was not at fault. A second,
silent symptom: a qualified spawn of a nested actor declared with `mailbox N
policy` looked up the qualified name in the mailbox table, missed, and dropped
the limit.

**Fix.** `Tir_names.actor_decl_name` maps an actor reference to the declared name
the glue uses (`"Inner.Box"` -> `"Box"`), and `Tir_names.actor_spawn_fn_name` builds
the spawn symbol from it. The `ESpawn` arm canonicalises the reference once and uses
that for both the spawn callee and the mailbox lookup. The supervisor child-spawn
builder in `lower_actor.ml` uses the same helper. That path is not reachable with a
qualified name today, because a `supervise` field rejects `Inner.Box child` at parse
time.

**Not changed: message constructors.** A nested actor's message constructors are
not visible from the parent, qualified (`Inner.Set(1)`) or bare (`Set(1)`), while a
plain nested variant's are (`Inner.A(1)` resolves). This is a typecheck-side
registration gap, not the TIR naming bug, so it is filed separately:
`specs/todos/2026-09-23-nested-actor-msg-ctors-invisible-from-parent.md`.

**Verification.** `test/native/nested_actor_spawn.march` spawns `Inner.Box` and a
`mailbox 8 drop_new` actor `Inner.Slow` from the parent. It sends to each through an
`Inner` helper and prints `spawned`, the box's state and `some dropped: true`. It has
two dune rules, compiled (`native_nested_actor_spawn`) and interpreted
(`interp_nested_actor_spawn`), both diffed against the same `.expected`. On origin/main
(528e8437e) the compile fails with undefined `_Inner.Box_spawn` and `_Inner.Slow_spawn`.
With the spawn fix in place but the mailbox lookup reverted to the qualified key, the
compiled run prints `some dropped: false`.

---

Original report:

# `[P2]` `spawn(Inner.Actor)` from the parent module typechecks, then fails to link

Found 2026-09-22 while writing `bench/actor_ping.march`.

```march
mod Outer do
  needs IO.Console
  needs IO.Spawn
  mod Inner do
    actor Box do
      state { n : Int }
      init  { n: 0 }
      on Put(k : Int) do
        { n: k }
      end
    end
  end
  fn main(_c : Cap(IO.Console), _s : Cap(IO.Spawn)) do
    let _p = spawn(Inner.Box)
    println("spawned")
  end
end
```

`march --check` exits 0. `march --compile` fails at link time:

```
Undefined symbols for architecture arm64:
  "_Inner.Box_spawn", referenced from:
      _march_main in nested_spawn-d50796.o
```

The spawn function for a nested actor is not emitted under the qualified name the
call site uses. Spawning from inside `Inner` (`fn new_box() do spawn(Box) end`) works,
which is what `bench/actor_ping.march` does. Related: a nested actor's message
constructors are not visible from the parent either (`Inner.Put(1)` is "I don't know a
constructor called `Inner.Put`"), so a parent cannot send to it without a helper in
`Inner`; that may be intended scoping, the link error is not.

**Acceptance.** The program above compiles, runs and prints `spawned`; a native golden
test covers it.
