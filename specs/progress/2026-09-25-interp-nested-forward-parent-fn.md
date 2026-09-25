# `[P3]` DONE Interpreter: a nested module calling a parent fn declared AFTER it died with "stub called before initialisation"

Filed 2026-09-25 while fixing the compiled side of the same shape
(`specs/progress/2026-09-25-nested-module-parent-call.md`, PR #645). Fixed
2026-09-25.

## The bug

```march
mod Main do
  needs IO.Console
  mod Outer do
    mod Inner do
      fn g(x : Int) : Int do later(x) end
    end
    fn later(x : Int) : Int do x * 10 end
  end
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(Outer.Inner.g(4)))
  end
end
```

`march --check` accepted it and `march --compile` printed `40`. The
interpreter exited 1 with `stub later called before initialisation`. The same
happened when `Outer` was a `MARCH_LIB_PATH` module, from an impl method or
actor handler inside `Inner`, and from a module two levels down
(`Outer.Inner.Deep`). Declaring `later` before `mod Inner` worked around it.

## Root cause

Module evaluation in `lib/eval/eval.ml` runs in two passes. Pass 1 binds a
placeholder (`<stub:NAME>`) for every fn of a scope. Pass 2 walks the decls
in order and replaces each placeholder with the real closure in the scope's
env ref. Closures look up names in that ref when they are called, so
same-scope forward references work.

A nested module's own env ref (`inner_ref` in the `DMod` arm of `eval_decl`)
starts from the parent env as it stands at the `mod`. At that point the
parent's binding for `later` is still the pass-1 placeholder. Nothing
re-points the nested env at the parent's final env, so `Inner.g` found the
placeholder at call time, and the placeholder only raised.

## Fix

The placeholders now forward. `forward_stub scope_ref name` (next to the
`stub` type in `lib/eval/eval.ml`) builds a placeholder that looks `name` up
in its own scope's env ref when it is called:

- If the real binding is there, it applies that binding.
- If the scope still holds this same placeholder (the fn really has not been
  declared yet), it raises the same `stub NAME called before initialisation`
  error as before.

All three places that install placeholders use it: top-level per-file runs
(`install_stubs` in `eval_module_env`, whose ref is now created before the
stubs so they can close over it), nested modules (`eval_decl`'s `DMod`), and
on-demand stdlib modules (`eval_stdlib_decls`). A nested impl, actor or
deeper module inherits the parent's placeholder in its env, so all of those
work without further changes.

Module-level `let` initialisation order does not change. A `let` that calls a
fn declared after it still fails when it is evaluated, with the same message
as on origin/main. At top level that is `stub later called before
initialisation`. Inside a nested module it is `unbound variable: Outer.later`.

## Tests

- `test/test_eval.ml`, `test_eval_nested_module_forward_parent_fn`: a nested
  fn, a fn two levels down, an impl method and an actor handler, each calling
  a parent fn declared after the nested module. RED on origin/main (`stub
  later called before initialisation`).
- `test/test_eval.ml`, `test_eval_let_calling_later_fn_still_fails`: a
  too-early `let` at top level and inside a nested module still raises the
  message origin/main raises.
- `test/test_codegen.ml`, `nested_module_parent_call`: #645's two compiled
  programs (the `MARCH_LIB_PATH` one and the entry-file one) now also run
  INTERPRETED against the same expected output
  (`..._lib_path_interpreted`, `..._entry_interpreted`). Both are RED on
  origin/main: after `42` they print the stub error.
