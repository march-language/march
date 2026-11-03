# `march test`: a fresh interpreter runtime per file (2026-11-03)

`march test a.march b.march …` (and `forge test --coverage`, which calls it) runs every
file, and the doctests of every loaded module including the stdlib, in one process. Named
Vaults (`Eval_runtime.vault_registry` / `vault_name_registry`) were never cleared between
files, so the stdlib's `Vault.incr`, `Vault.put_new`, `Vault.size` and `Config.fetch`
doctests, which each file runs again, saw the previous file's state. march_doc's CI showed
63 failures over its 10 test files (`Vault.incr` returned 42 where 6 was expected).

Fix: `bin/main.ml`'s per-file test loop calls `Eval.reset_scheduler_state ()` (which
clears the Vault registries, the logger, process and revocation tables) before the file's
tests run.

Test: `run_eval` group `march_test_cli`, "fresh runtime per test file": two test files under
`--filter=Vault.incr` must pass all 6 doctests. Without the reset, 3 of 6 fail.
