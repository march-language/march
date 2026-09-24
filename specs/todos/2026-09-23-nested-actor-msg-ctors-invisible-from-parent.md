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
