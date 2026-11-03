`[P3]` Diagnostics crash reports: backtrace quality and the open kinds

**Filed:** 2026-10-14, from `progress/2026-10-14-runtime-diagnostics-crash-observers.md`.
What the first cut left open:

Done since (`progress/2026-10-14-diagnostics-panic-location-fn-table.md`): the
panic's `location` compiled (lowering records the panic / todo / unreachable
call site), and frame names, files and definition lines on every platform from
a compiler-emitted function table (no dladdr, so Linux too).

1. **Exact line for every compiled frame.** Frames carry their function's
   DEFINITION line. The current line needs spans threaded through TIR (no
   `fn_def` or expr carries one; `lib/tir/provenance.ml` is a per-function side
   table), `DILocation`s on calls, and a DWARF line-table reader at runtime
   (`libbacktrace` (BSD); macOS keeps DWARF in the objects / a `.dSYM`, not the
   executable, so `dsymutil` at build time).
2. **Inlined frames.** A function LLVM inlined has no frame; an actor handler
   inlined into `<Actor>_dispatch` (which has no span) can leave a report with
   no frames at all. DWARF inline info (item 1) recovers both; cheaper, give
   the dispatch functions the actor's span so its frame at least names it.
3. **Locations for the other panics.** `unwrap` / `expect` (prelude helpers:
   track their caller's site as `panic` does, which needs a site that is
   cleared when the helper returns normally), `assert` and non-exhaustive
   matches (the interpreter reports neither line today), and runtime errors
   (division by zero).
4. **The stderr backtrace.** `march_print_backtrace` walks the `march_frame_*`
   stack the compiler never emits, so a compiled unhandled panic prints no
   stack trace. Print the unwinder's frames instead (changes every compiled
   panic's stderr, so goldens move).
5. **`TaskFailed`.** A compiled task panic exits the process (the task
   trampoline catches only cancellation, `march_proc.task_jmp`). Defining task
   failure (a crash trap that completes the `Task` with an error) is the
   prerequisite for reporting it.
6. **Global test-trap state.** `march_test_in_test` / `march_test_jmp_buf` (and
   now `march_panic_handled`) are process globals, so a `try_finally` or
   `__try_call` on one scheduler thread can catch a panic raised on another.
   Pre-existing; the crash observers inherit it. Move them onto `march_proc`.
7. **wasm / js backends.** The `diag_*` builtins exist in the native runtime
   and the interpreter only.
