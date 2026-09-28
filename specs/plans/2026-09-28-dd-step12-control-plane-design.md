# Distributed deploys, build step 12: the in-cluster control plane (design)

**Parent:** [2026-09-21-distributed-authority-and-deploys-plan.md](2026-09-21-distributed-authority-and-deploys-plan.md),
section 5 and II.9. **Todo:** [../todos/2026-09-22-dd-step12-control-plane.md](../todos/2026-09-22-dd-step12-control-plane.md).

The parent plan left step 12 as a sketch: a `Control ↔ Agent` `@[endpoints]` protocol, an
Agent that wraps the reload-socket verbs, a `cluster` backend for `reconcile.ml`,
certificate issuance, and a leader lease. This document is the design pass on that sketch,
done against the code on `main` as of 2026-09-28 (`5f4aa31dc`). Reading the code changed the
sketch in five places (section 2). The design is in sections 3–9, the staging in section 10,
and the owner's decisions (D37–D41, settled 2026-09-28) in section 11.

## 1. What exists to build on (verified in code)

| Piece | State | Where |
|---|---|---|
| Reconciler | `apply_pass` pushes a topology and waits for nodes to report it. Backends: `local`, `ssh`. The single-writer guard is a local `lockf` file; the module's doc says "a lease on the cluster needs the control plane". | `forge/lib/reconcile.ml:199-223`, `:371-378`, `:888-934`, `:67-69` |
| `forge deploy` | Does **not** go through `apply_pass`. It runs its own per-pool plan (canary, rolling or simultaneous, restart or hot patch), then pushes the topology last. It borrows the reconciler's lock, status and `run_on`. | `forge/lib/cmd_deploy.ml:453-479`, `:514-646` |
| Reload server | One C pthread per node on a Unix socket, one client at a time, text verbs. Signed: `ACTIVATE`–`ACTIVATE6`, `TOPOLOGY`, `DRAIN` (ed25519, key compiled in with `--signing-pubkey`). Unsigned: `PING`, `VERSIONS[_DETAIL]`, `CAS_CHECK`, `CAS_PUT`, `GET_EPOCH`, batches, `PINS`, `COMPACT`. | `runtime/march_reload.c:3-108`, `:1526-2440`, `:144-174` |
| In-process access to the reload server | None. The only March-callable reload builtins are the stdlib-only `epoch_*` ones. There is no Unix-socket client in the stdlib. | `lib/typecheck/typecheck_env.ml:1638-1646` |
| Host-persisted state | A signed patch stack, manifest and topology under `<cas_root>/hcr_state/<hash of socket path>/`, re-verified and replayed before `main` opens offers. | `runtime/march_reload.c:263-298`, `:1029-1204` |
| Node certificates | `Cert { node, roles, flags, not_after, issuer, pubkey, serial }`, SPIFFE-style names, one operator key, no chain. Revocations are operator-signed and gossiped. Rotation needs a restart. | `stdlib/node_cert.march:21-37`, `:198-208`; `stdlib/cluster_node.march:179-249`, `:458-495` |
| Role authorization | `SessionAP.authorize(cert, proto, role, mode)` gates offering, being offered to, and initiating. An agent certificate that lacks `Ctl.Control:*` already cannot play `Control`. | `stdlib/session_ap.march:49-56`; `stdlib/session_node.march:2510`, `:2742`, `:2819` |
| Coordination | No lease, lock or consensus. GlobalRegistry is a CRDT (vector clock, higher node id wins ties). `count = 1` placement is rendezvous hashing over SWIM membership and is documented as "not a lock". | `stdlib/global_registry.march:1-58`; `stdlib/topology.march:14-30`, `:233`, `:372` |
| Long-lived, hosted protocols | Work today: `loop` protocols, `offer_hosted`, drains at loop boundaries (`Ok(Drained(n))`). No infrastructure uses a protocol yet; SWIM, registry sync and revocations use raw control frames. | `test/two_node/stream`, `hosted`, `cluster_ap_hosted*`; `stdlib/cluster_node.march:270-290` |
| Audit log | Written only on the host by the runtime (activate, restore, topology). `DRAIN` is not audited. Forge keeps no audit log. | `runtime/march_reload.c:552-597` |
| Remote CAS for ephemeral hosts | Specified, not built. | parent plan 6.5 |

## 2. What the code changes about the sketch

