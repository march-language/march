# Quarantined tests — coverage that is currently DARK (inventory, 2026-07-24)


**Read this before assuming a green CI run means the corresponding behavior works.**
As of 2026-08-08, only **one** test remains pulled out of `dune runtest` onto its own
alias: `test/signal_term_suppress_quarantined`. The struck rows below were revived —
`forge/test/build_check` (made hermetic), and the three real-TCP node tests
(`node_call_loopback`, `node_discovery`, `rpc_auto_enroll`, now binding ephemeral ports).
The one remaining is quarantined on a **genuinely unresolved concurrency race, not a test
bug** — the behavior it pins is unverified on every commit, and a regression there would
not turn CI red. Quarantining was a containment decision (it flaked CI), explicitly not a
fix.

| Alias | Pinned behavior now unverified | Blocked on |
|---|---|---|
| ~~`test/node_call_loopback_quarantined`~~ | ~~multi-node RPC over real TCP loopback~~ | **RESOLVED 2026-08-08** — took option (b): the tests now bind an OS-assigned ephemeral port (`tcp_listen(0)` + the new `tcp_local_port` builtin, read back in-process) instead of a fixed 29850/29851/29760, so shared-host collisions cannot happen. Soaked 10/10 clean each (0 hangs) under host load ~10. Back on `runtest`. |
| ~~`test/node_discovery_quarantined`~~ | ~~SWIM node discovery / membership~~ | **RESOLVED 2026-08-08** — same ephemeral-port fix. Back on `runtest`. |
| ~~`test/rpc_auto_enroll_quarantined`~~ | ~~RPC auto-enrollment handshake~~ | **RESOLVED 2026-08-08** — same ephemeral-port fix. The macOS `result:15` vs `fail:call_error` mismatch was the fixed-port collision (a concurrent listener answering the connect), gone with ephemeral ports. Back on `runtest`. |
| `test/signal_term_suppress_quarantined` | a watched `SIGTERM` must NOT kill the process | `Signal.watch` deferred-dispatch race (entry below) |
| ~~`forge/test/build_check_quarantined`~~ | ~~`forge build` end-to-end check~~ | **RESOLVED 2026-08-08** — made hermetic (tests the just-built compiler via `MARCH_TEST_BIN`) and the constructor-resolution bug fixed; back on `runtest`. See `specs/progress/2026-08-08-forge-check-build-suite-un-quarantined.md`. |
