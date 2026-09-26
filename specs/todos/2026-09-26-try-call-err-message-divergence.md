# `__try_call` / `__try_call_val` Err messages differ between backends

Filed 2026-09-26 from `specs/progress/2026-09-26-same-named-builtin-abi-audit.md`.

When the thunk panics, the interpreter returns `Err("panic: boom 3")`, but a
compiled program returns `Err("boom 3")`. The compiled runtime
(`march_try_call` / `march_try_call_val` in `runtime/march_runtime.c`) copies
`march_test_fail_buf`, which `march_panic` fills without the prefix. The
interpreter's `Eval_error` message carries it.

`stdlib/check.march` reports this string when a property fails, so a property
failure reads differently interpreted and compiled. Pick one form, probably the
interpreter's, since other panic reports print `panic: ...`. Then pin it in
`test/native/same_named_builtin_abi_parity.march`, which today checks only that
the result is `Err`.
