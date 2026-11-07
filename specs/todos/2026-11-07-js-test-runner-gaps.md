# JS test runner: fixtures and features the JS target cannot run yet (2026-11-07)

`march --target js --test` runs test blocks with the native report format since issue
#1176 (`specs/progress/2026-11-07-js-test-runner.md`). These gaps in the JS backend keep
some tests native-only. Each blocks a `test/test_reports/` fixture, listed in
`js_unsupported` in `test/run_test_reports.ml`; when a gap closes, remove its entry there
and the fixture's JS case must match the golden.

- **`to_string` on a record without a `Show` impl** has no JS mapping ("builtin `to_string`
  has no JavaScript-target implementation"). Blocks `assert_records`: an `assert ==` on two
  plain records. Native and the interpreter print `{ x: 1, y: 2 }`.
- **Int `/` (and likely `%`) by zero is `NaN` on JS, not a panic.** `lib/tir/js_emit.ml`
  inlines Int `/` as `(a - a % b) / b` with no zero check (the `int_div` runtime helper
  does check). Blocks `panics` ("division by zero"): the test reaches its `assert` with
  `n = NaN` instead of panicking. Not a test-runner bug; any JS program dividing by zero
  gets `NaN`.
- **`Check.all` property tests** need `__try_call` (the panic-catching call
  `Check.try_prop` uses to shrink) and `process_env` (`MARCH_PROP_SEED`), neither mapped on
  JS. Blocks `properties`.
- **Capability mocks across an actor boundary** need `actor_caps` / `set_actor_caps`; the
  `test/cap_mock/cap_mock_actor*` and `cap_mock_supervised*` fixtures do not build on JS
  (actors are native-only anyway). `cap_mock_process` needs `process_cwd`.
