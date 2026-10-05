# `[P1]` Nodes restarted together can each allocate ~1 GB of heap in 30 s and be OOM-killed

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

## Next step

One node pair in the Linux container, both started together, `live_allocs()` sampled
every second and a heap census (by allocation site, if the runtime's observe tooling can
give one) at the peak. Then the same with `[control]` removed from the topology, to split
the control plane from cluster formation.

## Lab

`lab_fresh_nodes` (scripts/lab/lib.sh) restarts nodes one at a time for this reason.
