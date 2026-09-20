# Choreography access points, phase A1: offer and initiate

Shipped 2026-09-20. Part A, phase 1 of
[[2026-09-19-choreography-access-points-and-crash-branches-design]], which is phase 4 of
[[2026-09-18-choreography-failure-handling]]. The design's part B (crash branches) and
phase A2 (hosted offers) are not in this.

## What it adds

- `SessionNode.offer_role` / generated `<P>_Run.offer_<Role>(io, node, capacity, body)`:
  this node plays the role for up to `capacity` sessions at once, each run in its own
  task. Registered as `"ap:<P>/<role>/<node_id>"`, one per role per node.
- `SessionNode.initiate` / generated `<P>_Run.initiate_<Role>(io, node, body)`: mints a
  fresh session id (`<node_id>.<creation>.<counter>`) and fills every other role from the
  offers, each on a different node, then runs the session as `run_cluster` does.
- `<P>_Msg.fingerprint()`: a digest of the protocol's roles and steps, sent with the
  invitation. An offer built from a different version of the protocol refuses.
- `<P>_Msg.others_<R>()`: every role but R (an initiator fills all of them, not only its
  peers).
- `RunError.NoOffer(role, why)`, where `why` lists what each offer said, by node name.
- `ClusterNode.creation` / `global_pid`, for the session id and the reply address.

Wire, over the cluster node, routed by the offer's / the initiator's inbox pid:

```
SessionAP.Invite    [sid, fingerprint, reply pid]   initiator -> offer
SessionAP.Withdraw  [sid]                           initiator -> offer
SessionAP.Answer    [sid, node_id, verdict]         offer -> initiator   ("" accepts)
```

An offer answers in its actor's turn, so its count of running sessions is exact. A
session it accepts starts at once and can be abandoned while still finding its peers
(`run_cluster_with`), which is what `Withdraw` does.

## What the tests found

- **A candidate must be a node this one is connected to.** The registry shows a name
  learnt through a third node before the two have a connection, and the invitation's
  `send_msg` then fails; the initiator waited out the whole 20 s setup time for an answer
  that could not come. Candidates are filtered by `queue_for`, and a failed send counts
  as a refusal at once.
- **Every refusal is reported**, by node name, not just the last one: debugging the above
  was confused by a `NoOffer` that named one hashed node id and nothing else.
- **A marker printed after `offer_<Role>` returns can print after the first session.**
  The offer is live as soon as it registers. Three scenarios printed "offering" after the
  call and raced their own sessions; they print before it now.

- **A mutually recursive pair is miscompiled.** `invite_role` / `answer_or_next`
  were written as a pair; the ASAN gate caught a use-after-free on the accumulated
  `why` string inside their flattened loop, and it reproduces without the sanitizer as
  a wrong value. The invite loop is ONE self-recursive function until that is fixed:
  [[2026-09-20-mutual-tco-borrowed-forwarded-arg]].

## Tests

- `test/two_node/cluster_ap`: one offer, two sessions in a row, distinct session ids.
- `test/two_node/cluster_ap_retry` (three nodes): node-c offers the same role from a
  DIFFERENT version of the protocol, so its fingerprint differs. Four sessions in a row
  all land on node-a (the rotation makes some try node-c first and be refused), then two
  held sessions fill node-a's capacity and a third attempt fails `NoOffer`.
- `test/two_node/cluster_ap_restart`: node-b is killed and started again with a new
  creation; node-a's next session finds the new offer. Local restart, no coordination.
- `test/two_node/cluster_ap_withdraw` (three nodes, Ring): node-b offers B with capacity
  1 and node-c starts late, so node-a's first attempt fills B, finds no C and withdraws.
  The next attempt (retrying 20 s, less than the 30 s an abandoned session waits for its
  peers) must fill B again. With `withdraw_all` made a no-op it fails.

## Not in this phase

- **A2, hosted offers**: an actor hosting many sessions, one `Parked_<Role>` per session
  id in a `LinearMap` ([[2026-09-18-linear-map]]). Needs a hosted `run_cluster`, which
  does not exist yet.
- Choosing an offer by load (the rotation ignores how busy an offer is), and an offer's
  capacity counted across a restart.
