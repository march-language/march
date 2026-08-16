`[P2]` **Test runner unattributed non-zero exit finding (2026-08-15).**
`scripts/run-tests.sh` collapses all runner failures into one `FAILED` bit and
prints only `One or more suites FAILED.` It does not preserve the runner name,
original exit status, signal, or whether a later suite was reached. Therefore
a runner can emit `Test Successful` and still make the script exit 1 without a
`[FAIL]` line or an attributable diagnostic. The loop was audited directly;
the exact historical CI occurrence was not reproduced. A future fix should
add per-runner status capture, an explicit failure summary, and a regression
harness for a success-printing/non-zero fake runner.
