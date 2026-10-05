# `[P2]` A release's topology step halts when the node has not re-read the topology yet

Found 2026-10-04 by the multi-host lab (`scripts/lab/run.sh deploy`, docs/lab.md), on the
first `forge deploy` of `examples/lab_app` to four containers, with the Mac heavily loaded.

`forge deploy` on the cluster backend restarted every pool over ssh, then sent the topology
as a one-step release through the control plane. The step halted on one node:

```
==> 3 of 3: a release through the control plane
control plane: leader work-lab-3, head release 0
  step 1 pools:* hosts:all do:topology gate:none
uploading the topology (24ceb4f5f6b62fec8429598341b493a73de7461614a0ccac40f3c3744f322ade)
release 1791168801519 accepted (OK 1791168801519 d2a3bb5277b0...)
  step 1 of 1: step 1 pools:* hosts:all do:topology gate:none
    step 1: HALTED on work-lab-3: the node accepted every line but does not report topology at 24ceb4f5f6b62fec...
release 1791168801519 (d2a3bb5277b0) on leader work-lab-2: halted
  work-lab-3: release 1791168801519, healthy, versions -, topology 24ceb4f5f6b6, FAILED 1791168801519/1:...
```

The same node reports the wanted digest a moment later (the last line), so the node did
apply it.

## Cause (from the code)

`Control.agent_apply` (stdlib/control.march) relays the step's lines and then checks
`reports_state(ops.report(), ...)` once, at once. For a topology step the report's
`topology` is `-` until the node's placement loop has re-read the pushed file:
`Control.reload_report` sets `topology: if applied do topo else "-" end`, where `applied`
comes from the topology status (the runner re-reads on its next tick,
`MARCH_PLACEMENT_TICK_MS`, after `march_hcr_on_topology`). The reload server has stored and
verified the digest synchronously (`g_topology_digest`, runtime/march_reload.c), but the
Agent asks before the runner has caught up, and a not-yet-applied state is answered as a
failure, which halts the release. On an idle machine the runner usually wins; under load
it does not.

## Fix direction

For a topology step, treat "the reload server holds the digest, the runner has not
applied it yet" as pending: poll the report for a bounded time (a few ticks) before
answering not-ok, or answer ok-pending and let the level-triggered executor see it on the
next report. Add a control scenario whose release has a topology step and a slow runner
(a long `MARCH_PLACEMENT_TICK_MS`) to pin it.

The lab's `deploy` scenario notes it and deploys again when it happens.
