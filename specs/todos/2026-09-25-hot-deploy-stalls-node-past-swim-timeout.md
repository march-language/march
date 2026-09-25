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
