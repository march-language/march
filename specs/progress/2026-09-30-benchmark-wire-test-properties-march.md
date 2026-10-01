# `test/stdlib/test_properties.march`: measured, and run nightly (done 2026-09-30)

Filed 2026-08-12 alongside
`specs/progress/2026-08-11-test-stdlib-march-files-not-in-ci.md`. The file
sat on its own dune alias (`@test/stdlib-march-properties`) that nothing ran,
because its runtime was unknown ("several hours" under heavy contention).

## Measurement

The exact command the alias runs (`march test stdlib/test_properties.march`,
from `test/`), origin/main 771430bf3, arm64 dev Mac, one run:

| | |
|---|---|
| result | `1 file, 240 tests passed` (it was 228 when filed) |
| wall clock | **237.6 s** |
| `sysctl -n vm.loadavg` at start | `{ 6.07 6.83 8.03 }` |
| `sysctl -n vm.loadavg` at end | `{ 11.72 9.79 9.04 }` |

A second run through dune itself (`dune build --root .
@test/stdlib-march-properties`, i.e. exactly what the nightly job runs):
exit 0, 240 passed, **244.5 s** wall, load average `{ 4.73 5.19 6.23 }` at
the end.

The box was not idle (this session's other test suites were running), so the
uncontended time is lower, but not by the order of magnitude that would put it
in the todo's "seconds to low tens of seconds" band. The "several hours" figure
from 2026-08 was contention, not the test.

## Decision: nightly, not `runtest`

By the todo's own thresholds this is "genuinely slow" for a per-PR gate:
`runtest` runs on every PR on both OSes, and the macOS `test (all)` job already
runs close to its 45-minute timeout. So:

- `.github/workflows/nightly.yml`: new `stdlib-properties` job (ubuntu,
  `needs: gate`, 45-minute job timeout, 30 for the step) runs `dune build
  --root . @test/stdlib-march-properties`. Unlike `quarantined` it is NOT
  `continue-on-error`: these tests are not expected to flake, so a red run is a
  real stdlib regression. It does not gate `publish`, matching
  `stdlib-docs-smoke`.
- `test/dune`: the alias stays. Its comment now carries the measurement and
  points at the nightly job instead of "a follow-up should benchmark it".
- `.github/workflows/README.md`: lists the job, and notes that the file is
  covered nightly rather than per PR.
