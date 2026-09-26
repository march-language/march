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

1. ~~**The network acceptance test.**~~ Done 2026-09-25 (#663): the patch `.so` no
   longer carries the runtime, `test/two_node/protocol_evolve` runs in CI and passes on
   macOS and Linux (under ASan too). Two things it needed beyond that fix: the
   `@[endpoints]`-generated modules stay off the boundary (a session finishes on the
   protocol code it formed under), and `SessionNode.initiate` looks again when the only
   offer answers "closing" (an offer being replaced by a re-offer) instead of reporting
   the role unfilled.
2. ~~**`Topology.reoffer` after a real deploy**~~ Done 2026-09-25 (#663): a call
   dispatches whenever its callee is reloadable, and the entry file's nested modules
   are on the boundary under `--hot-reload <EntryModule>`; the forge `live` upgrade
   fixture asserts a role body reached through the generated `main` gets the new
   version. Item 4's post-deploy re-offer is what `protocol_evolve` exercises.
3. **Wire `Protocol_split.plan_project` into `forge deploy --plan`** when step 10b's
   classifier lands.
