`[P2]` **Test runner unattributed non-zero exit finding (2026-08-15).**
`scripts/run-tests.sh` collapses all runner failures into one `FAILED` bit and
prints only `One or more suites FAILED.` It does not preserve the runner name,
original exit status, signal, or whether a later suite was reached. Therefore
a runner can emit `Test Successful` and still make the script exit 1 without a
`[FAIL]` line or an attributable diagnostic. The loop was audited directly;
the exact historical CI occurrence was not reproduced. A future fix should
add per-runner status capture, an explicit failure summary, and a regression
harness for a success-printing/non-zero fake runner.

---

## Fixed 2026-09-08

The finding above was recorded but not acted on, and the corresponding item
stayed open in `specs/todos/`. It is now implemented, and that todo is removed
(a `git mv` would have clobbered this file).

### The bug

The old loop was

```bash
if ! $TIMEOUT_CMD ./_build/default/test/${runner}.exe -e $QUICK_FLAG; then
  FAILED=1
fi
```

`if ! cmd` **discards the status**: inside the branch `$?` is the status of the
`!` pipeline, which is always 0. The number has to be captured with
`|| status=$?` on the command itself, which is what the new code does.

### All four acceptance criteria

1. **Every non-zero invocation reports the runner name and original exit
   status, including signal-derived statuses.** `run_suite` captures the status
   and `record_failure` prints `!! SUITE FAILED: <runner> -- <why>` at the point
   of failure. `describe_status` decodes rather than printing a bare number:
   `exit status 3`; `killed by signal 9 (SIGKILL) [exit 137]` for `128 < st <
   192`; and `TIMED OUT after <N>s (exit 124)` for GNU `timeout`'s own code,
   with a note that timeout signals the whole process group.
2. **The final summary lists all failed or unstarted suites, preserving the
   existing non-zero exit.** The summary is now
   `N of M suite invocations FAILED:` followed by one `  - <runner>: <why>` line
   each. `exit $FAILED` is unchanged, and the literal line
   `One or more suites FAILED.` is still printed, so anything grepping for it
   keeps working.
3. **A successful summary followed by a launcher failure is attributed to that
   runner.** That is the headline case and is pinned by case 1 of the test.
4. **A regression test exercises a fake runner that prints `Test Successful`
   and exits non-zero.** `scripts/test-run-tests.sh`, 19 assertions over 5
   cases.

Beyond the criteria: a suite whose executable is missing is now reported as
`NOT RUN -- no executable at <path>` rather than silently counting as a pass.
That is a distinct failure mode — a green run of everything else says nothing
about a suite that never started — and it is the same class of gap as the
`test/stdlib/*.march` files that ran in no runner at all.

### How the test drives the script

Two hooks exist for the test alone and are documented as such in the script's
env block: `MARCH_TEST_RUNNER_ROOT` (where `test/<r>.exe` lives) and
`MARCH_TEST_SKIP_BUILD`. No dune, no real suites; the whole test runs in well
under a second. It is wired into CI's `doc-lint` job — a test that nothing runs
is precisely the failure mode this repo keeps rediscovering.

### RED/GREEN, proven

A GREEN alone would prove nothing here, so the test was first run against a
control: the **original** execution loop with only the two hooks bolted on.

- Against the old loop: **6 assertions FAIL** — the original exit status is not
  reported, the failure is not attributed at both the failure point and the
  summary, a signal is not decoded, "never started" is not distinguished from
  "tests failed", per-runner statuses are not kept, and the summary does not
  list the failures.
- Against the new script: **19 / 19 pass**.
- Case 5 (the all-green path) passes under **both**, so the test is not simply
  red on everything.

Note that "names the failing runner" alone passes even on the old script,
because the `==> <runner>` header happens to print the name. That is why case 1
also asserts the runner appears **at least twice** and that the exit status
appears — the header is not attribution.

`scripts/run-tests.sh -q eval`, `-q eval lsp`, and `-q test_jit` (the
env-passing branch) all still exit 0.
