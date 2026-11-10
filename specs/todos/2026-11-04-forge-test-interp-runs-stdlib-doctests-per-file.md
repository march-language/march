# `[P2]` Interpreter-mode `forge test` runs the stdlib's doctests in every project test file

Found 2026-11-04 testing depot on v0.7.0. `MARCH_TEST_INTERPRETER=1 forge test` in depot ran
121092 tests across 50 files, 366 of them failing. Run alone, `test/test_between.march` runs
441 tests on v0.6.0 and 2398 on v0.7.0. The difference is march's own stdlib doctests, which
0.7.0 runs inside each project test file. Still true on main (5ea851f2).

Two things then go wrong, neither of them the project's fault:

> **Re-checked 2026-11-09 on `c3cd49c76`: the shared-state half is fixed** (most likely by
> `066709110`, a fresh interpreter runtime per file,
> `specs/progress/2026-11-03-march-test-fresh-runtime-per-file.md`): two test files that both
> use `Vault.new("counters")` pass, 4808 tests across 2 files. **Still open:** the stdlib's
> doctests (about 2,400) run in every project test file, in that file's scope. A test file
> declaring `fn identity(a, b, c)` fails `doctest identity (1)` with "arity mismatch: expected
> 3 args, got 1". (depot's exact `filter` shadowing is now refused earlier, as
> `[prelude_collision]`.)

- ~~**Shared state across files.**~~ (fixed, see above) One interpreter process runs every file. The `Vault.*` and
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
