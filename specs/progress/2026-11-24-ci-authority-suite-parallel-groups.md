# CI: the authority suite runs its groups in two processes

**Seen** 2026-11-24 on PR #1322: the `test (ubuntu-24.04, rest)` step hit its 75-minute
limit with every finished suite green and `run_authority.exe` still running. The same step
took 74 minutes on PRs #1318 and #1320, and 52 to 54 on main.

**Cause.** `run_authority` (71 cases in 11 groups, each case a compile or a run) is one
alcotest process. It took 1940 s on main's run 45518748170 and 2567 to 2587 s on the slower
runners the three PRs got. The other suites of the shard finish in about 20 minutes
(`march-stdlib` is the last, 885 to 1186 s), so the authority suite then runs alone on one
of four cores for 15 to 25 minutes, and the step's length is its length.

**Fix.** `test/run_authority.ml` calls `Test_helpers.run_groups` (the mechanism
`test_refinecheck` uses), and the `rest` shard sets `MARCH_TEST_PROCS=2`. Two and not
`$(nproc)`: the stdlib end-to-end cases, which are sensitive to timing, run beside it.
Unset, as in a local `dune runtest`, the suite runs in one process as before.

**Not fixed here.** The `forge` shard has the same shape: `run_errors` (487 cases, one
group) took 2104 s on main and `run_cap_conformance` 1297 s, and the step timed out on three
PRs the same day. See `specs/todos/2026-11-24-ci-forge-shard-errors-suite-one-process.md`.
