# `march --target js --test` runs the tests (issue #1176, 2026-11-07)

## The bug

`march --target js --test` compiled the test blocks into the `.mjs` and never called them:
a test that must fail built with exit 0, and `node` printed nothing and exited 0. Three
causes:

- `lib/tir/js_emit.ml` never read `tm_tests`; its module tail emitted only `main()`. The
  native backend builds a test-runner `@main` from `tm_tests`
  (`lib/tir/llvm_toplevel.ml`, the `m.Tir.tm_tests <> []` branch).
- With a `main` in the file, `bin/main.ml` pruned the JS module to what `main` reaches
  (`Dce.prune_unreachable ~roots:["main"]`), so the test functions were removed and `main`
  ran.
- `--test` turns capability mocking on (`Flags.cap_mocking`), which injects the
  `__march_dispatch_*` wrappers; they call `cap_dict`, which had no JS mapping, so any
  program that prints failed to build: "builtin `cap_dict` has no JavaScript-target
  implementation".

Also, a failed `assert` on JS threw only the report's header (the first `\x1f` field of its
metadata): the value diff under it was native-only, and `__test_header` was a no-op, so a
panicking test could not have been reported as `This test panicked: ...` either.

## The fix: parity with the native runner

Chosen over rejecting `--test` with `--target js`: the native harness is small (init / run /
report) and the report's value differ is already a deliberate port in two languages, so a
third port keeps one format everywhere and the golden suite can hold all three to it.

- **`runtime/march_runtime.mjs`**: `march_test_init` (`--verbose` / `-v`, `--filter=`),
  `march_test_header`, `march_test_setup_all`, `march_test_run` (async; awaits the test,
  catches what it throws, prints `.` / `F` or the verbose lines), `march_test_report` (the
  failure blocks and `Finished:` line; `process.exitCode = 1` on a failure, not
  `process.exit`, so buffered output is never cut off), and `march_assert_fail`, a port of
  `lib/errors/test_report.ml`'s parser, differ and renderer (the same one
  `march_assert_fail` in `runtime/march_runtime.c` ports). Strings are handled as arrays of
  code points, so a column is a code point, as `test_report.ml`'s `width` counts UTF-8 lead
  bytes.
- **`lib/tir/js_emit.ml`**: `__test_header` and `__assert_fail` call those runtime
  functions; when `tm_tests` is non-empty the module tail runs `march_test_init`, the
  optional `setup_all`, `march_test_run` per test (with the optional per-test `setup`) and
  `march_test_report`, instead of `main`, as native does. Capability builtins:
  `cap_impl(c, d)` is `d`, `cap_dict(c)` is `None` for `undefined` and `Some(c)` otherwise,
  `cap_narrow` is the identity, `mint_cap` is `undefined`, and `root_cap` is a const
  `undefined` in the preamble (native: NULL-or-dictionary, `march_cap_*`).
- **`bin/main.ml`**: with tests, the JS module is pruned to the tests and their setup
  blocks instead of `main`.

## Tests

- `test/run_test_reports.ml` (suite `test_reports`) runs each golden fixture a third way,
  `march --target js --test --opt 0` then `node`, and requires the same failure blocks. New
  fixture `test/test_reports/runner.march` (a panic after `setup` / `setup_all`, a plain
  `assert`, an `assert !=`). Fixtures listed in `js_unsupported` are skipped on JS with the
  gap named; see `specs/todos/2026-11-07-js-test-runner-gaps.md`. Red before the fix:
  `assert_values` and `runner` received `exit 0` and no failure blocks.
- `test/test_codegen.ml`, group `iface_impl_mono_codegen`, case "--target js --test runs the
  tests like the native runner (#1176)": a program with `needs IO.Console`, a `main` and a
  printing test; the JS run must print what the native test binary prints, byte for byte,
  plain, with `--filter=` and with `--verbose`, must not run `main`, and must exit 1 / 0.
  Red before the fix: the build failed on `cap_dict`.
- By hand: the `test/cap_mock/` fixtures that use no actors or process builtins
  (`cap_mock_clock`, `cap_mock_io`, `cap_mock_iface_generic`) give their expected results
  under `--target js --test`.

## Docs

`docs/tooling.md`, JavaScript Backend, "Tests on this target"; the `--test` help text.
