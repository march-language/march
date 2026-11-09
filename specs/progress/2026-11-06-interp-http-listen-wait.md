# Interpreted HTTP server tests: wait for startup, not for 5 seconds

**Problem.** Two `run_stdlib` adversarial-regressions cases failed with "interpreted HTTP
server never started listening" in most CI runs on 2026-11-06, in the `test (ubuntu-24.04,
rest)` shard (case 61, `test_interp_http_server_idle_client_does_not_block_others`, and
case 62, `..._idle_websocket_does_not_block_others`). Every PR's run went red and needed a
rerun.

**Cause.** Both tests start `main.exe srv.march` (the interpreter) and then poll the port
50 times, 0.1 s apart: about 5 s in all. The interpreter loads and typechecks the stdlib
before it binds, so the poll was timing interpreter startup, which these tests do not
measure. Measured on a 14-core M-series Mac with a cold `HOME`:

| Load | Time to listen |
|---|---|
| idle | 2.1 s |
| 2× oversubscribed | 4.6–4.8 s |
| 3× oversubscribed | 9.0–9.4 s |

CI's `rest` shard runs `run_stdlib` next to the fixture compiles and other suites on 4
vCPUs, so it lands past 5 s. At 3× load, main's tests failed in all 3 runs with exactly CI's
message.

**Fix.** Both tests now call one helper, `wait_for_interp_listen`. It polls against a
60-second wall-clock deadline, not an attempt count. If the child exits before it listens
(a typecheck error, or a port already in use), the test fails at once and prints the
child's log; the old loop waited out its budget with no detail. At 3× load the fixed tests
passed in all 3 runs (11.5–12.8 s each).
