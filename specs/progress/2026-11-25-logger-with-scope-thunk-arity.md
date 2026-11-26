`[P3]` Logger.with_scope(fields, fn -> ...) typechecks, runs compiled, and dies with an arity mismatch in the interpreter (2026-11-11)

`with_scope` and `with_span` declare `thunk : () -> a` and hand the thunk straight to `try_finally`, whose callbacks receive one dummy argument. A zero-argument lambda `fn -> ...` satisfies the declared type and works in a compiled binary, but the interpreter calls it with one argument and stops with a runtime arity error. Only the documented `fn _ -> ...` spelling works on both. The JS target cannot build `with_scope` at all (`logger_pop_to_depth` has no JavaScript implementation).

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Logger.with_scope([Logger.LogField("x", Logger.i(1))], fn -> Logger.field_count())))
  println(to_string(Logger.field_count()))
end
end
```

Expected: `1` then `0` on every backend

Actual (interpreted / compiled): runtime error `arity mismatch: expected 0 args, got 1` / `1` then `0`

Source: `with_scope` in stdlib/logger.march; `try_finally` in lib/typecheck/typecheck_builtins.ml.

## Decision (2026-11-23, owner)

The root (2026-10-12-function-arity-not-in-types.md) is decided: arity goes in the type. Do
not wait for it here: wrap the thunk (`try_finally(fn _ -> thunk(), ...)`) so the interpreter
stops dying, and map `logger_pop_to_depth` on the JS target.

## Fixed (2026-11-25)

Not by wrapping the thunk. `try_finally(fn _ -> thunk(), ...)` would call the thunk with
no argument, and the spelling the docs give (`fn _ -> ...`, including the module's own
doctest) would then be the one to die in the interpreter. The fix is in the interpreter's
`try_finally` (lib/eval/eval_builtins.ml): a callback that is a zero-parameter closure is
applied to no argument, any other to the one placeholder, which matches what compiled
code does with the extra word. Both spellings now work on both engines, for
`Logger.with_scope`, `Logger.with_span` and a direct `try_finally`.

Tests: `test/stdlib/test_logger.march`, group "with_scope and with_span thunks" (four
cases). Three failed interpreted on main with "arity mismatch: expected 0 args, got 1";
all pass interpreted and compiled.

Other builtins that hand a callback a placeholder argument (`task_spawn`, `__try_call`)
are unchanged; arity in the type (2026-10-12-function-arity-not-in-types.md) is the root.

The JS half of the decision is not done and has its own todo: the JS target lacks
`logger_add_field`, `logger_field_count` and `logger_pop_to_depth`, not only the last
(`todos/2026-11-25-js-logger-context-builtins-missing.md`).
