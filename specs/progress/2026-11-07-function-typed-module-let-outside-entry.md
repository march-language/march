# A function-typed module-level `let` outside the entry module (2026-11-07)

Found while fixing #1170 (`specs/progress/2026-11-07-js-module-let-value.md`).

## Symptom

```march
mod LetFn do
  needs IO.Console

  mod Cst do
    let inc = fn x -> x + 1
  end

  fn main(_c : Cap(IO.Console)) : () do
    println(int_to_string(Cst.inc(4)))
    let g = Cst.inc
    println(int_to_string(g(5)))
  end
end
```

The interpreter printed `5` and `6`. A native binary printed pointer-sized integers
(`4304714848`), and `--target js` printed `[object Object]`.

## Cause

A non-entry module-level `let` is lowered to a zero-parameter fn returning its value
(`lib/tir/lower.ml`'s `lower_mod_decls`, `Lower_decls.lower_stdlib_mod_decls`); the entry
module's lets are `top_lets`, injected as locals. For a function-typed let, every reference
was lowered as if `Cst.inc` WERE the function:

- a call `Cst.inc(4)` became the known call `EApp (Cst.inc, [4])`, passing 4 to the zero-arg
  fn, which returned the closure pointer;
- a value use (`let g = Cst.inc`, `List.map(xs, Cst.inc)`) became an `AVar Cst.inc` atom at a
  `TFn` type, which native wraps in a closure trampoline over the zero-arg fn and JS emits as
  its `$clo` wrapper, so calling `g(5)` again just returned the closure.

## Fix

In lowering, so both backends get it. `Lower_state.note_module_let` records each module-let fn
whose value type is a `TFn` in `Lower_state._fn_typed_module_lets` (reset per `lower_module`).
At the end of `lower_module`, before `uniquify_fn`, `Lower_decls.call_fn_typed_module_lets`
rewrites every fn body:

- `EApp (f, args)` with `f` such a let becomes `let t = f() in call_ptr t(args)`, including
  `args = []`: a zero-parameter let (`let thunk = fn () -> 42`) called as `Cst.thunk()` is an
  `EApp (Cst.thunk, [])` that otherwise returned the closure (pointer natively,
  `[object Object]` on JS). Lowering never emits `EApp (let, [])` to read a let's value (value
  reads are atoms), so every `EApp` of one here is a source call;
- each value-use atom `AVar f` becomes a fresh `t` bound by `let t = f()` just before the
  expression that uses it.

A local binder of the same name shadows the let. `lower_more` (the remote shell's resumable
lowering) applies the same rewrite with the module's table plus any lets it lowers lazily.
Non-function lets are untouched: both backends already call a zero-arg fn read at a non-`TFn`
type (#1170). A program without a function-typed module let is unchanged (the rewrite returns
each fn as is and draws no fresh names).

## Tests

`test/native/module_let_fn.march`: calls, value uses, a two-parameter let, a polymorphic `ident` used at Int and String, a zero-parameter let (`Cst.thunk()` and
`let t = Cst.thunk; t()`), a closure built by a
call in another module, bare in-module uses (call, value, `List.map` argument), a let in a nested
module (`Cst.Inner.triple`) used from the parent and passed to `List.map`, a list of lets, and an
entry-module function let as the control. Its `.expected` is the interpreter's output; `test/dune`
diffs it against the native binary, the `--target js` output under node, and the interpreter.
Native and JS were red before the fix (pointers / `[object Object]`), all three green after.

## Not fixed here

A module-level `let` whose right-hand side names a sibling `fn` (interpreter: unbound
variable) or sibling `let` (checker: "Unknown module"):
`specs/todos/2026-11-07-module-let-rhs-sibling-reference.md`.
