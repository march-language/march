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

## Resolution (2026-10-04)

Fixed with two independent guards. Either one alone refuses the review's attack.

1. **The node orders certificates by issue time** (`NodeCert.supersedes` /
   `order_problem`, checked in `ClusterNode.replace_checked` and in
   `core_peer_cert_update`). `forge cluster cert` writes serials as
   `<issued unix ms>-<32 random hex>`. A running node refuses a replacement
   issued before the certificate it holds. It also refuses one with no issue
   time (a pre-fix random serial) when the held certificate has one. This
   survives restarts with no new state, because the node starts on the
   certificate it last took (`ctl_persist_cert` writes it back to
   `MARCH_NODE_CERT`).
   - *Why the serial and not a new field or `not_after`:* the v1 body is a fixed
     8-element MessagePack array that every node decodes exactly, so a ninth
     field would make pre-fix nodes refuse new certificates mid-upgrade. The
     serial is a free-form signed string, so this changes no format in either
     direction. `not_after` monotonicity would forbid a legitimate re-issue
     that lives shorter. Ordering by issue time allows it (the native test's
     "release 3"). A deliberate rollback is a fresh issue with the old roles,
     or a restart on the old file (the order is only checked on a live
     replace).
2. **The Agent's cert-release floor is persisted** in
   `$MARCH_CONTROL_DIR/cert-floor-<node>` (`lib/desugar/control_wiring.march`:
   `ctl_load_cert_floor` at `ctl_start`, `ctl_persist_cert_floor` in
   `ctl_prefetch_loop`, temp+rename). It is written before the certificate
   file, so a crash between the two never leaves the certificate ahead of its
   floor. This covers what (1) cannot: a node whose certificate is not a file
   (a delivered certificate would not survive the restart, so the node comes
   back on an older one), and legacy unordered certificates. Revocation
   releases advance the floor too, so a replay of the release that delivered
   a since-revoked certificate is refused.
   - *Why not advance the reload server's head instead:* that needs a new
     signed line type in `runtime/march_reload.c` and in forge's release
     writer. A parallel session owns `march_reload.c` (the artifact P1). A
     floor file of the Agent's own gives the same restart guarantee with no
     change to the release format.

Tests (each shown red against `origin/main`'s sources, by file copy, then
green):
- `test/native/cert_downgrade_after_restart.march` (dune `runtest`): the
  review's compiled repro with forge-style serials. Main prints
  `replay of release 1 after restart: ok=true ... serial-X-broad`. Now it is
  refused, a shorter re-issue is taken, and a legacy serial is refused.
- `test/two_node/control_certs_restart`: X then Y delivered to c, c restarts
  (logs its loaded floor), X re-delivered halts on c ("was issued before"), and
  a normal rotation after the restart completes. On main it fails at the floor
  file. With those checks removed it fails with "c took back its superseded
  certificate X after a restart: release accepted".
- `test/stdlib/test_node_cert.march` "issue order"; `test_cluster_node.march`
  "a CERT_UPDATE carrying a certificate issued before the one held is refused".
