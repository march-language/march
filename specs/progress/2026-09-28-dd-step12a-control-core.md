# Distributed deploys, step 12a: the control plane's pure core

**Design:** `specs/plans/2026-09-28-dd-step12-control-plane-design.md` (on PR #671's
branch when this landed), sections 3, 4, 7, 8, 10 ("12a") and decisions D37–D41.
**Remaining wiring:** [../todos/2026-09-28-dd-step12a-control-wiring.md](../todos/2026-09-28-dd-step12a-control-wiring.md).

## What was built

`stdlib/control.march` (module `Control`), everything that needs neither PR #671's
runtime changes nor a network, plus the `Ctl` and `CtlFetch` protocols in
`test/session/control_peers.march` (see "Where the protocols live" below):

- **The release document** (design section 4): `parse` / `serialize` for the text form,
  `check` (seq, parent, env, topology, distinct builds, steps numbered 1..n,
  `activate(b)` naming a shipped build, a `drain` line for a drain step, `line`
  entries naming real steps, `canary(n ≥ 1)`, positive gate windows), `digest`
  (sha256 of `signed_text`), `sign` / `verify` (ed25519 over the canonical
  `signed_text`, so a re-laid-out document still verifies), and `accept`, the
  leader's compare-and-set on `parent` (first release; the head again; higher seq
  with `parent == digest(head)`; refuses stale, fork and parent mismatch).
- Two additions to the design's format, both needed by the executor:
  `line <step> <signed request line>` carries the operator-signed `SEQ …` lines the
  Agent relays for a step (the control plane never signs), and a step may carry
  `batch:N` (at most N of its nodes with an order in flight). `gate:none` is the
  explicit no-gate spelling `serialize` writes.
- **The executor** `pass(release, members, obs, inflight, now)`, pure and
  level-triggered: the first step whose selected nodes do not all report its end
  state gets `RolloutApply(step, orders)` for the next nodes it allows; a done step
  whose gate has not passed is `RolloutWait`; a node's reported failure of this
  release's step, or an unhealthy node during a gate, is `RolloutHalted`; a node
  holding a newer release is `RolloutBehind`. "Done" is observation, not history: a
  node is done with `activate(b)` when it reports `b`'s manifest, with `topology`
  when it reports the digest, with `drain` when its drained epoch reaches the
  release's. So no step is ordered twice to a node that reports it, and none is
  skipped.
- **Host selection**: `targets` (pool members in node order; `*` is everyone),
  `select` (`canary(n)` the first n, `all` everyone, `rest` the targets no earlier
  step with the same action selected). Selection depends on the release and the
  membership only, never on progress, so every leader picks the same canary.
- **Gates as data over reports**: `observe` records a report with the leader-clock
  time the node became healthy in its current state; a state change or an
  unhealthy report restarts it. Windows are the leader's own, so a new leader
  restarts one in progress, as the design says.
- **The leader's memory** `CtlLeader` (`leader_new`, `leader_release`,
  `leader_report`, `leader_result`, `leader_pass`): orders in flight until the
  node's next report, a sticky halt until a new release, and a failure the leader
  learned from a `StepResult` kept across reports that omit it.
- **The Agent's apply** `agent_apply(AgentOps, StepOrder)`: idempotent (a node that
  already reports the end state answers ok without a request), refuses on missing
  artifacts, relays the signed lines through `ops.request` and fails on the first
  non-`OK` answer or when the node does not then report the end state.
  `AgentOps { report, has, request }` is the seam the `reload_request` builtin
  plugs into (design section 6).
- **The protocols' payloads and dictionaries** in `Control`: `AgentReport`,
  `StepOrder`, `StepResult`, `CtlChunk`, `chunks`, `CtlNext` and `ControlOps`. None
  derives Json: a `derive Json` in an eagerly loaded module puts its `from_json` in
  scope for every program, and a user's bare `from_json` became ambiguous
  (`derive_json_dispatch_codegen` and `interpreter_only_dsl` caught it). The
  protocol's own wire records (`WireReport`, `WireOrder`, `WireResult`,
  `WireChunk`, each with a `wire : Int` format version) derive Json next to the
  protocol declaration, and the role bodies convert at the boundary.
- **The protocols** (design section 7), every step labelled (D25):
  `Ctl` (`hello: Agent -> Control : AgentReport`, then a loop of
  `apply`/`stepped`, `observe`/`report`, `bye`) with grants
  `Agent needs IO.NetConnect`, `Control needs IO.NetConnect, IO.FileWrite`; and
  `CtlFetch` (`want: Agent -> Server : String`, then `chunk`* `fin`). Bodies:
  `agent_role`, `control_role` (driven by `ControlOps`), `fetch_agent`,
  `fetch_server`.

