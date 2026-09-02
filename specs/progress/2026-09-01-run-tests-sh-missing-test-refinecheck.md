# scripts/run-tests.sh silently skipped the refinement-checker suite

`test/dune` gives `test_refinecheck` (the ~550-case, z3-gated integration
suite for `lib/refinecheck/`) its own alcotest executable stanza, but
`scripts/run-tests.sh`'s `ALL_RUNNERS` array never listed it and
`test/run_compiler.ml` does not pull its test bodies in either. `dune runtest`
covered it; the documented agent-safe invocation (CLAUDE.md
"Parallel-agent / reliable test invocation") did not. A fully green
`scripts/run-tests.sh` therefore said nothing about the refinement checker —
discovered 2026-09-01 while diagnosing solver-undecided behavior on branch
`claude/refinement-errors-improvement-de2bdc`, where every task had to invoke
the exe directly.

Separately, `test/test_refinecheck.ml`'s `gated` helper calls `Alcotest.skip`
(not a silent pass) when no z3 binary is found, but alcotest still exits 0 and
prints "Test Successful" on an all-skipped run — so a z3-less machine could
see this suite reported green while verifying almost nothing.

## Fix

- Added `test_refinecheck` to `ALL_RUNNERS` in `scripts/run-tests.sh`, so
  `scripts/run-tests.sh refinecheck` (or `test_refinecheck`) resolves via the
  existing bare-name convention, and the full run includes it.
- None of its cases carry a `Slow` tag (so `-q` doesn't shorten it), and at
  ~3.5-4.5 min with z3 present it would dominate a "quick" loop's budget for
  no savings. Added a `QUICK_DEFAULT_EXCLUDE` list (currently just
  `test_refinecheck`) so `-q` with no suite names skips it by default, while
  naming it explicitly (`-q refinecheck` or `refinecheck`) still runs it.
  Documented the choice in the script's header comment.
- Added an explicit `command -v z3` check before running `test_refinecheck`
  in the script's execution phase, printing an unmissable banner and setting
  `FAILED=1` for the whole run when z3 is missing — mirroring how the script
  already avoids `test_jit`'s silent-skip hazard by fixing up `MARCH_BIN`
  itself, except here there is no environment fix-up available (z3 is an
  external binary), so the script fails loudly instead.
- Updated CLAUDE.md's "Suites:" list and the `dune build test/...` direct-
  invocation line to include `test/test_refinecheck.exe`, plus a z3 caveat for
  the direct-invocation path.

## Verification

`scripts/run-tests.sh -q refinecheck` (z3 present locally): builds
`test/test_refinecheck.exe` and runs it directly, printing the real per-suite
`[OK]` count (551 tests run with z3 4.16.0) rather than a vacuous green.
