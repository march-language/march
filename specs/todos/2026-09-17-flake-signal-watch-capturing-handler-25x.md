# `[P3]` Flake: `Signal.watch: capturing handler survives repeated delivery (25x)`

Filed 2026-09-17 on one CI sighting during the #500 series (log not retained). The case
is `test/test_codegen.ml` (search the title); it compiles a program whose `Signal.watch`
handler captures a value and delivers the signal 25 times, expecting every delivery to
run the handler with the capture intact.

A 25-iteration signal test is timing-sensitive by construction: each delivery is a
`kill` of the running process from the test, and the runtime drains watched signals on
the scheduler loop (`march_signal_drain`). A signal that lands while the previous
delivery's drain is still running, or after the program has already exited, changes
the count. Which of these it was is unknown without the log.

**What to do.** Capture the failing output next time (the ZIP, not `--log`). If it is a
count shortfall, the fix is in the test (wait for each delivery's acknowledgement before
the next `kill`); if it is a crash, it is a runtime bug in the drain.

**Update 2026-09-30: the diagnostics half is already in place.** The test does not abort
blind. Since #322 (`880dd5cb2`, 2026-08-21, before this file was filed) each iteration runs
`<bin> 2>&1; echo EXIT:$?`, retries a failing iteration once, and on a second failure calls
`Alcotest.failf` with the iteration number and BOTH attempts' full captured output, which
includes the `EXIT:<n>` line (see the comment above
`test_signal_watch_capturing_handler_repeated_delivery_compiled` in `test/test_codegen.ml`).
The next sighting therefore prints what failed without any test change; grep the job log for
`iteration %d failed twice`. If the exit code there is 137 it is host-level SIGKILL pressure
(the only failure reproducible locally in 6000 runs, per
`specs/progress/2026-08-21-signal-watch-capturing-handler-trmc-suite-flake.md`), not this
test. The file stays open only until a sighting is diagnosed.
