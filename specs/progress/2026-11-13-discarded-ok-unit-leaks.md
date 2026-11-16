# A discarded `Ok(())` leaks its cell (logged 2026-11-13, fixed 2026-11-16)

Found in ocap phase 2b Task 15. Under `--rc-trace` + `scripts/gc-trace-report.py`, and under
LSan, most native fixtures reported one or two live 24-byte `Ok(())` cells at exit: the
`Result` that `println` returns when it is discarded. That made both leak tools red on almost
every fixture and hid real leaks.

## Two causes

1. **A `match`/`if` used as a statement.** `Perceus_core.discarded_call_result_ty` rebinds a
   discarded owned call result (`ESeq (f(x), rest)`) to a dead `let` so the dead-binding
   branch releases it, but it only looked at an expression whose tail is an `EApp`. A
   statement `match n do 2 -> println("two") _ -> println("other") end` is an `ECase` whose
   arms end in calls, so nothing released its value. It now also accepts an `ECase` whose
   every arm (and default) ends in a call, recursively. An arm ending in an atom or a field
   read disqualifies the case: that value may be borrowed.
2. **A block-final `let`.** Typecheck gives a `let` in value position the type `()`
   (`infer_block`), but `Lower_expr` lowered `Ast.ELet` to its right-hand side's value, so
   `let _ = println("x")` as the last line of `main` returned the `Ok(())` to a caller
   expecting `()`. It now lowers as the block statement followed by `()`; the binding is
   dead and Perceus releases it.

## Tests

- `test/test_rc_trace.ml`, "a discarded Ok(()) is released": a program discarding three
  `println` results (a `match` statement, an `if` statement, a final `let _`) is built with
  `--rc-trace`, and `gc-trace-report.py` must report 0 live objects and exit 0. Before the fix:
  3 live `Ok(())` cells, all allocated in `println$String`.