**2.1 Signed messages can be replayed (P1, and a prerequisite).** No signed verb carries a
nonce or sequence number, and the node does not check that an epoch is fresh:
`march_epoch_next` returns `max(requested, current+1)` (`runtime/march_dispatch.c:643-646`).
So an old signed `ACTIVATE` can roll a function back, an old `TOPOLOGY` can be pushed again,
and a `DRAIN` can be replayed for any old epoch. Today that is contained, because the socket
is only reachable with the node's uid. Once signed requests travel through a control plane
over the network, every relay and every recorded frame is a replay source. Step 12 cannot
ship until the node rejects stale signed requests (section 5).

**2.2 The topology the node applies is not the one it verifies.** The `TOPOLOGY` verb checks
the signature and stores the file, but its hook `march_hcr_on_topology` is a no-op
(`runtime/march_reload.c:893-895`). The node actually applies an unsigned JSON digest that
forge writes over ssh, then signals with SIGHUP (`forge/lib/reconcile.ml:546-575`,
`stdlib/topology.march:698-740`). Over ssh that "rides on ssh's own authority" (step-10
progress entry). Without ssh it is simply unauthenticated. The signed verb has to become
the one that applies (also listed in `2026-09-25-dd-step10b-followups.md`).

**2.3 "Reuse `reconcile.ml` with a `cluster` backend" doesn't work as written.**
`reconcile.ml` is OCaml inside forge. The leader is a March node playing the `Control` role.
The leader can't run forge's OCaml, and forge's deploy logic isn't in `apply_pass` anyway
(section 1). So the work splits:
- **forge keeps everything that needs the compiler:** building patches, classifying the
  change (`Deploy_plan.classify`), the capability gates, choosing the rollout.
- **The leader runs a small executor in March** that carries out a rollout forge already
  decided and signed (section 4).
- **forge's `cluster` backend** becomes a client of the leader, not a reconciler.

**2.4 An Agent can't call the reload server from March.** There is no in-process API and no
Unix-socket client in the stdlib. Section 6 adds one stdlib-only builtin that hands a
request line to the same C code the socket runs.

**2.5 Artifacts shouldn't travel inside protocol messages.** Session payloads are
`derive Json` values over `List(Int)` framing (`stdlib/net_frame.march`). A 1 MB patch `.so`
as a JSON byte list would cost tens of MB of allocation per node. Messages should carry
content hashes, and bytes should move over a separate chunked fetch (section 7). This is
reasoned from the representation, not measured; a quick measurement belongs in 12a.

## 3. The shape of the design

The central proposal: **the control plane holds no root keys and authors nothing.** Every
change is a *release*, written and signed by the operator's deploy key where forge runs (a
laptop or CI). The control plane stores releases, hands them to agents in the order the
release says, and reports what happened. Nodes verify every release themselves.

```
 operator / CI                    cluster
 ┌──────────────┐  signed release  ┌───────────────────────┐   Ctl sessions   ┌──────────────┐
 │ forge deploy │ ───────────────▶ │ Control (the leader)  │ ◀──────────────▶ │ Agent, node 1│
 │  builds,     │  artifacts (CAS) │  executes the rollout │                  ├──────────────┤
 │  classifies, │ ◀─── status ──── │  stores releases,     │ ◀──────────────▶ │ Agent, node 2│
 │  signs       │                  │  serves artifacts     │                  ├──────────────┤
 └──────────────┘                  └───────────────────────┘ ◀──────────────▶ │ Agent, node n│
                                     standby Control nodes                    └──────────────┘
                                     hold copies of releases        each Agent relays to its
                                                                    node's reload server, which
                                                                    verifies the signature
```

What this buys:
- **A compromised control-plane node can delay or withhold changes, but can't forge them.**
  The parent plan called the control plane "the most sensitive component" because it held
  the keys. With this design it holds none, so that concern goes away.
- **Correctness doesn't need consensus.** The operator is the only writer of releases, and
  releases are totally ordered by a signed sequence number (section 5). A leader lease then
  only prevents wasted or duelling work; it isn't what keeps the cluster correct.
  That matches what exists: nothing in the stdlib can provide a safe lease anyway.
- **The parent plan's invariants hold by construction.** The control plane is never on the
  data path. Nodes still place their own roles (D16, D19). If the control plane is down,
  only changes stop.

## 4. Releases and the rollout executor

A release is one signed document, content-addressed like everything else:

