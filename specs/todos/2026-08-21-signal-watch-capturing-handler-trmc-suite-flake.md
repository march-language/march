# `Signal.watch: capturing handler survives repeated delivery (25x)` flakes on `trmc-suite` (ubuntu-24.04)

Filed while landing a test-only PR (#316, `test/native/qctor_collision`,
`boxed_adt_float_field`, `boxed_adt_atom_field_not_boxed` — zero `lib/`,
`runtime/`, or `bin/` diff against `main`).

## The flake

`test/test_codegen.ml`'s `test_signal_watch_capturing_handler_repeated_delivery_compiled`
(suite `try_call_capture_ownership_codegen`, case 9) compiles a program that
registers a capturing `Signal.watch` handler, raises the signal 3 times, and
runs the resulting binary 25 times, asserting each run prints `done`, exits
0, and never prints `RC underflow`. It failed on the `trmc-suite` CI job
(`MARCH_TRMC=1 ./scripts/run-tests.sh`, `ubuntu-24.04`) **twice in a row** on
PR #316's CI runs (`32494354229`, job re-run after the first failure) with:

```
Expected: `true'
Received: `false'
```

— i.e. one of the 25 iterations printed something other than the expected
`done`/`EXIT:0`/no-`RC underflow` combination. The assertion aborts the
`for` loop on first failure, so the log does not show which iteration or
what the actual captured output was; `Logs saved to
.../try_call_capture_ownership_codegen.009.output` was mentioned but not
retained past the job.

## Why this looks environment/timing, not code

- **Zero relevant diff.** PR #316 touches only `test/dune` (adds ~10 new
  native-golden dune rules) and new `test/native/*.march` fixtures + one
  progress doc — no `lib/`, `runtime/`, or `bin/` changes at all
  (`git diff origin/main..HEAD -- lib/ runtime/ bin/` is empty).
- **`main`'s own post-merge CI run of the SAME underlying fix (PR #315,
  which #316 stacks on) had `trmc-suite` pass** (run `32497549121`,
  conclusion `success`) — same signal-handling code, same runtime, no
  reproduction there.
- **18/18 local reproductions passed** on macOS (this repo's dev machine),
  including 10 runs under deliberately induced heavy CPU contention (6×
  `yes > /dev/null &` on a 14-core box) meant to simulate a loaded CI
  runner. `trmc-suite` itself runs on `ubuntu-24.04`, a different platform
  from what was tested locally, so this is not a full reproduction —
  Linux signal-delivery/scheduling timing can differ from macOS's.
- **The job's own header comment already documents a history of exactly
  this shape of problem**: `trmc-suite` was split out of `sanitize-gate`
  specifically because "failures were flaky/non-reproducible" when run
  alongside other resource-heavy steps on a shared runner, to isolate
  whether `MARCH_TRMC` itself was the cause. Splitting it out did not
  eliminate all timing sensitivity, just the ASAN-sweep-specific
  confounder.
- **A second, independently-filed flake** in the same area exists:
  `specs/todos/2026-08-20-signal-watch-output-ordering-flake.md`
  (`native_signal_watch`, a *different* fixture/dune-rule test, not this
  alcotest one) — measured at ~7% mismatch rate under load. Signal-delivery
  timing in this codebase is evidently marginal enough to be sensitive to
  ambient CI load, and PR #316 adding ~10 more native-compile dune rules to
  the same `dune runtest` invocation plausibly shifts scheduling enough to
  make a rare race more likely to land, without the underlying bug being
  new.

## Working hypothesis

`test_signal_watch_capturing_handler_repeated_delivery_compiled`'s own
comment claims "Confirmed deterministic (not flaky like `__try_call`'s
UAF)" — but that claim was evidently made/verified against SOME baseline
load level, not universally. Two back-to-back CI failures (vs. one CI pass
on `main` and 18/18 local passes) is stronger signal than pure noise, but
not strong enough alone to prove a real code defect over a marginal,
load-sensitive race (e.g. in the signal-delivery drain point relative to
when the 25-iteration loop launches/reaps the compiled subprocess).

**UPDATE (2026-08-21, later same day):** PR #317 (`fix(codegen):
typed_array_* must box a scalar entering its erased slot`, unrelated
`lib`/`runtime` code touching `typed_array_*` builtins, not signal
handling) merged with `trmc-suite` **passing cleanly**, including this
exact test. Tally is now 2 passes (main's post-merge run of #315, #317) vs
2 failures (both of #316's runs), across three different PRs touching
unrelated code. This is strong confirmation of genuine intermittent
flakiness rather than a defect in any of the PRs that happened to trip it —
closing the loop on the "is this real" question raised above. The
`## Suggested next step` below still applies to whoever picks this up; the
flake itself remains unfixed.

## Suggested next step

Same shape as the other Signal.watch flake's fix suggestion: either make
the test's timing assumption more robust (retry a failing iteration once
before failing the whole `for` loop, distinguishing "flaky under load" from
"broken"), or reduce the ambient load `trmc-suite` runs under so timing
margins widen back out. Reproduce on an actual `ubuntu-24.04` runner (or a
Docker container approximating one) under artificial load before attempting
any runtime-side fix — this repo has a documented history
(`project_prefix_control_before_attributing`,
`project_bench_load_contamination` in memory) of misattributing
load-induced timing noise to unrelated code changes.
