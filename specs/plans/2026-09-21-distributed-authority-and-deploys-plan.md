# Choreography, distribution, capabilities and deploys: one design

**Date:** 2026-09-21
**Status:** Design agreed in discussion; nothing here is built yet
**Related:** [specs/lang/choreography.md](../lang/choreography.md),
[specs/lang/capabilities.md](../lang/capabilities.md),
[specs/lang/clustering.md](../lang/clustering.md),
[docs/hot-code-reload.md](../../docs/hot-code-reload.md),
`specs/plans/archive/2026-06-25-hcr-phase7-fleet-spec.md`,
`specs/plans/archive/2026-06-25-hcr-phase5c-capability-safe-deploys.md`

This plan records how four systems should fit together: choreography (`@[endpoints]`
protocols), distribution (ClusterNode), capabilities, and deploys (hot reload and
topology). Each was built around a different unit. Choreography reasons about the
**role**, capabilities about the **module** and the **program** (`main`'s grant),
distribution about the **node**, and deploys about the **function**. None of them knows
about the others' unit, and most of the design below lives in that gap.

## Terms

| Term | Meaning here |
|---|---|
| **role** | One party of an `@[endpoints]` protocol, named `Protocol.Role` (`Checkout.Ledger`). |
| **offer** | A node making a role available for sessions (an *access-point offer*, `offer_R`). Not the session-type sense; for that this plan says *receiving a choice*. |
| **initiate** | Starting a session by inviting offers of the other roles (`initiate_R`). |
| **node** | One running March process that is a cluster member (a ClusterNode). |
| **host** | The machine or container a node runs on. |
| **pool** | A placement group in the topology: which roles its nodes serve, with what capabilities. |
| **build** | A compiled binary. Several pools may share one build; an isolated pool has its own. |
| **hook** | A pool's hand-written startup function (`start`), called by the generated `main`. |
| **epoch** | A code version, numbered per deploy. Units of work pin one (6.1). |
| **drain** | Retiring an epoch or an offer: a soft deadline, then a hard one (6.2). |

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Actors follow the **object-capability model**: holding a reference is authority, and authority is charged to whoever spawns an actor. A role body that messages a more powerful local actor it was handed is *delegating*, not violating its grant. | It matches the existing rule that the grant charges a spawned actor to its spawner. Tracking capabilities through message flow would be an effect system, and per-function grants were already rejected (capabilities.md, "stage C"). |
| D2 | One executable may serve **several roles**. Authority is bounded **per role**, not only per program. | Real services handle several kinds of request. `main`'s grant alone is the union of all of them. |
| D3 | **Segregated permissions within a cluster.** Code that needs `IO.Foreign` can be isolated on its own node, with no authority beyond its roles. | An `extern` makes a process unverifiable, so the boundary has to be the node. |
| D4 | **Link encryption and confidentiality are deferred.** The threat model for now is a misbehaving *member* on a trusted network. | Keeps scope down. Per-frame integrity (below) is the part segregation actually depends on. |
| D5 | **Protocol changes must be hot-deployable**, with a bounded drain so old code cannot run for ever. | Hot reload is the everyday production path (D8). |
| D6 | Topology is a **data file**, checked by the compiler, exported as JSON for other tools. | Operators and tools edit it; environments are overlays. |
| D7 | The topology format **leaves room for role sets** (one role played by a set of nodes), though protocols cannot express them yet. | Scatter/gather over "all workers" will come (census polymorphism in MultiChor). |
| D8 | **Option B:** March owns *code* orchestration (which version of which role runs where, offers, drains, certificates) and delegates *process* orchestration (machines, restarts, scaling) to Kubernetes, systemd, Nomad and the like. Hot reload is the everyday path and must be good. | The BEAM never owned machines either. Plain generators (option A) collide with immutable pods: the pod spec and the running code drift apart and a restart reverts a deploy. |
| D9 | **Level 0 first:** `forge run` runs every pool of a topology in one process. | Without it there is no easy path for development and tests. |
| D10 | Messages queued before a code switch **run on the old code**. At the soft deadline, whatever is left is **converted by `migrate_msg`** if the actor has one, and dropped and reported otherwise. | Running old messages through new code on old state is unsound (see "Bugs found"). |
| D11 | Two drain deadlines: **soft** (stop taking new work, let current work finish), then **hard** (kill; a supervisor restarts on the new code). | The BEAM's purge, but predictable, reported, and a last resort. |
| D12 | **One model for actors, sessions and tasks:** every unit of work pins an epoch when it starts; calls resolve against that epoch; a drain retires epochs. | Replaces three special cases with one rule. |
| D13 | 2–3 live code versions per slot is enough, provided drains guarantee retirement. | Today's limit is 2 (`MARCH_MAX_LIVE_VERSIONS`, runtime/march_dispatch.h). |
| D14 | A **closure received as a value** (in a message, or captured) is delegated authority, charged to the code that created it, not to the role or actor that calls it. | The consistent reading of D1: a closure is a capability like a pid. Charging it to the caller would be stricter than D1 for pids; charging it to nobody would be a hole. |
| D15 | In a topology app, **`main` is always generated**; hand-written startup is a pool **hook** (`start`) the generated `main` calls. A hand-written `main` is an escape hatch. | Level 0 must combine every pool into one process, and two hand-written `main`s cannot be combined. Drain, re-offering and health reporting come out right every time. |
| D16 | **Offers are declared in the topology, and each node opens its own** from the topology it was given, never from user code in a topology app. The reconciler distributes the topology; it never opens or closes an offer itself. `initiate_R` stays in user code. | `main` runs once, so offers must not live in code. With one decider per node there is nothing to fight over, and it works with no control plane at all. Initiating is application logic. |
| D17 | A hook passes resources to role bodies by **returning an environment record**, which the generated code hands to each body as its first argument. | Simple and explicit. Dependency injection was the alternative: more magic, more to design. |
| D18 | **A role with no placement rule is offered on every node** of the pools that serve it. | The simplest replicated monolith is then just `[roles]` plus a host list. |
| D19 | **`count = n` placement uses rendezvous hashing over SWIM membership,** computed by every node for itself. `count = 1` is not a lock. | Every node agrees without a control plane, so a role moves off a dead node once SWIM declares it dead, even when the reconciler is `forge` on a laptop. Offers tolerate a brief duplicate, as global names already do. |
| D20 | **A pool's hook runs on every node of the pool,** so a role's environment exists wherever the role is placed. | Placement can move a role between nodes at run time; its bodies need their `Env` wherever they land. |
| D21 | **In a monolith, a compatible protocol change becomes two deploys (expand/contract),** and `forge deploy --plan` splits it automatically. | Every node upgrades a choice's receivers and its chooser together, so "receivers before chooser" cannot happen within one deploy. |
| D22 | **In the topology, anything omitted is derived; anything written is an upper limit.** A pool's `caps` and `initiates` default to what its code reaches, shown by `--plan` and `export`; writing them makes the check enforce them. | The same rule as `needs`. A first topology is then just `[roles]` plus hosts. |
| D23 | **Stateful roles are bound to an actor in `[roles]`** (`actor = "..."`). The generated code spawns it with the hook's `Env` as its `init` argument (D24) and generates its start, deliver and cancel callbacks. | D16 forbids user code from calling `offer_hosted_R`, and stateful roles are the common case. |
| D24 | **An actor's `init` can take parameters,** supplied at `spawn`: `init(env : Quotes.Env) { ... }`. A language change, useful beyond topology apps. | Handing `Env` over as a first message would leave every such actor with an "uninitialised" state that each handler must cope with. |
| D25 | **Unlabelled steps are a warning in any protocol a topology app uses.** | Positional names (`Msg_A_C_2`) renumber when a step is added before them, which changes their wire tags (6.4). The warning moves the problem to when the protocol is written, not when it is deployed. |
| D26 | **A derived capability that widens goes through the existing monotonicity gate:** the deploy stops unless `--grant-cap` authorizes it, and `forge build` and `--plan` warn about it. | Otherwise D22's "derived" would mean authority can grow silently with a code change. |
| D27 | **Sessions drain automatically at loop iteration boundaries by default;** a role can override with a drain handler, and a loop can opt out. | Draining should not depend on every protocol's author remembering to handle it. |
| D28 | **The nesting rule is implemented as epoch holds on the proc:** code that keeps older-epoch work alive (a session party, a parked endpoint) takes a hold; a held proc defers its marker until the last hold is released. | Sessions then pin their epoch through the ordinary actor model (their Endpoint actor is held), instead of a session-specific mechanism (II.4.4). |
| D29 | **Message stamps live on the runtime's mailbox node, in every build.** | The March heap header has no free word, and the mailbox node is runtime-owned: four bytes per queued message, no ABI change, no wire cost. Supersedes "only hot-reload builds carry stamps" (II.4.5). |
| D30 | **An actor advances early when it dequeues a message from a newer epoch and its message schema changed at that epoch.** | A sender that has already advanced can put a new-format message ahead of the receiver's marker; migrating at that point keeps FIFO order and reuses the `migrate_msg` path for the old-format messages behind it (II.4.6). |
| D31 | **Unforgeability is a proof capability, `Actor.Introspect`, minted from `Cap(IO)`**, not a new IO lattice node. | The ceiling check charges stdlib-mediated calls to the caller, so an IO cap on `cluster_node` would be charged to every program; proof caps already have "only the declaring module mints" semantics (II.1). |
| D32 | **Units are pinned per epoch, separately from per-call `refs`; three live versions per slot; an activation that cannot reclaim a slot waits instead of failing.** | `refs` is what makes `dlclose` safe and must stay per call; the hard deadline bounds the wait (II.4.2). |
| D33 | **Boundary calls resolve against the running proc's epoch** (`march_dispatch_enter_unit`), in the base binary and in every `.so` alike; the per-`.so` epoch global is retired. | Today's split (per-`.so` for patched code, current for the base binary and the actor loop) is exactly what D12 replaces (II.4.1). |
| D34 | **Role grants are passed as values:** the generated body type carries one `Cap(P)` parameter per cap in `role R needs …`, narrowed by the runner. | The check becomes `main`'s check from another root; the composition root is explicit from `main` to every actor; tests substitute dictionaries (section 7). |
| D35 | **`ClusterHandle` becomes `Cap(ClusterNode.Live)` with an `Ops` dictionary.** (Landed 2026-09-23; the plan first wrote `Cluster.Live`, but `mod Cluster` is the unrelated address-discovery module and only the declaring module may mint.) | Placement, membership reactions and access points become unit-testable by injecting membership events, with no sockets (7.2). |
| D36 | **The generator emits a scripted peer and a chaos peer per role,** derived from the local type. | The protocol is its own test oracle; crash branches, cancellation and drains get property tests instead of only hand-written two-node scenarios (7.2). |

## 1. References are unforgeable (object capabilities)

D1 only holds if references cannot be manufactured. Today they can:

- `pid_of_int : Int -> Pid(a)` is a public builtin (lib/typecheck/typecheck_builtins.ml),
  polymorphic in the message type, so it forges a pid *and* picks its protocol.
- `Actor.list()` returns every live actor in the process (stdlib/actor.march).
- `Actor.register`, `Actor.whereis` and `Actor.registered` (stdlib/actor.march) are a
  process-wide name registry: any code can look up any registered actor by name.
- `GlobalPid.make(node, pid, creation)` builds a cross-node address from plain values, and
  `GlobalRegistry.lookup` hands out any registered name. Both are ambient authority.

**Change:** forging and enumeration become privileged. They move behind a capability
(working name `IO.Introspect`) that the runtime, the stdlib's cluster internals and
debugging tools hold and ordinary user code does not. The local name registry needs the
same treatment: either lookups are privileged, or a name is registered in a scope and only
code handed that scope can resolve it. Cross-node references are handed out, not computed;
under segregation (section 3) the global registry is permissioned.

**This is a breaking change.** `stdlib/cluster_node.march` alone calls `pid_of_int` about
ten times, and user code may too. The stdlib's diagnostic filter hides errors in stdlib
modules from programs that load them, so run `march --check stdlib/<mod>.march` on every
module touched rather than trusting a green program build.

## 2. Per-role grants

A protocol names what each role may do:

```march
@[endpoints]
protocol Checkout do
  role Client needs IO.NetConnect
  role Ledger needs IO.FileWrite, IO.NetConnect
  ...
end
```

**Where it is checked:** at every runner entry (`run_R`, `offer_R`, `cluster_R`,
`initiate_R`, `host_R`, `offer_hosted_R`, `cluster_hosted_R`). The existing grant walk
(reachability from `main`) starts at the body closure instead of at `main`. In a topology
app, where offers are generated (D16), the check runs on each `[roles]` binding: a body
function, or every handler of a bound actor (D23).

- **Callback bodies:** everything reachable from the closure, including captured functions,
  must sit under `grant(R)`.
- **Hosted actors:** every handler of an actor passed to a hosting runner is charged to R.
  An actor that hosts two roles must fit within both grants.
- **Shared helpers** are charged to every role that reaches them.
- **Delegation (D1, D14):** messaging a local actor the body holds a reference to is
  allowed, and so is calling a closure it received; both are charged to their creator.
- **Relation to `main`:** every role's grant must fit within `main`'s grant. The runner's
  own capabilities are charged to `main`, not to the role: `SessionNode` needs `IO.Mut`,
  `IO.NetConnect`, `IO.NetListen`, `IO.Process`, `IO.Spawn` and `Session.Live`, and the
  role grant covers only what the body reaches. In a topology app, `main` is generated and
  its grant includes those runtime needs (4.1).

**A role's grant bounds its code, not its authority.** Under D1, a role body that is handed
a pid to an actor with wider capabilities has that actor's authority. That is the
object-capability model working as intended, but a reader of `role Client needs
IO.NetConnect` would assume a narrow grant means narrow authority. So the compiler should
also produce an **effective-authority report**: for each runner call, the pids and closures
the body captures, and the capabilities of the actors and code behind them. That report is
what makes the object-capability model auditable. The effective authority of a role in a
multi-role binary is its grant plus whatever references `main` hands it.

**How strong it is:** inside one process the separation is static only; `forge cap run`
sees one process and can sandbox only the union. `IO.Foreign` removes it, as it already
cannot sit under a narrow `main` grant. Where an OS-enforced boundary is needed, split the
binary (section 4, `isolate`).

**In a replicated monolith (4.2) the static authority cannot be split at all:** every node
holds all the code, so the binary's grant, the OS sandbox and every node's capability
policy are the union of all roles, and every node receives every hot patch. Certificates
can still limit which roles a node may *offer* (runtime authority), but `role X needs ...`
does not sandbox a replicated monolith. When that matters, split the role into its own pool.

**Hot deploys:** a patch to a role body is checked against that role's grant in the
source, which is stronger than today's comparison with the previous version or with a
node's policy file.

## 3. Segregated permissions in a cluster

Today one HMAC secret admits a node, which can then invite any offer, register or look up
any name, and send to any global pid.

- **Identity:** each node has an ed25519 key and a certificate signed by an operator key,
  naming the node and its **role permissions** (`Checkout.Ledger: offer`,
  `Checkout.Client: initiate`). Use SPIFFE-style identities rather than inventing a
  format, so that a service mesh's mTLS can later provide the deferred encryption (D4).
  The deploy signing keys and the certificate-authority key should be separate, or the CA
  delegated to SPIRE.
- **Two-way checks when a session forms:** an offer checks that the initiator may play its
  role, and the initiator checks that every offering node may play the role it offers.
  Without the second check, a compromised node can offer `Ledger` and receive Ledger's
  messages.
- **Protocols bound reach:** a certificate says which conversations a node may join; the
  protocol, already type-checked, says what it may say in them. What a compromised node can
  reach is its roles' projections.
- **Raw primitives** (`Node.send`, `@[remote]`, `RemoteCall`, registry writes) are outside
  the protocol boundary. A certificate flag grants them; an `isolate`d node (D3) never gets
  it. Later: namespace registry names by permission and sign registrations.
- **Untrusted input:** the Foreign node's messages are untrusted by construction. Refinements
  on message types become a security boundary, not only a correctness one.
- **Revocation:** certificates expire; a revocation list is gossiped; sessions with a
  revoked node are cancelled through the existing cancellation path.
- **Threat model (D4):** authority, not availability. A member can still lie in SWIM
  gossip. The handshake authenticates a connection once and frames after it are not
  authenticated, so segregation holds against a member that speaks the protocol, not one
  that can inject into other nodes' connections. A per-frame MAC keyed from the handshake
  closes that without full encryption.

## 4. Topology

Four layers, each owned by someone different:

1. **Source (developers):** protocols, role grants, role code, pool hooks.
2. **Topology:** `topology.toml`. Its `[roles]` section (which function implements each
   offered role) belongs to the developers; its `[pool.*]` sections and environment
   overlays (placement, capabilities, isolation, public ports, drain bounds, hosts) belong
   to whoever operates the system.
3. **Derived facts (the compiler):** the connectivity graph (from the generated
   `peers_<Role>()`), each pool's capability closure and initiated roles (D22), certificate
   entries, node policy files, the builds. Exported by `forge topology export --json` under a versioned
   schema.
4. **Generators (plugins):** `forge topology gen <target>` runs a built-in generator or any
   `forge-topology-<target>` on PATH (the protoc plugin convention): Kubernetes manifests,
   NetworkPolicy, systemd units, docker-compose, SPIFFE registration entries.

The file has two kinds of section. `[roles]` is the application's wiring: which function
implements each offered role, and its default capacity. It changes with the code. `[pool.*]`
is placement: which pools serve and initiate which roles, with what capabilities. It
changes with the deployment.

```toml
# topology.toml
[roles]
"Checkout.Ledger" = { body = "Ledger.serve_one", capacity = 64 }
"Thumbs.Render"   = { body = "Render.render_one", capacity = 8 }
"Quotes.Server"   = { actor = "Quotes.ServerActor", capacity = 64 }   # stateful (D23)
# a table per role leaves room for role sets: `set = true` (D7)

[pool.edge]
start  = "Edge.start"                       # a pool hook (4.1)
public = [443]                              # the only ports open to the internet
# `initiates` and `caps` omitted: derived from what Edge's code reaches (D22)

[pool.ledger]
serves = ["Checkout.Ledger", "Quotes.Server"]
caps   = ["IO.FileWrite"]                   # written, so enforced as an upper limit

[pool.imaging]
serves  = ["Thumbs.Render"]
isolate = true                              # its own build, its own sandbox, no raw sends

[drain]
soft_ms = 30000
hard_ms = 120000
```

An **environment overlay** binds pools to machines and picks the process backend. With
the `ssh` backend there is no scheduling: you list the hosts, and a pool's replica count is
the length of its list. Other backends take `replicas` instead.

```toml
# topology.prod.toml
[backend]
kind = "ssh"

[pool.edge]
hosts = ["root@web-1"]

[pool.imaging]
hosts = ["root@render-1", "root@render-2"]
```

**Overlays merge** onto the base file: tables deep-merge, and an array in the overlay
replaces the base's array.

**Declare only what you want to constrain (D22).** A pool's `caps` and `initiates` are
derived from what its hook and roles reach when omitted; `forge deploy --plan` and
`forge topology export` show the derived values. Written, they become upper limits the
check enforces, as `needs` does for a module.

**Derived is not the same as unchecked (D26).** When a code change widens a pool's derived
capabilities (a helper starts calling `file_write`, say), `forge build` warns, `--plan`
marks the widening, and the deploy stops at the existing monotonicity gate unless
`--grant-cap IO.FileWrite` authorizes it. The same gate already guards hot deploys today;
D26 routes derived pool capabilities through it.

**`forge topology check`** runs automatically as part of `forge build`, `forge run` and
`forge deploy`, and its errors point into the TOML. It rejects: a served role with no
binding in `[roles]`; a binding whose function or actor does not exist or has the wrong
type; an offered role nobody serves; a role whose grant exceeds its pool's written `caps`;
a hook that reaches beyond them; code that initiates a role outside a written `initiates`;
an `IO.Foreign` role in a pool that is not isolated (when opted in); peers the network
policy would not let reach each other. Role and function names are strings in TOML, so the
LSP should offer go-to-definition and completion on them.

**Running locally:** `forge run` always runs every pool of the topology in **one process**
(D9), whatever the topology says about hosts. `forge run --processes` runs one local
process per pool, for multi-process testing. A program with no topology file keeps its
hand-written `main` and works exactly as today.

**Growing, one step at a time,** with no rewrite at any step: one pool on one host; more
hosts for that pool (the replicated monolith, 4.2); labels and counts to pin roles; more
pools when something needs its own binary (typically `isolate` for Foreign code); then
written `caps`, `isolate` and certificates. Placement stays in the topology throughout.

**Builds are separate from placement.** A pool says where roles run; which binary its
nodes run is a separate matter. Either one binary is shared by every non-isolated pool,
with the configuration choosing the pool at startup, or there is one build per pool. A
per-pool build is rooted at that pool's generated `main` (4.1), which reaches only the
pool's hook and roles, so dead-code elimination removes everything else. `isolate = true` forces a per-pool build: the Foreign
code, its `extern` blocks and its `--ffi-link` flags exist only in that binary. Isolated
roles are never in the shared binary.

**Public ports and firewalls:** `public` declares a pool's internet-facing ports. Together
with the connectivity graph, this gives each host's complete network policy: public ports
from anywhere, the cluster port only from the pools it talks to. Generators write it as
Kubernetes NetworkPolicy, cloud firewall rules (e.g. DigitalOcean), or `ufw` rules.

### 4.1 Entry points: `main` is generated, you write hooks (D15–D17)

A pool process does five things at startup: join the cluster; open offers for the roles
it serves; set up resources the roles use (a database pool, a cache actor); do work that is
not a role (an HTTP server, scheduled jobs, code that initiates sessions); and drain on
SIGTERM. The first, second and fifth are the same for every pool. The third and fourth are
the application.

**In a topology app, `main` is always generated (D15).** For each build it:
1. starts the ClusterNode from the environment;
2. runs each of its pools' `start` hooks, if any;
3. opens the offers its node is placed for, from the topology it was given (D16), spawning
   bound actors for stateful roles (D23);
4. installs drain on SIGTERM (soft, then hard deadline);
5. supervises all of it, re-offering after a restart.

Under `forge run`, the one generated `main` does this for every pool in one process. That is why
hand-written pool code must be a function the generated `main` calls, not a `main` of its
own: two hand-written `main`s cannot be combined into one process.

**A pool hook** is where hand-written startup lives:

```march
mod Edge do
  needs IO.NetListen, IO.NetConnect
  type Env = { cache : Pid(QuoteCache) }

  fn start(c : Cap(IO.NetListen), node : ClusterNode.ClusterHandle) : Env do
    let cache = spawn(QuoteCache)
    -- long-lived work runs in its own task; the hook must return
    let _ = task_spawn(fn _ -> Http.serve(c, 443, fn req -> handle(node, cache, req)))
    { cache: cache }
  end
end
```

**A hook must return promptly.** Offers open only after every hook has returned, so a hook
that blocks (serving HTTP inline, say) keeps its node from ever offering. Long-lived work
goes in a spawned task or actor, as above. The runtime reports a hook that has not returned
within a time limit, naming it.

**A pool's hook runs on every node of the pool (D20),** whichever roles that node is
currently offering, so a role's environment exists wherever placement puts it.

**Resources reach role bodies through the hook's return value (D17).** The hook returns an
environment record; the generated code passes it to every role body the pool serves:
`serve_one(env, s, st)`. A pool without a hook passes `()`. `forge topology check` checks
that each body's first parameter type matches its pool's hook return type. A body's third
parameter is the role's entry state; writing its generated name (`Fan_C.S_recv_Number`)
is unpleasant, so the `Entry` alias
(`specs/todos/2026-09-20-choreography-entry-state-alias.md`) becomes a prerequisite:
`serve_one(env : Ledger.Env, s : Cap(Session.Live), st : Checkout_Ledger.Entry)`.

**Stateful roles are bound to an actor (D23).** `{ actor = "Quotes.ServerActor" }` in
`[roles]` makes the generated code spawn one actor per offer on the node, that is per
(role, fingerprint) (one actor serving all of that offer's sessions, as `offer_hosted_R`
does today; during a protocol change the old and new fingerprints have one each, 6.1) and generate the
start, deliver and cancel callbacks that forward to it. The actor receives the pool's `Env`
through a parameterised `init` (D24):

```march
actor ServerActor do
  state { db : Pid(Db), sessions : LinearMap(String, Quotes_Server.Parked_Server) }
  init(env : Ledger.Env) { db: env.db, sessions: LinearMap.empty_string() }
  ...
end
```

`spawn(ServerActor, env)` supplies the argument; `forge topology check` checks that the
`init` parameter type matches the pool's hook return type. Because the generated code
spawns the actor, it is charged to the role (section 2), not to whoever wrote `main`.

**Offers are declarative, and each node owns its own (D16).** In a topology app, user code
never calls `offer_R`. Each node opens the offers the topology places on it, and
re-evaluates when the topology or the cluster's membership changes. The reconciler never
opens or closes an offer itself: it pushes a new topology, and nodes act on it. Changing a
capacity, adding a role to a pool or moving a role between pools therefore needs no code
change and no restart. `initiate_R` stays in user code, because initiating a session is
application logic.

**Hot reload of hooks:** a hook runs once, at startup. A deploy that changes a hook's code
is classified as a restart for that pool (6.8). Role bodies and everything else remain
hot-patchable.

**Capabilities:** a pool's `caps` bounds its *user code*: its hook and its role bindings.
The generated `main`'s grant is the union of its pools' `caps` plus what the runtime
itself needs (the runner and ClusterNode: `IO.Mut`, the network capabilities,
`IO.Process`, `IO.Spawn`, `Session.Live`), so the existing grant check still applies. Each
hook is checked against its own pool's `caps` (written or derived, D22), and each role
binding against its role's grant (section 2). In object-capability terms the
generated `main` is the *composition root*, the one place authority is handed out, and a
hook's `Env` is exactly what its roles receive. So the effective-authority report
(section 2) only has to look at hooks. A pool with no hook hands its roles nothing beyond
their declared grants: the strongest guarantee, and the right default for isolated pools.

**Escape hatch:** a pool may name a hand-written entry file, `main = "src/x_main.march"`.
It then gives up level-0 composition and runtime-owned offers, and `forge topology check`
warns about both.

### 4.2 The replicated monolith (D18–D21)

The same binary runs on N nodes, and every node has all the code. What differs is which
roles each node *offers*. D16 makes this work: offers are opened by the runtime, so a node's
roles are configuration applied to a running binary, not a property of its build.

A monolith is one pool, one hook, many roles, and a placement rule per role:

```toml
[roles]
"Checkout.Ledger" = { body = "Ledger.serve_one", place = { on = "db" } }
"Thumbs.Render"   = { body = "Render.render_one", capacity = 8, place = { count = 2 } }
"Reports.Nightly" = { body = "Reports.run", place = { count = 1 } }
# no `place`: offered on every node (D18)

[pool.app]
start  = "App.start"          # runs on every node (D20)
serves = "*"
public = [443]
# `caps` and `initiates` derived (D22)
```

```toml
# topology.prod.toml
[pool.app]
hosts = [
  { host = "root@vm-1", labels = ["public"] },
  { host = "root@vm-2", labels = ["db"] },
  "root@vm-3",
]
```

**Placement rules:**
- **None:** offered on every node of the pool (D18).
- **`on = "label"`:** offered on the nodes carrying that label.
- **`count = n`:** offered on n of the pool's live members, chosen by rendezvous hashing: a
  deterministic hash ranks the members for each role, and the top n offer it (D19). Every
  node computes this itself from the topology and SWIM's membership, so no control plane is
  needed. When SWIM declares a node dead (after its suspect timeout), membership changes
  and the next node in the ranking starts offering. `on` and `count` combine: `count` then
  ranks only the nodes carrying the label.
- **`count = 1` is not a lock.** During a partition each side can pick its own node. This is
  the same caveat as a global name: fine for offers, wrong for mutual exclusion, which is
  out of scope.
- **Losing a role is a drain, not a cut.** When membership changes so that a node no longer
  ranks for a role, it closes that offer under the drain deadlines (6.2); its running
  sessions finish.
- **Hysteresis against flapping.** A node that rejoins would otherwise reclaim its roles at
  once, and the node that stood in for it would drain, on every flap. A rejoined node
  counts in the ranking only after it has been up for a settling period.

**Prefer a local offer.** An initiator tries an offer on its own node first, then the
others in rendezvous order. An offer that is full refuses, and the initiator moves on;
initiators do not know other nodes' load today, so "least loaded" waits until offers
publish it. A local offer saves a network hop in the common case, and depends on the
level-0 prerequisite: two roles of one session on the same node.

**Protocol changes in a monolith (D21).** Every node upgrades all roles together, so the
rule "upgrade a choice's receivers before its chooser" (6.4) cannot happen within one
deploy. A compatible change becomes two deploys: first, receivers accept the new branch
while nothing chooses it; then choosers start choosing it. `forge deploy --plan` detects
this and splits the change. Breaking changes work as in 6.4: every node offers both
fingerprints while the deploy rolls through.

**Authority:** static authority cannot be split within a monolith (section 2); split a
pool out when it must be.

## 5. Code orchestration (option B)

- **Hosts** are long-lived. Each runs one build (the shared one, or its isolated pool's),
  whose base image changes only when the C runtime or the build's make-up changes. The
  platform keeps N of them alive. Role code versions are not in the pod spec, so nothing
  drifts.
- **The reconciler** takes desired state (the topology plus code versions, from git or a
  CAS hash, GitOps-style, so no consensus store) and observed state (from each node's
  agent: the reload server plus ClusterNode, reporting epochs, offers, live sessions per
  fingerprint, drain progress, pinned tasks). Each pass issues actions: hot-deploy a code
  hash, push a new topology, issue or revoke a certificate. It never opens or closes an
  offer or retires an epoch directly; nodes do that from the topology and code they hold
  (D16).
- **Every reconciler action is signed,** like today's `ACTIVATE`, and checked by the
  node's agent. Pushing a topology changes what a node offers, so an unsigned push would be
  a way around every other check.
- **At small scale the reconciler is `forge` itself,** run from a developer's machine: each
  `forge deploy` or `forge status` is one reconciliation pass over the backend (ssh for a
  few VMs). There is no daemon to run. The control plane running inside the cluster (build
  order step 12) is optional, for fleets where a person running `forge` is not enough.
- **Host setup:** `forge host init --env <env>` prepares each machine once: a `march` user
  and a directory for code and its applied-patch history, a systemd unit generated from
  the topology, the deploy public key, the cluster secret (until certificates exist), the
  node's capability policy, and its firewall rules (section 4).
- **Admission:** the existing node admission gate (`MARCH_DEPLOY_POLICY`) is too weak to
  enforce a pool's `caps` as it stands. It checks each *changed function's own*
  capabilities (its own body, not what it calls), as reported in a signed manifest, so a
  patch that calls an existing, more powerful helper passes. To enforce a pool's `caps`,
  the build computes each role's full capability closure (everything reachable), signs it
  into the manifest, and the gate checks that closure against a policy generated from the
  topology. The gate still authorizes a signed claim; it does not recompute effects.
- **Single writer:** GitOps removes the need for a consensus store, not for a single
  writer. Two reconcilers would issue conflicting actions, so the reconciler holds a leader
  lease (or runs as a guaranteed single instance).
- **Dogfooding:** the control connection is an `@[endpoints]` protocol, `Control ↔ Agent`.
  Agent certificates do not include `Control`.
- **Process backends are plugins:** `local` (spawns processes; this is the level-1
  launcher), `ssh` (replaces the fleet spec's hand-kept host lists), `k8s` (applies
  generated manifests), and third-party backends by the same convention.
- **Invariants:** the control plane is never on the data path (if it is down, only changes
  stop); it never schedules machines; it holds signing keys, so every action is audited
  (which also closes the open todo that the audit log records no capability data).
- **Later:** elastic pools in the style of FLAME: when initiators get `NoOffer` because
  every offer is full, the backend starts another host for the pool.

## 6. Hot reload as the everyday path

What made the BEAM's relups hard to use, and where March stands:

| Relup pain point | March |
|---|---|
| Upgrade instructions written by hand | Solved: content-hash diffing, and a changed signature must bring all its callers |
| Untyped, untested state migration | Typed, IO-free `migrate_state`, checked by `@invariant`. Testing is missing (below). |
| Two code versions; loading a third kills processes | Same limit (2) today, but publishing a third fails instead. Drains (6.2) are the missing purge; D32 raises the limit to 3 and makes a blocked activation wait. |
| Processes stuck in old code | An actor moves at its marker, which sits behind its queued messages (6.3); an actor with a deep queue or a held session (D28) stays old until the drain deadlines. Sessions and tasks need drains too. |
| Messages in flight in the old format | Decided: D10, with `migrate_msg` (6.3) |
| Conflicts with immutable infrastructure | The reconciler owns code versions; a restarted host restores its patches before offering (6.5) |
| Rollback untested | Rollback is deploying the previous version forward; a changed state schema needs a reverse migration or is refused |
| Nobody tests upgrades | `forge test --upgrade-from` (6.6) |

### 6.1 One model: every unit of work pins an epoch (D12)

- An **actor** pins an epoch and moves to the new one at its **marker**, a mailbox entry
  every deploy places behind whatever the actor already has queued (6.3, II.4.6). The
  marker carries `migrate_state` only when the actor's state schema changed; otherwise it
  is just the point where the actor's calls start resolving to new code. Messages ahead of
  the marker always run on the old code.
- A **session** pins the epoch it formed in, and keeps it until it ends.
- A **task** inherits the epoch of the code that spawned it, not the current one. A task
  spawned by an old handler runs old code.

Calls resolve against the unit's epoch, not the newest version and not the calling
`.so`'s epoch. This replaces today's split, where epoch-tagged dispatch applies per
calling `.so` and the actor loop always enters the current version. Cost: a per-unit epoch
read on every boundary call. Measure it with the Model B performance spike (6.7).

**Nesting rule: a unit cannot move past the oldest epoch held by the units it contains.**
The case that forces it: an actor hosting many sessions (a D23 actor binding, or
`offer_hosted_R` today) keeps each
session's parked endpoint in its state, a linear value typed by the protocol version the
session formed under. `migrate_state` cannot turn a half-finished old-protocol session into
a new-protocol one, so the actor cannot migrate while it hosts old sessions, and
new-protocol invitations cannot go to an actor still on old code. Consequences:

- An actor holding sessions from an older epoch reaches its marker only once they have
  ended; the soft and hard deadlines apply to those sessions first.
- For a hosted access point, a **protocol change spawns a new hosting actor** for the new
  fingerprint. The old actor keeps the old fingerprint's offer, closes it, drains its
  sessions, and exits.
- A deploy that changes only handler bodies, not the protocol, needs none of this: the
  sessions' types are unchanged.

### 6.2 Drains retire epochs (D11)

| Unit pinned to old code | Soft deadline | Hard deadline |
|---|---|---|
| Actor | finish the current handler; convert remaining old messages with `migrate_msg`, or drop and report them | kill; the supervisor restarts it on new code with `init` state. An unsupervised actor just dies, and its state is lost; the deploy reports it. |
| Session | end at the next loop iteration boundary through the drain handlers (automatic, D27), or finish | `Left("draining")`; peers can start a new session |
| Task | let it run | cancel; its supervisor restarts it if there is one |

When nothing pins an epoch, it is retired, and the versions only it used become
unloadable (they are `dlclose`d when a later publish reclaims their slot; II.4.2 has the
exact condition). A deploy that would need more live versions than D13 allows waits for the oldest
epoch to retire, and says so ("waiting on 3 sessions pinned to epoch 5, deadline 40s").

**Sessions drain automatically at loop boundaries (D27).** Every `loop` in a protocol is a
drain point by default. When any participant of a session is draining, the session ends
at the next iteration boundary:

1. The role that would receive the first message of the next iteration does not get it.
   The runner returns that message to its sender, marked undelivered, so no work is
   silently lost.
2. Every role ends at its current receive through a **drain handler**. The runner only
   has control between steps when it delivers a message, so this is the one place it can
   end a session without handing user code a state it did not expect; cancel handlers
   work at the same point for the same reason. Like a cancel handler, a drain handler gets
   no session state and finishes with a generated `drained(s, token)`.
3. `run_R` and the offer report the session as drained, which is a clean finish, not an
   error.

**Defaults and overrides:**
- **Default handler:** finish the session. A sender whose message came back undelivered
  is told so in the report.
- **Override per receive:** `recv_<Msg>_or_drain(s, st, on_msg, on_drain)`, following the
  existing `_or` convention for cancel handlers. The sender's handler receives the
  undelivered message, for example to requeue it elsewhere.
- **Opt out per loop:** `loop atomic do ... end` for a loop whose iterations must not be
  interrupted between them. Its sessions run until they end or are cut off at the hard
  deadline, and `forge deploy --plan` notes it when live sessions of that protocol exist.

Why not end the session at a `choose`: the generated `choose_*` functions return the next
state and the user's code carries on with it. Ending the session there would mean returning
a state the code does not expect, which the types cannot express.

### 6.3 Actor migration order and `migrate_msg` (D10)

For an actor whose state or message type changed:

1. At the switch, the migrate message goes into the mailbox as a **marker** (it already
   does; see "Bugs found").
2. Messages ahead of the marker run on the **old** handlers against the **old** state (the
   actor's pinned epoch).
3. At the marker: `migrate_state`, then the actor's epoch moves to the new version.
4. At the soft deadline: finish the current handler, convert whatever is still ahead of
   the marker with `migrate_msg` or drop and report it, then migrate.
5. At the hard deadline: kill; the supervisor restarts.

Messages carry a **type-version stamp**. An old-format message that arrives *after*
migration (from a sender still pinned to old code, or a node not yet upgraded) goes
through `migrate_msg` too, and is refused and reported only if there is none. So senders
do not have to finish draining before the actors they talk to migrate.

- **Remote messages:** today's `@remote` wire tag is the type's *name* (`Msgs.Ping`). A
  schema change keeps the name, so a decode can wrongly succeed. The stamp must include a
  schema hash, on the wire as well as locally.
- **Cost:** none worth measuring. The stamp is four bytes on the runtime's mailbox node,
  present in every build (D29, II.4.5); the message itself is untouched.

**When `migrate_msg` is needed:** adding a handler or changing a handler's body, no;
removing a handler or changing its parameter types, yes (or the deploy reports that those
messages will be dropped).

**Naming the old type:** an actor's message type is implicit in its `on` handlers, so the
old one exists nowhere in the new source. The tooling already keeps the previous version's
state schemas (`<name>_hot.so.schemas.json.prev`); it should keep handler signatures too,
and `forge deploy --plan` should generate a stub:

```march
-- generated from the running version's handler signatures
type CounterMsgV3 = Inc(Int) | Reset | SetLabel(String)

fn counter_migrate_msg(m : CounterMsgV3) : Option(CounterMsg) do
  match m do
    Inc(n)      -> Some(Inc(n))
    Reset       -> Some(Reset)
    SetLabel(_) -> None     -- dropped on purpose; reported as migrated-away
  end
end
```

Checked like `migrate_state`: IO-free, exhaustive, and the old type's hash must match what
is deployed.

**Naming the new type:** the stub's return type, `CounterMsg`, is not something March
source can name today; an actor's message type is implicit in its handlers. `migrate_msg`
needs a way to name it, for example `Counter.Msg`.

### 6.4 Protocol changes

"Offer" means two different things in this plan, so to be precise: an **access-point
offer** (`offer_R`) is a node making a role available to initiators; **receiving a
choice** is the session-type sense, a role taking whichever branch another role's `choose`
picks.

Three kinds of version change:
1. Same fingerprint: nothing to do.
2. Compatible: a mixed-version session is safe. To start with, only one change qualifies:
   **adding a branch to a `choose`, when every role that receives that choice runs the new
   version and the role that makes it still runs the old one.** An old chooser never picks
   the new branch; a new chooser could pick it towards an old receiver, which cannot
   handle it. So rollouts upgrade the receivers of a choice before its chooser. This has
   nothing to do with which role initiates the session.
3. Breaking: offer both fingerprints during the transition (one access-point offer per role
   *and fingerprint*, not per role), `close_offer` the old one with the drain bounds;
   sessions pinned to the old epoch finish or are cut off at the hard deadline.

**A mixed-version session has no single protocol version:** each role runs its own. So
session formation checks each role's version against the others, replacing exact
fingerprint equality. Subtyping for asynchronous multiparty sessions is undecidable in
general, so this stays a short list of allowed changes: the compiler emits, per protocol
version, a table of which (role, version) combinations are compatible, and formation checks
the combination it is about to create. The topology derives the rollout order from the
same table.

**Compatibility is about the wire, not only the structure.** An unlabelled step is named by
its position among messages between the same two roles (`Msg_A_C_2`), and the generated
codec is `derive Json`, which writes the constructor name as the tag
(lib/desugar/desugar_derive.ml). A new branch containing an unlabelled A→C message
renumbers every later A→C message, changing their wire tags, so a change the structural
rule calls compatible would break old peers. The compatibility table is therefore computed
over wire tags: a change is compatible only if every message both versions can exchange
keeps its tag. `forge deploy --plan` explains a failure by naming the renumbered messages
and suggesting labels, which pin tags.

**Unlabelled steps are a warning (D25)** in any protocol a topology app uses (one named in
`[roles]` or initiated by a pool's code). Labels pin wire tags, so a labelled protocol can
gain branches without renumbering anything. The warning names each unlabelled step and
suggests a label. Where one binary holds both the receivers and the chooser of a choice (a
replicated monolith, 4.2), that order cannot happen within one deploy, and the change is
split into two (D21).

**A session captures its protocol's code when it forms.** Old and new `Fan_C` are different
types and cannot be two versions of one thing chosen at run time. Checked: the generated
receive functions already pass the runner a *closure* (to `Session.suspend`), and
`try_decode` is called inside it (lib/desugar/desugar_endpoints.ml, `suspend_with`). The
runner never calls a decoder by name; it calls closures the role's own code created. So the
session's code is already handed over as values, and what remains is the resolution rule:
calls made inside those closures resolve against the session's pinned epoch, which is the
epoch of the party's Endpoint actor, held for the session's lifetime (D28, D33, II.4).

### 6.5 Hot deploys survive restarts

A restarted host restores the current version of its code **before opening any offers**.
Where it gets it depends on the backend:

- **Hosts with a lasting disk** (VMs with the `ssh` backend): each host persists its own
  applied state, its patch stack, the manifest of the last version deployed to it, and the
  last topology pushed to it, and restores all three at boot. This works even when the reconciler is `forge` on a laptop and
  nothing is running to pull from.
- **Ephemeral hosts** (Kubernetes pods, which get a fresh disk when rescheduled): the host
  pulls the current version from a remote content-addressed store (the fleet spec's third
  CAS tier, S3 or HTTPS) or from the in-cluster control plane. These backends require one
  of the two.

Either way the reconciler only *checks* a host's restored state on its next pass, and
corrects it if it differs from the desired state. Today drift is only detected, via
`baseline_impl_hash` per slot.

**Compaction:** a host that boots its base binary and then applies an ever-growing stack of
patches boots slowly and runs code no single build produced. When the stack gets long, the
reconciler rebuilds that build's base image from the current version and rolls its hosts
onto it.

### 6.6 Upgrade testing is a normal test

```bash
forge test --upgrade-from v1.4.0
```

Starts the level-1 local topology at the old version, drives traffic (live sessions,
stateful actors), hot-deploys the working tree, and checks: no unexpected session
failures, every `@invariant` holds on migrated state, drains finish within their bounds.
Also: capture actor state from a running old version and run the real migration on it.

### 6.7 Production performance

If hot reload is the everyday path, the hot-reloadable build is the production build.
Every call across a hot-swap boundary goes through `march_dispatch_enter`/`leave`, and
`--hot-reload` links the whole stdlib. Run the Model B Phase 0 spike
(`specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md`) early, together with the
per-unit epoch cost from 6.1. A large number changes the rest of this plan.

### 6.8 One command

`forge deploy` classifies each pool's change and picks the mechanism: hot patch; hot patch
with migration; hot patch with a protocol drain; rolling restart (the C runtime changed, a
pool hook changed (hooks run once, at startup; 4.1), or the change cannot be hot-patched).
The stdlib is March code and hot-patches like any other. A change to placement alone
(capacity, which pool serves a role) needs neither: the reconciler pushes the new topology
and nodes act on it (D16). Users never choose between "hot" and "restart".

**`--plan` is where users learn what a deploy will do,** so its output is part of the
design. Per pool and build, it shows:
- **what changed:** functions, actor state or message types, protocols (with fingerprints),
  placement, hooks;
- **the mechanism, and why:** "hot patch", "hot patch + migration (RenderCache: state
  changed, `migrate_state` found)", "restart (hook `Edge.start` changed)";
- **order and splits:** which pools go first and why (a choice's receivers before its
  chooser), and any expand/contract split into two deploys (D21);
- **drains:** which offers close, how many sessions are live on them, and the soft and hard
  deadlines;
- **what may be lost:** message types with no `migrate_msg` whose queued messages will be
  dropped, live sessions of protocols with `loop atomic` (or a long stretch with no loop)
  that will run to the hard deadline, unsupervised actors a hard deadline would kill;
- **authority:** any derived capability that widens, and the `--grant-cap` it needs (D26);
- **derived values** (D22): each pool's capabilities and initiated roles, marked where they
  changed since the last deploy.

### 6.9 Observability

Every node reports epochs per slot, sessions per fingerprint, drain progress, pinned tasks
and dropped or converted messages. `forge status` shows every pool. The audit log records
capabilities.

## 7. Capabilities as the seam (D34–D36)

Capabilities and choreography already share one mechanism, and the rest of this plan
should lean on it rather than build beside it. `Cap(Session.Live)` is a proof capability
whose dictionary *is* the transport: `Session.attach(io, ops)` is `cap_impl(mint_cap(io),
ops)` (stdlib/session.march:61-66), and every `Session.*` call dispatches through
`cap_dict`. So a role already runs as an effect whose handler is swappable at a binding
site, with the same `cap_impl`/`cap_dict`/`with_cap` machinery that mocks `IO.Console` in
a test build (capabilities.md, "Runtime dictionaries" and "Mocking an IO capability in
tests"). The principle: **a role is a capability boundary, and a session is an effect.**

### 7.1 Grants are values (D34)

`role R needs …` (section 2) is a static claim checked by the walk. Make it a value too:
the runner narrows the role's caps from the `Cap(IO)` it holds and passes them, so the
generated body type carries the grant:

```march
-- generated for `role Ledger needs IO.FileWrite, IO.NetConnect`
type Checkout_Ledger.Body =
  (Cap(Session.Live), Cap(IO.FileWrite), Cap(IO.NetConnect), Checkout_Ledger.Entry) -> Yield
```

with the caps in the order the `role` line lists them, after the session and before the
entry state (and after the pool `Env`, 4.1, in a topology app). Consequences:

- **The check is the existing one.** A body reaching `file_delete` fails the grant walk
  against its own `Cap` parameters, exactly as `main` does today; a body with the wrong
  parameter list does not typecheck against `run_R`. `check_role_grants` (II.2) reduces
  to "walk from the body with its parameters as the grant", which is `check_main_grant`
  with a different root, and the parser addition is all that is new. `Cap` types do NOT
  unify across the lattice (corrected 2026-09-22, see II.3: amplifying a cap is a type
  error), so the type and the walk each enforce it on their own; the parameters make the
  grant visible and give tests something to substitute.
- **The composition root is explicit end to end**: generated `main` → hook `Env` → role
  caps → actor `init(env)` (D24). Every role-bound actor receives its authority as values,
  so the interception limitation "an actor captures one cap at its spawn site"
  (capabilities.md, "What cannot be intercepted") never applies to it.
- **The fingerprint stays wire-only.** Grants change the body type, not the protocol
  (II.2 already keeps them out of `fingerprint_of`); two nodes with different grants still
  talk.
- **Effective authority** (section 2) is then mostly readable off the signature: the
  report only has to add what the `Env` and captured references carry.

### 7.2 Mocking parts of the system as effects

Three levels, one mechanism:

1. **A role's IO.** `with_cap(mock, fn _ -> serve_one(env, s, fw, nc, st))` with the
   dictionaries the test build derives (`cap_ops_empty`, `--emit-io-ops`). Exists today
   for the fully mockable caps (Console, Clock, Random, FileRead, FileWrite, NetConnect,
   TLS, WebSocket, Signal, FileSystem, Network); `IO.Mut` and polymorphic builtins are
   not interceptable, which is a known limit and unchanged here.
2. **A whole role, derived from the protocol (D36).** The projection gives every role's
   local type (`lty`, lib/desugar/desugar_endpoints.ml:64), so the generator can emit,
   per role, a **scripted peer** and a **chaos peer**:
   - `<P>_<R>.script(s, steps : List(<P>_<R>.Step))`: a body built from a list of
     expected receives and canned sends, where `Step` is a generated variant with one
     constructor per message the role sends or receives (`Send_Second(Int)`,
     `Expect_Verdict(Bool -> ())`) and one per choice; the script is checked against the
     state types when it runs and fails the test, not the session, on a mismatch.
   - `<P>_<R>.chaos(s, seed)`: a body that walks the local type taking every `choose`
     branch by the seed, sending arbitrary payloads (from the payload types' generators,
     which `Check` property tests already have), crashing at each `may crash` point when
     the seed says so, and draining at loop boundaries under D27. This is the property
     test for a protocol: run the real role against `chaos` peers over the in-process
     transport for N seeds. The crash-branch rules, cancellation, and the D27
     `Undelivered` rule get their fixtures from this, not from hand-written two-node
     scenarios alone (II.5.4 names this as the place to pin the three-role rule).
   Both are ordinary bodies of the role's type, so they also run over the network in
   `test/two_node/*` unchanged.
3. **The cluster (D35).** DONE 2026-09-23
   ([../progress/2026-09-23-dd-step04-cluster-live-cap.md](../progress/2026-09-23-dd-step04-cluster-live-cap.md)).
   `ClusterHandle` (stdlib/cluster_node.march) was a plain record; it is now
   `Cap(ClusterNode.Live)` with a `ClusterOps` dictionary (one field per operation: `members`,
   `subscribe`, `register`, `lookup`, `queue_for`, `route`, `creation` and the rest),
   minted by `ClusterNode.start(io, cfg)` and swappable by `ClusterNode.attach(io, ops)` in
   tests. The cap lives in `ClusterNode`, not `Cluster` (an unrelated module), because only
   the declaring module may mint it. A placement test then injects `NodeDead` and asserts a
   role moved, with no sockets; `Topology.place` (II.3), rendezvous placement and
   hysteresis (4.2) become unit-testable. `SessionAP` and `SessionNode` already took the
   handle everywhere, so the change was the type of one parameter plus the dictionary
   indirection at its use sites.

### 7.3 What goes in the protocol, and what does not

- `role R needs …` is the right amount of capability in a protocol. Per-branch authority
  is not worth it: a branch is inside one role's body, and the role grant covers it.
- **Delegating a session endpoint in a message** (session-type delegation) is the
  distributed form of passing a pid, and the only principled way to hand *authority*, not
  data, across nodes without an ambient registry lookup. It is how a node comes to hold a
  reference it was not configured with. Out of scope for the build order; recorded here
  as the answer to that question, so nobody reaches for the registry instead.
- Authority over **data** stays where it is: refinements on payload types, checked at the
  receive (section 3, "untrusted input").

### 7.4 Enforcing boundaries across nodes

Static capabilities stop at the process. Across nodes exactly three things are
enforceable, and the design should be read in these terms:

- **Reach.** With unforgeable references (D31), no raw sends for untrusted members, and
  certificates naming roles (section 3), a node's reach is *its projections*: the
  connections the protocol gave it. That is the object-capability rule applied to nodes:
  authority is what you hold, and the only things a node can hold are session endpoints
  its certificate let it form.
- **Shape.** The receiver enforces, never the sender: `try_decode` and the payload
  refinements are the border check on an untrusted peer, and a violation is already
  `Protocol(role, why)` (session_node.march:406).
- **Record.** Every cross-node interaction is a session, so a session log (who formed
  what with whom, under which certificate and fingerprint) is a complete authority trace,
  the distributed counterpart of the effective-authority report, and cheap because the
  frames already carry the role, session id and fingerprint.

Not enforceable, and said plainly in the guide: confidentiality without encryption (D4),
availability against a member that lies in SWIM, and anything that happens inside a
Foreign node.

## Part II: Implementation

Everything above says *what*. This part says *where* and *how*, against the code as it is,
and records what the code survey changed in the design (the D28–D33 revisions in the
decisions table). File references are to this repository.

### II.1 Unforgeable references (build step 2)

**What exists.** `pid_of_int` is a builtin typed `Int -> Pid(a)`
(lib/typecheck/typecheck_builtins.ml:887), lowered to `march_pid_of_int`
(lib/tir/llvm_builtins.ml:965), which returns a dead-actor sentinel for an unknown index
(runtime/march_runtime.c:7991). `actor_pid_indices`, `actor_register`, `actor_whereis`,
`actor_registered` are builtins likewise; their only stdlib callers are
stdlib/actor.march (the wrappers, and `Actor.list`), stdlib/cluster_node.march (about
17 `pid_of_int` sites) and stdlib/session_node.march (2). About 20 test and bench files
use `pid_of_int`, mostly supervisor-restart tests.

**Mechanism: a proof capability, not a new IO lattice node (D31).** The IO lattice is
the wrong tool: the ceiling check attributes a stdlib-mediated call to the *calling*
module (`Cap_attrib`'s transparent-stdlib rule, lib/tir/cap_attrib.ml), so a
`needs IO.Introspect` on `cluster_node.march` would be charged to every program that
starts a ClusterNode. Proof caps already have the semantics needed: `Session.Live` is
declared `proof cap Live with Ops` (stdlib/session.march:61), lives outside the IO
lattice, and Check 6 (lib/typecheck/typecheck_caps.ml) lets only public functions of the
declaring module mint it. So:

- stdlib/actor.march declares `proof cap Introspect` and one minting function,
  `Actor.introspect(io : Cap(IO)) : Cap(Introspect)`. The `Cap(IO)` parameter puts `IO`
  in the closure of everything that reaches `introspect`, so a role body or hook under a
  narrower grant fails the grant walk (II.2). **Corrected 2026-09-22:** it also fails to
  typecheck before the walk runs. `Cap(IO.NetListen)` does not unify with `Cap(IO)`
  (`Cap` is an ordinary type constructor); amplifying a cap is a type error, and the walk
  rejects the program independently. G2 pins both
  (specs/progress/2026-09-22-cap-narrowed-signature-grant-test.md). D31's conclusion
  stands; the earlier sentence "`Cap` types themselves unify across the lattice, so this
  is the walk's doing" was wrong. The composition root (`main`, or the generated `main`)
  holds `Cap(IO)`, which is the object-capability shape: authority is handed out from the
  root.
- The forging builtins take the cap: `pid_of_int(c : Cap(Actor.Introspect), n)`,
  `Actor.list(c)`, `Actor.whereis(c, name)`, `Actor.registered(c)`. The raw builtins
  become stdlib-internal: `Typecheck_builtins.stdlib_only` (G3,
  specs/progress/2026-09-22-stdlib-only-builtins.md), a reference gate keyed on the
  builtin's name and the referencing declaration's file being the stdlib's. **Landed
  2026-09-22** (specs/progress/2026-09-22-dd-step02-unforgeable-references.md); the
  wrapper is `Actor.pid_from_int(c, n)`, since a module-level `fn pid_of_int` shadows
  the builtin for its own body at runtime.
- `cluster_node.march` and `session_node.march` keep their raw `pid_of_int` calls: they
  are the stdlib, which the gate exempts by construction. `ClusterNode.start(cfg)` takes
  no `Cap(IO)` (this plan said it did), so it cannot mint, and `ClusterNodeActor`'s
  `init` must build a placeholder `ClusterHandle` before `Boot`, which no code outside
  `Actor` could give a cap field. Threading the cap would have changed `start`'s arity
  for every caller for no enforcement gain (the cap is erased at runtime and the gate is
  the boundary).
- `Actor.register(pid, name)` stays unprivileged: registering is not authority.
  `whereis` is.

**The migration is mechanical but must be verified per module** with
`march --check stdlib/<mod>.march`, because the stdlib diagnostic filter hides a stdlib
module's own type errors from programs that load it (this bit `cluster_node` once
already: specs/todos/2026-09-18-cluster-node-service-follow-ups.md).

**Cross-node references** (`GlobalPid.make`, `GlobalRegistry.lookup`) are left as they are
until section 3's certificates exist; without link integrity there is nothing to check
them against yet. Note this in the guide: unforgeability is a *process* property first.

**Tests:** a program that calls `pid_of_int` with no cap fails to typecheck, naming
`Actor.introspect`; one that mints in `main` and forwards the cap compiles; the existing
supervisor-restart tests migrate to `Actor.introspect(io)`.

### II.2 Per-role grants (build step 4)

**What exists.** `check_main_grant` (lib/typecheck/typecheck.ml:6583) takes the
capability rows solved by `March_caps.Cap_rows.solve` (lib/caps/cap_rows.ml:213), a
worklist fixpoint over `env.fn_refs` (reference edges collected with `free_vars_expr`, so
a function passed as a value still edges) seeded from `env.own_cap_closures`; looks up the
row for `"main"`; requires every `IO`-rooted cap in it to sit under some `Cap(P)`
parameter of `main`. Spawned actors are edges from the spawner
(`March_ast.Calls.spawned_actor_names`, lib/ast/calls.ml:98), so an actor is charged on
spawn. Non-IO caps (proof caps such as `Session.Live`) are skipped. The check ignores
`unknown` routes (`~with_rows:false`).

**Change: the same walk from more roots, with the grant as parameters (D34).** The
generator gives each role's body type one `Cap(P)` parameter per declared cap (7.1), so a
body's grant is its own signature. `check_role_grants` runs after `check_main_grant`
and, for each declared `role R needs …`:

1. **Find the roots.** In a topology app, the `[roles]` binding: a function's qualified
   name, or every handler of a bound actor plus its `init`. Without a topology, every call
   to a runner entry (`<P>_Run.run_R`, `offer_R`, `cluster_R`, `initiate_R`, `host_R`,
   `offer_hosted_R`, `cluster_hosted_R`): the body argument is a lambda or a named
   function; a lambda gets a synthetic row key (`<P>_Run.run_R#<span>`) whose seed is the
   lambda's own caps and whose refs are its free variables, which `record_fn_refs`
   already computes for `ELam` bodies (lib/typecheck/typecheck_caps.ml:508).
2. **Solve** with the existing `Cap_rows.solve`; project each root's `caps`.
3. **Compare** against the root's `Cap` parameters (which the generator made equal to the
   role grant) with `Cap_lattice.cap_subsumes`, skipping non-IO caps as `main` does. In
   the runner entries, the narrowing that produces those values is `cap_narrow(io)` per
   cap, emitted by the generator into `run_R` and friends. Report with `cap_reach_chain` (typecheck.ml:6550), so the message
   names the chain from the body to the frame that holds the capability, as `main`'s does.
4. **Role grant ⊆ `main` grant** is a one-line check on the parsed sets.

**Parsing.** `protocol_step` (lib/parser/parser.mly:949) gains
`role upper_name needs cap_path_list`, stored as `ProtoRoleNeeds of name * name list *
span` in `protocol_step` (lib/ast/ast.ml:380). The generator ignores it; the typechecker
collects it into `env.role_grants : (proto * role) -> cap paths`. It must appear before
any message step, so the fingerprint (`fingerprint_of`,
lib/desugar/desugar_endpoints.ml:521) does **not** include it: a grant is a claim about
code, not about the wire, and two nodes with different grants must still talk.

**The effective-authority report** is `--dump-role-authority`: for each root, the pids
and closures reachable as *values* (the `ELam`/`EVar` refs that are not calls, which the
row solver already distinguishes as `deps`) and the capability rows of the actors behind
them. It is a report, not a check; it exists so D1's delegation is visible.

**Hot deploys** (build step 10): `bin/main.ml:3428-3540` writes one manifest line per
boundary function with its *own* caps. Add one `ROLE <Proto.Role> caps=<closure csv>` line
per role, from the same solve. `forge deploy hot` gains a per-role widening gate beside
the per-function one (forge/lib/cmd_deploy_hot.ml:684-745, `compute_cap_widening`); the
server side needs the closure in the signed message, which is a new verb, `ACTIVATE5`,
adding `role_caps:<Proto.Role>=<root hex>;…` (appending to `ACTIVATE4` would break old
servers' signature reconstruction: runtime/march_reload.c:1183 rebuilds the canonical line
and the `callers:` parse runs to end of line). The policy file generated from a pool's
`caps` is checked against the role closures, which is the check section 5 asks for.

**Gotchas carried from the survey.** Two capability→name tables exist
(`Typecheck_builtins.builtin_cap_table` and `March_caps.Cap_symbols.table`), pinned equal
by test/test_cap_attrib_agreement.ml; a new builtin goes in both. The C lattice
(runtime/march_cap_lattice.c) is generated from lib/caps/cap_lattice.ml by
lib/caps/emit_c_table.ml with a CI freshness diff; a new lattice node is added once, in
OCaml. `check_main_grant` is not run by the REPL path (`check_module_with_env`); role
grants follow suit.

### II.3 Level 0: one process, generated `main`, hooks (build step 3)

**The self-link.** A ClusterNode never links to itself: `core_seed_self`
(stdlib/cluster_node.march:483) refuses to dial its own address and `queue_for(h,
own_id)` is `None`. `run_cluster_party` (stdlib/session_node.march:1799) needs
`queue_for(peer_node_id)` for every peer, and `initiate` seeds its `used` set with the
node's own id (session_node.march:2192) so `candidates` never picks a local offer. Three
changes:

1. `ClusterNode` gets a **loopback link**: `queue_for(h, own_id)` returns a `NodeQueue`
   whose writer, instead of a socket, calls the node's own `route` dispatch directly
   (`data_fd = -1`, like a cluster link). Delivery order is preserved because it is one
   queue. Credit flow control is bypassed on loopback (there is no peer to grant credit).
2. `initiate` no longer seeds `used` with its own node; `candidates` keeps the "one node
   per role per session" rule, which is what actually matters (two roles of one session on
   one node is fine; the same node playing two roles *of the same session* is what the
   Vault keys are per-party for, and already works: `party()` keys include `my_role` and
   the endpoint pid, session_node.march:718).
3. Prefer-local (4.2): `candidates` orders the local offer first.

`test/two_node/cluster_ap` gains a one-process variant (`cluster_ap_local`) whose two
roles run in one binary; `scripts/two-node.sh` already supports a single node.

**The generated `main`.** A new desugar pass, `lib/desugar/desugar_topology.ml`, runs
when the compiler is given `--topology <file>` (forge passes it) and the entry module has
no `main`. It reads the topology (a small TOML reader in OCaml; forge's `Toml` module is
in forge/, so the compiler gets its own minimal one, or `forge` pre-digests the topology
into a JSON the compiler reads: the second keeps one TOML parser and is what I would do)
and emits, into the entry module:

```march
fn main(c : Cap(IO)) do
  let cfg = match ClusterNode.config_from_env() do Ok(c) -> c  Err(e) -> panic(e) end
  let node = match ClusterNode.start(cfg) do Ok(n) -> n  Err(e) -> panic(e) end
  let env_edge = Edge.start(cap_narrow(c), node)              -- pool hooks, in file order
  Topology.place(node, [                                       -- one entry per served role
    Topology.role("Checkout.Ledger", 64, Topology.Everywhere,
      fn (sid, s, st) -> Ledger.serve_one(env_ledger, s, st)),
    Topology.actor_role("Quotes.Server", 64, Topology.On("db"),
      fn () -> spawn(Quotes.ServerActor, env_ledger)),
  ])
  Topology.drain_on_signal(node, 30000, 120000)
  Topology.supervise(node)
end
```

`Topology` is a new stdlib module (stdlib/topology.march) holding the runtime side:
`place` subscribes to `ClusterNode.subscribe` membership events, recomputes placement
(II.6) on every `NodeUp`/`NodeDead`/`NodeRejoined` and on a pushed topology, and opens
or drains offers through `SessionAP.offer_role`/`offer_hosted`/`close_offer`
(session_node.march:1974, 1993, 2026). The generated code is ordinary March, so the
existing grant check applies to it unchanged; `Desugar.check_main_signature`
(lib/desugar/desugar.ml:1433) accepts it because every parameter is a `Cap`.

**`main`'s grant** is `Cap(IO)`, narrowed per hook. A hook takes **one `Cap(P)` parameter
per entry in its pool's `caps`**, in the order the topology lists them (or a single
`Cap(IO)` when `caps` is `IO`), followed by the `ClusterHandle`; the generated `main`
passes `cap_narrow(c)` for each. `caps` is the written list, or the derived one from the
role/hook solve (D22). `forge topology check` verifies the hook's signature against it, so
a hook cannot receive more than its pool allows, and cannot call `Actor.introspect`
(II.1) unless the pool's `caps` is `IO`. **Corrected 2026-09-22 (G2):** `Cap(IO.NetListen)`
does *not* unify with `Cap(IO)`; a narrowed cap passed where `Cap(IO)` is expected is a
type error (`expected IO but got IO.NetListen`), so amplifying a cap is refused by the
checker. Independently, a signature `Cap(IO)` position counts toward the callee's own
capability closure, so a hook or role body that reaches `Actor.introspect` carries `IO`
in its closure and fails the grant walk (II.2) as well. D31 holds through both; the
2026-09-21 "verified: does unify" note here was wrong
(specs/progress/2026-09-22-cap-narrowed-signature-grant-test.md).
The generated `main` itself is excluded from HCR boundaries (`is_entry_fn`,
lib/tir/llvm_toplevel.ml:840), which is right: it never reloads, it restarts.

**Hooks return promptly.** `Topology.place` is called only after every hook returns; a
hook that has not returned within `MARCH_HOOK_TIMEOUT_MS` (default 10 s) is reported by a
watchdog task and the node exits non-zero (offering nothing is worse than failing loudly).

**`forge run`** (forge/lib/cmd_run.ml:136): with a topology present it **always compiles**
(the cluster runner is compiled-only; the default interpreted path is not available to a
topology app, and `forge run` says so), passing `--topology .forge/topology.json`
(pre-digested), and runs the one binary. `--processes`
builds once per distinct build (shared, plus each isolated pool), starts one process per
pool with `MARCH_NODE_NAME=<pool>-<n>`, ports from a free-port scan, seeds pointing at
each other, and forwards SIGTERM. forge has no process supervision today (everything is
one `Sys.command`, cmd_run.ml:103), so this is a new `forge/lib/procs.ml`: spawn with
`Unix.create_process_env`, collect exit statuses, kill the group on exit. It is the same
module `forge test --upgrade-from` and the `local` backend use.

**Parameterised `init` (D24)** touches: `parser.mly:749-761` (`INIT` then optional
`LPAREN params RPAREN`, and the contextual-keyword error arm at :769-780);
`ast.ml:355-364` (`actor_init_params : param list`); `ESpawn` (`ast.ml:73`, typed at
typecheck.ml:2749-2789, which today requires a bare constructor or variable) gains an
optional argument unified against the `init` parameter; `lower_actor.ml:326-360` gives
`<Name>_spawn` the parameters and threads them into `$init_state`; `lower_expr.ml:952-988`
passes the argument. Supervised children (`supervise_block`, parser.mly:862-905; lowering
at lower_actor.ml:362-400) register a raw `spawn_fn` pointer with
`march_actor_register_child` (lib/tir/llvm_builtins.ml:971) that respawn re-invokes, so a
child with an `init` argument needs the argument stored beside the pointer: the child spec
becomes `Type name(expr)`, lowering allocates the value once, and
`march_actor_register_child` gains a `void *init_arg` it holds a reference to and passes
on respawn. Interpreter (lib/eval/) mirrors the same three points.

### II.4 The epoch model (build step 6)

This is where the survey changed the design most. The facts:

- The dispatch table (runtime/march_dispatch.c) keeps `MARCH_MAX_LIVE_VERSIONS = 2`
  ring versions per slot, each with `fn_ptr`, `impl_hash`, `sig_hash`, `epoch`, a
  `live` gate, an atomic `refs`, and the dlopen `handle`. `enter`/`leave` bracket exactly
  one call. `publish` reclaims the slot with `refs == 0` and `dlclose`s its handle; if the
  other slot is still referenced it returns -1 and the activation fails (:190-197). There
  is no purge and no grace period.
- `enter_gen(name_id, caller_epoch)` picks the newest live version with
  `epoch <= caller_epoch` (:380). The caller's epoch is a **per-`.so` private global**
  written once by `__march_init` (lib/tir/llvm_toplevel.ml:867, :1350); base-binary call
  sites use plain `enter` (current). The actor loop also uses plain `enter`
  (runtime/march_runtime.c:3365).
- `march_actor_meta` has no code-version field, and its `epoch` field is the
  *capability-revocation* epoch (:2146): a name to avoid.
- Per-proc state must live on `march_proc`, never in TLS: procs migrate across OS threads
  (runtime/march_scheduler.h:340-348). `march_sched_current()` returns the running proc.
- A message's heap header has no free word: `pad` is multiplexed three ways
  (runtime/march_runtime.h:14-37). The mailbox node, `march_mbox_node { msg;
  enqueue_seq; next }` (march_scheduler.h:173), is runtime-owned and extensible at no
  cost to the March heap ABI.
- Migration is a fire-and-forget broadcast (`march_actor_broadcast_migrate`,
  march_runtime.c:4869) capped at 2048 actors, after the new version is already current.
- `publish_epoch` stores `epoch` after `live = 1` (march_dispatch.c:364), so
  `enter_gen` can briefly read epoch 0 on a fresh slot and select it for any caller.

**II.4.1 Where the epoch lives.** `march_proc` gains `uint32_t code_epoch`. A boundary
call resolves against `march_sched_current()->code_epoch`: the emitted call
(lib/tir/llvm_emit_call.ml:372-456) changes from `enter_gen(ID, %hrepoch, &v)` (with the
per-`.so` global) and from `enter(ID, &v)` (base binary) to one runtime function,
`march_dispatch_enter_unit(ID, &v)`, which reads the current proc's epoch and falls back
to current when there is no proc or the epoch is 0. That makes the base binary and every
`.so` resolve the same way, which is the point of D12. The `@__march_hcr_epoch` global and
`__march_init` stay (harmless, and the reload server still calls it) but nothing reads
them. Cost: one TLS read and two loads per boundary call, measured in II.7.

**II.4.2 Pinning and retirement (D32).** `refs` stays what it is: calls in flight, which
is what makes a version safe to `dlclose`. Units are counted separately, per *epoch*, in
a small table `g_epoch_pins[E mod 8]` (an epoch older than the last eight has no units
by construction, because deploys wait, below). A proc increments the pin of the epoch it
takes (at spawn, or when an actor advances) and decrements it on exit or advance. An
epoch is **retired** when its pin count is 0. Retirement is not by itself what frees a
version: a unit pinned to epoch 5 calling a function last changed in epoch 2 resolves to
the epoch-2 version ("newest at or before 5"), so that version is in use although epoch 2
has no pins. The reclaim condition is **per slot**: version V with epoch `e` is
reclaimable iff `refs == 0` and no pinned epoch E satisfies `e <= E < e_next`, where
`e_next` is the epoch of the next newer live version in the same slot (infinity for the
newest). That is one scan of the pin table per candidate. `MARCH_MAX_LIVE_VERSIONS` goes to 3, so
one drain can overlap the next deploy. When no version is reclaimable, the reload server
no longer fails the activation: it **queues** it (the batch stays staged, reusing the
`BEGIN_BATCH` staging array, runtime/march_reload.c:641) and answers
`WAIT epoch:<E> pins:<n> deadline_ms:<t>`; `forge deploy` prints that and polls. The hard
deadline guarantees the wait ends.

**II.4.3 Tasks inherit.** `march_sched_spawn` copies `code_epoch` from the spawning proc
(or the global `g_current_epoch` when there is none). `march_task_spawn_thunk`
(march_runtime.c:5159) needs no change beyond that.

**II.4.4 Epoch holds (D28): the nesting rule, mechanically.** A proc has a `uint32_t
epoch_holds` counter. While it is non-zero the proc does not advance at a marker; the
marker is remembered as pending and fires when the last hold is released. Holds are taken
by code that keeps work of an older epoch alive:

- `SessionNode.party()` holds for the party's Endpoint actor (session_node.march:718) and
  `finish` releases. So a session's callbacks run in a proc pinned to the session's
  epoch, and the closures the old code created resolve their calls against the old
  epoch. This is what "a session captures its protocol's code" (6.4) means mechanically,
  and it comes from the actor model rather than from a special session mechanism.
- The generated hosted API holds per parked endpoint: `await_*` and `idle`→`await_`
  transitions take a hold on the hosting actor's proc, `finish`/`cancel` release. An
  actor hosting three old sessions has three holds and advances when the last ends.
- `march_task_spawn` does not hold: a task inherits the epoch; it does not keep its parent
  from advancing (the parent's *messages* are stamped, II.4.5, which is what matters).

Two builtins, `epoch_hold()`/`epoch_release()`, exposed only to the stdlib (same
stdlib-only mechanism as II.1).

**II.4.5 Message stamps on the mailbox node (D29).** `march_mbox_node` gains
`uint32_t epoch` (the sender proc's `code_epoch` at enqueue) and one flag bit,
`marker`. Because the node is runtime-owned, the stamp exists in every build, costs four
bytes per queued message and nothing on the wire; the earlier idea of stamping only
hot-reload builds is dropped. Remote deliveries are stamped with the epoch of the
receiving node's route handler, plus the schema hash carried on the wire (II.5).

**II.4.6 Activation order and the marker.** `do_activate_inner`
(runtime/march_reload.c:294) becomes:

1. `dlopen`, `dlsym`, and for each slot in the batch `publish_epoch` with `live = 0`
   (fix the `epoch`-after-`live` ordering: set `epoch` before `live`).
2. For every HCR actor (`dispatch_name_id != 0`; walk *all* buckets in batches of 2048,
   fixing the snapshot cap) enqueue a **marker node** in its user mailbox: `marker = 1`,
   `epoch = E_new`, `msg = NULL` or the migrate struct when that actor's state schema
   changed (`migrate_required` per slot, as today). The marker rides the user mailbox,
   not the control mailbox, because its position relative to user messages is the whole
   point. It is exempt from overflow policies (as the migrate message is today,
   `march_actor_msg_dispose`, march_runtime.c:4724).
3. Flip `live = 1` and `current` for the batch, then advance `g_current_epoch = E_new`.
   New tasks and sessions now pin `E_new`; every existing actor is still at its own epoch.

The receive loop (march_runtime.c:3239-3420) then does, per dequeued node:

- **Marker:** if `epoch_holds > 0`, remember it and continue at the old epoch. Else run
  `migrate_fn` if present (the existing MIGR path), set `code_epoch = E_new`, move this
  proc's pin from the old epoch to the new, replay the deferred queue (next bullet), and
  continue.
- **Held actor, newer-format message** (`epoch_holds > 0`, `node.epoch > code_epoch`, and
  the schema changed at `node.epoch`): the actor can neither advance nor dispatch it. It
  goes to a per-actor **deferred queue**, replayed in order when the actor advances. This
  reorders that message relative to older messages behind it; the reorder is bounded by
  the drain deadlines and reported per actor. Role-bound actors never hit this case: a
  protocol change spawns a new actor, and new-epoch senders talk to that one (II.5.6). Only
  a hand-written actor that both hosts sessions and has user handlers whose types changed
  can, and `--plan` names it.
- **Message with `node.epoch > code_epoch`** (a sender that already advanced) **and the
  actor's message schema changed at `node.epoch`** (D30): advance *now*, exactly as at the
  marker, then dispatch. The actor's schema epoch is a per-slot field the activation sets
  (`msg_schema_epoch`, from the deploy's schema diff, alongside `migrate_required`). Then
  the marker, when it arrives, is a no-op.
- **Message with `node.epoch < msg_schema_epoch`** (old format after the actor advanced):
  call `migrate_msg` (a `__migrate_msg_<Actor>` symbol resolved like `__migrate_<Actor>`,
  llvm_toplevel.ml:1042); `None` or no symbol → drop, count, and if the delivery came
  from a remote node answer `DELIVERY_FAILED` on the existing path.
- Otherwise dispatch with `march_dispatch_enter_unit`, which resolves the actor's dispatch
  function at the actor's own epoch. This is the fix for the first bug in "Bugs found":
  messages ahead of the marker run the old `<Actor>_dispatch` against the old state.

**II.4.7 Drains (6.2) in the runtime.** `Topology.drain(node, soft_ms, hard_ms)` and the
reload server's `DRAIN epoch:<E>` verb do the same thing: mark epoch E draining
(`g_epoch_draining[E]`), which `SessionNode` reads to start D27 drains, and arm two
timers. At the soft deadline every actor still pinned to E with `epoch_holds == 0`
gets a forced marker (its remaining old messages take the `migrate_msg` path); actors
with holds are left to their sessions' drains. At the hard deadline: procs pinned to E
are stopped with the existing `stop_requested`/`stop_jmp` mechanism
(march_scheduler.h), which runs the actor's death path and lets its supervisor restart
it at the current epoch; sessions get `Left("draining")`. `forge status` reads the pin
table through a `PINS` verb.

**II.4.8 `migrate_msg` tooling.** The deploy already keeps the previous version's
schemas (`<name>_hot.so.schemas.json.prev`, forge/lib/cmd_deploy_hot.ml:1235); the
compiler adds each actor's handler signatures to `.schemas.json` (bin/main.ml:3543).
`forge deploy --plan` diffs them and, for a removed handler or changed parameter type,
writes `.forge/migrate_msg_stubs/<Actor>.march` with the old type spelled out and an
exhaustive match. Naming the *new* message type: `lower_actor.ml:317` already generates
`<Name>_Msg`; exposing it to source as `<Actor>.Msg` is a typecheck-side alias only.

### II.5 Protocol evolution (build step 9)

**What exists.** `fingerprint_of` (lib/desugar/desugar_endpoints.ml:521) is an MD5 over a
textual rendering: protocol name, roles in first-appearance order, and every step's
sender, receiver, constructor and structural payload type. Message names come from
`annotate` (:140): a label, a branch label, or `Msg_<From>_<To>_<k>` counted per ordered
pair. The codec is `derive Json` inside `<P>_Msg`, and the JSON `tag` is the constructor
name (lib/desugar/desugar_derive.ml:584). Offers register under
`ap:<P>/<role>/<node>` (session_node.march:1872), **without the fingerprint**, so a
second version of the same role on one node is `AlreadyOffered`, and an initiator's
`candidates` picks a wrong-version offer and only learns "protocol differs" a round trip
later, against the 20 s setup budget.

**Changes.**

1. **Offer names carry the fingerprint:** `ap:<P>/<role>/<fp>/<node>`. `candidates`
   filters by fingerprint (or by the compatibility table) before inviting, so no round
   trips are wasted, and two fingerprints can be offered side by side.
2. **The compatibility table.** The generator emits, per protocol, `<P>_Msg.compat()`: a
   list of `(fingerprint, role, accepts : List(String))` saying which *other* fingerprints
   a role at this fingerprint may form a session with. It is computed at compile time
   from the *previous* version's annotated projection, which the compiler is given with
   `--protocol-baseline <file>` (forge keeps `.forge/protocols/<P>.json`, written on every
   build, the same way it keeps schema baselines). **The table reaches one version back
   only:** a peer two versions behind gets "protocol differs". That is enough for the
   monolith's expand/contract split (D21), which is two consecutive deploys, and keeps the
   baseline a single file. Rule one: the old and new annotated
   step lists are identical except that one `choose` has an extra branch, every message
   both versions can exchange keeps its constructor (wire tag) and payload `ty_key`, and
   the role is not the chooser. Everything else is "same fingerprint only".
3. **Formation checks the table.** `Invite` carries the initiator's fingerprint already;
   `offer_verdict` (session_node.march:1885) consults `compat()` instead of equality. The
   two-way check of section 3 slots in at the same place later.
4. **Automatic drain at loop boundaries (D27).** The projection knows loop heads
   (`LRec`/`LVar`, desugar_endpoints.ml:64). The generated receive for a loop-head state
   calls `Session.suspend_at_boundary` (a new `Ops` field, alongside `on_drain`; the
   same-thread transports treat it as `suspend`, and every hand-written transport,
   including the ones in `test/session/*`, gains the two fields). In `SessionNode`, when the party's epoch is draining and a
   delivery arrives for a boundary-suspended endpoint, `deliver` (session_node.march:475)
   does not resume: it sends the frame back as `SessionNode.Undelivered [to, from, msg]`
   and runs the endpoint's drain handler (installed by the generated `_or_drain` form
   through a new `Ops.on_drain`, or the default). The sender's party, on `Undelivered`,
   marks the peer role drained and reports at the sender's next suspension (or in `run`'s
   result). Messages sent to a drained role are returned the same way. With three or more
   roles, a role mid-iteration reaches its own boundary or a receive from a drained role
   and ends there; the exact statement and its proof of "no message silently lost" is the
   open question already listed, and the `test/session/*` single-process fixtures (FIFO
   run queue, reproducible traces) are the place to pin it before touching the network.
   `loop atomic` is a contextual identifier after `LOOP` in `protocol_step`
   (parser.mly:988), like `stop`.
5. **A drained session's result:** `Ok(Session.Drained(undelivered : Int))` is the least
   disruptive: `run_R` keeps its `Result((), RunError)` shape by widening `()` to a
   `Session.Outcome = Finished | Drained(Int)`. Every existing `Ok(_)` match still
   compiles.
6. **Hosted access points across a protocol change** (6.1): `Topology.place` opens the new
   fingerprint's offer with a fresh actor (`actor_role` spawns per offer, not per node),
   closes the old offer, and the old actor exits when its holds drop to zero.
7. **`@remote` schema hashes.** The wire tag is the qualified type name recorded by
   `Json_dispatch.record` (lib/typecheck/typecheck_caps.ml:1874). Rather than change the
   tag string (old receivers compare it), `Node.send_tagged` adds a `schema` field to the
   envelope with the type's schema hash; `Node.tag_is` on a new receiver checks both, an
   old receiver ignores the field. Mismatch → `migrate_msg` if the receiving actor has one
   for that hash, else `DELIVERY_FAILED`.

### II.6 Topology, placement, generators (build steps 7 and 8)

**forge's TOML parser has no positions** and silently drops malformed pairs
(forge/lib/toml.ml:173) and unknown keys everywhere. Before `forge topology check` can
report `topology.toml:12`, `Toml.parse` tracks line numbers per key and section and
rejects unknown keys in sections it owns. That is the first task of step 7 and improves
`forge.toml` errors as a side effect.

**Files.** `topology.toml` next to `forge.toml`; overlays `topology.<env>.toml`; the
digested form `.forge/topology.json` (what the compiler and the runtime read). Digest =
parse base, deep-merge overlay tables, replace arrays, validate, resolve every `body`,
`actor` and `start` name against the project's parse (forge already parses every
`.march` in-process for `cap query`, forge/lib/cmd_cap.ml:15), and write JSON with a
`version: 1` field.

**`forge topology check`** does the static checks of section 4 by invoking `march
--check --topology .forge/topology.json`, which is where role grants (II.2), hook grants
and the reach checks run; forge adds the placement checks it can do alone (every served
role bound, `on` labels exist in the overlay, `count` ≤ hosts). The compiler's derived
values (pool `caps`, `initiates`, role closures) come back through `--emit-core-ast`'s
JSON, extended with a `topology` object, and `export` writes them with the connectivity
graph from `peers_<Role>()`.

**Placement at runtime (stdlib/topology.march).** For each served role on this node:
`Everywhere` → offer; `On(label)` → offer if this node's labels (from
`MARCH_NODE_LABELS`, set by the launcher) include it; `Count(n)` → rank the live members
(`ClusterNode.members`, filtered by label if combined) by
`blake3(role_name ++ node_id)` and offer if this node is in the top n. Recompute on every
membership event, debounced by the settling period for `NodeRejoined` (default 15 s,
`MARCH_PLACEMENT_SETTLE_MS`). Losing a role calls `close_offer`, which already lets
running sessions finish. Hysteresis is one timestamp per member in the handle's Vault.

