# `[P2]` Distributed deploys, build step 9: protocol evolution

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 6.4, II.5, D5, D21, D25.

**What.** Multi-fingerprint offers; the per-protocol
version-compatibility table and its first rule; a new hosting actor per fingerprint
for hosted access points (6.1); automatic expand/contract splitting of a compatible
change into two deploys for monoliths (D21), done by `forge deploy --plan`. (The drain
points of II.5.4, D27, landed separately:
[../progress/2026-09-24-dd-d27-session-drains.md](../progress/2026-09-24-dd-d27-session-drains.md).)

**Acceptance.** A protocol that adds a choice branch deploys hot across a two-node
cluster with sessions in flight on both fingerprints; `--plan` splits the same change
into two deploys when every node both chooses and receives.

## Status 2026-09-25

Items 1-6 of the step landed; see
[../progress/2026-09-25-dd-step09-protocol-evolution.md](../progress/2026-09-25-dd-step09-protocol-evolution.md).
The `--plan` half of the acceptance holds at the function level
(`Protocol_split.plan` splits a monolith's change into expand and contract; forge tests).
What is left:

1. **The network acceptance test.** `test/two_node_pending/protocol_evolve` is written
   and fails on a pre-existing hot-reload defect: a patch `.so` carries its own copy of
   the runtime, so the first session its code starts crashes the process
   ([2026-09-25-hcr-patch-so-private-runtime-copy.md](2026-09-25-hcr-patch-so-private-runtime-copy.md)).
   Once that is fixed, move it to `test/two_node/` and make it pass.
2. **`Topology.reoffer` after a real deploy** reopens a role through the `open` closure
   the old `main` built, which runs the old code (closures and entry-module functions are
   outside the reload boundary). It needs calls inside older closures to resolve by the
   unit's epoch (Model B, deferred in step 5), or roles built by reloadable code.
3. **Wire `Protocol_split.plan_project` into `forge deploy --plan`** when step 10b's
   classifier lands.
