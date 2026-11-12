# CI keeps the evidence of a failed test job

Logged 2026-11-11. The "failure-evidence capture" item of package E3 in
`specs/plans/2026-11-11-pre-1.0-execution-plan.md`.

**Before.** Only the Linux `test` shards kept anything: core files and their executables
(`cores-<os>-<shard>`, 14 days). A two-node or sanitize-gate failure left the job log and nothing
else, a macOS crash left nothing, and several flake sightings were closed as "log not kept".

**Now.** `scripts/ci-evidence.sh` (`setup` / `collect`), called by `ci.yml`'s `test` (every
shard, macOS included), `two-node` and `sanitize-gate` jobs. A failed job uploads
`evidence-<job>-<shard>`, kept 7 days:

- the test step's full output (`test.log`, `two-node.log`, `sanitize.log`), teed by the step;
- Linux: cores (up to 2 GB in total), `cores/backtraces.txt` for the first 8, the executable of
  each under `binaries/`;
- macOS: crash reports written to `~/Library/Logs/DiagnosticReports` since `setup`;
- `dune.log` (`_build/log`);
- the work directory `scripts/two-node.sh` leaves for a failed scenario (node binaries, stdout,
  stderr, golden diffs), with sockets and fifos removed;
- `sanitize/`: `specs/lang/golden/sanitize.sh` copies each failure's ASan binary, output and
  compile log there before it deletes its work directory (`keep`, a no-op without
  `MARCH_EVIDENCE_DIR`).

No new job; three steps per job, two of them failure-only.

**Checked.** `scripts/test-ci-evidence.sh` (a `doc-lint.yml` step) stages a failure and asserts
what `collect` keeps. Run for real: a segfaulting C program in an `ubuntu:24.04` container
produced the core, the gdb backtrace and the binary; the same program on macOS produced a crash
report that `collect` copied.

**Not covered.** macOS core files (GBs each; the crash report has the backtrace). ASan builds
dump no core (ASan's default). `macos-checks`, `property-*` and the oracle jobs are unchanged.
