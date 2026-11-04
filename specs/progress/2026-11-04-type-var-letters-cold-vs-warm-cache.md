Fixed (logged 2026-11-03 as `[P3]`): a diagnostic's type-variable letter depended on whether the
typecheck cache was warm. `test/errors/type_mismatch_14.march` said "expected `Pid(b)`" from a
cold `HOME` and "expected `Pid(a)`" from a warm one, so a partial `run_errors` run could record
the wrong golden.

Cause: `tvar_display_name` (`lib/typecheck/typecheck_types.ml`) assigns letters on first print from
a process-wide table that nothing reset in a CLI run. A cold run typechecks the stdlib in the same
process and can print one of its variables first, which takes `a`.

Fix: `check_module_core` calls `reset_tvar_display_names` on entry, as the LSP already did once
per analysis pass, so each check letters from `a`. Messages already rendered keep their text, and
within one check two variables still never share a letter.

Guard: `scripts/determinism-oracle.sh` has a diagnostic leg. It runs every `test/errors` program
with `--check` under its four conditions (cold/warm `HOME` × two cwds) and requires identical text
and exit status: `--corpus errors` alone, and part of `--corpus all` (CI). Proven red: the compiler
without the reset fails 8 of 340 programs (`type_mismatch_8`, `_14`, `_19`, `linear_module_let_1`,
`linear_generic_param_9`, …); with it, 340 of 340 are identical.
