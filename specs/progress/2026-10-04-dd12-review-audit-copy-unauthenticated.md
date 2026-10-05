# [P2] DD step 12: AUDIT_COPY lets any unauthenticated peer forge audit-log entries

**Status:** Fixed 2026-10-04: `AUDIT_COPY` (and `RELEASE_COPY`) now require the cluster handshake.

**Review:** `specs/progress/2026-10-04-dd12-security-review.md`.

## What breaks

Design section 9: "the leader appends every release it accepts and every step it
orders to an audit log on the candidates. Nodes audit each applied release." The
audit log is the forensic record of what was deployed. The control API's
`AUDIT_COPY` verb — meant for the leader to copy its own audited lines to
standby candidates (`ctl_audit_copier`) — accepts the body from **any** TCP peer
with no authentication and appends it verbatim:

`lib/desugar/control_wiring.march:1245-1256`:

    "AUDIT_COPY" ->
      let size = arg(1)
      if size <= 0 || size > 1048576 do ctl_reply(fd, "ERR bad_size\n"); true
      else match tcp_recv_exact(fd, size) do
        Err(_) -> false
        Ok(b) -> ctl_audit_append(Bytes.to_string(b)); ctl_reply(fd, "OK\n"); true

No caller check, no cluster-secret, no signature. `ctl_audit_append`
(`:741`) just appends to `<control_dir>/audit.jsonl`, which the unauthenticated
`AUDIT` verb then serves back. An attacker can fabricate release/order/complete
records (wrong leader, wrong seq, "result":"ok" for things that never happened),
or bury real entries. The threat model (misbehaving member on the trusted
network) is exactly a peer that can reach the port.

## Attack, concretely

1. Reach a candidate's control port (binds `INADDR_ANY`, no auth —
   `ctl_api_accept`, `control_wiring.march:1309`).
2. `AUDIT_COPY <n>\n<n bytes of forged JSON>` → `OK`.
3. The forged line is now in that candidate's audit log and is returned by
   `AUDIT` / `forge deploy --env … --audit`.

## Evidence

`bash specs/reviews/dd12/repro.sh` (not run in CI). The network probe
(`specs/reviews/dd12/api_probe.py`) sends, from a plain TCP socket:

    AUDIT_COPY -> OK
    AUDIT contains forged line: True
    == audit log on disk (attacker-forged line) ==
    {"ts":0,"type":"release","leader":"ATTACKER","seq":999999,"result":"ok","why":"FORGED BY UNAUTH PEER"}

## Suggested fix (as filed)

Accept `AUDIT_COPY` only from an authenticated peer: require the
`MARCH_CLUSTER_SECRET` (as cluster frames do) or a leader signature on the copied
block, and/or restrict the verb to connections from known candidate addresses.
Audit entries should be integrity-protected end to end, not appendable by anyone
who can open the port. See also the resource-exhaustion todo (same verb, no total
size cap).

## Fix

`AUDIT_COPY` and `RELEASE_COPY` are candidate-only verbs: the server answers `AUTH`, both
ends run the cluster link's handshake on the API connection (`ClusterNode.handshake`), the
peer must hold the cluster secret or a certificate carrying `Ctl.Control:offer`, and a
sealed digest frame binds the body to the handshake. An unauthenticated peer gets `ERR
unauthenticated` and the candidate prints `control: refused an unauthenticated write`. The
audit log is also rotated past `MARCH_CONTROL_AUDIT_MAX_BYTES`. The full design, the
alternatives rejected and the tests are in the companion entry,
`2026-10-04-dd12-review-control-api-resource-exhaustion.md`.
