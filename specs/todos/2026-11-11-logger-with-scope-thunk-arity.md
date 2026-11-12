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
