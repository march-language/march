# `[P2]` Distributed deploys, build step 9: protocol evolution

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 6.4, II.5, D5, D21, D25.

**What.** Multi-fingerprint offers; drain points; the per-protocol
version-compatibility table and its first rule; a new hosting actor per fingerprint
for hosted access points (6.1); automatic expand/contract splitting of a compatible
change into two deploys for monoliths (D21), done by `forge deploy --plan`.

**Acceptance.** A protocol that adds a choice branch deploys hot across a two-node
cluster with sessions in flight on both fingerprints; `--plan` splits the same change
into two deploys when every node both chooses and receives.
