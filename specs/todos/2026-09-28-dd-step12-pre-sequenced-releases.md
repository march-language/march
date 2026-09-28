# `[P1]` Distributed deploys, step 12-pre: sequenced signed releases, signed topology apply

**Design:** [../plans/2026-09-28-dd-step12-control-plane-design.md](../plans/2026-09-28-dd-step12-control-plane-design.md),
sections 2.1, 2.2, 5 and 10 (D41: lands ahead of the rest of step 12).

**Why.** No signed reload verb carries a nonce or sequence number, and the node does not
check that an epoch is fresh (`march_epoch_next` returns `max(requested, current+1)`,
runtime/march_dispatch.c). Anyone who can reach a node's reload socket can replay an old
signed `ACTIVATE` (rolling a function back), an old `TOPOLOGY`, or a `DRAIN` for any old
epoch. Separately, the signed `TOPOLOGY` verb's apply hook (`march_hcr_on_topology`) is a
no-op; the node applies an unsigned digest that forge writes over ssh and signals with
SIGHUP.

**What.**
1. Signed requests name a release: `seq` and `parent` are inside every signed message. The
   node persists the highest applied `seq` (and its digest) in the hcr state file and
   refuses a lower `seq`, or a new `seq` whose `parent` is not the release it holds (a
   fork: reported, nothing changed). Re-applying the same `seq` is a no-op. Replay at boot
   applies the same rule.
2. forge allocates `seq`/`parent` from the environment's recorded head
   (`.forge/deploy/<env>/`) and signs them in.
3. A node started with `MARCH_HCR_REQUIRE_RELEASE=1` refuses the old unsequenced verbs.
4. `march_hcr_on_topology` applies the verified topology (through `Topology.reload`), so
   the signed path is the one that takes effect; in `REQUIRE_RELEASE` mode the unsigned
   SIGHUP digest is ignored.
5. `DRAIN` writes an audit line.

**Acceptance.**
- Replaying any recorded signed line after a newer release is refused, also after a restart.
- Two releases with the same `seq` and different content: the second is refused and reported.
- In `REQUIRE_RELEASE` mode a topology changed on disk without a signature is never applied.
- The existing C HCR harness, `forge test --upgrade-from` fixtures and two-node hot-deploy
  scenarios pass unchanged on the ssh path.
