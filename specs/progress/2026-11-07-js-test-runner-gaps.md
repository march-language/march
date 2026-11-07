# JS test runner gaps closed: div/mod by zero, `to_string` without Show, `Check.all` (2026-11-07)

From `specs/todos/2026-11-07-js-test-runner-gaps.md`; what is still open (capability mocks
across actors, `cap_mock_process`'s argv check) stays there. Every
`test/test_reports/` fixture now runs on JS and matches its golden: `js_unsupported` in
`test/run_test_reports.ml` is empty.

## Int `/` and `%` by zero panic on JS

`lib/tir/js_emit.ml` inlined Int `/` as `(a - a % b) / b` and `%` as `a % b` with no zero
test, so a zero divisor gave `NaN` and the program went on (`panics` reached its `assert`
with `n = NaN`). Both now go through `emit_int_div` / `emit_int_mod`:
`(b === 0 ? march_div_zero() : (a - a % b) / b)`, the fast path one strict compare. The
runtime helpers throw the interpreter's and native's operator messages, "division by zero"
and "modulo by zero" (`march_checked_div_op` / `march_checked_mod_op`). The same helpers
cover the named `div_int` / `mod_int` forms (`div_int` was `Math.trunc(a / b)`, which also
rounds wrongly near 2^53) and the fallback typed `/` arm. The `int_div` / `int_mod` family
already checked in the runtime.

Test: `test_int_overflow_uncaught_panic` (test/test_codegen.ml) gained `h / (h - h)` and
`h % (h - h)` rows, run interpreted, compiled and on JS.

## `to_string` on a value with no `Show` impl

Mono routes a value with no `Show` impl (a plain record, an underived variant) to the
`to_string` builtin, which had no JS mapping, so the build failed. JS values carry no
Int/Float distinction, so a runtime-only printer would print `1.0` as `1`; instead
`show_expr` renders from the STATIC type: records with fields sorted by name, `Ctor(a, b)`,
a `List` as `[a, b]`, Float through `march_float_to_string` (`1.`), every String beneath
the top quoted and escaped like native's `cb_put_escaped` (`march_show_str`). A named type
gets one generated `__show$N(v)` printer per instantiation, appended after the functions;
a one-parameter type (`Tree(Int)`, `Option(String)`) substitutes its argument into the
fields. A field typed by a type variable that cannot be resolved (two or more parameters)
is classified at run time by `march_show_dyn`, which prints a whole-number Float as an Int:
the one residual difference from native, which reads a boxed Float's tag.

## `Check.all` on JS: `__try_call` and `process_env`

- `__try_call` / `__try_call_val` map to `march_try_call(thunk)`: `thunk._0(thunk, true)`,
  `Ok(result)`, or `Err(message)` on a throw. The message carries the prefix the interpreter
  and native put on a caught panic ("panic: boom", "todo: later"): `panic` / `todo` now throw
  `march_panic_error(prefix, msg)`, an Error whose message stays the bare text (what a test
  report and an uncaught panic print) with the prefix on a side property. A JS stack
  overflow is "stack overflow". `unreachable()` now throws the interpreter's
  "unreachable: reached unreachable code" (it threw "panic").
- `process_env` maps to `march_process_env` (node's `process.env`; `None` in a browser), so
  `MARCH_PROP_SEED` works under node.
- `process_cwd` and `process_pid` map too (node's `process.cwd()` / `process.pid`; "/" and 0
  in a browser), so a value-typed capability mock (`cap_mock_process`'s `process_cwd` /
  `process_pid` fields) builds on JS.

A thunk that is async (it awaits a JS-module extern) is not caught: its panic rejects a
Promise `march_try_call` cannot wait for.

Test: `test_js_test_runner_gaps` (test/test_codegen.ml) builds one `--test` program with
both backends (records and variants through `to_string`, panics caught by
`Check.try_prop` including `%` by zero and `todo`, `process_env` set and unset, a
`process_cwd` / `process_pid` mock) and requires the JS run to print exactly what the
native binary prints.

## Stale follow-up removed

`specs/todos/2026-11-05-test-report-followups.md` listed "`__assert_fail` throws the header
only (the value diff is native)" for JS; #1176 ported the differ to
`runtime/march_runtime.mjs` (`march_assert_fail`), and `assert_values` / `assert_records`
pin it on JS, so that bullet is gone.
