# Capability mocking: no dispatch wrapper for value-typed IO ops

Logged 2026-10-13. Found validating forgepm against the 0.5.0 tree: its
`forge test` (756 tests, green on 8f2f6608) stopped compiling with
`__march_dispatch_process_argv (called from Bastion.main) is not a function in
scope and not a runtime builtin`.

## The problem (`lib/typecheck/io_ops_gen.ml`)

`process_cwd`, `process_argv` and `process_pid` are typed as bare values
(`Mono t_string`, `Mono (t_list t_string)`, `Mono t_int`), not arrows.
`field_ty_of_builtin` accepts any `Mono` type, so `dict_fields` gives them
dictionary fields, and so `Cap_passing.cap_of_interceptable_op` treats them as
interceptable and rewrites every call to `__march_dispatch_<op>`. But
`dispatch_wrapper` returned `None` for a non-arrow type ("nothing to wrap"),
so the wrapper the rewrite targets was never generated.

Latent since compiler-inserted capability passing landed (#389, 2026-09-01).
Hidden until now because an unreachable function that calls one of these ops
was dropped before codegen; on 8f2f6608 a test that actually *calls* such a
function already failed at link (`___march_dispatch_process_argv` undefined).
Current main emits bastion's CLI `Bastion.main` (which calls `Process.argv()`)
in a test build, so every bastion-dependent project hit it. `--test` only:
cap mocking is off in ordinary builds, so `forge build` was unaffected.

## The fix

`dispatch_wrapper` now generates a wrapper for a value-typed op too. Its
dictionary field already had the value's type (`Option(String)` for
`process_cwd`, documented that way by `--emit-io-ops`), so the wrapper
returns the mocked value, or calls the op when the field or the dictionary is
`None`, matching the arrow case's fallback.

## Test

`test/cap_mock/cap_mock_process.march` (compiled `--test`, diffed against its
`.expected`): mocks `process_cwd` and `process_pid` inside `with_cap`, checks
the real cwd before and after, and that an un-mocked `process_argv` falls
through. Failed with the undefined-wrapper error before the fix. The other six
`cap_mock_*` fixtures and the `cap_dict`, `prog_argv` and
`cap_sandbox_runtime` suites still pass. forgepm main: 756/0 with the fix.
