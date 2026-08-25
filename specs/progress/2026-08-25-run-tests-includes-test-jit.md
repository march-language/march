# `scripts/run-tests.sh` now runs `test_jit`

Landed 2026-08-25.

## The gap

`test/test_jit.exe` (19 alcotest cases covering the REPL JIT and
`march --jit`, added 2026-08-24/25) ran under `dune runtest` — and therefore
in CI — but was never in `scripts/run-tests.sh`'s `ALL_RUNNERS` list. Local
agent/dev runs via `scripts/run-tests.sh` (the documented, agent-safe way to
run tests — see `CLAUDE.md`) silently never exercised it, which is how a
REPL-JIT regression reached CI twice in one month without a local run ever
having a chance to catch it.

## The subtlety

`test_jit` is not a plain alcotest exe: `test/dune`'s `(test (name test_jit)
...)` stanza sets `HOME` to a project-relative tmp dir and `MARCH_BIN` to the
freshly built `bin/main.exe`, because the tests spawn the real compiler as a
subprocess to drive REPL/`--jit` sessions. `test_jit.ml`'s `march_bin ()`
falls back to `../bin/main.exe` (relative to dune's per-test sandbox cwd)
when `MARCH_BIN` is unset, which does not resolve when the exe is invoked
directly from the repo root the way `run-tests.sh` invokes every other
runner. When the binary doesn't resolve, the affected cases don't fail —
`check_session` calls `Alcotest.(check pass) "... (skipped: no main.exe)"`,
which alcotest reports as `[OK]` — so a naively-added entry would have looked
identically green whether or not the JIT cases actually ran.

## The fix

- Added `test_jit` to `scripts/run-tests.sh`'s `ALL_RUNNERS`.
- In the execution loop, `test_jit` gets a special-cased invocation that sets
  `HOME="$PWD/_build/jit_home"` (mirroring dune's own env) and
  `MARCH_BIN="$PWD/_build/default/bin/main.exe"` (the exe the script's own
  build phase already ensures is fresh), and `mkdir -p`s the HOME dir first.
- Documented the suite in the script's usage header and in `CLAUDE.md`'s
  "Suites:" line and direct-invocation examples.
- `-q` continues to work: the JIT/ORC/clang session cases are tagged `Slow`
  in `test_jit.ml`'s own `Alcotest.run` call (same mechanism as the other
  suites' Slow tests), so `run-tests.sh -q test_jit` skips them and only runs
  the two `Quick` cases.

## Non-vacuity evidence

- `scripts/run-tests.sh test_jit` → exit 0, "19 tests run", and the per-test
  output log (`_build/_tests/march_jit/jit.003.output`) shows a real REPL
  transcript (`val fib = <fn>`, `= 144`, …) rather than a skip message.
- Control: re-running `test/test_jit.exe` directly with `MARCH_BIN` pointed
  at a nonexistent path reproduces the vacuous-pass failure mode this fix
  avoids — same `[OK]` alcotest summary, but the per-test log reads
  `ASSERT orc fn-after-let-lambda (skipped: no main.exe)`. This confirms
  `run-tests.sh`'s correct-`MARCH_BIN` run is exercising the real subprocess
  path, not silently skipping like the naive case would.
- `scripts/run-tests.sh -q test_jit` → exit 0, "3 tests run" (16 Slow cases
  reported `[SKIP]` — alcotest's real Quick/Slow skip, distinct from the
  vacuous no-`MARCH_BIN` skip above).
