# Compiled Logger appenders are no-ops; atoms log as `null`

Filed 2026-09-26 from `specs/progress/2026-09-26-same-named-builtin-abi-audit.md`.

**Appenders.** The interpreter keeps a registry of `(name, LogEntry -> Unit)`
callbacks (`eval_runtime.ml`'s `logger_appenders`). `logger_dispatch` builds a
`LogEntry(Level, msg, ts_ms, source, fields)` and calls each appender. It falls
back to the stderr text line only when the registry is empty.

The compiled runtime has no registry. `march_logger_register_appender`,
`march_logger_remove_appender` and `march_logger_clear_appenders` are no-ops,
`march_logger_appender_names` always returns `Nil`, and
`march_logger_dispatch` always prints the fallback line. So a compiled
program's `Logger.add_appender(Logger.Appender("json", cb))` silently never
calls `cb`, and `Logger.list_appenders()` is `[]`.

What a fix needs:

- A runtime registry that holds an OWNED reference to each callback.
  `logger_register_appender` then moves from `extern_borrow_table` to
  `extern_owned_builtins` in `lib/tir/borrow.ml`. Its entry there is borrowed
  only because the C function is a no-op today.
- `march_logger_dispatch` needs to build the `LogEntry` and a `Level`
  constructor in C, in whatever representation the compiled `Logger.Level` /
  `Logger.LogEntry` types use, and call each closure through the documented
  closure-call convention (`march_runtime.h`). The dispatch mutex must not be
  held across the call, because an appender may log.
- A parity case in `test/native/same_named_builtin_abi_parity.march`, which
  today checks only that `list_appenders()` is empty on both backends.

**Atoms.** A `Logger.LAtom(a)` field renders as `:a` interpreted and as `null`
compiled (`logvalue_scalar_str` in `runtime/march_runtime.c`). Atoms are
interned integers compiled, and the runtime has no name table. The
compiler-generated `march_atom_to_string` is only emitted when a program calls
it directly.
