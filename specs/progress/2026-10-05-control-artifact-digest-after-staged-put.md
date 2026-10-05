# two-node `control_artifact_digest`: substitute through the reload socket

**Date:** 2026-10-05

Two PRs landed on main within minutes of each other on 2026-10-04 and broke
two-node shard 2/2:

- #782 (dd12 P1) added `control_artifact_digest`. It played the attacker by
  sending `CAS_PUT` to a candidate's unauthenticated control API.
- #776 (control-API auth) made that same `CAS_PUT` accept only a hash that a
  release staged on the same connection names.

Each was green alone. Together, the scenario's first upload got
`ERR not_staged` in place of the `ERR digest_mismatch` it asserts. main's
run 37255861181 failed this way.

## Change

- `test/hcr_deploy.ml` gained `reload-put <socket> <hash> <file> [<blake3>]`.
  It sends the same `CAS_PUT` exchange, over a reload socket.
- The scenario now makes both of its substitution uploads through node a's
  reload socket. The reload socket has the same `so_blake3` check
  (`runtime/march_reload.c`), and after #776 it is the writer left to an
  attacker: a local user who can open the socket. The scenario also now
  asserts that the control API refuses an unstaged upload (`ERR not_staged`).
- The restart, replay and audit checks are unchanged.