**Generators.** `forge topology gen <target>` looks for a built-in generator, else
`forge-topology-<target>` on PATH (the same convention `forge` already uses for unknown
subcommands, forge/lib/cli_ext.ml:43), and feeds it the export JSON on stdin. Built-ins
ship as embedded templates (the dune rule idiom in forge/lib/dune:8-46): `systemd` (one
unit per pool, `Environment=` from the overlay), `ufw` and `do-firewall` (rules from the
connectivity graph and `public`), `compose` (one service per pool, for laptops). `k8s`
comes with its backend (step 10 onwards).

**The reconciler.** A new `forge/lib/reconcile.ml` with one interface,
`Backend.{hosts; run_on; push_topology; status}`, and two implementations in step 8 and
10: `local` (uses `procs.ml`; `push_topology` writes the JSON and sends `SIGHUP`, which
the generated `main` handles by re-reading it) and `ssh` (extracts the rolling and
simultaneous drivers that are local closures inside `deploy_env` today,
forge/lib/cmd_deploy_hot.ml:1426-1432, into `run_on`; pushes the topology over the
reload socket with a new signed `TOPOLOGY <blake3> <sig>` + body verb). The entry-file
rule is duplicated four ways and disagrees (`lib/<name>.march` in build/check/run,
`src/<name>.march` in the hot-deploy paths, cmd_deploy_hot.ml:1160); factor it into
`Project.entry` first, since the topology adds a fifth consumer.

