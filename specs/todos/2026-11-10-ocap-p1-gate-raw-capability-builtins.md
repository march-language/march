# Raw capability builtins are still callable from user code

Logged 2026-11-10 by ocap phase 1 (specs/plans/2026-11-10-ocap-p1-result-plan.md,
Task 5, deferred). Phase 1 put every check in the stdlib entry points
(`Authority.check`), so a program that calls a raw builtin directly
(`unix_time_ms(())`, `task_spawn(...)`, `file_read(p)`, `process_env(k)`)
bypasses the check and gets the old, never-refused type.

Today that bypasses nothing: no limit refuses at run time until ocap phase 4
(only the test hook `MARCH_TEST_REFUSE` does). It becomes a hole the moment
phase 4 lands, so the gate belongs with phase 4 (or phase 2 for the handle
builtins it re-types).

What to do: add every `Checked { gated = true }` row of
`lib/caps/cap_ops.ml` (`Cap_ops.gated`) to the stdlib-only table
(`Typecheck_env.stdlib_only`), except the two the stdlib shadows (`println`,
`random_bytes`: a user call already reaches the checked stdlib function); give
the `stdlib_internal` diagnostic a machine-applicable rename to the row's first
entry point where the arity matches (`file_read` -> `File.read`,
`process_env` -> `Process.env`, `print` -> `IO.write`, `vault_new` ->
`Vault.new`, ...), none for unit-argument builtins (`unix_time(())`) or a
different shape (`task_spawn` -> `Task.async`, `print_stderr` adds no newline
where `IO.warn` does); then migrate the corpus (about 300 direct calls in
test/, bench/, examples/, most `task_spawn`, `unix_time`, `unix_time_ms`),
including the builtin-level tests in test/test_codegen.ml that call them on
purpose (they move behind a stdlib-spanned fixture). Check that the literal
path-scope check (`path_arg_builtins`, lib/typecheck/typecheck_caps.ml) still
fires on the `File.*` entry points after the rename.
