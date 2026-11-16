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

## Fixed 2026-11-11

`Desugar_derive` now emits `Show.show(field)`, `Ord.compare(a.f, b.f)` and `Hash.hash(x.f)`. (The
derived `Eq` body uses the `==` operator, which a user fn cannot capture; the user's `fn eq` in the
repro never ran.) The qualified spelling had to be made the type-directed method on both backends
first, since neither treated it that way:

- **Compiled.** `Lower.lower_module`'s `reg_method` registered the primitive impls (`Eq$Int.eq`,
  `Ord$Int.compare`, `Show$Int.show`, `Hash$Int.hash`, …) under the bare method name only, while
  every written impl is also registered as `Iface.method`. `Ord.compare(1, 2)` therefore found the
  program's own impls and stopped with "no `Ord` implementation for type `Int`". The primitive
  rows are now registered under both keys. The TIR name stays `Show.show`, which neither
  `Lower_state.resolve_use_alias` nor `Lower_decls.rename_tir_vars` can rewrite to a user fn, and
  `Mono` already resolves it by key (so a generic `derive Show for Box(a)` works).
- **Interpreted.** `Show.show` resolved through `module_registry`, whose `Iface.method` slot holds
  the LAST impl evaluated: with two types deriving `Hash`, `Hash.hash(P(..))` ran `R`'s impl
  ("field access on non-record value"), and on a primitive there was no binding at all once a
  user fn shadowed the bare name. `Eval_builtins.base_env` now binds the four qualified names to
  the same dispatcher builtins as the bare ones, and the `DImpl` arm writes that dispatcher (not
  the impl) into the shared registry slot.

The repro's second line was mis-stated: `P(1, "a") < P(2, "a")` is `false` with or without the
user fns, because a derived `Ord` on a variant compares constructor index only.

Tests: three interpreter-vs-compiled parity tests in `test/test_codegen.ml`
(`newtype_derived_method_crash` group): the entry-level repro, the same inside a nested module
with a generic type, and the qualified methods written by hand (primitives; two types
implementing one interface). All three failed before the fix.

Left open: `specs/todos/2026-11-11-derived-impl-bare-builtin-calls-capturable.md` (the derived
`Hash` and `Json` bodies still call three plain builtins by bare name).
