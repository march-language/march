# ocap p6: `:load` in a REPL session skips the static grant checks

Logged 2026-11-23 by ocap phase 6, Task 7 (re-review M7).

`march repl FILE` runs the dependency-grant checks on its entry file before loading it: a
child `march --check` with the same environment and `--dep-grants` flag, and a refusal to load
when the output has a `[dep_grant_…]` or `[dep_module_conflict]` diagnostic (`bin/main.ml`,
the `march repl` branch). A file loaded later in the session with `:load` is not checked that
way. Its code still runs under the run-time grant frames (the interpreter always frames; the
JIT REPL's lowering wraps package functions), so a reached violation fails closed, as a
refusal at run time rather than an error at load.

What to do: run the same check (or the in-process `check_dep_grants` and the resolver's
module-conflict claims) on a `:load`ed file, in both the JIT and the interpreter REPL, and add
a `test_dep_grants` `forge 4`-style case for `:load`.
