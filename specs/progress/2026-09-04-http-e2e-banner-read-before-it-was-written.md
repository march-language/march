# The compiled HTTP e2e test read the server's banner before it was written

**Status:** filed and **fixed 2026-09-04.** Pre-existing; the window is
unconditional, not load-dependent.

## The failure

`test (ubuntu-24.04)` on main run
[33916841033](https://github.com/march-language/march/actions/runs/33916841033)
(`3cc33fb8`):

```
[FAIL] http server (compiled, end-to-end)  0  thread-pool s...
ASSERT [compiled HTTP server: thread pool (default)] asked for the THREAD POOL
but the server did not announce it — the runtime implementation selector
(march_http_evloop_enabled) is broken, and both variants of this suite are
testing one server
server process: still running
--- server stdout/stderr (.../srv.log) ---
```

Note what follows that last line: **nothing.** The server log was empty.

## The race

`test/test_http_native.ml` waits for readiness by *connecting* to the port, and
then reads the log once to confirm which server announced itself.

A successful connect does not imply the banner exists. On the thread-pool path
the serve routine binds and `listen()`s, and only afterwards calls
`march_http_pool_start_max` (`runtime/march_http.c:2314`), which is what prints
`march: HTTP thread pool started` (`runtime/march_http.c:2188`). A client can
therefore complete a TCP handshake out of the **listen backlog** strictly
before the banner is written. The readiness poll returns, the single
`read_log ()` samples an empty file, and the assertion fails.

The window is unconditional — it does not require an overloaded runner, only
that the connect land in the gap between `listen` and `pool_start`. A slow
runner widens it, which is presumably why it surfaced on the Linux leg.

## The trap in the diagnostic

The failure message accuses `march_http_evloop_enabled` of being broken. It was
not. The distinction is in the log contents and nothing else:

- log **empty** → the banner has not been written yet. Timing.
- log carries the **other variant's** banner → the selector really did
  regress, both arms are testing one server, and this suite's whole point has
  evaporated into vacuous green.

The old code could not tell those apart, and the message it chose was the
alarming one. That reading is now stated in the source next to the fix.

## The fix

Wait for the expected banner (30s deadline) instead of sampling the log once.
This does not weaken the assertion:

- a log carrying the wrong banner still fails immediately, since the loop is
  looking for the *expected* string and the mismatch is checked after;
- a genuinely broken selector still fails, after the deadline;
- only "correct banner, not yet flushed" changes outcome, which is the bug.

## Verification

| run | result |
|---|---|
| both e2e cases (`thread-pool`, `event-loop`) after the fix | **PASS**, full `run_stdlib` green at 878 tests |
| **RED control**: force `MARCH_HTTP_EVLOOP=1` for *both* variants, i.e. exactly the selector regression this assertion guards | **FAIL**, `asked for the THREAD POOL but the server did not announce it` — and the event-loop arm still passes, as it should |

The RED control is the one that matters. A "fix" to a flaky assertion that also
stops catching the real defect is worse than the flake; this one still catches
it.

## Context

Third distinct failure on main's Linux leg in one afternoon, after
`test_pinned_park_wake`
(`specs/progress/2026-09-04-pinned-park-wake-resume-count-flake.md`) and a
single unreproduced `native_actor_monitor_down_reason` SIGSEGV
(`specs/todos/2026-09-04-actor-monitor-down-reason-sigsegv-on-linux.md`). All
three are timing-sensitive tests rather than one common defect, but three in an
afternoon is itself worth noticing.
