# `__try_call` / `__try_call_val` Err messages match the interpreter (fixed 2026-09-28)

**Form chosen: the interpreter's.** A panic caught by `__try_call` reads
`panic: <msg>`, which is also what an uncaught panic prints on either backend.
`todo(msg)` reads `todo: <msg>`, and `unreachable()` reads
`unreachable: reached unreachable code`.

**RED on origin/main (14ec3b71f)**, from `test/native/try_call_err_message.march`:
- compiled: `Err(boom 3)`, `Err(boom 7)`, `Err(later)` and `Ok(Err(boom 9))`;
- interpreted: `Err(panic: boom 3)`, `Err(panic: boom 7)`, `Err(todo: later)` and `Ok(Err(panic: boom 9))`.

Found along the way: compiled `unreachable()` **segfaulted**, both caught and
uncaught. The `unreachable_` row shared `march_panic_ext(ptr %s)`, but
`unreachable_` takes no argument, so the IR called `@march_panic_ext()` and
`march_panic` dereferenced a missing string
(`march: fatal SIGSEGV ... addr=0x10`).

**Fix (runtime/march_runtime.c, lib/tir/llvm_builtins.ml).**
- The fail buffer `march_panic` fills keeps the bare message, because the
  compiled test runner prints it that way. The diverging entry points now
  record which prefix the interpreter would use:
  - the `panic` builtin row now names `march_panic_user`, which sets
    `panic: ` and calls `march_panic`;
  - `march_panic_ext` sets `panic: `;
  - `march_todo_ext` sets `todo: `.
- `march_try_call` / `march_try_call_val` clear the prefix on entry, build
  the Err as prefix + message (`march_caught_panic_message`), and restore the
  outer prefix on exit, as they already did for the jump buffer.
- `unreachable_` has its own `march_unreachable_ext(void)`, which panics
  with the interpreter's message and no prefix.
- `march_panic` keeps its declare through `runtime_only_declares`, because
  the case emitter's non-exhaustive fallthrough calls it directly.

**Still different (not panics).** A compiled assert or non-exhaustive match
goes through the same `panic` builtin with the compiler's own text, and now
reads `panic: assertion failed`. The interpreter reads `assert failed at
<file>:<line> ...` and `match failure: Non-exhaustive ...`. These texts
already differed before this change. A division by zero (`division by zero`)
is caught identically on both backends and is unchanged.

**Verification.** `test/native/try_call_err_message.march` runs compiled
(`native_try_call_err_message`) and interpreted
(`interp_try_call_err_message`), diffed against one `.expected`. It covers
panic under both builtins, a panic after a `let`, `todo`, `unreachable`, a
nested try, and the success paths. A standalone uncaught `unreachable()`
now prints `panic: unreachable: reached unreachable code` and exits 1
instead of SIGSEGV. The golden native preamble in `test/test_codegen.ml`
gains the two new declares.

---

Original report:

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
