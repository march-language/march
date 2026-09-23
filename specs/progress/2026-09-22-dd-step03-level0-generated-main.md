# Distributed deploys, build step 3: level 0 (one process, generated `main`, hooks)

**DONE 2026-09-23.** Parent:
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
sections 4, 4.1, 4.2, II.3, II.6 "Placement at runtime"; D9, D15-D18, D20, D23, D24, D34.
Built on D24 (parameterised `init`), step 4 (grants as values), step 7 (the digest) and
G6 (`forge/lib/procs.ml`). Four commits, in the order the task asked for.

## 1. `stdlib/topology.march`

- `Topology.place(node, roles)`: one `Role` per served role (`role(name, place, open)`
  for a function binding, `actor_role(name, place, mk, open)` for an actor binding; an
  actor spawned for an offer that failed to open is kept for the next attempt). A task
  re-evaluates every `MARCH_PLACEMENT_TICK_MS` (200): `everywhere()`; `on_label(l)` from
  `MARCH_NODE_LABELS`; `count(n)` / `count_on(l, n)` by rendezvous ranking over the
  eligible live nodes. A lost role is drained through `SessionNode.close_offer`.
  The constructors behind them are `Place`-prefixed (`PlaceCount`, ...): a bare
  `Count` broke user code writing DataFrame's nullary `Count` unqualified
  (`test/native/dataframe_groupby_count` in the IR validity gate), and the anchor
  actor's state record got a unique field name because `{ n : Int }` made the
  `@[remote]` codec choice for a user's `type Hit = { n : Int }` ambiguous
  (`remote_actor_dispatch`). Both were caught by `run_codegen`, not by any
  topology test.
- **Eligibility is a cluster name.** Membership does not carry other nodes' pools or
  labels, so every node eligible for a ranked role registers `topo:<role>/<node_id>`
  (bound to a small anchor actor) and the ranking reads those names back; a dead node's
  names become invisible with its membership. A Suspect member still counts (a role
  moves only when SWIM declares the node Dead, 4.2): counting only Alive members made
  `topology_move` flake under load (1 in ~8 runs) with a brief offer on the ranked-second
  node.
- Hysteresis: `NodeRejoined` stamps the member in the node's Vault; it counts again after
  `MARCH_PLACEMENT_SETTLE_MS` (15000). A node cannot tell its own restart from a first
  start, so it is not debounced for itself.
- `drain_on_signal(node, soft, hard)`: SIGTERM and SIGINT close every offer; the process
  exits 0 once no session runs, reports at the soft deadline, and exits 1 at the hard one
  (epoch drains are step 6). `drain(node, soft, hard)` does it directly.
- `supervise_offers(node)` (not `supervise`: that is a keyword): re-offers a role whose
  offer actor or hosting actor died, and blocks until the node stops, keeping `main` alive.
- `hook(name, f)`: the `MARCH_HOOK_TIMEOUT_MS` (10000) watchdog; reports the hook by name
  and exits 1.
- `start_node()` / `config_from_env()` (defaults `local-1`, port 7946), `runs_pool(p)`
  (`MARCH_POOLS`), `offered`, `running`, `offer_worker`.

Tests: `test/stdlib/test_topology.march` (the pure core over fake membership: labels,
ranking agreement, exactly-n, a dead node's role moving to the next ranked, markers,
settling; a perturbation of `wants` fails two cases); `test/native/topology_place`
(one real node: which roles open, the marker, re-offer after `kill`, SIGTERM drain exits
0); `test/native/topology_hook_timeout`; `test/two_node/topology_move` (a `Count(1)` role
moves when its node is SIGKILLed).

## 2. The generated `main` and typed checks

`lib/desugar/desugar_topology.ml` reads the AST and writes March SOURCE (lib/desugar
does not link the parser); `bin/topology_gen.ml` converts forge's digest, parses and
splices the source, and after typechecking derives each pool's caps. The generated code
is therefore checked like hand-written code (grant walk, linearity, endpoint types).

- Function bindings: `fn (s, x1..xk, st) -> Body.f(env, s, x1..xk, st)` passed to
  `<P>_Run.offer_<R>`, k = the role's `role R needs` entries.
- Actor bindings (D23): `spawn` takes only a BARE actor name (a qualified one is a parse
  error) and message constructors resolve in the actor's module, so four helpers are
  injected INTO THE ACTOR'S MODULE (`topology_spawn_<A>`, `topology_start_<A>`,
  `..._deliver_...`, `..._cancel_...`) and `main` calls them. The actor takes the same
  `Start(sid, s, caps...)`, `Deliver(sid, s, from, msg, ep)`, `Cancel(sid, s, role,
  cause, ep)` a hand-written hosted offer's actor does.
