# REPL TUI `:reload` has no test

Logged 2026-11-23 by ocap phase 6, Task 6 (review M1).

Task 6 made the TUI's `:reload` load through `tui_load_decls_list` (dependency order, module
impls), the same path as the TUI's first load (`lib/repl/repl.ml`), after the batch REPL's
file loading was fixed to reach `MARCH_LIB_PATH` modules in dependency order
(`specs/progress/2026-11-23-repl-preload-lib-path.md`). No test covers it: the TUI needs a
terminal, and `test_jit`'s `repl_session` cases drive the line REPL only.

What to do: drive the TUI under a pseudo-terminal (or factor `:reload`'s load step so a test
can call it) and pin that a reloaded file still reaches its `MARCH_LIB_PATH` modules, in
dependency order, with their impls.
