# `[P2]` Interpreter-mode `forge test` runs the stdlib's doctests in every project test file

Found 2026-11-04 testing depot on v0.7.0. `MARCH_TEST_INTERPRETER=1 forge test` in depot ran
121092 tests across 50 files, 366 of them failing. Run alone, `test/test_between.march` runs
441 tests on v0.6.0 and 2398 on v0.7.0. The difference is march's own stdlib doctests, which
0.7.0 runs inside each project test file. Still true on main (5ea851f2).

Two things then go wrong, neither of them the project's fault:

- **Shared state across files.** One interpreter process runs every file. The `Vault.*` and
  `Config.fetch` doctests use fixed table names (`Vault.new("counters")`, `:test/:port`), so
  from the second file on they see the earlier file's writes. `Vault.incr (1)` expected 1 and
  got 5, then 9. `Config.fetch (1)` expected `Err(KeyMissing(...))` and got `Ok(8080)`. That's
  49 of 50 files failing 7 doctests each.
- **Scope.** The doctests are evaluated in the test file's scope. In depot's
  `test_sqlite_compile.march`, a 3-argument `filter` shadows the prelude's, and
  `doctest filter (1)` fails with "arity mismatch: expected 3 args, got 2".

Expected: a project's `forge test` runs the project's tests and its own doctests, not the
stdlib's. If stdlib doctests are meant to run there, they need a fresh environment per file
and the stdlib's own scope.

depot's CI moved to the compiled suite (depot#7) to stay green on v0.7.0.
