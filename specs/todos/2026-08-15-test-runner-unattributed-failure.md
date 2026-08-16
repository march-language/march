# Test runner must attribute non-zero suite exits

`scripts/run-tests.sh` aggregates suite failures into one `FAILED` integer.
When a runner exits non-zero, the script records `FAILED=1` but does not print
the runner name, raw exit status, signal, or a diagnostic. The final line is
only `One or more suites FAILED.`

This permits a misleading CI result: every Alcotest runner can print
`Test Successful`, while a runner invocation still returns non-zero (for
example, a wrapper/launcher failure after the test process has emitted its
summary). The script exits 1 without naming the failed invocation, and the
reported output contains no `[FAIL]` line. A failure before or around the
stdlib runners is therefore especially difficult to distinguish from a test
failure or a runner that was never reached.

## Audit evidence

The current execution loop is:

```bash
if ! $TIMEOUT_CMD ./_build/default/test/${runner}.exe -e $QUICK_FLAG; then
  FAILED=1
fi
```

The only information retained is the aggregate bit. The shell's `!` also
removes the original status from the conditional unless it is captured inside
the branch. No per-runner failure list is emitted before the aggregate exit.

## Acceptance criteria

- Every non-zero runner invocation reports the runner name and original exit
  status, including signal-derived statuses.
- The final summary lists all failed or unstarted suites, while preserving the
  existing non-zero exit behavior.
- A successful test summary followed by a launcher failure is visibly
  attributed to that runner rather than reported as an anonymous suite
  failure.
- A regression test exercises a fake runner that prints `Test Successful` and
  exits non-zero, proving the script reports it.
