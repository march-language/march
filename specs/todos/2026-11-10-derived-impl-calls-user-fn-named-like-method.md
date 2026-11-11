`[P2]` A derived impl's body calls a user top-level fn named like the method instead of the method

Found 2026-11-10 while fixing `specs/progress/2026-11-10-user-stdlib-name-collisions.md`. Both
backends agree, so it is not a parity bug, but the answer is wrong:

```march
mod Main do
  needs IO.Console
  type P = P(Int, String)
  derive Show, Eq, Ord for P
  fn show(_x : Int) : String do "U" end
  fn eq(_a : Int, _b : Int) : Bool do false end
  fn main(_c : Cap(IO.Console)) do
    println(P(1, "a"))                          -- prints P(U, U), want P(1, "a")
    println(to_string(P(1, "a") < P(2, "a")))   -- prints false, want true
  end
end
```

`Desugar_derive` builds the impl bodies with bare `show(field)` / `eq(a, b)` / `compare(a, b)`
calls, and inside the entry module a bare name resolves to the user's top-level fn (the
interpreter's env, and lowering's `Lower_state._entry_builtin_shadows`), even for the `String`
field, which the user's `show(Int)` cannot take: the generated calls are not typechecked against
the user's signature. Fix: have the derive emit the qualified method (`Show.show`, `Eq.eq`,
`Ord.compare`, `Hash.hash`; the typechecker already binds those, `builtin_interface_bindings`), or
mark the generated calls as method calls, so a user fn of the same name cannot capture them.