### II.7 Performance spike (build step 5)

Two numbers, measured before step 6 is built, on `bench/list_ops.march` and a
`bench/actor_ping.march` (two actors exchanging a million messages), all compiled with
`--hot-reload` and `--opt 2`:

1. Today's boundary cost: `--hot-reload` versus plain, on the same commit. The Model B
   Phase 0 spike in specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md is the
   larger version of this and is still worth running for the ORC question, but the number
   this plan needs is the smaller one.
2. `march_dispatch_enter_unit` versus `enter`: a prototype that adds the TLS read and the
   `code_epoch` load, with no other change.

If (1) is above about 10 % on `list_ops`, hot-reloadable production builds need Model B
before D8 holds, and steps 6–12 wait on it. If (2) is measurable at all on
`actor_ping`, the epoch read moves off the call path: the actor loop can read it once per
message and pass it, since a handler's calls all resolve at the same epoch.

### II.8 `forge deploy --plan` and `forge test --upgrade-from` (steps 8 and 10)

`--plan` reuses the diffing `cmd_deploy_hot.run` already does (manifest set-diff at
:594, sig_hash gate :606, callers gate :637, cap gate :684, schema diff :760) and adds:
protocol baselines (II.5), hook change detection (a hook's `impl_hash` changed → restart
for that pool), placement diff (topology JSON old vs new), and the derived-values diff.
The classification is a pure function over those diffs, unit-tested in forge/test with
fixture pairs; the renderer prints the six blocks of 6.8.