```
release v1
seq      42
parent   <digest of release 41>
env      prod
topology <blake3 of topology digest>
build    web     base:<hash> manifest:<hash>
build    render  base:<hash> manifest:<hash>
step 1   pools:render  hosts:canary(1)  do:activate(render)  gate:healthy(60s)
step 2   pools:render  hosts:rest       do:activate(render)  gate:healthy(30s)
step 3   pools:*       hosts:all        do:topology
drain    epoch<=41  soft:30000 hard:120000
sig      <ed25519 over everything above>
```

- **Everything in a release is decided by forge.** That covers the classification, the
  expand/contract split (a D21 split becomes two releases), the order (receivers of a
  choice before its chooser), canary counts and gates, and drain deadlines. `--plan` prints
  exactly the release it would sign.
- **The executor is level-triggered.** Its state is "the newest release I hold" plus "what
  each agent reports". Each pass finds the first step whose target nodes don't yet report
  the step done, and applies that step to the next nodes it allows. So a new leader resumes
  a half-finished rollout from observation alone, with nothing to hand over. A gate whose
  window was in progress restarts its window on a new leader; that's conservative and
  correct.
- **The executor is small March code** in a new `stdlib/control.march`: parse and check a
  release, match steps against reports, pick hosts. It doesn't build, classify or sign.
- **A failed gate halts the release** and reports it. The executor never rolls back on its
  own. Rolling back is a new release (the previous version deployed forward, as the parent
  plan already says), which only the operator can sign.
- **Restart-class steps** (runtime change, hook change, compaction) are the one thing an
  agent can't do to its own process. See section 8.

## 5. Replay protection and ordering (prerequisite, lands first)

- **Every signed request names a release:** `seq` and `parent` go into each signed message
  (a new `ACTIVATE7`, plus `TOPOLOGY2` and `DRAIN2`, or a single `RELEASE` envelope verb
  whose signature covers the items it contains). The node keeps the highest `seq` it has
  applied in its hcr state file, alongside the patch stack it already persists.
- **The node refuses:**
  - any `seq` lower than its highest;
  - a new `seq` whose `parent` isn't the release it holds. That is a fork: two operators
    each signed a release 43. The node reports it and changes nothing.
  - re-applying the same `seq` is allowed and does nothing, which gives retries for free.
- **Replay after a restart** checks the same rule against the persisted `seq`.
- **The old unsequenced verbs stay for the ssh path**, since ssh already implies uid-level
  access. A node started in control-plane mode (`MARCH_HCR_REQUIRE_RELEASE=1`, set by
  `forge host init --control-plane`) refuses them.
- **Two operators racing.** forge sends release 43 with `parent = 42`. The leader accepts it
  only if 42 is its head (compare-and-set). The loser gets "stale parent; re-plan from
  release 43", the way `git push` refuses a non-fast-forward.

This fixes the replay gap on the ssh path too, whenever that path opts in.

## 6. The Agent

- **Every node runs the Agent role.** The generated `main` offers it whenever the topology
  has a `[control]` section. No pool configuration is needed.
- **One new stdlib-only builtin, `reload_request(line : String) : String`,** runs a request
  line through the same C dispatch the socket uses and returns the response. It has to be
  a refactor of the socket loop into a function the loop and the builtin both call, not a
  second implementation. It is gated to `stdlib/control.march` with the G3 mechanism.
- **The Agent needs no authority of its own.** It relays operator-signed lines, and the C
  code verifies them exactly as it does for socket requests. A compromised Agent can refuse
  or delay, which a compromised node can do anyway. Its capabilities are to fetch
  artifacts (`CAS_PUT` through the same builtin) and to read status.
- **Topology through the signed path:** `march_hcr_on_topology` stops being a no-op and
  calls into `Topology.reload` with the verified file (2.2). The unsigned SIGHUP path
  remains for the `local` backend only.
- **What the Agent reports:** the status file's contents (offers, draining, running), plus
  `VERSIONS_DETAIL` and `PINS`, the highest applied `seq`, and the result of the last step
  applied. The parent plan wanted live sessions per fingerprint and drain progress per
  offer; nothing exposes those today, so 12a adds them to `Topology.write_status`.

## 7. The `Ctl` protocol

