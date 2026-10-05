# [P2] DD step 12: unauthenticated control-API writes allow disk exhaustion

**Status:** Fixed 2026-10-04: write verbs authenticated or bound to a signed release, and bounded.

**Review:** `specs/progress/2026-10-04-dd12-security-review.md`.

## What breaks

The control-API listener (`lib/desugar/control_wiring.march:1309-1352`) binds
`INADDR_ANY` with no authentication and exposes write verbs that persist
attacker-controlled bytes to disk, with per-request caps but no aggregate bound
and no admission control:

- `CAS_PUT <hash> <size>` — up to `CAS_MAX_ARTIFACT` = 64 MB per call
  (`runtime/march_reload.c:225`, `:1979-2009`), keyed by an **arbitrary**
  client-declared hash. Each distinct hash is a new file; artifacts are never
  garbage-collected on this path. A peer loops over distinct hashes and fills the
  disk (and inodes).
- `AUDIT_COPY <size>` — up to 1 MB per call appended to `audit.jsonl`
  (`control_wiring.march:1245-1256`), no total-size cap, unauthenticated (see the
  companion AUDIT_COPY integrity todo). Repeated calls grow the file without
  bound.
- `RELEASE`/`RELEASE_COPY` bodies are capped at 1 MB each
  (`control_wiring.march:1289-1301`) but a peer can still spend a leader's CPU and
  replication effort by resubmitting; the leader verifies the signature so this
  is bounded by signature-check cost, not storage.

The threat model (parent plan section 3) is a misbehaving member on the trusted
network — a peer that can reach the port. Filling the disk stops all further
deploys, audit writes, state persistence and CAS staging on the victim node.

## Attack, concretely

1. Reach a candidate's control port (no auth).
2. Loop: `CAS_PUT <random-64-hex> 67108864\n<64 MB>` until the filesystem backing
   `~/.march/cas/artifacts` is full. (Or `AUDIT_COPY 1048576` in a loop against
   `audit.jsonl`.)

## Evidence

`bash specs/reviews/dd12/repro.sh` confirms an unauthenticated network `CAS_PUT`
is accepted and stored (`CAS_PUT verdict -> OK …`, `CAS_CHECK -> PRESENT`) and an
unauthenticated `AUDIT_COPY` is appended. The repro stores one object of each;
the exhaustion is the same call in a loop (not run to completion to avoid filling
the reviewer's disk — the accept-and-store is the load-bearing fact).

## Suggested fix (as filed)

Authenticate the control-API write verbs (`CAS_PUT`, `AUDIT_COPY`,
`RELEASE[_COPY]`) with the cluster secret or a peer-identity check, as the design
assumes network-level restriction that the in-threat-model attacker defeats. Bound
total CAS bytes and audit-log size per node, and admit `CAS_PUT` only for hashes a
pending signed release actually references (so bytes cannot be staged
speculatively). Fixing the CAS content-address binding (the P1 todo) is
independent and still required.

## Design (why this, and not the alternatives)

Three kinds of writer reach the control API, and each now proves what it is with
something it already holds; the control plane gains no key (D37).

- **Candidate to candidate** (`AUDIT_COPY`, `RELEASE_COPY`): the cluster link's own
  handshake, run on the API connection (`ClusterNode.handshake`, a new op over
  `NetKernel.handshake_auth`). The server answers `AUTH`, both ends handshake with the
  node's current identity and credentials (a replaced certificate and new revocations
  apply), and the peer must be a candidate: in certificate mode its certificate carries
  `Ctl.Control:offer` (`SessionAP.authorize`, as for the `Ctl.Control` offer itself); in
  shared-secret mode it holds the secret, which is that mode's whole trust boundary on the
  cluster links too. The connection must be sealed, and a sealed frame carrying the body's
  sha256 binds the plain body to the handshake. Moving these verbs onto the cluster link
  itself was rejected: a session payload over the link is what drove two nodes past 2 GB
  in 12a (artifacts and releases are why the API exists), and the handshake gives the same
  authentication on the existing connection with no new protocol.
- **forge** (`RELEASE`, `CAS_PUT`): forge holds no node credential and should not need
  one; it holds the deploy key. `RELEASE` was already signature-checked. An upload is now
  bound to a signed release: `STAGE <size>` + the release (deploy-key signature, `seq` not
  below the candidate's head) on a connection lets that connection `CAS_PUT` exactly the
  hashes the release names (`r.topology` and each build's patch). Nothing nobody signed for
  can be stored. The leader pushes artifacts to standbys the same way.
- **Forwarding** (`FORWARDED RELEASE/STATUS`) stays unauthenticated on purpose: the body is
  the same operator-signed release the leader verifies, and the marker only stops a second
  forward, so authenticating it would protect nothing a direct `RELEASE` does not already
  reach.
- **Reads** stay open (D4: not confidential; the port belongs on the operator's network).

Bounds: request line 64 KiB (unchanged), release/audit bodies 1 MiB checked before the
read, an artifact 64 MiB (the CAS limit) checked before `READY`; artifacts the API stored
that no stored release names yet are recorded (`<dir>/cas_pending`), capped in total
(`MARCH_CONTROL_CAS_PENDING_MAX_BYTES`, 1 GiB), adopted when a stored release names them,
and otherwise removed after `MARCH_CONTROL_CAS_GRACE_MS` (10 min) unless some service's
persisted patch stack (`<cas>/hcr_state/*/state`) names them. Only API-stored artifacts
are ever removed. The audit log rotates at `MARCH_CONTROL_AUDIT_MAX_BYTES` (16 MiB, one
old generation). At most `MARCH_CONTROL_MAX_CONNS` (64) connections at once, each closed
after `MARCH_CONTROL_IDLE_MS` (30 s) of silence.

Not covered here: the bytes of an artifact are still not checked against the signed
`cas_hash` (the P1, `2026-10-04-dd12-review-cas-artifact-unverified.md`, fixed separately
in the reload server and forge); artifacts named by old adopted releases are not removed
after compaction (the step-10b follow-up "CAS after compaction"); a compromised
*candidate* can still send large frames after authenticating, as it can over a cluster
link.

## Tests

`test/two_node/control_api_auth` (new): a normal hot release through the control plane
(the standby holds the copied release and audit lines, so the authenticated verbs work),
then `hcr_deploy probe` from a plain socket against each candidate: `AUDIT_COPY` refused
and the forged line absent from `AUDIT`, `RELEASE_COPY` refused, `CAS_PUT` with nothing
staged refused (`not_staged`), an unsigned `STAGE` refused, a hash the staged release does
not name refused, an artifact over 64 MiB and bodies over 1 MiB refused, a stale `STAGE`
refused, the quota enforced (`probe-quota`), the probe's unadopted upload collected while
the deployed patch stays, the connection cap (`ERR busy`) and idle close (`probe-conns`),
and the audit log rotated. Red on main (`a: an unauthenticated AUDIT_COPY was taken:
audit_copy: OK`, `audit_forged_present: true`), green after. `control_plane`,
`control_leader_kill`, `control_cert`, `control_certs`, `control_forge_deploy` pass
(`control_partition` needs iptables: CI).
