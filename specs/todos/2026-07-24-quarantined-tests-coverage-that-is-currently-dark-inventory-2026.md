> **Wiring fixed 2026-09-11** (`specs/progress/2026-09-11-quarantine-wiring-derived.md`):
> the nightly derives its alias list from the dune files and `check-docs.sh`
> Check E keeps this table's live rows equal to the defined `*_quarantined`
> aliases.
>
> **No test is quarantined as of 2026-09-28**: `signal_term_suppress` came back
> on `runtest` (`specs/progress/2026-09-28-signal-term-suppress-unquarantined.md`).
> This file stays in `specs/todos/` because it is the inventory Check E reads;
> file a new live row here whenever a test is quarantined again.

# Quarantined tests — coverage that is currently DARK (inventory, 2026-07-24)


**Read this before assuming a green CI run means the corresponding behavior works.**
As of 2026-09-28, **no** test is pulled out of `dune runtest` onto its own alias
(`node_discovery` came back on 2026-09-14 and `signal_term_suppress` on
2026-09-28; see their rows).
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
| ~~`test/node_discovery_quarantined`~~ | ~~SWIM node discovery / membership~~ | **RESOLVED 2026-09-14** — the torn-`println` race it was quarantined for was fixed on 2026-08-21 (`march_stdout_mu`, `specs/progress/2026-08-21-println-writev-not-atomic-across-threads.md`), after the quarantine; measured 60/60 clean locally by running the binary directly, and the ubuntu `test` job now soaks it 200× per run as the guard. Back on `runtest`. Original note: **RE-QUARANTINED 2026-08-08** — the ephemeral-port fix resolved the port collision, but node-a and node-b println CONCURRENTLY and ~1-in-2 ubuntu CI runs tears two lines together with a lost newline (`...peer=node-anode-a: handshake...` + a stray blank line), which the sort-before-diff golden cannot absorb. Same pre-write allocator/GC torn-output race as `signal_term_suppress` (a writev-retry fix was measured ineffective and reverted). Un-quarantine once that race is fixed. |
| ~~`test/rpc_auto_enroll_quarantined`~~ | ~~RPC auto-enrollment handshake~~ | **RESOLVED 2026-08-08** — same ephemeral-port fix. The macOS `result:15` vs `fail:call_error` mismatch was the fixed-port collision (a concurrent listener answering the connect), gone with ephemeral ports. Back on `runtest`. |
| ~~`test/signal_term_suppress_quarantined`~~ | ~~a watched `SIGTERM` must NOT kill the process~~ | **RESOLVED 2026-09-28** — the torn output was the `march_println` race fixed on 2026-08-21 (`march_stdout_mu`); the remaining reordering (`term handler` before `survived term`) is the documented asynchronous delivery, so the golden is now compared sorted. Soaked 2000 runs directly (up to 8 in parallel, host load 10-21): 0 torn lines, 0 non-zero exits. Back on `runtest`. See `specs/progress/2026-09-28-signal-term-suppress-unquarantined.md`. |
| ~~`forge/test/build_check_quarantined`~~ | ~~`forge build` end-to-end check~~ | **RESOLVED 2026-08-08** — made hermetic (tests the just-built compiler via `MARCH_TEST_BIN`) and the constructor-resolution bug fixed; back on `runtest`. See `specs/progress/2026-08-08-forge-check-build-suite-un-quarantined.md`. |

> **Design spec (2026-09-11):** `specs/2026-09-11-ci-tooling-fixes-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
