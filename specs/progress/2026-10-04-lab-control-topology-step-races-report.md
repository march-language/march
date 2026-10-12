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

Seen again 2026-10-05 at load 5 (so not only under load): the first deploy's topology
release halted the same way, on work-lab-2. The lab's first deploy now goes `--via ssh`
(see [2026-10-05-lab-forge-cluster-deploy-retry-and-leader-change.md](2026-10-05-lab-forge-cluster-deploy-retry-and-leader-change.md)
for why retrying did not work either).

## Fixed 2026-10-12

**Cause.** As described above: `Control.agent_apply` relayed the step's lines and then
read the node's report exactly once. A `TOPOLOGY` line is taken by the reload server
synchronously (it stores and verifies `g_topology_digest`), but the report's `topology`
stays `-` until the placement loop re-reads the pushed file on its next tick
(`MARCH_PLACEMENT_TICK_MS`, after `march_hcr_on_topology`), because `reload_report` only
reports the digest once `applied`. So "taken, not yet applied" was answered as not-ok,
`leader_result` recorded it as the node's failed step, and the next pass halted the
release.

**Fix.** stdlib/control.march: after a fully accepted relay, a topology step polls the
report (`await_state`) for a bounded time before answering not-ok:
`agent_apply_within(ops, o, wait_ms, poll_ms)` does the work;
`agent_apply_ticked(ops, o, tick_ms)` derives the bound from the placement tick
(`topology_wait_ms(tick)` = ten ticks, at least 2 s, at most 60 s; poll every
min(tick, 100) ms); `agent_apply(ops, o)` assumes the default tick (200 ms). Every other
action still reads the report once after the relay, so non-topology steps are neither
slower nor different. `agent_apply_recording` takes the tick, and the generated control
wiring (lib/desugar/control_wiring.march) reads `MARCH_PLACEMENT_TICK_MS` once into its
config (`cfg:placement_tick_ms`) at `ctl_start` and passes it. `Control` itself stays
free of `Env` (reading the variable inside `Control` added `IO.Process` to its
capability footprint). Polling inside the Agent was preferred over answering ok-pending:
an ok answer leaves the order in flight until the next report, after which the executor
would order the node again and relay lines the reload server had already taken.

**Test.** test/stdlib/test_control.march, `describe "agent_apply"`:
- "a topology step waits for the runner to apply the digest": a fake node whose report
  shows the digest only from its third read (check, post-relay read, one tick later);
  `agent_apply` must answer ok "applied".
- "a topology step the runner never applies fails once the wait is over" (bounded).
- "a non-topology step does not wait: one report after the relay" (exactly two report
  reads for an activate step that changed nothing, even with a 60 s budget).

RED (old stdlib/control.march, the first new test only, the other two need the new
function): `./_build/default/test/test_stdlib_march.exe test control` exits 1 with
`FAIL: "agent_apply a topology step waits for the runner to apply the digest"`,
`Finished: 47 tests, 1 failure`. GREEN (this change): the same command exits 0,
`Finished: 49 tests, 0 failures`.
