# CI: shard the `test` job, drop `trmc-suite` and `MARCH_NO_TRMC`, cancel superseded PR runs (2026-09-21)

## Why

Measured over the 40 most recent completed CI runs (2026-09-21): median wall
time 67 min (max 152), and the worst-waiting job in each run queued a median of
24 min (max 75). The org is on GitHub's free plan (20 concurrent Linux jobs, 5
macOS, org-wide) and one CI run already asks for 26 jobs, so queueing is slot
contention. The wall time was set by two jobs:

| job | avg | where it went |
|---|---|---|
| `trmc-suite` | 54.7 min | `MARCH_NO_TRMC=1 scripts/run-tests.sh`, serial: codegen 18.6, refinecheck 18.7, compiler 12.1, stdlib 3.8 |
| `test (ubuntu-24.04)` | 50.4 min | `dune runtest` 36 (codegen 24.4, refinecheck 23, compiler 17.5 side by side after ~9 min of build), then two-node scenarios 15.4 |

## What changed

- **`concurrency:` on ci.yml.** Grouped by PR number with
  `cancel-in-progress: true`; pushes to main group by `run_id`, so they never
  cancel. Last week 0 of 295 CI runs were cancelled and about 20 of 195 PR runs
  were still running when a newer push landed.
- **`trmc-suite` removed, and `MARCH_NO_TRMC` with it** (bin/main.ml). The env
  var was read only in bin/main.ml, so the job only ever changed tests that
  spawn the compiler; in-process suites (most of refinecheck, LSP, eval) ran
  twice for nothing. And with the stdlib moving to natural-style recursion,
  a whole-suite TRMC-off run is the "green for the wrong reason" job described
  in specs/todos/2026-09-09-rewrite-stdlib-list-producers-into-natural-style.md.
  `--no-trmc` stays.
- **`test` sharded 4 ways per OS**: `codegen`, `refinecheck`, `compiler` run
  their per-test dune aliases (`@test/runtest-run_codegen`, ...); `rest` runs
  `dune runtest` with `MARCH_CI_RUNTEST_SPLIT=1`, which an `enabled_if` on
  those three `(test)` stanzas in test/dune turns into "everything except
  them". Verified with `dune show aliases test`: the three `runtest-*`
  aliases disappear with the variable set, `runtest-run_stdlib` stays.
  Unset (every local run) nothing changes.
- **`two-node` job**: the node_discovery soak and the two-node scenarios moved
  out of the ubuntu `test` leg onto their own runner.

## Not verified locally

CI wall-clock after the change: the new numbers come from the first runs on
this branch. Net job count per run goes from 26 to 32 (Linux 20 -> 23, macOS 6
-> 9); the macOS legs are the likeliest to queue now.
