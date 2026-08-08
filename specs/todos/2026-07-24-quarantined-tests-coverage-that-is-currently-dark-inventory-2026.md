# Quarantined tests — coverage that is currently DARK (inventory, 2026-07-24)


**Read this before assuming a green CI run means the corresponding behavior works.**
As of 2026-08-08, **four** tests remain pulled out of `dune runtest` onto their own
aliases (`forge/test/build_check` is back on `runtest` — see the struck row below).
Each remaining one is quarantined on **genuinely unresolved concurrency races, not on
test bugs** — the
behavior each one pins is unverified on every commit, and a regression in that behavior
would not turn CI red. Quarantining was a containment decision (these hung or flaked CI,
in one case silently consuming the full 6h GitHub Actions job ceiling), explicitly not a
fix.

| Alias | Pinned behavior now unverified | Blocked on |
|---|---|---|
| `test/node_call_loopback_quarantined` | multi-node RPC over real TCP loopback | deadlock is FIXED, but local verification is blocked by shared-host port collisions: these tests bind FIXED ports (29850, ...) and this dev host runs several concurrent March sessions — found a 34-hour-old zombie `native_node_call_loopback` holding 29850 (causing "bind failed" + a stale-era server answering with "malformed hello"). Un-quarantine after either (a) a clean soak on an isolated host/CI, or (b) making the tests bind port 0 / a per-run port. |
| `test/node_discovery_quarantined` | SWIM node discovery / membership | same port-collision verification blocker |
| `test/rpc_auto_enroll_quarantined` | RPC auto-enrollment handshake | same (was quarantined preemptively; the deadlock it was quarantined against is now fixed) |
| `test/signal_term_suppress_quarantined` | a watched `SIGTERM` must NOT kill the process | `Signal.watch` deferred-dispatch race (entry below) |
| ~~`forge/test/build_check_quarantined`~~ | ~~`forge build` end-to-end check~~ | **RESOLVED 2026-08-08** — made hermetic (tests the just-built compiler via `MARCH_TEST_BIN`) and the constructor-resolution bug fixed; back on `runtest`. See `specs/progress/2026-08-08-forge-check-build-suite-un-quarantined.md`. |
