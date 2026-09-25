# Distributed deploys, build step 8: the local reconciler, topology re-read, `forge topology apply`, `forge test --upgrade-from`

**DONE 2026-09-24.** Parent:
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
sections 5, 6.6, II.6 "The reconciler", II.8; D16, D19. Built on G6 (`Procs`), G7
(`Hosts.run_on`), step 3 (`Topology.place`, the generated `main`, `forge run
--processes`), step 6 (`PINS`, the counters, `Cmd_deploy_hot.run`), step 7 (the digest).

**Scope, narrowed from the original todo.** Placement (`on`, `count` by rendezvous
hashing, hysteresis, settling, local-first) shipped in step 3 and is not repeated here.
D27 automatic session drains at loop boundaries belong to the parallel item "D27
session drains and step-6 follow-ups" (`stdlib/session_node.march`,
`stdlib/session.march`, `lib/desugar/desugar_endpoints.ml`, the runtime). Four commits,
one per item.

## 1. `forge/lib/reconcile.ml`

`backend = { kind; hosts; run_on; push_topology; status }`. `run_on` is
`Hosts.run_on`. The `local` backend runs over the processes `forge run --processes`
started: that command (`Topology_run.start_processes`, split out of `run_processes`)
records them in `.forge/run/state.json` (pids, cluster ports, reload sockets, node
names, labels, status files, the overlay), removed when the run ends, and gives each
process `MARCH_TOPOLOGY_FILE` (the digest) and `MARCH_TOPOLOGY_STATUS`
(`.forge/run/<node>.status`). `forge run --processes --hot-reload` builds with
`--hot-reload <entry module>` (and the project's public key, if any) and a reload
socket per process (`Reconcile.socket_path`: under `.forge/run/`, or a short `/tmp`
directory when the path would exceed `sun_path`).

- `push_topology t`: `Topology.write_digest`, then SIGHUP to every live node that has
  reported; a node with no status file is not signalled (with no watcher installed the
  default action would kill it) and is reported as `Not_reporting`.
- `status ()`: liveness by `Unix.kill pid 0`, the node's report (applied digest sha,
  offers, draining offers, running sessions), and for a hot-reload build
  `VERSIONS_DETAIL` and `PINS` over the socket with a receive timeout.
  `pins_counter`/`pins_epochs` parse the `PINS` answer.
- Single writer: `with_lock` takes `.forge/run/reconcile.lock` with `Unix.lockf`
  `F_TLOCK` (a POSIX record lock; the kernel releases it when the holder dies) and
  writes its pid into it; a second forge reports the holder and stops.
- `forge topology status` prints `render_status`.

Tests: `forge/test/test_reconcile.ml` (in-process, 9 cases): state round trip and a
dead run reading as none; the lock (exclusive, released on exit and on SIGKILL of the
holder); push against stand-in shell nodes (SIGHUP delivered only to the reporting
one, the non-reporting one alive); status against a forked fake reload server; the
diff (item 3). Perturbation: dropping the "not reporting" guard fails the push case.

## 2. Nodes re-read the topology on SIGHUP (D16)

`stdlib/topology.march`: `place` installs `Signal.watch(Signal.Hup, fn -> reload(node))`
and keeps the roles the build contains as `base`. `reload` reads `MARCH_TOPOLOGY_FILE`,
`desired_of` types the digest (version 1 only; the roles served by this process's pools
via `runs_pool`, each with placement and capacity; the drain deadlines), `apply_desired`
gives every base role the digest's placement and capacity, or `PlaceNowhere` when no
pool of this process serves it any more; the next evaluation runs at once and opens or
retires offers as for a membership change. A role newly served that the build has no
code for is reported ("rebuild and restart to offer it"). A file that cannot be read or
parsed changes nothing, with a report.

- **Capacity from the topology.** The generated `main` now passes each role's capacity
  as an argument: `Topology.offer_role(name, place, capacity, fn cap -> ...offer_R(io,
  node, cap, ...))` and `offer_actor_role(..., fn (a, cap) -> ...)`
  (`lib/desugar/desugar_topology.ml`). `role`/`actor_role` stay for hand-written code
  and fix the capacity (0). When an open offer's capacity differs from the role's, the
  offer is retired and reopened at the new size.
