# Quarantined tests — coverage that is currently DARK (inventory, 2026-07-24)


**Read this before assuming a green CI run means the corresponding behavior works.**
As of 2026-08-08, **two** tests remain pulled out of `dune runtest` onto their own
aliases: `test/signal_term_suppress_quarantined` and `test/node_discovery_quarantined`.
The struck rows below were revived — `forge/test/build_check` (made hermetic) and two of
the three real-TCP node tests (`node_call_loopback`, `rpc_auto_enroll`, now binding
ephemeral ports). `node_discovery` was revived then RE-QUARANTINED the same day: the
ephemeral-port fix resolved its port collision, but it also prints from two green threads
concurrently and hits the same torn-output race as signal_term_suppress on Linux CI.
Both remaining are quarantined on a **genuinely unresolved concurrency race, not a test
bug** — the behavior each pins is unverified on every commit, and a regression there would
not turn CI red. Quarantining was a containment decision (they flaked CI), explicitly not
a fix.

| Alias | Pinned behavior now unverified | Blocked on |
|---|---|---|
| ~~`test/node_call_loopback_quarantined`~~ | ~~multi-node RPC over real TCP loopback~~ | **RESOLVED 2026-08-08** — took option (b): the tests now bind an OS-assigned ephemeral port (`tcp_listen(0)` + the new `tcp_local_port` builtin, read back in-process) instead of a fixed 29850/29851/29760, so shared-host collisions cannot happen. Soaked 10/10 clean each (0 hangs) under host load ~10. Back on `runtest`. |
| `test/node_discovery_quarantined` | SWIM node discovery / membership | **RE-QUARANTINED 2026-08-08** — the ephemeral-port fix resolved the port collision, but node-a and node-b println CONCURRENTLY and ~1-in-2 ubuntu CI runs tears two lines together with a lost newline (`...peer=node-anode-a: handshake...` + a stray blank line), which the sort-before-diff golden cannot absorb. Same pre-write allocator/GC torn-output race as `signal_term_suppress` (a writev-retry fix was measured ineffective and reverted). Un-quarantine once that race is fixed. |
| ~~`test/rpc_auto_enroll_quarantined`~~ | ~~RPC auto-enrollment handshake~~ | **RESOLVED 2026-08-08** — same ephemeral-port fix. The macOS `result:15` vs `fail:call_error` mismatch was the fixed-port collision (a concurrent listener answering the connect), gone with ephemeral ports. Back on `runtest`. |
| `test/signal_term_suppress_quarantined` | a watched `SIGTERM` must NOT kill the process | `Signal.watch` deferred-dispatch race (entry below) |
| ~~`forge/test/build_check_quarantined`~~ | ~~`forge build` end-to-end check~~ | **RESOLVED 2026-08-08** — made hermetic (tests the just-built compiler via `MARCH_TEST_BIN`) and the constructor-resolution bug fixed; back on `runtest`. See `specs/progress/2026-08-08-forge-check-build-suite-un-quarantined.md`. |
