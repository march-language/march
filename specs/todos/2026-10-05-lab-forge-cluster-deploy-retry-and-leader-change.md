# `[P2]` A halted first `forge deploy` is not recorded, and its retry gives up on a leader change

Found 2026-10-05 by the multi-host lab (`scripts/lab/run.sh deploy` with `--via auto`,
docs/lab.md), load average 5, four containers. Two problems in `forge deploy` on the
cluster backend (forge/lib/cmd_deploy.ml `run_cluster`, forge/lib/cluster_deploy.ml), seen
one after the other.

## 1. A halted release after successful restarts records nothing

The first deploy restarted every pool over ssh (all four nodes `restarted`), then sent
the topology as a release, which halted on the topology-step race
([2026-10-04-lab-control-topology-step-races-report.md](2026-10-04-lab-control-topology-step-races-report.md)).
forge exited 1 and recorded nothing under `.forge/deploy/lab/`. Running the same deploy
again planned it as a first deploy ("nothing is deployed yet: install the base build and
start it") and restarted all four nodes a second time, with traffic running.

The restarts are done and the nodes run the new base: forge should record each segment
as it completes (the restart segments, at least), so a retry only redoes the release.

## 2. Following a release gives up when leadership moves

On that second run the restarted nodes rejoined, and the `count = 1` ranking that
places `Ctl.Control` moved the leader once the placement settle period passed. forge
was following the release it had just sent:

```
==> 3 of 3: a release through the control plane
control plane: leader work-lab-3, head release 1791217700150
  step 1 pools:* hosts:all do:topology gate:none
uploading the topology (24ceb4f5...)
release 1791217768182 accepted (OK 1791217768182 e8b1a7004ac3...)
    waiting for every node to report
error: no control node answered: connection closed; ERR no_leader; ERR no_leader
(3 of 3; this was the last part)
```

`ERR no_leader` from every candidate is a transient state during a handover (the new
leader loads the newest release from disk and carries on). `Cluster_deploy.follow`
should keep polling for a bounded time (as `prepare` waits up to 120 s for a leader)
instead of failing the deploy, and say that leadership moved.

## Repro

`scripts/lab/run.sh deploy` with the first deploy changed from `--via ssh` to the default
(`--via auto`). The lab deploys its first version with `--via ssh` until this and the
topology-step race are fixed.
