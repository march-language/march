# CI: macOS `test (all)` step timeout 75 → 105 min

**Landed:** 2026-11-02

`test (macos-15, all)` timed out on every `main` CI run from 2026-10-31 (d4096b583
through 976519ef2) and on every PR, at the Test step's 75-minute limit. It was not a hang:
- Every suite that printed its results passed. In each run, the two that never printed
  were `run_codegen` and `run_compiler`, the two that always finish last.
- On green runs those two take about 37 and 32 minutes. They run side by side with
  everything else on the runner's 3 cores.
- Green runs on `main` took 44-64 minutes in mid-October and 61-72 minutes in late
  October. The job grows with every suite added, and the slowest green run is only 3
  minutes under the limit, so ordinary runner variance now pushes it over.

Two other macOS failures in the same window (8d7cd4b53, d4096b583) were not timeouts.
They were the `js_bundle` file-order diff that dd5082acd already fixed.

**Change:** on macOS, the Test step limit goes to 105 minutes, about 45% over the worst
green run, and the job limit to 130 (105 plus setup 12 plus build 10). The ubuntu shards,
all under 30 minutes, keep 75 and 100, so a stuck dune on ubuntu is still stopped early.
Both values are matrix expressions (`matrix.os == 'macos-15' && … || …`).

**Not done:** splitting the macOS job. On 2026-10-07 that turned 32 minutes into 67
job-minutes against the org's limit of 5 concurrent macOS jobs (`.github/workflows/README.md`,
"Runner budget"). The next lever, if 105 is reached too, is less CPU work on macOS, as
`MARCH_CI_SKIP_OS_INDEPENDENT` did (2026-10-08 entry): for example, running only the
OS-sensitive groups of `run_compiler`.
