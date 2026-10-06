# A qualified call with too few arguments typechecked, then crashed

**Date:** 2026-10-06
**Filed:** 2026-10-06 during observe R5.1 as "the REPL segfaults on Linux when
an input calls a function with too few arguments"
([R5.1 progress](2026-10-06-observe-r5-1-shell-latency.md)).

## What was wrong

It was not Linux-specific, and not the REPL's. `let g = List.map([1, 2])`
typechecked in any program; the interpreter then raised `arity mismatch`, and
compiled code (and the REPL's compiled fragment) died with SIGSEGV. The
earlier macOS run that printed `arity mismatch` was the interpreter.

March has no partial application. The typechecker's curried `infer_app`
accepts a short call and returns the remaining arrow, so the call site checks
arity separately (the `EApp` rule, `typecheck.ml`): against `env.fn_arities`
for functions defined in the current module, and against builtin schemes.
Neither covered a **qualified** name, a function another module exports
(`List.map`, `M.add`).

## The fix

`env.qual_fn_arities` (new): the arity of every qualified function key a
public `DMod` exports, filled at the `DMod` export step from the inner
module's `fn_arities` (its own functions) and its `qual_fn_arities` (nested
modules), and merged outward the way `qual_fn_names` is. The call-site rule
consults it for a dotted name not in `fn_arities`, with the same condition as
for local functions (argument count differs from the declared arity, and the
callee's type is at least that deep, so a function that returns a function is
never flagged). The note names the definition only when it is in the caller's
file, since the renderer prints the related span from the caller's source.

```
Function `List.map` expects 2 arguments, but got 1.
March has no partial application — a call must supply all arguments.
```

Functions loaded from a compiled module registry (`ExFn` exports) carry no
arity and are not checked; source-loaded modules and the stdlib are.

## Tests

`test/test_compiler.ml`: a qualified under-application (`M.add(1)`), a
two-level nested one (`A.B.three(1, 2)`), and correct qualified calls,
including a function that returns a function, staying clean. By hand: `march
--check` on `List.map([1, 2])` reports the error, and the REPL reports it and
continues instead of dying.
