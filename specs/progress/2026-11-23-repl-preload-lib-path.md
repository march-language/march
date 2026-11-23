# `march repl FILE`: library modules, load order, module impls

Found by ocap phase 6, Task 6: the cap conformance suite's REPL mode preloads
each fixture (`march repl FILE`, with `MARCH_REPL_INTERP=1`), and the
dependency-grant fixtures call modules on `MARCH_LIB_PATH`. Three gaps in the
REPL's file loading (`lib/repl/repl.ml`), each also present without grants:

1. **No library discovery.** The file's imports were resolved with
   `~auto_discover:false`, so a module named only by a qualified call
   (`Libmod.hello()`) was "Unknown module". The three file-loading sites
   (`parse_file`, `tui_parse_file`, the TUI reload) now use the batch driver's
   discovery, with its reachability pruning. Per-input `import` resolution at
   the prompt is unchanged (still `~auto_discover:false`, kept cheap).
2. **Load order.** The REPL checks a loaded file's declarations one at a time,
   so a library module checked before one it calls failed. `load_in_dependency_order`
   retries a failing declaration after the others while a pass makes progress;
   what still fails reports its diagnostics.
3. **Impls inside modules.** `check_decl` of a `DMod` keeps the module's impls
   in its inner env, so a later declaration's `show` of the module's type was
   `missing_impl`. `register_module_impls` (factored out of the stdlib preload,
   which had the same fix for the stdlib) now also runs on each module the REPL
   loads.

Tests: `test/test_jit.ml`, group `repl_session`, "a preloaded file reaches
MARCH_LIB_PATH modules (interpreter)" and "a loaded file's modules load in
dependency order, impls too (interpreter)". Both fail without the fix.

Not fixed: the JIT REPL still cannot call a preloaded file's own functions
(`Unknown_callee`, `specs/todos/2026-11-10-repl-module-call-unknown-callee.md`);
the conformance suite's REPL mode is the interpreter REPL.
