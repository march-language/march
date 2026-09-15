# Interpreter: prelude bodies resolve free names in the prelude's own scope

Shipped 2026-09-15.

## Bug

```march
mod ShowShadow do
  needs IO.Console
  pfn show(r : Result(Bool, String)) : String do
    match r do
      Ok(_) -> "ok"
      Err(e) -> e
    end
  end
  fn main(_c : Cap(IO.Console)) do
    println("hi " ++ show(Ok(true)))
  end
end
```

Interpreted: `panic: match failure — ... no branch matched the value "hi ok"`
inside `println`. Compiled: `hi ok`. `stdlib/prelude.march`'s
`fn println(x) do print_line(show(x)) end` resolved its bare `show` to the
user's `pfn show`.

The pre-existing `test/native/iface_method_collision.march` fixture had the
same failure interpreted; it only had a compiled rule, so nothing noticed.

## Cause

The interpreted pipeline hands `Eval.eval_module_env` one flat decl list,
prelude.march's unwrapped top-level decls followed by the entry module's
(also unwrapped). Pass 1 installed stubs for every top-level fn in that list,
and pass 2 closed every top-level fn over ONE shared `env_ref` holding the
program-wide final environment. So a prelude body's lookup of `show` hit the
entry module's binding (shadowing the `show` builtin), and prelude `impl`
closures (which freeze `env` at declaration time) saw the user's stubs.
`Prelude_collision` deliberately allows `show`/`eq`/`compare`/`hash` at the
interface arity because the compiler resolves them by type, so this reached
runtime.

## Fix

`lib/eval/eval.ml`: `top_level_file_runs` splits the top-level list into
maximal runs of consecutive decls from the same source file (decls with no
real file, e.g. a stdlib `DMod`'s dummy span or a string fixture's `""`, join
the current run, so a single-file module is exactly one run, unchanged).
`eval_module_env` evaluates each run with its own stubs and its own scope ref:
an earlier run (prelude) never sees a later run's bindings; a later run sees
everything before it.

Performance: an earlier run's closures no longer share the physical
`global_tail`, so `assoc_str` also probes `scope_tails` (a hashed table per
earlier run's final env, installed with the global tail and cleared by
`clear_global_tail`). Interpreted `bench/list_ops.march`: 31.2s before,
31.7s after (noise).

## Tests

- `test/native/prelude_scope_user_shadow.march`: native AND `interp_` rules
  against one `.expected`. Red on the pre-fix interpreter (the panic above),
  green after.
- Added the missing `interp_iface_method_collision` rule for the existing
  fixture.

Related (compiled-side analogues, already fixed): user fn named like a libc
symbol; defun capture-shadowing of a stdlib HOF's param.
