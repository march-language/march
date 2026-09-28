# Distributed deploys, step 12-pre: sequenced signed releases, signed topology apply

**DONE 2026-09-28.** Design:
[../plans/2026-09-28-dd-step12-control-plane-design.md](../plans/2026-09-28-dd-step12-control-plane-design.md),
sections 2.1, 2.2, 5 and 10 (D41: lands ahead of the rest of step 12). The rest of step
12 stays open in [../todos/2026-09-22-dd-step12-control-plane.md](../todos/2026-09-22-dd-step12-control-plane.md).

## The gap

No signed reload verb carried a nonce or sequence number, and the node never checked
that an epoch was fresh (`march_epoch_next` returns `max(requested, current+1)`). Anyone
who could reach a node's reload socket could replay a recorded signed `ACTIVATE` (rolling
a function back), `TOPOLOGY` or `DRAIN`. Separately, the signed `TOPOLOGY` verb's hook was
a no-op. Nodes applied the unsigned digest forge wrote over ssh, and a restarted node
came back on its compiled-in placement, not the one last pushed.

## What changed

**Runtime (`runtime/march_reload.c`).**
- **A wrapper verb,** `SEQ <seq> <id> <sig64> <signed line>`, signed over
  `SEQ <seq> <id> <signed line>`. It wraps any of `ACTIVATE*`, `TOPOLOGY` and `DRAIN`; the
  inner line's own signature is still checked.
- **The node's head** is kept in `<state_dir>/release`, a separate file so a stack set aside
  does not forget it. A higher `seq` is accepted, with gaps. The head again is a retry.
  The head's `seq` with another id is `ERR release_fork`, and a lower one is
  `ERR stale_release`.
- **Once a head exists,** or under `MARCH_HCR_REQUIRE_RELEASE=1`, an unwrapped signed verb
  is refused with `ERR release_required`. An unreadable head file refuses every signed
  line rather than reopening replays.
- **`RELEASE_HEAD`** answers `HEAD <seq> <id|-> [required]`.
- **Audit lines** are written for every release accepted or refused (`type` `release`) and
  for `DRAIN` (`type` `drain`), which was not audited before.
- **`march_hcr_on_topology`** raises SIGHUP after a push, but only when a watcher is
  installed; the default action would kill the process. It does nothing at start.
- **`march_reload_server_start`** sets `MARCH_TOPOLOGY_VERIFIED_FILE` to the verified copy.

**Stdlib (`stdlib/topology.march`).**
- `reload` reads the verified copy before `MARCH_TOPOLOGY_FILE`.
  `MARCH_HCR_REQUIRE_RELEASE=1` never reads the unsigned file.
- `place` applies the verified copy at start, so a restarted node comes back on the
  topology last pushed to it. Only the verified copy is read at start: a node that never
  received a signed push boots exactly as before.

**forge (`forge/lib/cmd_deploy_hot.ml`).**
- Every signed line (the ACTIVATE3–6 sends and `push_topology_conn`) goes through
  `as_release`. It asks `RELEASE_HEAD` once per connection. A server that doesn't know the
  request gets the line unwrapped, as before.
- One invocation is one release: a random 32-hex id, and
  `seq = max(now in ms, first head + 1)`.
- `describe_release_refusal` explains stale and fork refusals in words.

## Deviations from the design

Both are recorded in the design's section 5.
- **No per-node `parent` check.** A node a release did not touch would refuse every later
  release. Forks are caught as same number, different id.
- **forge numbers releases from the clock,** not a recorded head in `.forge/`, so operators
  share no state. The leader's compare-and-set replaces this in 12a.

## Tests

**`test/test_reload_activate4.c`, main mode** (`test_sequenced_releases`, run last because
it switches the server into sequenced mode):
- the head before any release;
- `DRAIN` audited;
- a release accepted and audited;
- an unwrapped replay refused once a release is held;
- a stale release and a fork refused, and the fork audited;
- a retry accepted;
- a signature over another number refused;
- a non-signed inner verb refused;
- a later release accepted with a gap;
- the stream staying in sync.

**Restore mode (phases 9–11):**
- `MARCH_HCR_REQUIRE_RELEASE` refuses unwrapped lines and reports `required`;
- a release push wakes an installed SIGHUP watcher exactly once, and
  `MARCH_TOPOLOGY_VERIFIED_FILE` names the verified copy;
- after a restart onto another build (the stack set aside), the head survives, and both an
  unwrapped replay and an older release are refused;
- a restart with a persisted topology and no watcher doesn't kill the process.

**Proven red:** with the stale-release check and the release-required check disabled,
10 main-mode checks and 5 restore-mode checks fail.

**forge unit test** `SEQ: a signed line wrapped in a release` checks the wrapper's wire
shape and signature, and the refusal descriptions.

## Left open

- The control plane itself (12a–12c): the step-12 todo.
- `hcr_deploy.exe`, the two-node suite's own deploy helper, sends unwrapped lines. That is
  fine while nothing in a scenario sends a release first; a scenario that mixes it with
  forge would need it wrapped.
- The ssh backend still writes the unsigned digest and sends SIGHUP after the signed push,
  for nodes built before this change. It can stop once no such nodes are expected.
