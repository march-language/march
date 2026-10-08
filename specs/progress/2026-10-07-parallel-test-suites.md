# Serial corpus loops in three suites run in parallel; property-oracle packs 4 per runner

**Landed:** 2026-10-07 (follows `2026-10-07-ir-validity-gate-parallel.md`)

A CI audit profiled each alcotest suite locally (per-case mtimes of alcotest's output
files). Three suites were dominated by one group that runs a subprocess per item, one at
a time, on 4-vCPU CI runners:

| Suite | Group | Share of suite wall time (serial) |
|---|---|---|
| run_codegen | `llvm_ir_validity_gate` (previous entry) | 1704 of 2159 s |
| test_refinecheck | `audit-baseline` | 382 of 870 s |
| run_stdlib | `adversarial-regressions` (47 `Slow` compile-and-run cases) | 544 of 664 s |

**Shared helpers (`test/test_helpers.ml`).** `parallel_map` maps over up to
`MARCH_TEST_JOBS` domains (default `Domain.recommended_domain_count ()`, capped at 8),
keeps input order, passes a worker index, and re-raises the first failure only after
joining every domain. `parallel_cases` runs a list of alcotest bodies as one batch the
first time any is reached, and each case re-raises its own stored outcome (pass, failure
or skip). `parallel_slow ?serial` applies that to a group's `Slow` cases in place, so case
indices don't move. It rejects a `serial` name that isn't in the group.

**`Sys.command` is shadowed** for `test_helpers.ml` and every file that opens it, with the
same contract on top of `Unix.system`. On macOS libc `system()` lets only one caller run
at a time: four domains each running `sleep 1` took 4.1 s through `Sys.command` and 1.0 s
through `Unix.system`. The first parallel audit sweep was no faster than serial until this.

**audit-baseline** runs each worker with its own `HOME` and cwd, so the per-file CAS clear
cannot race another worker's compile, and each worker keeps its own solver-verdict cache.
Output lines are sorted, so the baseline comparison is unchanged.

**adversarial-regressions** keeps five cases serial: the two that run forge in-process,
the hot-reload dispatch test, and the two that time an interpreted HTTP server.

**property-oracle** (`ci.yml`): the eight case lists now run four at a time on each of two
runners, each process with its own alcotest `-o` dir (which must exist first), every log
printed in a group, and the job failing if any list fails. It was 8 jobs, each using one
core of a 4-vCPU runner.

Measured locally (load 14-25 from other sessions, `MARCH_TEST_JOBS=4`):
- audit-baseline case 0: 329 s serial → 99 s, identical baseline.
- adversarial-regressions: 544 s → 184 s, 60 OK and the same one macOS skip as serial.
- Proved RED: a forced failure in one batched adversarial case is reported as `[FAIL]` on
  that case (index 15) with its message, the other 59 pass, and the exit code is 1.
- property-oracle step: simulated with a stub binary (one failing list fails the job, and
  the others still run and print). The `-o` order was checked against the real binary.