```march
@[endpoints]
protocol Ctl do
  role Agent   needs IO.NetConnect
  role Control needs IO.NetConnect, IO.FileWrite    -- stores releases and artifacts
  hello: Agent -> Control : AgentReport
  loop do
    choose by Control:
      apply ->
        step:   Control -> Agent : StepOrder        -- release seq + step id + items
        result: Agent -> Control : StepResult
      observe ->
        poll:   Control -> Agent : Unit
        report: Agent -> Control : AgentReport
      bye -> stop
  end
end
```

- **The Agent initiates; `Control` is offered only by the leader.** That makes the offer
  itself the discovery mechanism. An agent finds the leader by initiating a session, and
  when the leader changes, the session fails through its crash branch and the agent starts
  a new one with whoever offers now. No leader address is ever configured.
- **Every step is labelled** (D25), because the control protocol is the one protocol that
  must evolve across deploys of itself. A deploy of control-plane code drains `Ctl`
  sessions at their loop boundary (D27), and agents reconnect. Changing `Ctl` itself goes
  through step 9's compatibility table like any other protocol.
- **`StepOrder` carries hashes, not bytes.** The Agent checks `CAS_CHECK` for each hash and
  fetches what's missing with a chunked `CtlFetch` protocol (`want: Agent -> Control : Hash`
  then a loop of fixed-size `chunk` messages) from the leader or any standby. The chunk size
  comes from the 12a measurement. The same fetch answers the parent plan's open question
  about where ephemeral hosts pull from when there's no external store: from the control
  plane.
- **Certificates:** agent certificates carry `Ctl.Agent:initiate`. Control-candidate nodes
  also carry `Ctl.Control:offer`. Existing `authorize` checks enforce both, so no new
  mechanism is needed (section 1).

## 8. Leader, standbys, and what "lease" means here

- **Placement picks the leader.** The topology's `[control]` section names candidates by
  label and becomes an ordinary role binding: `Ctl.Control` with
  `place = { on = "control", count = 1 }`. Rendezvous hashing over SWIM membership (D19)
  chooses the leader, with the existing rejoin settling period. That is the "lease", and
  it's built entirely from existing parts.
- **It isn't a lock, and it doesn't need to be.** During a partition, both sides can have a
  leader. Neither can author anything. Each drives its side toward the newest release it
  holds, nodes refuse anything older than they already hold, and a fork is refused (section
  5). What a split brain can break is rollout *policy*: two leaders can each advance
  different nodes, so a canary gate may be skipped on one side. The design says so plainly.
  An operator who needs a strict single leader can plug in an external lease (etcd,
  Consul, a Kubernetes `Lease`) as a later backend.
- **Releases are durable before forge is told "accepted".** The leader stores each release
  and its artifacts, copies them to every reachable candidate, and only then answers
  forge. A new leader takes the highest valid `seq` among candidates and agents. Since
  releases are signed, any copy is as good as any other.
- **Restart-class steps (settled as D38: option a).** An agent can't swap its own
  process's base binary without process authority. Two options:
  - **(a)** The release's restart steps still go through the process backend (ssh or k8s)
    that forge runs. The control plane covers hot deploys, topology and drains. `--plan`
    says which steps need the backend.
  - **(b)** Self-restart on systemd hosts. The agent fetches the new base into the CAS,
    points `current` at it in a directory it may write, and exits with a dedicated code.
    systemd restarts the unit, and a `ExecStartPre` selector boots `current`. This needs
    `IO.FileWrite` on one directory and an exit, and `forge host init --control-plane`
    generates the unit.

  12a does (a); (b) stays optional in 12c, if restarts turn out to be common.

## 9. forge's side

- **The `cluster` backend** in forge is a client of the control API: a TCP listener on the
  leader and on standbys, speaking the same line protocol as the reload socket plus three
  verbs:
  - `RELEASE <sig> <size>` followed by the release body (compare-and-set on `parent`);
  - `STATUS` returns the executor's view: head release, current step, per-node reports;
  - `CAS_PUT` and `CAS_CHECK` for artifacts, as today.

  Reusing the reload-socket client in `cmd_deploy_hot.ml` keeps the forge change small.
  Standbys forward `RELEASE` to the leader, so forge can talk to any candidate.
- **Reads are not confidential** (D4 defers confidentiality). The control port should
  still be reachable only from the operator's network: `forge topology gen` emits the
  firewall rule, like the cluster port today.
