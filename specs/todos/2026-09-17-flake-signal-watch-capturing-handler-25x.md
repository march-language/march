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
