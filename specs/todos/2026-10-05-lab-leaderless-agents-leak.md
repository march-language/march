# `[P1]` Without a control-plane leader, every node grows by ~13k heap objects a second

Found 2026-10-05 by the multi-host lab (docs/lab.md), main at 53d66f068, four containers,
shared-secret mode, after the first `forge deploy --via ssh`.

After the deploy no candidate leads (the topology push closes `Ctl.Control`,
[2026-10-05-lab-topology-reread-closes-ctl-control.md](2026-10-05-lab-topology-reread-closes-ctl-control.md)).
With the app's own traffic paused (`lab-traffic` = 0: no session started, none running),
every node kept growing, live heap objects (`live_allocs()`, from the lab's probe) and
RSS sampled every 30 s:

```
t=1791218965 lab-1=12810123/832784KB lab-2=9530406/621044KB lab-3=10775419/695152KB lab-4=14195622/910500KB
t=1791218995 lab-1=13196642/858612KB lab-2=9918904/654880KB lab-3=11164757/725736KB lab-4=14584845/940468KB
t=1791219026 lab-1=13582781/895452KB lab-2=10306890/695812KB lab-3=11555396/765472KB lab-4=14974333/978324KB
t=1791219056 lab-1=13970868/938476KB lab-2=10695670/739216KB lab-3=11945340/808548KB lab-4=15364514/1021436KB
```

About 386k objects and 35-45 MB per node per 30 s, the same on the ingress node (no
roles) as on the work nodes. A node reaches 1.5 GB about 20 minutes after it starts.

## Likely cause

With no leader, each node's Agent loop (`ctl_agent_loop`, lib/desugar/control_wiring.march)
tries `Ctl_Run.initiate_Agent` every 5 s (backoff capped at 5000 ms) and gets
`NoOffer`. A failed initiate leaves its session tables behind
([2026-10-01-session-node-vault-tables-leak.md](2026-10-01-session-node-vault-tables-leak.md);
#785 closes them, not merged when this was measured), but one attempt per 5 s would mean
~65k objects per attempt, more than the ~40k #785 reports for a whole session. Measure
with the attempts disabled before concluding; the placement loop and the Agent's report
(`NODE_STATE` and `PINS` read every poll) run every tick too.

## Repro

`scripts/lab/run.sh deploy`, then `echo 0 > /var/lib/march/lab_app/lab-traffic` on lab-1
and sample `/var/lib/march/lab_app/lab-probe` on each host. `scripts/lab/run.sh soak`
reports the same growth with traffic.
