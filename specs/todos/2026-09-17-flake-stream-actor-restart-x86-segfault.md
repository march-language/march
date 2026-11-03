# `[P3]` Flake: `stream_actor_restart` segfaulted once on the x86 CI leg

Filed 2026-09-17 on one sighting during the #500 series (the ubuntu-24.04 `test` job;
the log was not retained -- the run was superseded by a rerun that passed). The fixture
(`test/session/stream_actor_restart.march`) kills an actor hosting a session endpoint
mid-session and replaces it, so the death path runs while the transport still holds the
continuation.

Most likely the same defect as [[2026-09-04-actor-monitor-down-reason-sigsegv-on-linux]]
(an intermittent SIGSEGV in the actor death path, Linux only, 60 000 local runs without
a reproduction): a second fixture crashing in the same path on the same leg is the
"next sighting will say where" that file asks for, except that this one's log is gone.

**What to do.** Nothing to bisect. Next time either fixture fails on Linux, download
the run's log ZIP (`gh api repos/.../actions/runs/<id>/logs`; `gh run view --log`
truncates) before rerunning, and attach the trace to the 09-04 file.

## 2026-10-12: did not reproduce under ASAN on Linux arm64

30 runs at `MARCH_NUM_SCHEDULERS=14` under `MARCH_SANITIZE=1
MARCH_DEBUG_RUNTIME=1` (`ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`), Docker
`march-ci-ubuntu-step6b` (arm64, glibc 2.39), concurrently with a 6-way ASAN
sweep for load: 0 failures, no sanitizer report. (It lives in test/session/,
so the test/native sanitizer sweep does not cover it.)