- Hooks: one `cap_narrow(io)` per `Cap(P)` parameter the hook declares (the io itself
  for `Cap(IO)`), then the handle. The plan said "one per pool cap"; the hook's own
  signature is used instead, and checked against a written `caps`, because a derived
  pool's caps are not known before typechecking.
- `--topology-pools` restricts a build's pools (isolated builds); `MARCH_POOLS` picks
  them at run time in a shared build.
- Checks (`march --topology`): body arity and first parameter vs the hook's return type
  (type names resolved per declaring module), actor `init` and the three handlers, hook
  signature, role grant and hook caps within a written `caps`, reach within a written
  `caps` after typechecking (naming the hook or role), `--topology-isolate-foreign`
  (the plan's "when opted in", as a flag). A hand-written `main` is kept with a warning.
- `--emit-core-ast` gains a `topology` object (`caps`, `reached_from`, typed
  `initiates`, `generated_main`), only with `--topology`.
- Zero-parameter closures stored in a record field or `let`-bound with an expected
  type are mistyped (`expected () -> Int but got Int`); `Topology.Role.open` takes a
  dummy `Int`. Filed: `../todos/2026-09-23-zero-arg-lambda-checked-against-thunk-type.md`.

Tests: `test/test_topology_flag.ml`, 17 cases (was 5; its fixtures used placeholder
shapes the new checks reject, so it was rewritten around a real two-pool app).

## 3. `forge run`

`forge/lib/topology_run.ml`. A topology app always compiles (`forge build` too passes
`--topology`), saying so when the interpreted default was asked for. Level 0 runs one
process with defaults for `MARCH_NODE_NAME`/`PORT` and every `place.on` label, forge
ignoring SIGINT while it waits so the program drains. `--processes`: one build per
distinct build, one process per pool (per overlay host), `Procs.free_port`, seeds =
every other process, `--fail-fast`, `--env`. `forge topology export`/`gen` take caps and
initiates from the compiler (`"source": "compiler"`), else `null` caps with a warning.

Acceptance: `examples/topology_app` (two pools; a function role with a granted cap, an
actor role keeping a total across sessions) under `forge/test/test_topology_run.ml`:
`--processes` (SIGINT to forge drains both, both exit 0, none left), level 0 (SIGINT to
the process group drains the one process), export.

## 4. Loopback and prefer-local

`origin/main` had not moved when this item started (3656afd99) and D35 had not landed,
so it was first built on `ClusterHandle`. D35 landed right after (35e8e77ce, #601), and
the branch merged it: the loopback moved into `h_queue_for` over the backing `CnHandle`
(so it is behind the `Ops` dictionary like every other operation), and everything in
this step now takes `Cap(ClusterNode.Live)`. Two consequences for the generated code:
`ClusterNode.start` takes `Cap(IO)`, and a module other than `ClusterNode` may not
return the cap it mints, so the generated `main` calls `ClusterNode.start(io,
Topology.config_from_env())` itself (`Topology.start_failed` reports a failure); a hook
takes the node as `Cap(ClusterNode.Live)` and its module declares `needs
ClusterNode.Live`. `Topology.stop(node)` replaces reading the handle's `stopped` flag,
which the cap no longer exposes. The diff to the D35 files stayed small: `NodeQueue.start_local
(sink)` (a writer whose negative "fd" names a sink; budget effectively unbounded, so
credit is bypassed); `ClusterNode` creates one loopback queue at `start` and
`queue_for(h, own_id)` returns it, its sink routing like the data reader
(`deliver_loopback`, DELIVERY_FAILED to the handler directly); `SessionNode.initiate`
seeds `used` with nothing and no longer adds chosen nodes, and `candidates` puts a
local offer first (the rest keep their rotation, not rendezvous order: changing that
would change which node every existing scenario picks).

With D35, placement is also tested through the dictionary, as the plan's 7.2 asks:
`test/session/topology_placement.march` attaches a fake `ClusterOps` (member table,
name registry, subscribers) and runs `Topology.place` with real `SessionNode` offers over
it; a `count(1)` role moves to the node when the peers ranked above it are declared
dead, and stays while a rejoined peer settles (with `MARCH_PLACEMENT_SETTLE_MS=0` the
rejoined peer takes it back, which is the perturbation that turns it red). Compiled
only: the interpreter runs `place`'s background task to completion at spawn.
`Topology.reconcile_now` exists for such tests.

Acceptance: `test/two_node/cluster_ap_local` (one node: two Echo sessions, a hosted
session, and a `cluster_<Role>` pair, all local). Restoring the own-node exclusion
turns it red.
