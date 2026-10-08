# IR validity gate runs its corpus in parallel

**Landed:** 2026-10-07

`llvm_ir_validity_gate` (`test/test_ir_verify.ml`, part of `run_codegen`) emits and
`opt`-verifies every `test/native/*.march` fixture twice (plain, then `--debug-info`).
It walked them one at a time, and the corpus grew from 37 fixtures (2026-07) to ~335,
so the two corpus cases became ~80% of `run_codegen`'s wall time and the long pole of
both the `test (ubuntu, codegen)` shard (~50 min) and `test (macos-15, all)` (~72 min).
A CI audit found this by profiling the suite (per-case mtimes of alcotest's output files).

The walk now runs over `Domain.recommended_domain_count ()` domains, capped at 8,
overridable with `MARCH_TEST_JOBS` (the shared `Test_helpers.parallel_map`; see
`2026-10-07-parallel-test-suites.md`). Each fixture already had its own temp dir and
subprocesses; the verifier tool is resolved before any domain spawns, and
`Filename.temp_file`'s PRNG is domain-local. Results keep input order, and an exception
from one fixture re-raises only after every domain is joined.

Measured locally (M-series, load ~10, `MARCH_TEST_JOBS=4` to match a CI Linux
runner): the two corpus cases took 1704 s serially, 465 s in parallel; CPU time was
unchanged (~1540 s). Proved RED: a fixture with a type error in `test/native/` fails
case 3 with `1/335 fixtures failed ... [EMIT FAILED] zz_ci_audit_red_probe.march`.