## Where the protocols live

The protocols were first declared inside `stdlib/control.march`. That compiled only
after the lowering fix below, and then broke every program whose entry module
shadows a stdlib module's name (`mod Test`: ten `test/native` fixtures): such a
program takes the combined from-scratch typecheck, where `Control` is nested, and an
`@[endpoints]` protocol does not typecheck below an entry module's top level
([../todos/2026-09-28-endpoints-protocol-in-nested-module.md](../todos/2026-09-28-endpoints-protocol-in-nested-module.md)).
Eager loading also charged every program for them (below). So their canonical
declaration and role bodies live at the top of `test/session/control_peers.march`'s
entry module, over `Control`'s types and functions, until that todo is fixed or the
wiring puts them in the generated topology `main`.

## Deviations from the design sketch, and why

- `observe` carries the leader's head seq and `bye` a reason, where the sketch had
  `Unit`: a `()` payload does not JSON-encode in the interpreter
  ("to_json: cannot determine type of value").
- The wire records are flat. `derive Json` encodes String / Int / Float / Bool
  fields and nothing else reliably: a `List` field fails at run time in the
  interpreter ("to_json: no Json derive for type List"). So `AgentReport.versions`
  is canonical text (`versions_text` / `report_versions`), its failure is three
  fields (`report_failure` / `with_failure`), and `StepOrder` carries its artifact
  hashes space-separated and its signed lines newline-separated
  (`order_artifacts` / `order_lines`).
- Every type and constructor is prefixed (`CtlRelease`, `CtlStep`, `HostsCanary`,
  `DoTopology`, `RolloutApply`, `NextBye`, …). March has one global type namespace
  and the module loads eagerly into every program; `Step`, `Release`, `Version` or a
  constructor named `Topology` would collide with user code, with the generated
  role modules' own `Step`, and (for `Topology`) with a stdlib module. Before the
  rename, two arms of `leader_pass` matching `Apply(...)` / `Halted(...)` silently
  resolved to OTHER constructors (the generated `Ctl` message `Apply`), which is
  the hazard in miniature.

## Tests

- `test/stdlib/test_control.march` (31 tests, `scripts/run-tests.sh stdlib_march`):
  parsing, serialising and round-tripping the design's example; malformed documents
  with line numbers; `check`; signing, re-laid-out verification, digests; `accept`;
  host selection; gate windows (and a new leader restarting one); full rollouts
  over a simulated cluster; **resume after a leader change mid-rollout** from
  observation alone; an order the old leader sent and the node applied is not sent
  again; an order lost with the old leader is sent once; **a canary turning
  unhealthy halts the release at its gate** and the halt sticks; a refused order
  halts; a new leader re-derives an apply failure from the agent's report; every
  node's applied-step list is checked exactly, so **no step applied twice or
  skipped**.
- `test/session/control_peers.march` (dune golden, interpreted AND compiled, one
  expected file, which also holds the protocol declarations): scripted Control against the real Agent and scripted Agent
  against the real Control (the generated peers check every step against the
  projection); a whole rollout over `Ctl` sessions against four simulated nodes,
  agents reconnecting every round and the leader replaced mid-step-2; a refused
  order halting over sessions; chaos Control, chaos Agent and chaos CtlFetch peers
  (30 seeds each) against the real roles, every session closing.

## Costs and findings

- **Eager-load cost.** `control.march` is in the eager stdlib manifest (the lazy
  path skips body inference). Measured on `hello.march` with a private `HOME`: the
  pure core costs about 0.02–0.05 s warm (0.49 s → 0.51–0.55 s, the upper figure at
  a higher machine load). With the two protocols in it, it was 0.59 s warm and
  about +0.8 s cold, one more reason they are not in the stdlib yet.
- Compiling the protocols while they were inside the stdlib module found a lowering
  bug (nested-module sibling calls did not link), fixed alongside:
  [2026-09-28-nested-module-sibling-call.md](2026-09-28-nested-module-sibling-call.md).
- A compiled-only corruption of a scripted peer's received order turned out to be a
  Perceus use-after-free (a borrowed field projection outliving its consumed owner),
  fixed alongside:
  [2026-09-28-borrowed-field-outlives-owner.md](2026-09-28-borrowed-field-outlives-owner.md).
- Record impls are structural: a user record with exactly `StepOrder`'s (or
  `AgentReport`'s, `StepResult`'s, `CtlChunk`'s) fields that derives Json is now an
  overlapping-implementation error. Unlikely with these field sets; noted.
