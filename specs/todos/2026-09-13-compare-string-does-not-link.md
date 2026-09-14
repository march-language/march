# `compare_string(a, b)` typechecks but the compiled program does not link

Found 2026-09-13 (`specs/progress/2026-09-13-builtin-borrow-classification.md`).

`compare_string` is in the typechecker's builtin table
(`lib/typecheck/typecheck_builtins.ml`: `String -> String -> Int`), but
`lib/tir/llvm_builtins.ml` has no `in_is_builtin` row for that name. It has
only `march_compare_string`, marked `in_is_builtin = false`. The emitter falls
back to a direct call of the bare name:

```
Undefined symbols for architecture arm64:
  "_compare_string", referenced from: _march_main
```

The interpreter runs it. String ordering through `<`/`>` is unaffected, since
it calls `march_compare_string` directly (`llvm_emit_arith.ml`).

**Fix:** add a row `march_name = "compare_string"; c_name = Some
"march_compare_string"; in_is_builtin = true`, and add `compare_string` to
`Borrow.extern_borrow_table` (the C function only reads). The classification
guard (`test/test_builtin_borrow_classification.ml`) will require one or the
other. Add a native golden that calls it on two fresh strings and checks both
the value and the `live_allocs` delta.

Check the other `compare_*` names in `defun.ml`'s builtin list
(`compare`, `compare_int`, `compare_float`) the same way.
