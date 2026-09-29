# A nested actor's message constructors are reachable from the parent, qualified (fixed 2026-09-28)

**Reproduced on origin/main (9f4c543f2).** From the parent, `send(p, Inner.Set(1))`
failed with ``I don't know a constructor called `Inner.Set` ``. The suggestion
list offered `Inner.A` and `Inner.Box` but never a message constructor.

**Cause.** The `DMod` arm of `check_decl` (`lib/typecheck/typecheck.ml`)
exports an inner constructor only when its `ci_type` is in the module's public
name set. An actor's message constructors have `ci_type = "<Actor>_Msg"`. That
is a generated name, never a declared one, so they were exported under neither
spelling, bare or qualified.

**Fix.** A public actor's message constructors (`ci_is_actor_msg`, where the
`_Msg` prefix is a public actor) are now added to the QUALIFIED constructor keys
(`Inner.Set`) only. The bare `Set` stays local to `Inner`, a deliberate
choice. For an ambiguous bare constructor the most local candidate wins, so
exporting the bare name would add a candidate to every bare `Set` the parent
already writes for its own types, and existing code could silently change
meaning. The fixture pins that the parent's own `Set` keeps working.
`specs/lang/actors.md` (Sending Messages) documents both rules, and
`docs/actors.md` is regenerated from it. No TIR change was needed:
`Inner.Set` lowers to the bare `Box_Msg` constructor on both backends. The
fixture checks the handler's effect on state, and the compiled run matches
the interpreter.

**Verification.**
- `test/native/nested_actor_msg_from_parent.march` runs compiled
  (`native_nested_actor_msg_from_parent`) and interpreted
  (`interp_nested_actor_msg_from_parent`), both diffed against one
  `.expected`. It sends `Inner.Set(1)`, then an `Inner.Set(2)` bound through an
  `Inner.Box.Msg` annotation, then a two-argument `Inner.Tag("tagged", 10)`,
  and prints `n = 30`. The parent's own `type Cmd = Set(Int) | Stop` still
  resolves its bare `Set(7)`.
- `test_nested_actor_msg_ctor_qualified_from_parent` (typecheck group): the
  qualified send and the `.Msg` annotation are accepted, and a bare `Set` from
  the parent is still rejected.

---

Original report:

# `[P3]` A nested actor's message constructors are invisible from the parent module

Found 2026-09-23 while fixing the nested-actor spawn link error
(`specs/progress/2026-09-23-nested-actor-spawn-link.md`).

```march
mod Outer do
  needs IO.Console
  needs IO.Spawn
  mod Inner do
    type T = A(Int) | B
    actor Box do
      state { n : Int }
      init  { n: 0 }
      on Set(k : Int) do
        { n: k }
      end
    end
  end
  fn main(_c : Cap(IO.Console), _s : Cap(IO.Spawn)) do
    let _t = Inner.A(1)            -- resolves
    let p = spawn(Inner.Box)       -- resolves (and links, since 2026-09-23)
    send(p, Inner.Set(1))          -- "I don't know a constructor called `Inner.Set`"
    send(p, Set(2))                -- "I don't know a constructor called `Set`"
    println("ok")
  end
end
```

A plain variant declared in `Inner` is reachable from the parent as `Inner.A`. The
suggestion list even offers `Inner.Box`. An actor's message constructors in the same
module are reachable under neither spelling, so the parent can only send to a nested
actor through a helper fn inside `Inner`. Unless hiding them is a deliberate
encapsulation rule (nothing in `specs/lang/` says so), the typechecker should register
a nested actor's `Box_Msg` constructors under the module prefix, like other nested
variants.

Watch the TIR side too. Actor glue types are bare (`Box_Msg`), so a qualified
`Inner.Set` has to lower to the bare constructor, the same way `spawn(Inner.Box)` has
to reach `Box_spawn` (`Tir_names.actor_decl_name`).

**Acceptance.** `send(p, Inner.Set(1))` from the parent typechecks, compiles and runs
identically on both backends, or `specs/lang/` documents why it is rejected and the
diagnostic says so.
