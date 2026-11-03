# `[P1]` Nodes restarted together can each allocate ~1 GB of heap in 30 s and be OOM-killed

**FIXED 2026-10-05 by #808** (cedee2fae, `lib/tir/drop.ml`: a dying value of a colliding
short-named type is dropped deeply,
[2026-10-05-colliding-type-shallow-drop.md](2026-10-05-colliding-type-shallow-drop.md)).
Confirmed and pinned with a regression scenario 2026-10-12.

## Cause

Not a retry storm, a queue or replayed state: a leak per cluster message. Every frame a
node decodes is a `Msgpack.Value`, whose short name `Value` collides with
`Config.Value` and `DataFrame.Value`; `drop.ml` freed such a cell shallowly, so a `Bin`
payload's byte list (one heap object per byte) was orphaned on every message. Nodes
that start together exchange the most cluster traffic (registry and membership syncs
between new incarnations, the `count = 1` roles settling, sessions refused and retried
while they do), so the leak showed there first, at 300k-600k objects a second and
speeding up as it went. It is not the
leaderless per-tick leak
([2026-10-05-lab-leaderless-agents-leak.md](../todos/2026-10-05-lab-leaderless-agents-leak.md)):
the burst came back with a leader present (cedee2fae reverted alone), and does not
come back on main without one (the `Ctl.Control` pin reverted).

## Evidence (2026-10-12, the lab, 4 hosts capped at 1.2 GB, shared secret)

`forge deploy` (which starts every node at once), then every node restarted at once
with one session a second (`lab_traffic 1000 4`), `live_allocs()` per node:

| Build | after the deploy | 30 s after the restart | OOM-killed |
|---|---|---|---|
| 53d66f068 (the finding's) | 15-21 M (3 of 4 killed) | 1.4-2.2 M, 19 M by 70 s | yes, 3 of 4 |
| 78c124921 (#785 merged) | 16-21 M (3 of 4 killed) | 1.3-2.2 M, 20 M by 80 s | yes |
| 33527ba9e (#808's parent) | 20-21 M (2 of 4 killed) | 1.1-3.9 M, 16 M by 82 s | yes |
| 3926df302 (#808 merged) | 28k-45k | 130k-415k | no |
| 3926df302 with cedee2fae reverted | 6.6-8.8 M | 0.8-2.9 M, 4 M by 80 s | (heading there) |
| main 0c50b9a4c | 0.7-2.0 M (7 min of traffic) | 45k-155k | no |
| main with the `Ctl.Control` pin reverted (leaderless) | 0.7-2.0 M | 49k-154k | no |

With traffic paused, the old builds did not burst on a restart in this run (the
finding's paused restart did; its nodes had more history), and main does not either
(42k-264k after 60 s).

## Test

`test/two_node/control_restart_together`: the lab's app (examples/lab_app) on three
nodes, an ingress and two `control,books` work nodes, all started at once with one
session a second; then all stopped (SIGTERM) and started at once again on the state the
first run left. In each run, for 30 s after sessions flow, no node's `live_allocs()` may
pass 400,000 objects (a node past 1.5 GB RSS fails it at once). Main peaks at 37k-106k;
3926df302 with cedee2fae reverted fails at 19 s (402,670 objects, rising ~25k/s).

## The original finding

Found 2026-10-05 by the multi-host lab (docs/lab.md), main at 53d66f068, four containers
capped at 1.5 GB each, shared-secret mode, no control-plane leader
([2026-10-05-lab-topology-reread-closes-ctl-control.md](2026-10-05-lab-topology-reread-closes-ctl-control.md)).

`systemctl restart` of all four nodes at once (the lab's stand-in runs each unit's
`ExecStart`; the nodes come back on their persisted topology), app traffic paused
(`lab-traffic` = 0: one session attempted in all, refused). Live heap objects
(`live_allocs()`) / RSS in KB, every 15 s:

```
t=15 lab-1=9262859/536984  lab-2=8235122/486880  lab-3=860952/100728  lab-4=13453364/773420
t=30 lab-1=18637418/1040496 lab-2=16335825/921424 lab-3=1045652/122036 lab-4=29542654/(OOM-killed)
t=45 lab-1=19060145/1051404 lab-2=16908314/932828 lab-3=1326389/137000
t=60 lab-1=19229051/1067084 lab-2=17078845/949856 lab-3=1497781/155360
```

Three of the four allocated 8-30 million objects (0.5-1.5 GB) in their first 30 s and
then went on at the usual ~11k objects/s
([2026-10-05-lab-leaderless-agents-leak.md](2026-10-05-lab-leaderless-agents-leak.md));
lab-4 hit the cap and the kernel killed it. Which nodes burst differs between runs (the
same restart with traffic at one session a second: lab-1 and lab-2 burst, ~400k
objects/s, both killed within 75 s). Restarting ONE node alone (lab-3, the others up) shows
no burst: it starts at ~450k objects and grows ~11k/s.

So the burst comes from nodes meeting each other while several start at once: the
membership/registry sync between new incarnations, the topology placement converging
(`count = 1` roles, `Ctl.Control`), or the Agents' retries against a leader that does not
exist. The objects are reachable March heap (`live_allocs`), not stacks.

### Next step (as filed)

One node pair in the Linux container, both started together, `live_allocs()` sampled
every second and a heap census (by allocation site, if the runtime's observe tooling can
give one) at the peak. Then the same with `[control]` removed from the topology, to split
the control plane from cluster formation.

### Lab (as filed)

`lab_fresh_nodes` (scripts/lab/lib.sh) restarts nodes one at a time for this reason.
