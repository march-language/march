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

**Forge side landed in step 10b** (2026-09-25): `forge deploy --plan` detects a choice
that gained one branch (from forge's structure of the declarations, `Deploy_plan`),
orders receivers' pools before the chooser's, and splits the change into two deploys
when one build both chooses and receives it; `forge deploy` runs deploy one and does
deploy two when run again. Still this step's: the compatibility table over wire tags
(the finer rule) and everything on the node side.
