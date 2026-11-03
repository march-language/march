---
description: Build and test — the March compiler itself (dune, scripts/run-tests.sh) or a March project (forge)
allowed-tools: Bash(dune:*, scripts/run-tests.sh:*, scripts/check-docs.sh:*, forge:*)
---

# Build and test

Pick the section by what is at the root: a `dune-project` is the March compiler itself, a
`forge.toml` is a March project. If the user named a suite, test or file, run only that.

## In the March compiler repo (`dune-project`)

1. **Build.** Always pass `--root .` inside a `.claude/worktrees/*` checkout, or dune builds the
   enclosing main checkout instead:
   ```bash
   dune build --root . bin/main.exe @test/stage-source-trees
   ```
   `@test/stage-source-trees` restages `stdlib/` and `runtime/` into `_build`. A targeted
   `dune build bin/main.exe` does not, so a stdlib or runtime edit would not be in the build.
   Check with `diff -rq stdlib _build/default/stdlib` (empty means staged).

2. **Test** with the agent-safe runner, which stops a stale dune daemon and runs the binaries
   directly:
   ```bash
   scripts/run-tests.sh -q              # quick: skips the Slow tests
   scripts/run-tests.sh                 # full suite, before merging
   scripts/run-tests.sh compiler codegen  # named suites
   ```
   Suites: `compiler`, `eval`, `codegen`, `stdlib`, `stdlib_march`, `test_jit`, `lsp`, `utf16`,
   `jsonrpc`, `incremental`, `query_cli`, `refinecheck` (needs `z3`). The snapshot and
   rendered-error goldens run separately: `./_build/default/test/run_snapshots.exe -e`,
   `./_build/default/test/run_errors.exe -e`.

3. **Docs lint**, if you touched docs or skills: `scripts/check-docs.sh`.

Judge every result by the exit code and the final "Test Successful"/failure line, never by the
tail of a piped command. Don't run `scripts/run-tests.sh` while a `dune build` is running in the
same tree: its daemon shutdown kills the build.

## In a March project (`forge.toml`)

1. **Typecheck first** (fast, catches most errors). If it fails, stop and report the type errors:
   ```bash
   forge check
   ```
2. **Build:**
   ```bash
   forge build
   ```
3. **Lint strictly** (warnings become errors); report each finding with its file and line:
   ```bash
   forge lint --strict
   ```
4. **Test:**
   ```bash
   forge test
   ```
   - To filter: `forge test --filter=PATTERN`
   - To replay a failed property: `forge test --seed=N`
   - To skip property tests while iterating: `forge test --skip-properties`

## On failure

For each failing test, report:
- the test name and its suite or describe block;
- what it asserted;
- the actual against the expected value, if the output shows it;
- the likely cause and a suggested fix.

For a compiler-repo failure you didn't cause, compare against `main` before attributing it to
your change. For lint failures, fix them directly unless the rule is wrong for this context;
then justify the suppression instead of silently ignoring it.
