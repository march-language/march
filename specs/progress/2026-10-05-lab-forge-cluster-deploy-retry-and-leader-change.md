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

## Fixed 2026-10-12

**Cause.** (1) `Cmd_deploy.run_cluster` ran its segments (restart-class pools over
ssh, then releases) and called `record` only once every segment had succeeded, so a
release that halted after the restarts left `.forge/deploy/<env>/` exactly as before;
the retry's `Deploy_plan.classify` saw no `<build>.hcr_manifest` (`b_old = None`) and
planned "nothing is deployed yet" again. (2) `Cluster_deploy.follow` tolerated a gap in
STATUS answers for only 30 polls, and a handover in which every candidate answers
`ERR no_leader` (the new leader loading the newest release, the placement settle
period) can last longer.

**Fix.** (1) The segment loop is now `Cmd_deploy.run_segments ~step ~settle`: after
each segment that succeeds, the builds it carried that no later segment touches are
passed to `settle`, which `run_cluster` points at the new `Cmd_deploy.record_builds`
(the per-build half of `record`: the build's manifest, schemas and base-image
identity, the existing format). The topology, derived caps and protocol baselines are
still recorded only when the whole deploy completes, so the retry still pushes the
topology (as a release) and the protocol baselines advance only on a completed
deploy. A build shared by several restarted pools is recorded once its last pool has
restarted; if the deploy stops between two pools of one build, the retry restarts
that build's pools again (the record has no per-pool state). (2) `follow` keeps
polling through a gap for up to `?leader_wait_s` (default 120 s, as `prepare`'s
`status_wait`), prints `no control node answered (...): leadership is moving` once
per gap and `leadership moved: <node> leads now` when a different leader answers,
and fails with the last error plus "no leader for 120 s" only after the bound. Its
STATUS poll, sleep and clock are injectable (`?poll ?sleep ?now`) for the test.

**Tests** (forge/test/test_deploy_plan.ml, group "cluster backend"):
- "a halted release after restarts: the retry skips them": a first-deploy plan
  (`ssh:back | ssh:front | release[]+topology`) run through `run_segments` with the
  restarts succeeding and the release failing; build `shared` is settled once (after
  the second restart), its manifest and base.json are on disk, and classifying again
  with that manifest as `b_old` gives only `release[]+topology`.
- "following a release through a leader change": a scripted STATUS that answers,
  then 60 polls of `ERR no_leader`, then a new leader with the release complete,
  returns Ok; an endless `ERR no_leader` errors after ~120 fake seconds.

**RED/GREEN.** RED by perturbing copies of the fixed files back to the old behaviour
(record only after every segment succeeds; give up after 30 missed polls):
`./_build/default/forge/test/test_deploy_plan.exe test cluster` exit 1, "settled after
the restarts: Expected `[["shared"]]` Received `[]`" and "gave up on a leader change".
Restoring the fixes: exit 0, 29 tests run. Not verified on the multi-host lab
(`scripts/lab/run.sh deploy` needs containers); the lab still deploys its first version
`--via ssh` because of the topology-step race
([2026-10-04-lab-control-topology-step-races-report.md](../todos/2026-10-04-lab-control-topology-step-races-report.md)).
