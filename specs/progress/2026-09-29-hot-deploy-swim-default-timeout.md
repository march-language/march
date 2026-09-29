`[P2]` A hot deploy may stall a node past its peers' SWIM suspect timeout

Filed 2026-09-25 from #663's CI. Asked for by the distributed-deploys session:
the plan promises a deploy does not cancel sessions, and a node that stops
answering SWIM during one gets declared dead, which does.

## What was seen

`test/two_node/protocol_evolve` on the `two-node` CI job (ubuntu runner, head
85c809043), node-b's golden diff:

```
node-b: session failed: session_node: cancelled while waiting on role Shop: connection lost   (x2)
node-b: session failed: session_node: cancelled while waiting on role Shop: node node-a dead: suspect timeout   (x2)
node-b: sessions lost: 2
node-b: sessions still running at the end
```

node-b's SWIM declared node-a dead (3 s default suspect timeout) around node-a's
deploy. The same scenario passed every local run, on macOS and in the arm64
ubuntu container.

## What is known

- **Not the deploy's own work, as far as it can be measured locally.** Timed
  with the scenario's real patches (1.1 MB, the whole program), each
  `hcr_deploy deploy` (upload, signature and cap checks, dlopen, activation)
  took 70 ms on macOS. In a single-process repro deploying every 250 ms
  heartbeat arrives on time across the deploy (largest gap is the program's
  own final sleep). The reload server is its own pthread
  (runtime/march_reload.c, `reload_server_thread`); it does not run on a
  scheduler thread.
- **A likely cause, fixed in #663 before it merged:** that CI run's compiler
  folded lambda hashes by name, so every deploy re-activated the stdlib's own
  actors, including `ClusterNodeActor_dispatch`, the actor that runs SWIM, and
  `Endpoint_dispatch`, the session endpoints: each moved to a new epoch at its
  next marker with a migration pass. With the canonical fold, a deploy
  activates only the app's changed functions, and `protocol_evolve` passes with
  the DEFAULT 3 s suspect timeout (three runs on macOS, three in the container
  pinned to 2 CPUs with `taskset -c 0,1`).
- **Not confirmed on the CI runner.** The scenario keeps a 15 s suspect
  timeout (as does `hcr_new_code_session`), so CI no longer shows whether the
  stall is gone. No timing exists from the runner.

## To close

1. Run `protocol_evolve` on the CI runner with the default suspect timeout
   (a scratch branch reverting the four `swim: Swim.config(500, 15000, 2)`
   overrides) a few times. If it passes, drop the overrides from both
   scenarios and close this.
2. If it still fails: log, per node, the wall time of each ACTIVATE phase
   (verify, dlopen, `march_hcr_activate`, marker enqueue) and the SWIM ack
   latency across it; the question is whether the actor that answers pings
   can be starved by marker processing or a state migration on a 2-vCPU box.
   Even a correct deploy should never hold the scheduler that answers SWIM.
3. Independently: whether a stdlib actor should be a hot-reload slot at all.
   `is_actor_dispatch_fn` puts every `*_dispatch` on the boundary, stdlib
   actors included (lib/tir/llvm_toplevel.ml, `hr_names`); only app actors
   need to be.

## Resolution (2026-09-29, PR #692)

Items 1 and 2 are done; item 3 is split out, undecided, as
`specs/todos/2026-09-29-stdlib-actors-as-hot-reload-slots.md`.

**Step 1: default suspect timeout on the CI runner.** Both scenarios now run
SWIM at its default (`Swim.config(500, 3000, 2)`) in the `two-node` job, the
only CI job that runs them without a sanitizer (ubuntu only; no macOS job runs
two-node scenarios). Results, head of PR #692:

CI_RESULTS_PLACEHOLDER

**The one failure was under AddressSanitizer, and it is not the deploy.** The
first CI run's `sanitize-gate` (job 109228055256) failed `hcr_new_code_session`
at the default: node-b lost 8 sessions, 5 refused, three of them "node node-a
dead: suspect timeout". Step 2's measurement, in a 2-CPU (`--cpuset-cpus 0,1`)
arm64 ubuntu container (`ci/Dockerfile.ubuntu` image), on a scratch copy with:
a probe actor on each node logging any gap over 150 ms between its 20 ms
self-beats; a `ClusterNode.subscribe` hook logging each SWIM verdict about the
peer with wall-clock ms; a per-node `MARCH_AUDIT_LOG` (one timestamped line per
activated function); and wall-clock stamps around each `hcr_deploy deploy`.

- **Each deploy is short and activates only app code.** Six ASan deploys took
  35-57 ms end to end (the client's upload through the activation reply), and
  every audit log reads the same: node-b's deploy activates `Buy.version`,
  node-a's `Host.version` and `Host.host_tick`. No stdlib actor
  (`ClusterNodeActor_dispatch`, `Endpoint_dispatch`) is activated since #663.
- **node-a's scheduler does not stall across its deploy.** The probe logged no
  gap over 150 ms within seconds of either deploy in any run; the largest gaps
  seen at all (164-480 ms) came late in the drive, on both nodes, in runs with
  and without deploys.
- **The same failure happens with no deploy at all.** With both deploys
  skipped (a control mode of the scratch scenario), under ASan the two nodes
  still suspect each other at nearly the same moment, about 9-10 s after
  joining, then declare each other dead and lose sessions: 2, 3 and 0 lost in
  three control runs, against 4, 4, 4 (and 12, 5 in an earlier batch) with
  deploys. The first suspicion came 9.0-9.8 s after joining with deploys and
  9.3-14.2 s without. Mutual, simultaneous suspicion with a responsive
  scheduler on both nodes is SWIM under ASan's slowdown on 2 CPUs with a
  session starting every 150 ms, not a node stalled by its deploy.
- Without ASan in the same container, the instrumented scenario passed (so the
  probes do not perturb it), and in the plain runs neither node suspected the
  other until node-b had printed its summary and stopped.

So `hcr_new_code_session` keeps the default everywhere except under
`MARCH_SANITIZE`, where its scenario.sh sets `HCR_SUSPECT_MS=15000` and the
node programs apply it. `protocol_evolve` skips itself under ASan, so it has no
override at all. The old comment blaming "a deploy under AddressSanitizer"
for a seconds-long stall was wrong: the deploy takes tens of milliseconds and
the loss happens without one.

A local ASan container is not an oracle for this scenario at 15 s: `main`'s
own version (hardcoded 15 s) timed out twice (330 s each) waiting for node-b's
summary on the 2-CPU arm64 box, the same as this PR's. `sanitize-gate` on the
x86 runner, where `main` passes, is the judge.

Seen in passing, unrelated: the first CI run's `test (macos-15, all)` failed one
timing assertion in `test/test_hcr_migrate_order.c:561` ("after the soft
deadline a held actor is left alone", a 20 ms soft / 80 ms hard drain
deadline).
