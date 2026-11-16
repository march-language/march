# A generalized `let x = None` at a niche-unsafe Option segfaulted compiled (2026-11-07)

GitHub issue #1173.

## Symptom

```march
fn start() : Option(Float) do
  let x = None
  x
end
```

Compiled at any `--opt`, matching on `start()` died with SIGSEGV at address 0x8. The
same happened at `Option(())` and `Option(Option(Int))`, and for a record
`{ n: s, o: None }` returned as `{ n : Int, o : Option(Float) }`, which printed its
output and then crashed when the record was dropped. The interpreter and the JS backend
were correct. `let x : Option(Float) = None` and a bare `None` with no `let` were fine.

## Root cause

March generalizes every `let` (no value restriction), so `let x = None` binds
`x : forall a. Option(a)`. Lowering typed the binder and its RHS at the scheme's residual
variable, and nothing later substitutes it: it is not a type parameter of the enclosing
function, so mono leaves it alone. `--dump-tir` showed

```
let $t45517 : Option(Float) = let x_i1 : Option('_55612) = alloc Option.None('_55612)() in x_i1
```

Codegen encodes `Option(TVar)` under the erased niche convention (None is raw null,
`lib/tir/llvm_emit_alloc.ml`), which is deliberate and stays. But `Option(Float)`,
`Option(())` and `Option(Option(_))` fail `Kind.niche_payload_ok` and are Boxed, so the
match and the drop glue at the use type loaded the constructor tag from `ptr + 8` on the
null.

## Fix

The binding is now lowered at the type it is used at (`lib/tir/lower_expr.ml`, the
`EBlock (ELet …)` case; `lib/tir/lower_state.ml`, `_poly_let_uses`):

- An unannotated `let name = e` whose binder type still holds a type variable (and no
  function type), and whose RHS builds its value in a layout the type decides
  (`poly_let_rhs_ok`: constructors, record/tuple literals and literals, over leaves
  that are literals, variables with no type variable in their type, or another tracked
  binding), registers `name` in `Lower_state._poly_let_uses` while the rest of the
  block lowers. EVar lowering records each use's span type there. A use is counted only
  while `_fn_param_types` still holds the exact type value the `let` installed, so a
  lambda or nested-fn parameter that shadows the name is never counted.
- When every use instantiates the binding at one type `T`, `poly_let_specialisation`
  matches the binder type against `T`. If the substitution moves a variable and maps the
  binder type exactly onto `T`, the binder becomes `T`, the RHS is rewritten with that
  substitution (`alloc Option.None(Float)()`, now Boxed like its consumer), and the
  uses in the body are retyped (`retype_var_uses`, which respects shadowing).
- A chain (`let x = None; let y = x; y`) works because the inner binding, once
  specialised, applies its substitution to the uses recorded by the enclosing bindings.
- Anything else falls back to the old lowering: uses at two different types, a use typed
  with the unknown placeholder, or a substitution that does not reproduce `T` exactly.

The RHS restriction matters. A call is never retyped: `let built = record_from_list(..)`
is a dynamic record whose layout the runtime fixed. Retyping it to the record type its
`{ built with a: .. }` use infers moved the update off the erased
`march_record_update_dyn` path, and the B5 tests in `erased_record_update_codegen`
failed. A generic fn called in the RHS is still specialised by mono, from its arguments.

Bindings whose variables belong to the enclosing function (a polymorphic fn's `'a`)
record uses at the same variable, so the substitution is the identity and they are left
alone. Mono specialises them as before. The `Option(TVar)` niche convention for code
that really is polymorphic is untouched.

## Tests

`test/test_codegen.ml`, `poly_let_none_codegen`: one program with every shape from the
issue (Float, Unit, nested Option, the record field and its drop), a `let y = x` chain,
a closure capturing the binding, and a poly `None` merged with an annotated `Some`. It
compiles at `--opt 0` through `3` and must print the interpreter's output and exit 0.
RED before the fix: SIGSEGV at 0x8, exit 139.

## Not covered

- A binding used at two different concrete types still falls back. It needs one copy of
  the value per type. The fallback is no worse than before.
- `let x : Option(Float) = make_none()`, where `fn make_none() : Option(a)` has its type
  variable only in the return type, still segfaults, with or without the annotation. Mono
  specialises from argument types only, so `make_none` is emitted generic and returns a
  niche null. This has a different root cause and predates this fix. Filed as
  `specs/todos/2026-11-07-return-only-poly-fn-niche-unsafe-option.md`.