- **Closed offers drain under the deadlines.** A retired offer is stamped; the tick
  reports it at the topology's soft and hard `[drain]` deadlines while sessions still
  run on it, and forgets it once drained. It is not cut: cancelling one offer's sessions
  needs a `SessionNode` API that does not exist (a SIGTERM drain still ends at
  `drain_on_signal`'s hard deadline).
- **Status.** `status_text` (`node`, `topology <sha256 of the applied digest | compiled>`,
  `offers`, `draining`, `running`) is written to `MARCH_TOPOLOGY_STATUS` when it changes,
  atomically (temp file + rename).
- A `TopoRole` gained `capacity`, `TopoOpened` the capacity it was opened at,
  `TopoState` a string vault; `TopoPlacement` gained `PlaceNowhere`.

Tests: `forge/test/test_topology_reconcile.ml` on `forge/test/fixtures/reconcile_app`
(three pools, each serving `Echo.Server` with `count = 1`; `topology.dev.toml` labels
them a, b, c), run by the real `forge run --processes --env dev`: exactly one node offers;
its process group is SIGKILLed and the role moves once SWIM declares it dead; a pushed
topology `{ on = "<third node's label>", count = 1 }` moves it to that node with the same
pids (no restart); a capacity push reopens the offer (`capacity 4 -> 2` in the node's
output). Red when `reload` keeps the old roles ("the role is on the labelled node").
`test/stdlib/test_topology.march` +3: `desired_of` over a digest (served roles only,
placements, capacity default 64, drain defaults), refusal of other versions and non-JSON,
`apply_desired` (red when unserved roles keep their placement).

## 3. `forge topology apply [--env E]`

`Reconcile.apply`, under the lock: load and check the topology (`--env`, else the overlay
the cluster started with), diff it against `.forge/run/applied.json` (the digest the
nodes were last given, recorded at start and after every push; `.forge/topology.json`
itself is rewritten by every build and check, so it is not the observed state), push,
`wait_applied` (every signalled node reports the new sha, then the offers stop changing
for a few polls), and print each node. `diff_topologies` classifies every difference:
placement, capacity, a pool that stops serving a role, a removed role and the drain
deadlines are `Placement`; a rebinding, a new role, a role newly served by a pool, a
hook, `caps`, `initiates`, `isolate`, hosts and labels, pools added or removed are
`Needs_restart`, and a pass with any of those is refused with the list ("stop the cluster
and run `forge run --processes` again"). The same topology twice says so.

Tests: `test_reconcile.ml` +2 (the classification; red when a hosts change is not a
restart); `test_topology_reconcile.ml` +1 (`forge topology apply` moves the role on the
three-node cluster with no pid change, a second apply reports no change, a label change
is refused and nothing is pushed).

## 4. `forge test --upgrade-from <ref>` (II.8)

`forge/lib/upgrade_test.ml`. `git worktree add --detach` at the ref under
`.forge/upgrade/<ref>` (the directory writes a `.gitignore` of `*`; removed at the end);
build the working tree's patch (`--compile --compile-so --hot-reload <entry module>
--topology <digest>`) and the ref's (for its `.schemas.json`: how a deploy detects a
message-type change); start the ref with `Topology_run.start_processes ~hot_reload:true`
signed by a key minted for the run; compile each `test/upgrade_*.march` of the working
tree and start it as one more cluster node (seeds = the processes;
`MARCH_UPGRADE_SOCKETS`, `MARCH_UPGRADE_READY`, `MARCH_UPGRADE_DEPLOYED`); once every
test file has signalled ready, deploy through `Cmd_deploy_hot.run ~tunnel:false` (new:
`remote_socket` is a local socket, no ssh) on every process; create the deployed file;
wait for the tests and the drain; read `PINS`. Fail on: a test file exiting non-zero or
not finishing, an old process exiting, `dropped > 0`, `killed > 0`, `markers_lost > 0`,
a reload server that stopped answering. Report: the counters per process, actors still
on an old epoch (held for an unfinished session or in a nested receive) and units that
are not actors (tasks) still pinned; those fail only under
`MARCH_UPGRADE_STRICT_DRAIN=1`. Knobs: `MARCH_UPGRADE_DRAIN_S` (60),
`MARCH_UPGRADE_TEST_S` (180), `MARCH_UPGRADE_READY_S` (180). Topology apps only; no
isolated pools yet (one shared build is patched).

Fixtures, `forge/test/fixtures/upgrade/`: `v1` (one pool; `Tally` with `Add | Legacy`; a
feeder TASK sending `Legacy(1)` every 20 ms for 6 s, which stays on the old epoch after
the deploy, so it keeps sending the old format; `test/upgrade_traffic.march`: a session
on the old code, one that waits for the deploy between its two exchanges, one on the new
code), `good` (the `Legacy` handler's body changes; same message type: PASSES), `drops`
(`Legacy` removed, no `migrate_msg`: FAILS with `dropped 25x`). Test:
`forge/test/test_upgrade_from.ml` (3 cases): both fixtures through the real forge on a
git repository made from `v1`, plus a non-topology project refused.

## Deviations and findings

1. **The passing fixture does not use `migrate_msg`.** It was written that way first
   (`Legacy` removed, `tally_migrate_msg` converting to `Add`) and the process died with
   `panic: non-exhaustive pattern match` on the first old message: an old actor message
   carries a global actor-message tag (`0x0100_0000 + n`, by build order), while the
   user's old-message type compiles to ordinary tags 0, 1, so the compiled match cannot
   see it. Codegen, outside this item's ownership; filed as
   `../todos/2026-09-24-migrate-msg-actor-message-tags.md` (with the second problem
   behind it: removing a handler shifts the tags of every actor declared later). The
   runtime path and the `dropped` counter are exercised by `drops`.
2. **A CAS cache hit copies a `.so` without its sidecars** (`.hcr_manifest`,
   `.schemas.json`): the second run of `--upgrade-from` in a project found no manifest.
   Worked around by building each patch from a fresh working directory (the store is
   `<cwd>/.march/cas`), a full recompile per run. Filed as
   `../todos/2026-09-24-cas-hit-skips-so-sidecars.md`.
3. **"Drains finish within their bounds" is reported, not asserted, by default.** After
   the soft deadline, one `Endpoint` and a `RegWatch` actor and six tasks stayed pinned
   to the old epoch on the passing fixture (a hard `DRAIN` named the slots); step 6
   leaves held and nested-receive actors and non-actor procs to the hard deadline, which
   is off by default. `MARCH_UPGRADE_STRICT_DRAIN=1` turns the leftover actors into a
   failure.
4. **Test files declare their protocols.** A topology app's entry module is not
   loadable as a library from a test file, and `@[endpoints]` code generated inside an
   imported module does not typecheck from another file (`Unknown module Echo_Client`),
   so `upgrade_traffic.march` repeats the `Echo` protocol; the wire fingerprint is the
   protocol's name, roles and steps, so the copy interoperates.
5. **A closed offer's sessions are not cut at the hard deadline** (item 2): no per-offer
   cancel exists in `SessionNode`; the deadlines are reported.
6. **`Procs.free_port` and `pgrep -f <dir>`** are the same helpers step 3's tests use;
   liveness is always `Unix.kill pid 0`.
7. Two-parameter function types in March are `Pid(a) -> Int -> R`; a `(Pid(a), Int) -> R`
   annotation typechecks the stdlib file to an internal error that only the compiler
   suite's stdlib ratchet (`entry_mod_qual_erasure`) reports, not `--check`.

## Results

Run from the worktree with `--root .`; the process suites run directly with the
hermetic environment their dune rules give them.

| suite | cases | result |
|---|---:|---|
| forge/test/test_reconcile | 9 | pass (0.5 s) |
| forge/test/test_topology_reconcile | 2 | pass (27 s) |
| forge/test/test_topology_run | 3 | pass (23 s) |
| forge/test/test_upgrade_from | 3 | pass (148 s) |
| test/stdlib_march (incl. `test_topology.march`) | 72 | pass |
| compiler (`scripts/run-tests.sh -q compiler`) | 1205 | pass |
| dune rules `native_topology_place`, `native_topology_hook_timeout`, `topology_placement` | 3 | pass |
| `scripts/two-node.sh topology_move` | 1 | pass |

Perturbations, each red on exactly its case: the push guard (item 1), `reload`
keeping the old roles (item 2), `apply_desired` keeping unserved roles (item 2), hosts
not a restart (item 3, unit and cluster).
