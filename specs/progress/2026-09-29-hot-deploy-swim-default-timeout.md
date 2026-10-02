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
3. ~~Independently: whether a stdlib actor should be a hot-reload slot at all.~~
   **Decided 2026-09-30 (the owner, "Todo list review"): no.** A stdlib change
   comes with a toolchain or language change, which is a restart deploy, never
   a hot patch; and it keeps a deploy from pausing or migrating the actor that
   answers SWIM pings. Done in the same change:
   - The boundary predicate is `Hot_reload.is_slot_actor_dispatch`
     (lib/tir/hot_reload.ml): every `*_dispatch` except a stdlib actor's. The
     reload name table (`hr_names`), the patch `.so`'s visibility exemptions
     (lib/tir/llvm_toplevel.ml, lib/tir/llvm_tco.ml) and the slot-hash fold in
     bin/main.ml all use it; the fold no longer descends into a stdlib actor's
     glue either. (`Llvm_emit.clo_wrap_borrowed` keeps the suffix predicate on
     purpose: the runtime-call ABI is the same for every actor.)
   - "Stdlib" is loader provenance, never a name: lowering records each
     actor's glue with whether the declaring `DActor`'s span is the stdlib's
     (`Typecheck_builtins.span_is_stdlib`, the stdlib-only gate's predicate).
     A user file named `node_queue.march` or a user actor named `Writer` keeps
     its slot. (A user actor named like a stdlib actor does not compile today
     at all: "actor-message tag table has no row for Writer_Msg.Bump", on main
     too, filed separately.)
   - On the upgrade fixture the compiled slot set drops from 12 (nine of them
     stdlib actors: `ClusterNodeActor`, `Endpoint`, `Writer`, `CtlWriter`,
     `RegWatch`, `HostWatch`, `Anchor`, `OfferActor`, `ApInbox`) to 3.
   - So a stdlib change is not silently undeployed: the `.hcr_manifest`
     records `# stdlib_hash` (the stdlib source digest); `forge deploy --plan`
     plans the affected pools as a restart with the reason printed, and
     `forge deploy hot` refuses before connecting (`Cmd_deploy_hot.stdlib_change`).
     Before, with the stdlib actors unslotted, deploy hot would have found no
     slotted change and reported the server up to date.
   - A `--hot-reload` build with zero slots (all code in the entry module,
     whose slots used to be the stdlib's session actors) now still starts its
     reload server; the start had been emitted only alongside a non-empty slot
     table.
   - Tests: test/test_hcr_stdlib_actors.ml (run_compiler; in-process
     provenance and look-alikes, the driver's slot set, and the v1/v2
     manifest diff: a one-line app edit flags exactly `Counter_Bump` and
     `Counter_dispatch`; a stdlib-only edit changes no slot and differs in
     `stdlib_hash`), test/test_hot_reload.ml (`actor_provenance`),
     forge/test/test_deploy_plan.ml (restart; deploy hot's refusal).

   This removes the candidate cause above for good (no deploy touches
   `ClusterNodeActor` any more), but points 1 and 2 stay open: nobody has
   run the scenarios on the CI runner at the default suspect timeout.

## Resolution (2026-09-29, PR #692)

Items 1 and 2 are done here; item 3 was decided and done by #727 (above).
#727's write-up reached the same conclusion as the measurement below: the
ASan-only suspect timeouts are SWIM under ASan load, with or without a deploy.

**Step 1: default suspect timeout on the CI runner.** Both scenarios now run
SWIM at its default (`Swim.config(500, 3000, 2)`) in the `two-node` job, the
only CI job that runs them without a sanitizer (ubuntu only; no macOS job runs
two-node scenarios). Results, head of PR #692:

| CI run (attempt) | commit | job | `protocol_evolve` | `hcr_new_code_session` |
|---|---|---|---|---|
| 36512671315 (1) | eb8dbfd39 | `two-node` 109228055470 | ok | ok |
| 36535093512 (1) | 1facf8490 | `two-node` 109297571240 | ok | ok |
| 36535093512 (3) | 1facf8490 | `two-node` 109568940081 | ok | ok |

3/3 green on ubuntu at the default, both scenarios. Under ASan
(`sanitize-gate`, 15 s via `HCR_SUSPECT_MS`), `hcr_new_code_session` was
CLEAN in both attempts of run 36535093512 (jobs 109297571271 and
109496048041); `protocol_evolve` skips itself there. Attempt 1 of that job went
red on an untouched scenario, `cluster_stop_loopback` ("timed out waiting for
node-a to exit"), which was CLEAN on the re-run.

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
  (`ClusterNodeActor_dispatch`, `Endpoint_dispatch`) was activated even before
  #727 removed their slots, given #663's canonical lambda-hash fold.
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
