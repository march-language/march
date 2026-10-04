# [P2] DD step 12: unauthenticated control-API writes allow disk exhaustion

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

## Suggested fix (not applied)

Authenticate the control-API write verbs (`CAS_PUT`, `AUDIT_COPY`,
`RELEASE[_COPY]`) with the cluster secret or a peer-identity check, as the design
assumes network-level restriction that the in-threat-model attacker defeats. Bound
total CAS bytes and audit-log size per node, and admit `CAS_PUT` only for hashes a
pending signed release actually references (so bytes cannot be staged
speculatively). Fixing the CAS content-address binding (the P1 todo) is
independent and still required.
