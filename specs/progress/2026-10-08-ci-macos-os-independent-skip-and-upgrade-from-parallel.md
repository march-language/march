# CI: macOS skips OS-independent suites; upgrade-from runs its cases in parallel

**Landed:** 2026-10-08 (fourth PR from the CI audit; see the three 2026-10-07 entries)

After the first three PRs, the macOS `test (macos-15, all)` job was unchanged (median
64 → 63.5 min) and still the slowest in the workflow. That runner has 3 cores and its
`dune runtest` already runs every suite side by side, so parallelism inside one suite
bought nothing there: the job is bound by total CPU work. The ubuntu `rest` shard
(median 38 min) ended on `upgrade-from`: 913 s for 7 cases, one after another.

**macOS: less work.** `MARCH_CI_SKIP_OS_INDEPENDENT=1` (set only by the macOS `test` job)
disables the run of the suites whose answer does not depend on the OS. They still run on
the ubuntu shards:
- `test_refinecheck` (z3 over `--check`; 800 s on macOS);
- `run_errors` (golden `--check` diagnostics; 371 s);
- the `lsp/test` suites (`test_lsp`, `test_jsonrpc`, `test_query_cli`, `test_incremental`,
  `test_utf16`; ~150 s).

It works like `MARCH_CI_RUNTEST_SPLIT`: `enabled_if` on each `test` stanza. For a `test`
stanza that disables the run, not the build. Verified: with the variable set,
`@test/runtest-run_errors`, `@test/runtest-test_refinecheck` and
`@lsp/test/runtest-test_lsp` are empty aliases; unset, `run_errors` runs as before.
What is given up: refinecheck no longer runs against Homebrew's z3 build in CI (apt's is
still covered; dev machines are macOS).

**upgrade-from: 3 cases at a time.** `forge/test/run_cases_parallel.sh EXE [JOBS]` runs
each alcotest case of EXE as its own process (`EXE test '^<group>$' <index>`), JOBS at a
time (default `$MARCH_TEST_JOBS`, else 3), prints every case's log in order, and exits 1
if any failed.
- Processes, not domains: the tests `Unix.fork`, which OCaml 5 refuses once a second
  domain exists.
- Each case already used private temp dirs, `HOME` and `MARCH_HOME`. Ports come from
  `Procs.free_ports` (kernel-assigned).
- Remaining risk: the control-plane case also uses `port + 1000`, which nothing
  reserves, so two concurrent runs could rarely collide on it.

Guards, all three found by testing the script:
- **Missing last line.** Alcotest's `list` output has no final newline, so BSD `sed`
  plus `while read` dropped the last case (6 of 7 ran, reported green). The listing is
  normalised with `awk 1`, and the parsed count is cross-checked against a plain count
  of case lines.
- **Empty selector.** Each process must report exactly `1 test run`, so a selector
  that matches nothing fails.
- **Bare exe name.** As an argument, dune's `%{exe:x.exe}` is the bare name, which bash
  looks up on PATH. The script treats a bare name as `./`. An empty listing now prints
  the binary's own output and stderr, which is how this one was found.

Measured locally (load 15-30 from other sessions): the 7 cases took 685 s at 1 job and
210 s at 3, all passing. Through the real dune rule (`dune build @forge/test/runtest`),
all 7 pass and the whole forge test alias takes 227 s. Proved RED: with `FORGE_TEST_BIN=/usr/bin/false` all 7 fail,
each is reported, and the script exits 1.
