# `[P2]` Distributed deploys, step 6 follow-ups: what the epoch model left open

**Parent:** [../progress/2026-09-23-dd-step06-epoch-model-and-drains.md](../progress/2026-09-23-dd-step06-epoch-model-and-drains.md)
("Deviations"), plan II.4.6-II.4.7, D27.

1. **`DELIVERY_FAILED` for a remote delivery the receive loop drops.** A remote
   delivery reaches the mailbox as a plain local send from a route closure in
   `stdlib/cluster_node.march` (`read_data` / `deliver_local`), so the actor loop
   cannot answer the sending node. Needs the delivery's `(connection, seq)` carried
   on the mailbox node (it is runtime-owned, like the epoch stamp) and a hook the
   loop calls on a drop.
2. **D27 session drains.** `march_hcr_epoch_draining(epoch)` exists in the runtime;
   `SessionNode` needs a builtin to read it and end sessions at loop boundaries
   (`recv_<Msg>_or_drain`, `loop atomic`, per plan 6.2).
3. **A party session whose held Endpoint is killed at a hard deadline** should end as
   `Left("draining")`, as a hosted one does; today it ends through the dead-endpoint
   paths.
4. **Tasks at a hard deadline** get `stop_requested` (ends a blocking receive), not a
   cancel through their handle; a computing task runs on.
5. **Step 3's loopback and `Topology.drain_on_signal`** should call `march_hcr_drain`
   (the reload server's `DRAIN`) once step 3 lands.

**Acceptance.** Each item has a test beside `test/test_hcr_migrate_order.c` or the
session suites, and the progress file's deviation list shrinks accordingly.