`forge test --upgrade-from <ref>`: `git worktree add` at `<ref>` into
`.forge/upgrade/<ref>`, build it, start it with `procs.ml` under `forge run --processes`
semantics and `MARCH_HOT_RELOAD_SOCKET` set per process, run the project's test traffic
(a `test/upgrade_*.march` file that drives sessions and actors, given the socket paths),
then deploy the working tree into the running processes through `cmd_deploy_hot.run`
with a local socket and no tunnel, wait for drains, and assert on the `PINS` and
delivery-failure counters plus the test file's own checks. It is `forge test`'s one
multi-process case, and the reason `procs.ml` is built in step 3 rather than later.

### II.9 Segregation (step 11) and the control plane (step 12): sketches only

These are far enough out that only their touchpoints are worth recording. Certificates
replace the shared secret in `ClusterAuth.prove`/`NetKernel.handshake`
(stdlib/cluster_auth.march, stdlib/net_kernel.march); the per-frame MAC goes in
`NetFrame`; the two-way role check goes in `offer_verdict` and `fill_roles`
(session_node.march:1885, :2143); raw-send denial is a check in `ClusterNode.send_msg`
and `route` against the peer's certificate flags. The control plane is an
`@[endpoints]` protocol between `Control` and `Agent` roles whose `Agent` body wraps the
reload socket verbs; it reuses `reconcile.ml` with a `cluster` backend.

