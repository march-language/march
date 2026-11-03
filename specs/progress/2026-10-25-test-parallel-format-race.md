# Test harness: `parallel_cases` bodies raced on alcotest's shared Format formatter

CI flake: `test (macos-15, all)` on PR #1025 (run 40142534056, job 121017084702) failed
run_stdlib `adversarial-regressions` case 33 ("FBIP same_arity: dead 1-field cell NOT reused
for 5-field ctor, parity (compiled)") with

```
[invalid] Format: Unsynchronized access to formatter
  Raised at Test_helpers.parallel_cases.(fun) in file "test/test_helpers.ml", line 689
```

Branch `claude/test-format-race`. Test-only change; no compiler code and no user-visible
behaviour changed, so no CHANGELOG entry.

## Cause

Not the compiler. The case's body is subprocess-only (runs `main.exe`, compiles, runs the
binary). The formatter it raced on is **alcotest's**: every `Alcotest.check`, `check'`,
`fail`, `failf`, `check_raises` and `match_raises` with a non-empty message calls
`show_assert` (alcotest 1.9.1, `src/alcotest-engine/test.ml:164-171`), which flushes
`Formatters.get_stdout ()` and `Format.fprintf`s an `ASSERT <msg>` line to
`Formatters.get_stderr ()`. Those are one `Format.formatter` each, held in a global ref
(`formatters.ml`). `Test_helpers.parallel_cases` (via `parallel_map`) runs the `Slow` bodies of
`adversarial-regressions` on up to `test_jobs ()` domains, so several bodies asserting at once
drive the same formatter's pretty-printing queue concurrently. OCaml 5.5.1's `Format`
detects a torn queue in `advance_left` (`format.ml:450`) and raises
`Invalid_argument "Format: Unsynchronized access to formatter"` out of whichever body lost
the race; `parallel_cases` stores it and line 689 re-raises it as that case's outcome. On
5.3 (the local default switch) the same race shows as interleaved/garbled ASSERT lines and,
under pressure, `Stdlib.Queue.Empty`.

The harness rule in `parallel_map`'s doc ("no in-process compiler pipeline") never mentioned
alcotest's own printing, and every batched body asserts.

## Fix

`test/test_helpers.ml`: a `module Alcotest = struct include Alcotest ... end` shadow, next to
the existing `Sys` shadow, so every file that opens `Test_helpers` (all `parallel_cases` /
`parallel_slow` / `parallel_map` users whose workers assert) gets it. Its printing assertions
take one process-wide `Mutex` around the real call:

- `check` / `check'` / `fail` / `failf`: the whole real call under the lock (it runs no user
  code but the testable's `equal`).
- `check_raises` / `match_raises`: the thunk and the predicate run *outside* the lock; the
  outcome is replayed through the real function under it, so a thunk that asserts cannot
  deadlock and slow thunks do not serialise.
- `check` / `check'` pass the caller's location as `~here`. Without it the real `check`'s
  callsite guess (`callsite_loc.ml`, stack frame 2) names the shadow in `test_helpers.ml`.

`parallel_map` / `parallel_cases` gain `?jobs` (default `test_jobs ()`) so the regression
test can force several domains regardless of `MARCH_TEST_JOBS`; `parallel_map`'s doc now
lists shared formatters among the things a body must not touch.

## Regression test

run_stdlib group `test-harness` (`test/test_stdlib_suite.ml`):

- "parallel_cases: bodies assert concurrently without a Format race": 4 rounds of
  `parallel_cases ~jobs:8` over 8 bodies, each looping 250× through `check`, `check'`,
  `check_raises` and `match_raises`.
- "parallel_cases: a failing body keeps its message and caller location": one of 4 batched
  bodies fails a `check`; its re-raised error carries the message and names
  `test_stdlib_suite.ml`, not the shadow.

## Reproduction evidence

- Stress test with the shadow disabled (module renamed), OCaml 5.5.1 (`march55` switch):
  **10/10 runs fail**, `[invalid] Format: Unsynchronized access to formatter`, the CI error.
- Same, OCaml 5.3.0 (default `march` switch): **10/10 runs fail**, garbled ASSERT output and
  `[exception] Stdlib.Queue.Empty`.
- With the fix, 5.5.1: 20/20 runs pass.
- The real group (`run_stdlib.exe test adversarial-regressions`), pre-fix, 5.5.1,
  `MARCH_TEST_JOBS=4`: 0/10 runs failed (~120 s each). The natural flake does **not**
  reproduce on this machine; the stress test is the reproducer, and the cause is the code path
  above (CI's 5.5.1 error string is the one Format raises there and nowhere else).
- The real group, post-fix, 5.5.1, `MARCH_TEST_JOBS=4`: 0/20 runs failed.
- Full `scripts/run-tests.sh` post-fix (5.3.0): all 13 suites passed (run_stdlib 1453 tests).

## Rulings

Ruling: lock in a test-side `Alcotest` shadow rather than mark the cases serial or swap
alcotest's formatters — alcotest reads one global formatter ref on every assertion, so no
per-domain formatter can be installed from outside, and serialising the batch would undo
the 2026-10-07 CI-audit speedup — cost if wrong: a test file that runs `parallel_*` bodies
without `open Test_helpers` (or calls `Stdlib`-qualified alcotest) is still racy; today
every such file opens it.

Ruling: the ASSERT lines a batch prints still land in whichever case log is active when the
batch runs (the documented `parallel_cases` cost); the lock only makes them whole — fixing
attribution would need per-case capture inside alcotest — cost if wrong: a reader of a batched
case's log sees other cases' ASSERT lines, as before.
