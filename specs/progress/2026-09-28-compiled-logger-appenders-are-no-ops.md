# Compiled Logger appenders run, and atoms log by name (fixed 2026-09-28)

**Reproduced on origin/main (9f4c543f2)** with
`test/native/logger_appenders_parity.march`. The interpreted run called every
appender and listed `[b][a]`. The compiled run listed nothing, printed every
line through the stderr fallback, and rendered `state=null` where the
interpreter printed `state=:closed`.

## Appenders

- **Registry (runtime/march_runtime.c).** Appenders are a linked list of
  `(name, callback)`, newest first, under `march_logger_mutex`. This matches
  the interpreter: registering prepends and replaces a same-named entry,
  names are listed newest first, and dispatch calls newest first.
  `logger_register_appender` stores both arguments, so it moved from the
  borrow table to `extern_owned_builtins` (`lib/tir/borrow.ml`).
  `remove_appender` and `clear_appenders` unlink entries under the lock and
  release them after dropping it.
- **Dispatch.** Under the lock, dispatch takes a snapshot of the callbacks,
  one `march_incrc` each, which the call consumes. It then drops the lock
  and calls each callback with a fresh argument cell. With no appenders it
  prints the existing fallback line.
- **Why the runtime does not build the `LogEntry`.** The compiler picks
  `Logger.Level`'s constructor tags, and they are global (`Info` =
  33554478), not 0..3, because another type is also named `Level`. A first
  version built `Level` cells with tags 0..3: every level match fell through
  to the default arm. Instead:
  - the runtime passes `Logger.AppenderCall(level_string, msg, ts_ms, source, fields)`;
  - `add_appender` registers `fn call -> deliver(cb, call)`;
  - `deliver` builds the `LogEntry` in March, via `level_from_string`.
  The interpreter's `logger_dispatch` passes the same `AppenderCall`. The
  builtins' signatures are unchanged, since they were already polymorphic.
- **Why a constructor and not a tuple.** A 5-tuple leaked one object per
  message. Compiled tuple destructuring leaks fields that are moved on
  (`specs/todos/2026-09-28-compiled-tuple-destructure-leaks-moved-fields.md`),
  and a single-constructor type does not. A tuple's Int slot is also tagged
  while a constructor field's is raw: an untagged ms timestamp in a tuple
  segfaulted the tuple's drop.

**Ownership story.** The registry owns one reference to each name and each
callback. It releases them on replace, remove or clear. Each dispatch holds
one extra reference per callback, which the call consumes. **Known
limitation:** releasing a closure from C is shallow (`march_decrc` frees the
cell, not what it captured). The same applies to every closure the runtime
stores, such as `delivery_failed_watch`. A removed CAPTURING appender
therefore leaks its captures; LeakSanitizer reports two 32-byte cells in the
fixture, one for each capturing appender that was replaced or cleared. A
non-capturing appender, whose closure is static, leaks nothing, and the
fixture's register/remove loop uses one.

## Atoms

`logvalue_scalar_str` renders `LAtom` through the program's generated
hash-to-`:name` table. `emit_atom_show_table` (`lib/tir/llvm_toplevel.ml`)
now also emits the table when the module calls `march_logger_dispatch` or
`march_logger_get_context`. It does not scan for the declares, so programs
that never log are unchanged.

**Registration, not a weak symbol (2026-09-29).** The first version gave the
runtime a weak default `march_atom_to_string` returning NULL, for the strong
generated one to override. That broke the classic REPL JIT on Linux only
(CI run 36529641362, `test (ubuntu-24.04, rest)`, `repl_compiler_parity` case
6: `show(:ok)` gave `null`, not `":ok"`). The runtime `.so` is dlopen'd
`RTLD_GLOBAL` before any fragment. ELF lookup is flat, and at load time a
weak definition binds exactly like a strong one, so each fragment's own
`show(:ok)` call bound to the runtime's stub. Confirmed in the
`march-ci-ubuntu` container: the test runtime `.so` built from the PR exports
`W march_atom_to_string` and case 6 fails; on origin/main it has no such
symbol and the test passes. macOS two-level namespaces bind a fragment's
call to its own definition, which hid the bug.

Now the runtime defines no `march_atom_to_string` at all. Each module emits:
- its table as an internal function, `@march_atom_name_or_null`, which
  returns NULL for a hash it never saw;
- `@march_atom_to_string`, also internal, which calls the lookup and falls
  back to `":<atom>"`, so nothing can interpose it;
- on native targets, an `llvm.global_ctors` entry that calls
  `march_set_atom_namer(lookup)`, and an `llvm.global_dtors` entry that calls
  `march_unset_atom_namer(lookup)`.

The runtime keeps a mutex-protected list of registered lookups, tries them
newest first, and renders `null` if none of them knows the hash. Unregistering
from the destructor matters because REPL fragments and hot patches are
dlclose'd, and a stale pointer would call into unmapped code. A side benefit:
with the old default linkage, a later RTLD_GLOBAL fragment could also bind to
an earlier fragment's table, which lacked the later fragment's atoms.

## Verification

- `test/native/logger_appenders_parity.march` has one dune rule that runs
  it interpreted and compiled, and four diffs against one stdout and one
  stderr golden. It covers:
  - a capturing appender that survives its binding;
  - two appenders, newest first;
  - replace-by-name moving an appender to the front;
  - `remove` of a missing name;
  - `clear`;
  - `log_in` with a source and an atom field (appender path);
  - the fallback with an atom field (stderr);
  - `live_allocs` leak probes for register/remove (non-capturing) and for
    50 dispatches through a capturing appender.
- ASAN in a Linux container (arm64): no AddressSanitizer errors in 3 runs.
  LeakSanitizer shows only the two capturing-closure cells described above.

---

Original report:

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