## Bugs found while designing (read from code, not reproduced)

Being fixed in a separate piece of work; its `specs/todos/` or `specs/progress/` entry is
the durable record.

- **Queued messages run new code on old state.** Activation publishes the new version
  first, then appends the migrate message to the *tail* of each mailbox
  (runtime/march_reload.c, the shared activation body). The actor loop enters the
  *current* version for every message (runtime/march_runtime.c, `march_dispatch_enter` in
  the receive loop). So every message queued before a schema-changing deploy is handled by
  the new handlers against the old state layout. docs/hot-code-reload.md says actors are
  migrated "before they handle any new messages", which is not what the code does.
- **Actors beyond 2048 are never migrated.** `march_actor_broadcast_migrate` collects at most
  `MARCH_MIGRATE_SNAPSHOT` (2048) actors.
- **A full mailbox drops the migrate message.** It is sent with `march_sched_send` under the
  actor's overflow policy; on `MARCH_SEND_DROPPED` the dtor frees it
  (runtime/march_runtime.c:4724, and the DROPPED case discussed at :4895), so an actor
  whose mailbox is at its limit during a deploy never migrates and runs new code on old
  state. The marker (II.4.6) bypasses overflow policies.
- **`publish_epoch` stores the epoch after `live = 1`** (runtime/march_dispatch.c:364), so a
  concurrent `enter_gen` can read epoch 0 on a fresh slot and select it for any caller.
  Harmless today (nothing load-bearing reads it); load-bearing under D33.

