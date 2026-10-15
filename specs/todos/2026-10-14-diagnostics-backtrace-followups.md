`[P3]` Diagnostics crash reports: backtrace quality and the open kinds

**Filed:** 2026-10-14, from `progress/2026-10-14-runtime-diagnostics-crash-observers.md`.
What the first cut left open:

1. **Linux frame names.** `dladdr` sees only the dynamic symbol table, which a
   non-hot-reload Linux executable does not export, so compiled reports there
   carry an empty backtrace. Read the executable's own `.symtab` instead
   (`/proc/self/exe`, bias from `dladdr`'s `dli_fbase`), or vendor
   `libbacktrace` (BSD), which also gives item 2. Do not turn on
   `--export-dynamic` globally: a user function named like a libc symbol would
   interpose it.
2. **File and line.** `--debug-info` emits one `DISubprogram` per function
   (`lib/tir/llvm_toplevel.ml`), so a DWARF reader gives each frame its
   definition line; per-call-site lines need `DILocation`s on calls. Then fill
   `StackFrame.file/line` and `CrashReport.location` compiled.
3. **Readable names.** Lambda-lifted and specialised functions report their
   LLVM names (`$lam0__lam0__top$apply$1_Fragile_Poison`). The provenance side
   table (`lib/tir/provenance.ml`) maps them back to source functions; it is
   compile-time only today.
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
