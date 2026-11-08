`[P3]` JS target: a builtin passed as a closure value escapes the unmapped-builtin check

`lib/tir/js_emit.ml` fails the compile with "builtin `X` has no JavaScript-target
implementation" only for a builtin it sees in a direct call (`ctx.unmapped`). A builtin
referenced as a first-class value (passed to a higher-order function after defunctionalization)
is emitted as a bare identifier, so the program compiles and throws `ReferenceError: X is not
defined` at run time. `try_finally` was one (found while adding the Diagnostics builtins,
`progress/2026-11-07-diag-builtins-js.md`; it now has a closure wrapper const). The check should
also cover builtin names emitted as values, or every value-position builtin should get a
`wrapper` const.