## Open questions

- **Prerequisite for level 0:** a node cannot run two roles of one cluster session today (a
  node has no connection to itself; `specs/todos/2026-09-18-cluster-node-service-follow-ups.md`).
- **Name for the introspection capability** (`IO.Introspect` is a placeholder), and exactly
  which stdlib modules hold it.
- **Role-set syntax** in protocols (D7): out of scope, but the topology format must not
  preclude it.
- **Whether to raise `MARCH_MAX_LIVE_VERSIONS` to 3** once drains exist (D13).
- **How to name an actor's message type** in source (`Counter.Msg`?), needed by `migrate_msg`.
- **Whether the deferred queue for held actors (II.4.6) should instead refuse the
  message,** if the reorder it causes turns out to matter in practice.
- **Chaos-peer payload generation** (7.2) needs a generator per payload type; `Check`
  has them for built-in types, and user types need `derive Gen` or equivalent.
- **A stdlib-only builtin mechanism** for the raw forging builtins and `epoch_hold`
  (II.1, II.4.4).
- **The `Undelivered` rule for three or more roles** (II.5.4) needs a statement and a
  single-process fixture before the network version.
- **The local name registry's replacement:** privileged lookups, or scoped names (section 1).
- **The format of the version-compatibility table** emitted per protocol (6.4).
- **The generated message types for actor-bound roles** (D23): their names, and whether the
  actor's handlers for them are written by the user or generated.
