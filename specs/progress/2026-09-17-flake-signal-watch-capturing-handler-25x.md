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

## Closed 2026-11-11: the test now acknowledges every delivery

**What the test really did.** It sent no `kill`s. The 25 is the number of times the
test runs one compiled binary; inside it the program called `Signal.raise` three times
in a row and printed `done`. The test asserted `done`, exit 0 and no `RC underflow`.
It never counted deliveries.

**Why that was a race, measured.** A watched signal is one pending flag. The C signal handler
sets it and the scheduler drain claims it (`march_signal_drain`, `atomic_exchange`),
so raises that arrive before the drain runs collapse into one delivery. The old
program, 2000 runs on 2026-11-11 (macOS arm64, default scheduler count):

| Handler ran | Runs |
|---|---|
| once | 1800 |
| twice | 184 |
| three times | 16 |

Two consequences. The regression the test guards (a capturing watcher freed on
delivery one, a crash dispatching delivery two) needs a second delivery, so nine
runs in ten could not have caught it. And whenever a delivery was still pending or
running on another scheduler thread as `main` returned, the handler raced the
process's exit: how many deliveries happened, and whether one overlapped the
teardown, was decided by scheduling alone.

**The change** (`test/test_codegen.ml`,
`test_signal_watch_capturing_handler_repeated_delivery_compiled`). The watcher
counts its own runs in a Vault, after its `println`. `main` waits for that count
after each raise before sending the next, and before `done`. The test additionally
requires exactly three `caught 99` lines. The watcher still captures (`k`, and now
the Vault), which is the property under test. The retry-once and the full-output
failure message are unchanged.

**Why that removes the race.** Each raise now finds the pending flag clear, because
the previous delivery has finished: three raises are three deliveries, never fewer.
No delivery is pending or running when `main` returns, so nothing overlaps the exit.
The assertion on the count means the test cannot quietly go back to exercising one
delivery.

**Is the old race a runtime bug?** Coalescing is documented behaviour
(`Signal.raise`: delivery is asynchronous, from the next drain). A crash when a
process exits with a watcher mid-run would be one, and none was seen: all 2000 old
runs exited 0 with `done`, as did the 6000 of 2026-08-21 apart from one host
SIGKILL. The two CI failures (ubuntu-24.04, a job since removed) left no output, so
what they were is still unknown; the test's failure message has printed both
attempts' output since #322.

**Evidence** (macOS arm64, load average 25 to 60 from seven other sessions).
- The new program, 2000 runs: three deliveries, `done`, exit 0 in all 2000.
- The alcotest case (25 runs of the binary each), 50 times in a row: 50 passed.
- A Linux x86_64 run, where the two CI failures were, is left to this PR's CI.
