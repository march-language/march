# JS test runner: capability mocks the JS target still cannot run (2026-11-07)

`march --target js --test` runs test blocks with the native report format since issue
#1176 (`specs/progress/2026-11-07-js-test-runner.md`). The gaps that kept the
`test/test_reports/` fixtures native-only (Int `/` and `%` by zero, `to_string` without
`Show`, `Check.all`'s `__try_call` / `process_env`, `process_cwd` / `process_pid`) closed
on 2026-11-07 (`specs/progress/2026-11-07-js-test-runner-gaps.md`), and
`js_unsupported` in `test/run_test_reports.ml` is empty. What is still open:

- **Capability mocks across an actor boundary** (`actor_caps` / `set_actor_caps`). The
  `test/cap_mock/cap_mock_actor*` and `cap_mock_supervised*` fixtures do not build on JS,
  and mapping those two builtins alone would not change that: the JS target has no actors
  at all (`spawn`, `send`, `run_until_idle`, `register_actor_inspect` and
  `actor_inspect_store` are all unmapped, and `lib/tir/js_emit.ml` has no actor runtime).
  This closes only with actor support on JS, a subsystem of its own (a mailbox and
  scheduler in `runtime/march_runtime.mjs`), not with a builtin mapping.
- **`cap_mock_process` on JS fails one assertion, by design of `process_argv`.** It now
  builds and its mocks work on JS (`process_cwd` / `process_pid` are mapped; the same
  mocks are checked against native by `test_js_test_runner_gaps` in
  `test/test_codegen.ml`), but its last check, `List.length(Process.argv()) >= 1`, relies
  on native's `argv[0]` (the executable, as `stdlib/process.march` documents). On JS,
  `process_argv` is deliberately the arguments after the script (`test/native/js_argv.march`,
  pinned by a dune rule), so the list is empty under a plain `node prog.mjs`. Running the
  fixture on JS needs a decision: give JS an `argv[0]` (the script path, which changes
  `js_argv`'s pinned output) or keep the difference and leave this fixture native-only.
  Until then there is no JS rule for `test/cap_mock/` in `test/dune`.
- **`to_string` without `Show` on JS: a whole-number Float under a multi-parameter type
  prints as an Int.** `show_expr` (`lib/tir/js_emit.ml`) substitutes a one-parameter type's
  argument into its fields, but `Tir.TDVariant` / `TDRecord` do not record the declared
  parameter order, so with two or more parameters a field typed by a parameter is printed
  by `march_show_dyn` at run time, where a JS number cannot say it was a Float:
  `to_string(Pair(1, 2.0))` for `type Pair(a, b) = Pair(a, b)` prints `Pair(1, 2)` on JS and
  `Pair(1, 2.)` natively. Closing it needs the parameter list kept on the TIR type
  definition (`lower_type_def` in `lib/tir/lower_decls.ml` drops it).