- **Parameterised `init` (D24):** the grammar, and how `spawn` and supervisor child specs
  pass the argument (a restart must re-supply it).
- **The settling period for rejoined nodes** (4.2), and whether it is per pool.
- **Automatic drain with three or more roles** (D27): a role that is not at a receive when
  the boundary is reached ends at its next one, and messages it sends in between must also
  come back undelivered rather than be dropped. The exact rule needs working out.
- **How `run_R` reports a drained session:** a variant of `Ok`, or its own result (6.2).
- **Which remote store ephemeral hosts pull from** when there is no control plane (6.5).

## Build order

Each step is useful on its own. The infrastructure the steps assume (a performance
measurement, a stdlib-only builtin rule, TOML positions, one entry-file rule, process
supervision in forge, reusable multi-host drivers) is specced separately in
[2026-09-21-distributed-deploys-groundwork-plan.md](2026-09-21-distributed-deploys-groundwork-plan.md)
and lands first.

1. **Fix the two migration bugs** (in progress separately). Build the fix as the first slice
   of the per-actor epoch pin (6.1): a per-actor pinned version that moves at the marker,
   not a patch the unified model later throws away.
2. **Unforgeable local references** (section 1, II.1) as the `Actor.Introspect` proof cap,
   including the local name registry. Small and local, and everything else assumes it,
   but a breaking change (see section 1).
