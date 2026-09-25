# CI: real headroom for the macOS test step and the two-node scenarios

Two jobs in `.github/workflows/ci.yml` were timing out with no failing test.

- **`test (macos-15, all)`**: plain `dune runtest`, unsharded. On 2026-09-24
  it ran 37-49 min against a 45 min step budget: #619 run 36046879334 (~48
  min), #635 twice at 48 min (`run_codegen` alone took 28-29 min on the macOS
  runner), and main's own last three runs at 39, 41 and 48 min, two of them
  timing out. ac66548fd raised the step to 60 / job to 85, ~11 min over the
  worst run seen. Now **step 75, job 100** (job = step + setup 12 + build 10,
  rounded up), about 50% over the worst run.
- **`two-node`**: runs every `test/two_node/<scenario>` serially. Recent runs
  took 22-24 min (36086716005, 36086607806, 36084132828) and #642's run
  36087619570 timed out at ~26 min; one main run got through only 36 of the 52
  scenarios in 25 min, which extrapolates to ~36 min for the full list. The
  new `cert_*` scenarios from distributed-deploys step 11a (#635) pushed it
  up. ac66548fd's 35 min step sat right at that extrapolation. Now **step 45,
  job 75** (step + setup 12 + build 10 + soak 5, rounded up).

Not done, deliberately:

- **No macOS split.** Sharding `dune runtest` across macOS runners turned one
  32 min job into 67 min of macOS job-minutes and was reverted; the org has 5
  macOS runners (see `.github/workflows/README.md`, "Runner budget").
- **No two-node split.** Each extra job pays another toolchain setup + build
  (~5-8 min of Linux runner time) every run; a longer step costs nothing when
  the scenarios pass on time.

Other jobs' timeouts are unchanged. `.github/workflows/README.md` does not
quote timeout values (it defers to the workflow comments), so it needed no
edit.
