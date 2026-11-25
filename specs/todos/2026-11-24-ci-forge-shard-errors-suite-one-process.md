# `[P3]` CI: the `forge` shard times out on a slow runner; `run_errors` is one 35-minute process

**Seen** 2026-11-24: `test (ubuntu-24.04, forge)` hit its 75-minute step limit on PR #1319
(run 45487315828) and on two other branches the same evening (runs 45518529134,
45524190947). In each, `run_errors.exe` and `run_cap_conformance.exe` were still running
when the step was killed. On main the step takes 46 to 51 minutes.

**Measured on main (run 45518748170).** `errors` 2104 s, `cap_conformance` 1297 s,
`march-dep-grants` 1245 s, `deploy-e2e` 1011 s, each `upgrade-from` case 468 to 724 s. On
the runner PR #1319 got, every suite took about 1.5 times as long (`march-dep-grants`
2187 s, `deploy-e2e` 1559 s), which puts `errors` past the limit on its own.

A slow runner also failed one `upgrade-from` case with a wrong exit code (#1319: "an
upgrade that drops", forge exited 0 where 1 was expected, after 1088 s; run 45524190947:
"an upgrade that removes"). Not looked into; it may be a deadline inside the test.

**What would fix it.** `run_errors` is a single alcotest group (`golden diagnostics`), so
`Test_helpers.run_groups` cannot split it as it stands. Split the cases into groups by
slug prefix, or give `run_errors` its own fan-out over `ERRORS_ONLY` prefixes, then set
`MARCH_TEST_PROCS` for the shard as `rest` and `refinecheck` do. `run_cap_conformance` is
also one process.