3. **Level 0:** the `[roles]` section (functions and actors, D23), the generated `main` with
   pool hooks and environment records (4.1), and `forge run` running every pool in one
   process. Prerequisites: two roles of one session on the same node, the `Entry` state
   alias, and parameterised actor `init` (D24).
4. **Per-role grants as values** (section 2, 7.1), the effective-authority report, the
   scripted and chaos peers (7.2, D36), and `Cap(ClusterNode.Live)` (D35). The peers are the
   test harness for every later step, which is why they sit here.
5. **The Model B performance spike plus the per-unit epoch cost** (6.7). Its result can
   change later steps.
6. **The unified epoch model and drains** (6.1–6.3, II.4): `code_epoch` on the proc and
   `enter_unit`, per-epoch pins with a waiting activation, epoch holds, mailbox-node
   stamps and the marker, early advance, `migrate_msg` (and a name for an actor's message
   type), the soft and hard deadline machinery.
7. **Topology file** (II.6; first, positions in forge's TOML parser): pools,
   `serves`/`initiates`, `public` ports, environment overlays and
   their merge rules; derived `caps` and `initiates` (D22) with widening routed through
   `--grant-cap` (D26); the unlabelled-step warning (D25); `check` (run automatically by
   `forge build`/`run`/`deploy`), `export`, `gen` (including network policy and firewall
   rules); LSP support for the TOML; static only (section 4), including the placement-rule
   syntax (4.2).
8. **The reconciler with the local backend** (`forge run --processes`), nodes that open
   their own offers from a pushed topology (D16), placement for the monolith (4.2: `on`,
   `count` by rendezvous hashing over SWIM membership, hysteresis, local-first offer
   selection), automatic drain at loop boundaries with `_or_drain` overrides and
   `loop atomic` (D27), and `forge test --upgrade-from` (6.6).
9. **Protocol evolution:** multi-fingerprint offers, drain points, the per-protocol
   compatibility table and its first rule (6.4), a new hosting actor per fingerprint for
   hosted access points (6.1), automatic expand/contract splitting for monoliths (D21).
10. **The ssh backend** with `forge host init` (section 5) and host-local persisted state
    (6.5); signed reconciler actions (section 5); `forge deploy` classification and the
    `--plan` output (6.8); patch-stack compaction (6.5); per-role capability closures in
    the signed manifest, checked by the admission gate (section 5). The remote CAS pull
    for ephemeral hosts comes with the first ephemeral backend (`k8s`).
11. **Node certificates and segregation** (section 3), including the per-frame MAC.
12. **The control plane running in the cluster,** with certificate issuance and a leader
    lease.

## Prior art

From memory, not researched for this plan: Service Weaver (logical components separated
from physical placement; pluggable deployers), Akka Cluster roles (role tags on nodes),
Erlang/OTP releases, `release_handler` and distribution (and why relups are avoided),
libcluster, Horde and Partisan (what grew around a fixed distribution layer), FLAME
(elastic pools from inside the language), Orleans (placement as policy), Choral, HasChor
and MultiChor (roles as locations; census polymorphism), Kubernetes NetworkPolicy,
SPIFFE/SPIRE (workload identity), protoc plugins (extension by convention).
