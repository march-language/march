# `[P1]` After nodes are restarted one by one, no initiator sees any offer ("no access point is registered")

**FIXED 2026-10-05** (`stdlib/cluster_node.march`, `retire_stale`).

## Cause

The first suspect was right, with one more step. A restarted node registers its offer
names again from an EMPTY replica, so the registration's clock (`next_clock` on an empty
replica: our slot at 1) is causally OLDER than the clock its peers hold for the same
name from its previous life, which a long-running node had bumped many times. The first
registry exchange merges, and the merge keeps the old binding (older creation, hidden by
`visible`). `retire_stale` then sees "our own binding from an earlier creation" and
tombstones it with a clock past the merged one -- erasing the name the node had just
registered again, on every node it pushes to. The node's `regs` still says it holds the
offer, so it never registers again; anti-entropy only spreads the tombstone. Hence
"no access point is registered" for good. A simultaneous restart of every node escaped
it: no peer kept the old binding.

## Fix

`retire_stale` re-registers a stale name this life holds again (it is in `regs`) at the
current creation, with the bumped clock, and pushes it, instead of tombstoning it. A
stale name nobody holds now is tombstoned as before.

## Test

`test/stdlib/test_cluster_node.march`, "a restart re-registers a name it holds again
rather than retiring it": the restarted node (creation 2) registers `ap`, then merges a
peer's sync carrying its creation-1 binding at a newer clock. `ap` stays visible at pid
42, creation 2, the change is pushed, and a peer holding the old binding sees the new
one after merging the push. Red before the fix (the name was gone).


Found 2026-10-05 by the multi-host lab (docs/lab.md), main at 53d66f068, four containers,
shared-secret mode, no control-plane leader
([2026-10-05-lab-topology-reread-closes-ctl-control.md](2026-10-05-lab-topology-reread-closes-ctl-control.md)).

State before: lab-1 (ingress, the initiator) and lab-4 (the Ledger) had been OOM-killed
minutes earlier ([2026-10-05-lab-simultaneous-restart-memory-burst.md](2026-10-05-lab-simultaneous-restart-memory-burst.md));
lab-2 and lab-3 were running. The lab then ran `systemctl restart` on each node in turn,
10 s apart: lab-1, lab-2, lab-3, lab-4.

From then on every session lab-1 initiated was refused:

```
refused 340
started 340
last_refused no access point is registered
```

for 3.5 minutes, and again after restarting lab-1 alone once more (11 of 11 refused).
Meanwhile:

- every work node's status file lists its offers open (`offer Order.Stock ... sessions
  0` on lab-2, lab-3, lab-4; `offer Order.Ledger ...` on lab-4);
- every node has established TCP connections to every other on the cluster port
  (`/proc/net/tcp`: two each, the control and data pair);
- nothing in any node's log but the usual `control: no session with a leader` lines.

So the members are linked but the initiator's registry replica holds no visible
`ap:Order/...` binding. Contrast: restarting all four nodes at the same moment (the same
lab, earlier) gave a cluster in which sessions finished within 15 s.

## Suspects

The registry rules for a restarted holder (stdlib/cluster_node.march header): a binding
whose holder "has restarted since (a stale creation) is hidden"; "the owner tombstones
its own stale-creation bindings when it learns of them"; a registration's clock is "the
name's current clock with our slot bumped". A restarted node registers its offer names
again from an empty replica; if the peers still hold the previous incarnation's binding
for the same name with a causally newer clock, the new registration could lose the merge
and stay hidden everywhere. The anti-entropy round (30 s) did not repair it in 3.5
minutes.

## Next step

Two nodes: B offers, A initiates; restart B (not A) and check `ClusterNode.lookup` on A
for B's offer name, and the registry entries both hold, before and after the 30 s
anti-entropy round.
