# `[P2]` ClusterNode link reader tasks pin the startup epoch and stamp remote deliveries with it

**Filed** 2026-09-25 from the distributed-deploys review's unconfirmed item 1
(`2026-09-24-dd-review-unconfirmed.md`, now triaged and deleted).

**What.** `read_data` (stdlib/cluster_node.march) runs in a task spawned when a link
forms. Tasks never advance (II.4.3), so the task holds the link's creation epoch for
the life of the link, and the local `send` its route closures make stamps every
remote delivery with that epoch (`march_sched_send_epoch`). After a deploy that
changes an actor's message type, remote messages to that actor carry a stamp older
than `msg_schema_epoch` and go through `migrate_msg` or are dropped, even when the
remote sender already sends the new format. And any long-lived link pins its epoch,
so with the hard drain deadline off by default the baseline version is never
reclaimable in a cluster process.

**Evidence so far.** Confirmed in part: in `forge test --upgrade-from` on
`forge/test/fixtures/upgrade/migrates`, 20 s after the deploy PINS still reported
`epoch 1 (6 unit(s)) still pinned by units that are not actors (tasks)`, while a
plain program with no ClusterNode drains to zero (see
`2026-09-25-name-units-pinning-old-epoch.md`). Which six tasks is not yet known, and
the stamping consequence has no repro.

**Repro to write.** A two-node hot-reload test that sends a remote message across a
message-type-changing deploy, from a sender already on the new format; assert it is
delivered, not converted or dropped. Then either run route handlers at the current
epoch or document the consequence in II.4.5.
