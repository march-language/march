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
- **`test` sharded 4 ways on ubuntu** (macOS: see below): `codegen`, `refinecheck`, `compiler` run
  their per-test dune aliases (`@test/runtest-run_codegen`, ...); `rest` runs
  `dune runtest` with `MARCH_CI_RUNTEST_SPLIT=1`, which an `enabled_if` on
  those three `(test)` stanzas in test/dune turns into "everything except
  them". Verified with `dune show aliases test`: the three `runtest-*`
  aliases disappear with the variable set, `runtest-run_stdlib` stays.
  Unset (every local run) nothing changes.
- **`two-node` job**: the node_discovery soak and the two-node scenarios moved
  out of the ubuntu `test` leg onto their own runner.

## A missing dep the split exposed

The first CI run on this change failed `test (*, codegen)` on both OSes: every
`repl_jit_*` case said "could not find runtime/march_runtime.c". The
`run_codegen` stanza never declared the staged `runtime/` tree (or
`bin/main.exe`, which some cases shell out to); a full `dune runtest` only
passed because another rule staged `runtime/` first. Declared now, the same way
`run_compiler` does. Same run, the other shards and jobs were green, and wall
time was 30 min against a 67 min median before.

## macOS un-split

The same first run measured job-minutes per pool: Linux 224 (down from ~250,
`trmc-suite` gone), macOS 94 (up from ~57). The four macOS shards summed to 67
min against 32 for one `dune runtest`, and macOS was never the critical path,
so the split cost the 5-slot macOS pool for no wall-time gain. macOS is back to
one `test (macos-15, all)` job; only ubuntu is sharded. Per run: 29 jobs
(23 Linux, 6 macOS).

## Markdown-only changes skip CI

`ci.yml` now has `paths-ignore: ['**.md']` on both triggers. Nothing in it reads
the repo's Markdown (checked: forge's tests read a README.md they generate in a
temp project; the other hits are comments). `doc-lint`, whose checks do read
Markdown, moved to its own always-on `doc-lint.yml`. A Markdown-only commit on
main gets no CI run, which the nightly gate handles: it builds the newest
commit with a green run.

## Not verified locally

CI wall-clock after the change: the new numbers come from the first runs on
this branch.
