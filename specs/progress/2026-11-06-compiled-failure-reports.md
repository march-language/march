Compiled programs: an unhandled failure is reported in the compile-error style (2026-11-06)

Follow-up to `progress/2026-11-05-runtime-failure-reports.md` (the interpreter's report); item 4
of `todos/2026-10-14-diagnostics-backtrace-followups.md`. A compiled unhandled panic used to
print `panic: <msg>` and nothing else: `march_print_backtrace` walked a `march_frame_*` stack
the compiler never emits.

- `runtime/march_runtime.c`: `failure_report` replaces that line in `march_panic`'s exit path
  (not the test trap, not a supervised actor's crash trap, not a crash observer's own panic).
  Layout as `Errors.render_diagnostic`: `-- RUNTIME ---- file`, headline with `[panic]` or
  `[runtime_error]`, the recorded site's source line with a caret, then the functions on the
  stack by definition line. The headline wording is the interpreter's (`bin/main.ml`'s
  `classify`): the prelude wrappers' prefix tells `panic` from `todo`; a panic raised with no
  prefix (checked division, overflow, shifts) is a run-time error.
- The caret: `__panic_site` takes the call's columns as well (`file, line, col, end_col`;
  `end_col` 0 when the call runs past its first line). `lib/tir/lower_expr.ml` passes them;
  `llvm_builtins` declare, `borrow` row, the wasm stub and `march_scheduler.h`'s proc fields
  follow. `march_int_overflow` passes column -1: its site is the enclosing function, so the
  line is shown without a caret.
- The functions: from the function table (`fn_table_block`), innermost first, a recursion's
  repeats collapsed, stdlib hidden unless `MARCH_BACKTRACE=full`, at most 8. They are
  definition lines, and the report says so and says inlined functions are missing.
- Two bugs this exposed in the existing crash-observer frames (`Diagnostics.report_of`):
  macOS `backtrace()` follows frame pointers, which compiled March functions do not keep, so
  it returned the first caller only; `diag_capture_stack` now uses `_Unwind_Backtrace` there
  (glibc's `backtrace` already unwinds by CFI). And Perceus's owned clones (`f$own0`) had no
  provenance, so their table entry was unnamed and the frame dropped; `perceus_core` now
  records them as `Clone_of (f, "owned")`.
- Source lines are read at run time from the path the compiler was given (relative paths
  resolve against the process's working directory). Unreadable: `at file:line` and
  `` `f`, defined at file:line ``.
- Corpus: `-- MARCH-MODE: run-compiled` (`test/run_errors.ml`) compiles a case at `--opt 0`
  and pins the binary's stderr (`panic_2`, `panic_3`, `runtime_error_2`).

Not done: a line for `assert`, non-exhaustive matches, `unwrap` and run-time errors (they have
no recorded site, so the report starts at the function list); the exact line of each call
(needs spans through TIR and a DWARF reader); the actor report compiled; the JIT prints the
same report but has no function table, so no function list.
