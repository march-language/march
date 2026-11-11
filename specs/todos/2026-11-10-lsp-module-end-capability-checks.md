# The editor's edit-time typecheck runs no module-end capability checks

Found 2026-11-10 (ocap phase 3, Task 7). The LSP typechecks each edit with
`Typecheck.check_module_with_env_full` over a seeded stdlib env (`lsp/lib/typecheck_cache.ml`).
That entry point stops after the declarations: it never runs what `check_module_core` runs at
the end of a module, so the editor shows no entry-module `needs` check (Check 1b at the entry), no
`main` grant (`cap_grant`, `cap_grant_exceeded`), no function `needs` bound (`cap_bound`), and not
the typecheck-side ceiling. `--check` reports all of them.

Phase 3 made the background TIR pass (`run_tir_pass`) report the full ceiling and host scopes, so
those two reach the editor. Simply running the module-end checks on the seeded env was tried and
over-reports: `cap_grant_exceeded` on a program `--check` accepts, and errors on an IO-free
program, because the seeded env's capability closures differ from a whole-module check's. The fix
is to find what the seeded env lacks (likely the stdlib's per-function closure rows) or to run
these checks in the background pass on a whole-module typecheck.