- **`forge deploy --env prod` in cluster mode:** build, classify, write the release, sign
  it, upload missing artifacts, send `RELEASE`, then follow `STATUS` until the release
  completes or halts. The reconciler's local lock stays for the ssh path; in cluster mode
  compare-and-set on `parent` replaces it.
- **Audit:** the leader appends every release it accepts and every step it orders to an
  audit log on the candidates. Nodes audit each applied release, including drains, which
  today aren't audited at all.

## 10. Staging

**12-pre: node-side hardening.** Useful on its own, even without a control plane.
- Sequenced, parent-linked signed requests, with fork refusal and persisted `seq` (section 5).
- The signed `TOPOLOGY` actually applies (`march_hcr_on_topology` calls `Topology.reload`).
- `DRAIN` writes an audit line.

*Acceptance:*
- Replaying any recorded signed line after a newer release is refused, including after a
  restart.
- Two releases with the same `seq` and different content: the second is refused and
  reported.
- A topology changed on disk without a signature is never applied in `REQUIRE_RELEASE` mode.

**12a: control plane for hot deploys.**
- `reload_request` (refactoring the socket loop into a shared function).
- `stdlib/control.march`: the release parser, the executor and the Agent.
- The `Ctl` and `CtlFetch` protocols.
- The `[control]` topology section.
- The control API listener.
- forge's `cluster` backend.
- Status per fingerprint and per offer.
- The chunk-size measurement.

*Acceptance* (a two-node scenario in `test/two_node/`, plus one `forge test --upgrade-from`
fixture):
- `forge deploy` sends a hot release with no ssh, and every node reaches it.
- Killing the leader mid-rollout: a standby takes over and the release either completes or
  halts with a report. No node applies a step twice, and none is skipped.
- A partition during a rollout: both sides converge on the same release after healing, and
  the report shows any gate that was skipped.
- An agent node with a certificate lacking `Ctl.Control:offer` cannot become leader.

**12b: certificate distribution and live rotation** (D39: issuance stays offline).
- Live certificate replacement: `ClusterOps.replace_cert`. Existing links re-handshake
  before the old certificate expires.
- The control plane distributes operator-issued certificates and revocations to agents, as
  signed items in a release.
- Deferred, not rejected: a control-plane issuer certificate limited to a set of roles
  (never `Ctl.Control`), minting short-lived node certificates, and enrollment of new nodes
  with a one-time join token. That would be the one key the control plane holds.

**12c (optional): self-restart on systemd hosts** (8, option b), and an external lease
backend.

## 11. Decisions (settled 2026-09-28)

| # | Decision | Consequence |
|---|---|---|
| D37 | **The control plane holds no root keys.** Every change is a release written and signed by the operator's deploy key where forge runs; the control plane stores and executes releases, and nodes verify them (section 3). | Replaces the parent plan's "the control plane holds the signing keys" (section 5 there). A compromised control-plane node can delay changes, not forge them. |
| D38 | **Restart-class steps go through the process backend** (ssh, or whatever backend the environment uses), run by forge. The control plane covers hot deploys, topology pushes and drains (section 8, option a). | `--plan` marks which steps need the backend. Self-restart (option b) stays in 12c, optional. |
| D39 | **Certificate issuance stays offline** with the operator (`forge cluster cert`), for now. The control plane holds no issuer key. | 12b shrinks to distributing operator-issued certificates and revocations, plus live certificate replacement on nodes. Rotation needs the operator or CI to issue; the control plane only delivers. The chained issuer design in section 10 is deferred, not rejected. |
| D40 | **The leader is `count = 1` placement over SWIM, with no strict lease,** for now. A partition can give each side a leader, and a canary gate can be skipped on one side; releases stay correct because nodes enforce sequence and parent (section 5). | An external lease backend (etcd, Consul, a Kubernetes `Lease`) stays in 12c for fleets that need a strict single leader. |
| D41 | **12-pre lands now,** ahead of the rest of step 12. | The replay gap is closed on the ssh path too, where it exists today. |

## 12. Open questions (not blocking the decisions)

- The size of the control API and the artifact fetch at fleet scale. A leader serving every
  artifact to 100 nodes may want agents fetching from each other.
- Whether the executor's step matching needs per-step idempotency keys beyond `(seq, step)`.
- How `forge topology status` and a future `forge status` present a halted release.
- Whether a node in control-plane mode should still accept an ssh-path deploy in an
  emergency (break-glass), and how that is recorded.
