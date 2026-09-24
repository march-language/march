**CLOSED 2026-09-23 by build step 6** (`specs/progress/2026-09-23-dd-step06-epoch-model-and-drains.md`):
the marker is now a mailbox-node flag that bypasses every overflow policy, so a
`DROP_NEW` actor whose mailbox is full at deploy time handles its pre-deploy
messages on the old version, then migrates (`test/test_hcr_migrate_order.c`,
"DROP_NEW actor whose mailbox is full at deploy time"; RED when the marker is
made to obey the policy). `hcr_marker_lost` survives as `hcr_lost_epoch`, reachable
only when malloc fails; the test asserts it never fired.

# `[P2]` The four HCR migration bugs from the distributed-deploys plan: status, and the one gap left

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
"Bugs found while designing", and build step 1. Groundwork item G8 was a message to
the session fixing them; that session has ended, so this file records what landed.

**Checked 2026-09-22 against main (70af5b0dc):**

| Bug (parent plan) | Status | Where |
|---|---|---|
| Queued messages run new code on old state | Fixed | #564 (`6579b97ad`): per-actor `hcr_pin`, pinned before publish; queued messages run on the old version until the actor reaches its marker; drain deadline (`MARCH_HCR_DRAIN_MS`, default 5000 ms) drops and reports what is left. `test/test_hcr_migrate_order.c`. |
| Actors beyond 2048 never migrated | Fixed | #564: `hcr_snapshot` grows on the heap, no cap; 2100-actor case in the same test. |
| A full mailbox drops the migrate message | Fixed differently | #564: a lost marker (`DROP_NEW`, `DROP_OLD` eviction, nested `receive()`, failed malloc) sets `hcr_marker_lost`, and the actor migrates at its next message boundary. The marker still goes through the overflow policy. |
| `publish_epoch` stores the epoch after `live = 1` | Fixed | #551 (`fb4192890`): the epoch is stamped before the publication store (`runtime/march_dispatch.c`, `publish_impl`). |

So all four are addressed on main. #564's progress entry
(`specs/progress/2026-09-21-hcr-migrate-order-and-snapshot-cap.md`) names only the
first two; the third is covered by its lost-marker handling and the fourth by #551.

**The gap left (bug 3).** When the marker is lost, the actor migrates at its next
message boundary, so the messages still queued from before the deploy run on the NEW
code (against the migrated state, so no layout mismatch). D10 says they run on the old
code. The parent's II.4.6 closes this by making the marker a `march_mbox_node` flag
that bypasses overflow policies. That belongs to build step 6
(`specs/progress/2026-09-23-dd-step06-epoch-model-and-drains.md`), not a separate patch.

**Acceptance.** In step 6: a `DROP_NEW` actor whose mailbox is full at deploy time
handles its pre-deploy messages on the old version, then migrates; the test beside
`test_hcr_migrate_order.c`'s cases.
