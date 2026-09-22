# `[P1]` Distributed deploys, build step 3: level 0 (one process, generated `main`, hooks)

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 4.1, II.3, D9, D15-D17, D20, D23, D24. Groundwork
done: G5 (`Project.entry`), G6 (`forge/lib/procs.ml`).

**What.**
- Prerequisites: a ClusterNode loopback link (`queue_for(h, own_id)`), `initiate` no
  longer excluding its own node, prefer-local `candidates`; the `Entry` state alias;
  parameterised actor `init` (D24) through parser, typecheck, lowering, supervised
  child specs (`march_actor_register_child` gains an `init_arg`) and the interpreter.
- `[roles]` in the topology (functions and actors, D23); `lib/desugar/desugar_topology.ml`
  generating `main` from `--topology .forge/topology.json` (forge pre-digests the TOML);
  `stdlib/topology.march` (`place`, `drain_on_signal`, `supervise`); hook timeout
  watchdog.
- `forge run` with a topology always compiles; `--processes` starts one process per
  pool through `Procs.spawn`/`supervise`, with `Procs.free_port` ports and
  `MARCH_NODE_NAME=<pool>-<n>`.

**Acceptance.** `test/two_node/cluster_ap_local`: two roles of one session in one
binary. A topology app with two pools runs under plain `forge run` and under
`forge run --processes`, and Ctrl-C stops every process (Procs' group handling).
