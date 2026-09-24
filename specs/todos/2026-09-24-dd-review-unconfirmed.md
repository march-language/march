# `[P2]` Distributed-deploys review: findings read from the code but not reproduced

Filed 2026-09-24 by the review of `12c062761..d3396f743`. Each item below was
read from the code only. None has a repro yet, so each needs one before it
gets its own todo. The confirmed findings have their own
`2026-09-24-dd-review-*.md` files.

## Step 6 (PR #612)

1. **ClusterNode's link reader tasks pin the startup epoch for the life of
   the link, and stamp every remote delivery with it.** `read_data`
   (`stdlib/cluster_node.march:1317-1342`) runs in a task spawned when the
   link forms (`:1125-1126`). Tasks never advance (II.4.3), and the route
   closures run in that task, so the local `send` they make stamps the mailbox
   node with the link's creation epoch (`march_sched_send_epoch`). After a
   deploy that changes an actor's message type, every remote message to that
   actor carries a stamp older than `msg_schema_epoch`, and goes through
   `migrate_msg` or is dropped, even when the sender already sends the new
   format. Separately, any long-lived link pins its epoch, so with the hard
   deadline off by default (deviation 5) the baseline versions are never
   reclaimable in a cluster process. II.4.5 does say "stamped with the epoch of
   the receiving node's route handler", so this may be intended. What is
   missing is a statement of the consequence, or a route handler that runs at
   the current epoch. Repro: a two-node hot-reload test sending a remote
   message across a message-type-changing deploy.
2. **The actor loop does not handle a NULL from `march_dispatch_enter_unit`.**
   `runtime/march_runtime.c:4345-4353` calls `fn_raw` unconditionally and
   then leaves `tbl_version`, which is 0 on the NULL path, so `refs` of ring 0
   would wrap. This existed before step 6 (`hcr_enter`). Step 6 adds a NULL
   return: `enter_gen`'s back-out when the version it picked was retired
   between the scan and the pin. By the reclaim condition a pinned unit's own
   version cannot be retired, so this should be unreachable today. A NULL
   check that falls back to `march_dispatch_enter` (and skips the leave) would
   make it hold without that argument.

## Step 3 (PR #610)

3. **The SIGTERM drain counts only offer sessions.** `running`
   (`stdlib/topology.march:399-411`) adds up the offer workers' `active`
   counts. Sessions a hook's task started with `initiate_R`, or a
   hand-written `cluster_R`, are not counted. A pool that serves no role exits
   0 at once on SIGTERM and cuts its in-flight sessions. The progress entry
   says it "exits 0 once no session runs", with no listed deviation. Fix:
   count initiated sessions too, for example with a per-node counter that
   `SessionNode.initiate` maintains.
4. **The loopback link outlives `ClusterNode.stop`.** `h_stop`
   (`stdlib/cluster_node.march:1619`) releases only real links. The loopback
   writer is never closed, `queue_for(h, own_id)` still returns `Some`, and
   `deliver_loopback` checks the creation but not `stopped`
   (`:1713-1736`). The sink closure stays in the global `node_queue_sinks`
   Vault (`stdlib/node_queue.march:347`, `:407`). Harmless in a process that
   exits. It leaks, and keeps local sessions running, in one that starts and
   stops nodes (tests, embedding).
5. **Placement changes leak actors.** `retire`
   (`stdlib/topology.march:373-377`) adds each retired offer to
   `st.draining` and never removes it, and the retired `OfferActor` (and an
   actor role's host) is never stopped. `offer_with`
   (`stdlib/session_node.march:2126-2138`) spawns the `OfferActor` before
   registering. On `AlreadyOffered` it leaves the actor alive, and
   `open_role` retries every tick, leaking one actor per tick until the old
   name is released.
