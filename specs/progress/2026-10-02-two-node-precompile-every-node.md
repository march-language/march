# two-node: the first `start_node` compiles every node (cert_direct on CI)

**Date:** 2026-10-02

## Symptom

`two-node (2/2)` failed on main (8ee63159c, job 110873092020) and on many
unrelated PRs, always in `cert_direct`, the first scenario of shard 2:

```
-node-a: Pair closed / Pair got 21 / Ledger: ... not authorized for Ledger.B
+node-a: Pair: session_node: accept: no connection from role(s) 2 within 15000 ms
+node-a: Ledger: session_node: accept: no connection from role(s) 2 within 15000 ms
-node-b: Pair closed / Audit: ... not authorized for Audit.A
+node-b: Pair: session_node: connect to role A: connection failed: tcp_connect: Connection refused
```

It passed locally (macOS and an ubuntu-24.04 arm64 container, 3/3 each).

## Cause: node-b was compiled inside node-a's accept deadline

`start_node` compiled each node lazily, at the moment it started. The scenario
starts node-a, waits for `node-a: up`, and only then runs `start_node b`. So
node-b's compile happened while node-a was already inside
`SessionNode.accept_all`, with a deadline of MARCH_SESSION_CONNECT_MS = 15 s.
When that compile takes more than 15 s, node-a's Pair accept times out and
closes its listener. node-b then dials a port that nobody is listening on, and
its whole `dial_retry` window of refused connections lands on Pair and Audit.
That is the observed diff, phase for phase. The session code did not regress.

Why only on CI, and only since the sharding (abc1509f8): `cert_direct` is the
first scenario of shard 2 (the sorted list is dealt round-robin), so it now
compiles against a cold runner. Unsharded, it ran after a dozen other
scenarios had warmed the compiler's caches.

The same trap had already hit `setup_timeout` and `wrong_secret`, and each
was fixed by adding `compile a; compile b` to its own scenario.sh. 53
scenarios still compiled lazily.

## Fix

`scripts/two-node.sh`: the first `start_node` compiles every node of the
scenario (each `node_<x>.march` present) before starting any of them. This is
safe because:

- `compile` is once-only, so later calls are no-ops.
- Every scenario sets its `COMPILE_FLAGS_<x>` before its first `start_node`.
- No scenario rewrites a `node_<x>.march` after its first `start_node`.
- Every node file present is started by its scenario, so nothing extra is built.

These conditions were checked over all 71 scenarios. The binaries do not
change, only when they are built. The header's helper docs now say this.

## Verification

- RED control: a `MARCH_BIN` wrapper that sleeps 20 s before compiling
  `node_b.march` reproduces the exact CI diff in the ubuntu container on
  the unfixed harness.
- With the fix and the same wrapper: `two-node[cert_direct]: ok`.
- With the fix, in the container: `cert_direct` (x4), `cert_rotate` and
  `cluster_ap_retry` (three-node), `setup_timeout` and `wrong_secret`
  (explicit `compile`), and `protocol_mixed_local`, `hcr_new_code_session`
  and `protocol_evolve` (`COMPILE_FLAGS_<x>`) all passed. Only
  `protocol_expand_contract` failed, and it fails the same way on the
  unfixed harness (below).

## Not this: `protocol_expand_contract`

Its intermittent "the contract deploy to node-a failed" (job 110709588938,
branch `claude/nostalgic-lumiere-7fd591`) is a different failure. That
scenario already precompiles. Both nodes died with
`march: fatal SIGSEGV si_code=1 addr=0x62` just after their reload servers
came up, which is a crash, not a timing problem. It is tracked in
`specs/todos/2026-10-02-protocol-expand-contract-hcr-sigsegv.md`.
