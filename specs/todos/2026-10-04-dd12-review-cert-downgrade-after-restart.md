# [P2] DD step 12b: after a restart, a compromised leader can replay an old cert-only release and roll a node's certificate back

**Review:** `specs/progress/2026-10-04-dd12-security-review.md`. PR #749/#676.

## What breaks

`docs/cluster-certificates.md` §4 says a release "older than one the node already
took certificates from" is refused, and a control-plane node "can only delay"
cert changes. Across a restart that guarantee is lost: a compromised leader
replays an earlier, genuinely-signed cert-only release and reinstalls the older
certificate — restoring roles/flags the operator had removed, or an
earlier-expiring cert (a timed DoS). The rollback is then written to
`MARCH_NODE_CERT` so it survives further restarts.

Root cause — the Agent's replay floor is `max(reload-server head, cert_floor)`
(`lib/desugar/control_wiring.march:353-356`):
- `cert_floor` lives in the in-process Vault `ctl_agent_memory`
  (`stdlib/control.march:1337`), so it is **lost on restart**.
- The reload-server head (`runtime/march_reload.c:1101-1110`) only advances on a
  signed `SEQ … ACTIVATE/TOPOLOGY/DRAIN` line, but forge's cert release carries
  `lines = []` (`forge/lib/cmd_cluster.ml:255`), so a cert-only release never
  moves it.
- `replace_checked` (`stdlib/cluster_node.march:2893-2900`) checks signature,
  expiry, node name, key and revocation — but has **no `not_after`/serial
  monotonicity**. Every older, still-unexpired cert for the same node+key passes
  (`--deliver` reuses one node key, `cmd_cluster.ml:170`).

## Attack, concretely

1. Operator delivers release S1 (cert X: broad roles) then S2 (cert Y: narrowed).
2. Node b restarts (crash, upgrade, or a process-backend deploy).
3. Compromised leader sends b a `do:certs` StepOrder carrying S1's stored,
   genuinely signed text. `order_release` (`control.march:1261-1263`) passes:
   S1's seq is above the (restart-reset) floor.
4. `apply_cert` → `replace_cert` accepts X; `ctl_persist_cert`
   (`control_wiring.march:348`) writes X over `MARCH_NODE_CERT`.

## Evidence

`specs/reviews/dd12/cert_downgrade_after_restart.march` — uses the real
`ClusterNode.start`/`replace_cert`; a fresh Vault models the restart. The
interpreter hangs in `ClusterNode.start`, so compile it:

    dune build --root . bin/main.exe
    ./_build/default/bin/main.exe --compile -o /tmp/r1bin specs/reviews/dd12/cert_downgrade_after_restart.march
    /tmp/r1bin

Output:

    release 2 (operator narrows b): ok=true certificate serial-Y-narrow in use
    after release 2: serial=serial-Y-narrow roles=Ctl.Agent:initiate flags=
    replay of release 1, same process: ok=false stale: release 1700000000001 is older than release 1700000000002, which this node has taken
    floor after restart: 1600000000000
    replay of release 1 after restart: ok=true certificate serial-X-broad in use
    after replay: serial=serial-X-broad roles=Ctl.Agent:initiate,Ctl.Control:offer flags=raw_send

The same-process replay is refused (floor works); the post-restart replay
succeeds and restores the broad `Ctl.Control:offer` + `raw_send`.

## Suggested fix (not applied)

Persist `cert_floor` durably (reload-server state dir, or make every cert release
carry a signed `SEQ` marker line so `g_release_seq` advances); and/or in
`replace_checked` refuse a cert whose `not_after` is earlier than the current one
for the same node+key unless the operator opts in; and/or derive the floor from
the installed cert. (Hand-revoking the old serial blocks it, but the docs frame
that as optional.)
