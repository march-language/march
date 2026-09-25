---
layout: docs
title: Topology
nav_order: 10.95
permalink: /docs/topology/
---

# Topology

A `topology.toml` next to `forge.toml` says which function or actor implements each
offered protocol role, which **pools** of nodes serve which roles, what each pool may
do, and (per environment) which hosts run each pool. `forge topology check` validates
it against your sources with errors that point into the file; `forge topology export`
turns it into JSON for other tools; `forge topology gen` writes systemd units, firewall
rules or a compose file from it.

A topology app has **no hand-written `main`**: the compiler generates it from the
topology (see [Running a topology app](#running-a-topology-app)). `forge run` runs every
pool in one process; `forge run --processes` runs one process per pool as a local
cluster. This is build steps 7 and 3 of the
[distributed-deploys plan](https://github.com/march-language/march/blob/main/specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md);
`forge deploy --plan`, epoch drains and the reconciler are later steps.

## The file

```toml
# topology.toml
[roles]
"Checkout.Ledger" = { body = "Ledger.serve_one", capacity = 64 }
"Thumbs.Render"   = { body = "Render.render_one", capacity = 8, place = { on = "gpu" } }
"Quotes.Server"   = { actor = "Quotes.ServerActor" }          # stateful: an actor per offer

[pool.edge]
start  = "Edge.start"          # a pool hook; runs on every node of the pool
public = [443]                 # the only ports open to the internet
# `initiates` and `caps` omitted: derived from what Edge's code reaches

[pool.ledger]
serves = ["Checkout.Ledger", "Quotes.Server"]
caps   = ["IO.FileWrite"]      # written, so enforced as an upper limit

[pool.imaging]
serves  = ["Thumbs.Render"]
isolate = true                 # its own build; no role shared with another pool

[drain]
soft_ms = 30000
hard_ms = 120000
```

`[roles]` is the application's wiring and changes with the code. `[pool.*]` is
placement and changes with the deployment. A role key is always `"Protocol.Role"`,
where `Protocol` is an `@[endpoints]` protocol declared somewhere in the project and
`Role` one of its parties. Names in strings are fully qualified from the file's
top-level module (`Shop.Ledger.serve_one` for `fn serve_one` inside `mod Ledger`
inside `mod Shop`).

| Section | Key | Meaning |
|---|---|---|
| `[roles]` `"P.R"` | `body` | The function that serves one session of the role. Exactly one of `body`/`actor`. |
| | `actor` | The actor that serves the role (one per offer). |
| | `capacity` | Sessions served at once (positive integer). |
| | `place` | `{ on = "label" }`, `{ count = n }`, or both. No `place`: offered on every node of the pools that serve it. |
| | `set` | Reserved for role sets (one role played by a set of nodes). |
| `[pool.<name>]` | `start` | The pool's hook: hand-written startup, called by the generated `main` on every node. |
| | `serves` | `["P.R", ...]`, or `"*"` for every role in `[roles]`. |
| | `initiates` | Roles the pool's code may initiate. Omitted: derived from `<P>_Run.initiate_<R>` call sites reachable from the hook and the served roles' bodies. Written: an upper limit the check enforces. |
| | `caps` | Capabilities the pool's user code (its hook and its roles) may use. Omitted: derived by the compiler from what that code reaches. Written: an upper limit the compiler enforces. |
| | `isolate` | `true`: its own build and sandbox; no role it serves may be served elsewhere. |
| | `public` | Internet-facing ports. |
| | `main` | Escape hatch: a hand-written entry file for this pool. Warns, since it gives up `forge run`'s single-process composition and runtime-owned offers. |
| | `hosts` | Usually in an overlay: `["user@host", { host = "user@host", labels = ["gpu"] }]`. |
| | `replicas` | For backends that schedule instead of taking a host list. |
| `[drain]` | `soft_ms`, `hard_ms` | Stop taking new work, then kill. `hard_ms` must be at least `soft_ms`. |
| `[backend]` | `kind` | `"ssh"` (a host list per pool) or another process orchestrator. |
| | `port` | The cluster port the firewall generators open between pools (default 7946). |

**Unknown keys are errors**, with the file and line:

```
topology.toml:7: unknown key 'publik' in [pool.edge]
```

### Environment overlays

`topology.<env>.toml` merges onto the base file: tables deep-merge (an inline table
too), and an array in the overlay **replaces** the base's array. `--env prod` on any
`forge topology` subcommand applies `topology.prod.toml`; `forge deploy hot --env prod`
applies it when it exists.

```toml
# topology.prod.toml
[backend]
kind = "ssh"

[pool.edge]
hosts = ["root@web-1"]

[pool.imaging]
hosts = [{ host = "root@render-1", labels = ["gpu"] }, "root@render-2"]
```

### Placement rules

- **No `place`:** offered on every node of the pool.
- **`on = "label"`:** offered on the nodes whose host carries that label.
- **`count = n`:** offered on n of the live nodes that serve the role, chosen at run
  time by rendezvous hashing over cluster membership: every node ranks the candidates
  the same way and offers when it is in the top n. When a node is declared dead, the
  next one in the ranking takes the role over. A node that rejoins counts again only
  after `MARCH_PLACEMENT_SETTLE_MS` (default 15000), so a flapping node does not pull
  roles back and forth. `count = 1` is not a lock: during a partition each side may
  offer.
- **Both:** `count` ranks only the labelled nodes.

## `forge topology check`

Runs on its own and automatically at the start of `forge build`, `forge run` and
`forge deploy hot` whenever a `topology.toml` exists. On success it writes the digest
`.forge/topology.json`. It rejects, each with `file:line`:

- a malformed file, or an unknown key or section;
- a role key that is not `"Protocol.Role"`, a role with neither or both of
  `body`/`actor`, a non-positive `capacity` or `count`, a port outside 1-65535;
- a `body`, `actor` or `start` that names no declaration in the project's sources;
- a role whose protocol or role name no `protocol` declaration has, in `[roles]`,
  `serves` or `initiates`;
- a served role with no `[roles]` binding, and a bound role no pool serves;
- a `place.on` label no host of the serving pools carries, and a `place.count` above
  the number of (labelled) hosts, once an overlay supplies hosts;
- an `isolate = true` pool that shares a role with another pool;
- a written `initiates` that omits a role the pool's code initiates (anything
  written is an upper limit).

It warns about a `main` escape hatch, a pool that serves nothing and has no hook, a
source file that does not parse (its names cannot be resolved), and, for every
protocol the topology names, **unlabelled steps**: a step without a label gets a
positional name (`Msg_A_B_2`) that renumbers when a step is added before it, which
changes its wire tag on a hot deploy. Label each step: `order: Client -> Ledger : Int`.

The compiler side, `march --topology .forge/topology.json` (which `forge build` and
`forge run` pass), refuses any schema version but 1 and checks, against the loaded
modules, that:

- every bound name exists;
- a `body` takes the pool's environment (its hook's return type, or `()` without a
  hook), the session, one `Cap(P)` per `role R needs` entry of its protocol, and the
  entry state;
- a bound actor's `init` takes the pool's environment, and the actor handles `Start`,
  `Deliver` and `Cancel` (below);
- a hook takes `Cap(P)` parameters, then the `Cap(ClusterNode.Live)`, and declares
  its return type;
- a role's grant, and a hook's `Cap` parameters, fit within a written `caps`;
- after typechecking, what a pool's hook and roles actually **reach** fits within a
  written `caps`, naming the hook or role that reaches beyond it;
- with `--topology-isolate-foreign`, no role or hook needing `IO.Foreign` sits in a
  pool that is not `isolate = true`.

A hand-written `main` is kept, with a warning: it gives up running every pool in one
process and the node-owned offers.

## Editor support

`march-lsp` serves `topology.toml` and `topology.<env>.toml` (it recognises them by
name; see `lsp/docs/editors.md` to attach it). It reads them with forge's own parser
and runs forge's own checks, so what the editor shows is what `forge topology check`
prints:

- **Diagnostics**, with forge's message on the line forge names. An overlay shows
  what `forge topology check --env <env>` reports in the overlay. The base file shows
  what `forge topology check` reports, plus what each overlay next to it adds in the
  base file (a `place.count` above the host count only exists once an overlay
  supplies hosts); those carry the source `forge topology --env <env>`. The names
  resolve against the open editor buffers, so editing a `.march` file (renaming the
  function a `body` names, say) updates the topology file's diagnostics without a
  save.
- **Go to definition** on a `body`, `actor` or `start` string jumps to the declaration
  it resolves to. On a `"Protocol.Role"` string (a `[roles]` key, a `serves` or
  `initiates` entry), the protocol part jumps to the `protocol` declaration and the
  role part to the role inside it: its `role R needs` line, else its first message.
- **Completion** inside those strings: functions for `body` and `start`, actors for
  `actor`, `Protocol.Role` for `serves`, `initiates` and new `[roles]` keys, host
  labels for `place.on`. Outside strings, the known keys of the section (or inline
  table) the cursor is in, and section names in a header, including the base file's
  pool names when an overlay starts a `[pool.`.
- **Hover** on a role string shows its `role R needs ...` grant and its body type,
  `(Cap(Session.Live), Cap(P)..., <P>_<R>.Entry) -> <P>_<R>.Yield`, with the pool
  environment a topology-bound `body` takes first.

## `forge topology export --json`

Prints the digest plus the derived facts:

- `derived.<pool>.caps` and `derived.<pool>.initiates`: the capabilities the pool's
  hook and roles reach and the roles its code initiates, as the compiler derives them
  (`"source": "compiler"`). When the compiler cannot run (the program does not
  typecheck, say), `caps` is `null`, `initiates` falls back to a by-name search of the
  sources (`"source": "names"`), and forge says why;
- `connectivity`: which pools talk to which, and over which protocols. Two pools are
  connected when a role one of them serves or initiates exchanges a message with a
  role the other does, the same rule the generated `peers_<Role>()` uses. A pool whose
  own roles talk to each other has an edge to itself, which matters when the pool
  spans several hosts;
- `cluster_port` and each pool's `public` ports.

The JSON schema is documented in
[specs/features/topology.md](https://github.com/march-language/march/blob/main/specs/features/topology.md).

## `forge topology gen <target>`

Built-in targets, each written to stdout behind `# ==> <file> <==` markers, or under a
directory with `--out DIR`:

| Target | Output |
|---|---|
| `systemd` | One `march-<pool>.service` per pool, run as `User=march`: `MARCH_POOLS`, `MARCH_TOPOLOGY_FILE`, the status file, the reload socket and `HOME`, an `EnvironmentFile` for secrets, `TimeoutStopSec` from `[drain] hard_ms`. `forge host init` writes one per host with that host's own settings too. |
| `ufw` | One `ufw-<host>.sh` per host: ssh, its pool's public ports from anywhere, the cluster port only from the hosts of the pools it talks to. |
| `do-firewall` | `do-firewalls.json`: one DigitalOcean firewall per pool, keyed by droplet tag `march-<pool>`, with the same rules. |
| `compose` | `docker-compose.yml`: one service per pool, `replicas` from the host count, `ports` from `public`. |

Any other target runs `forge-topology-<target>` from `PATH` with the export JSON on
its stdin, the same convention as `forge-<subcommand>` plugins, so a Kubernetes or
Nomad generator can live outside forge.

```bash
forge topology gen systemd --env prod --out deploy/systemd
forge topology gen ufw --env prod
forge topology gen k8s        # runs forge-topology-k8s if it is on PATH
```

## Running a topology app

In a topology app the compiler generates `main`. For each pool it contains, the
generated `main`:

1. starts the cluster node from the environment (`MARCH_NODE_NAME`, default
   `local-1`; `MARCH_NODE_PORT`, default 7946; `MARCH_CLUSTER_NODES`, the seeds);
2. runs the pool's hook, passing one narrowed capability per `Cap(P)` parameter it
   declares, then the node handle;
3. opens the offers the topology places on this node, re-evaluating as nodes join
   and leave;
4. on SIGTERM or SIGINT, closes every offer, lets running sessions finish, and exits
   (`[drain] hard_ms` is the most it waits);
5. offers a role again if its offer, or the actor serving it, dies.

A process of a shared build runs the pools named in `MARCH_POOLS` (comma-separated),
or every pool when it is unset. `MARCH_NODE_LABELS` (comma-separated) are the labels
`place = { on = ... }` looks for.

### Hooks

A pool's `start` is where hand-written startup goes. It runs on every node of the
pool, before any offer opens, and its return value is the environment every role of
the pool receives:

```march
mod Back do
  type Env = { factor : Int }

  fn start(_con : Cap(IO.Console), _node : Cap(ClusterNode.Live)) : Env do
    { factor: 10 }
  end
end
```

**A hook must return promptly.** Start long-lived work (a server, a loop that
initiates sessions) in a task or actor. A hook still running after
`MARCH_HOOK_TIMEOUT_MS` (default 10000) is reported by name and the process exits 1.

### Role bindings

A **function** binding serves one session: the pool's environment, the session, the
role's granted capabilities, the entry state:

```march
-- protocol Echo do  role Server needs IO.Console  ...  end
fn serve_one(env : Env, s : Cap(Session.Live), con : Cap(IO.Console),
             st : Echo_Server.Entry) : Echo_Server.Yield do ... end
```

An **actor** binding (`actor = "..."`) holds state across sessions. The generated code
spawns one per offer with the pool's environment as its `init` argument, and forwards
each session to it:

```march
actor CounterActor do
  state { total : Int, sessions : LinearMap(String, Count_Counter.Parked_Counter) }
  init(env : Env) { total: 0, sessions: LinearMap.empty_string() }
  on Start(sid : String, s : Cap(Session.Live)) do ... end   -- plus the role's granted caps
  on Deliver(sid : String, s : Cap(Session.Live), from : Int, msg : Bytes, ep : Int) do ... end
  on Cancel(sid : String, s : Cap(Session.Live), role : Int, cause : String, ep : Int) do ... end
end
```

These are the three messages a hosted access point's actor takes
(`offer_hosted_<Role>`, see the Choreography chapter).

### `forge run`

```bash
forge run               # every pool in one process
forge run --processes   # one process per pool, a cluster on this machine
```

A topology app always runs **compiled**, even when `forge run` would otherwise
interpret: the runner that serves roles is compiled-only, and forge says so. In one
process, every pool's roles are served by the same node, and a session whose roles
are all local runs over the node's loopback link. An initiator prefers an offer on its
own node.

`--processes` builds once for the pools that share a build and once per isolated pool,
then starts one process per pool (one per host, when an `--env` overlay lists hosts),
named `<pool>-<n>`, each on a free port with every other process as a seed, and prints
their output prefixed with the process name. Logs are kept under `.forge/run/`.
Ctrl-C drains and stops every process; `--fail-fast` stops them all as soon as one
exits.

[examples/topology_app](https://github.com/march-language/march/tree/main/examples/topology_app)
is a complete two-pool app.

## Changing placement on a running system

A node opens its own offers from the topology it was given, and it re-reads that
topology on **SIGHUP**. The reconciler (at small scale, `forge` on your machine) never
opens or closes an offer itself: it writes the new topology and signals the nodes, and
each node decides what it now serves. A placement change therefore needs no code change
and no restart.

```bash
forge run --processes --env dev   # in one terminal: the cluster, one process per pool
# edit topology.toml or topology.dev.toml: place = { on = "b", count = 1 }
forge topology apply --env dev    # in another: one reconciliation pass
forge topology status             # what each node holds
```

`forge topology apply` is one pass: it loads and checks the topology (with the overlay
the cluster was started with, unless `--env` says otherwise), diffs it against what the
nodes were given, pushes it (`.forge/topology.json` rewritten, SIGHUP to every node),
waits until every node reports the new digest and its offers have settled, and prints
each node's offers:

```
1 change(s), none needs a restart:
  Echo.Server: placement count 1 -> count 1 on a
pushed c5d272a26c83 to 3 node(s)
a-1 (pool a, pid 83370, port 57968)
  topology: c5d272a26c83
  offers: Echo.Server
b-1 (pool b, pid 83371, port 57969)
  topology: c5d272a26c83
  offers: (none)
```

What a node applies from a re-read topology, for the roles its build contains:

- a role's **placement** (`place`): a role this node now ranks for is offered; one it
  no longer ranks for is closed and **drains** (new invitations are refused, running
  sessions finish; the closed offer is reported at the topology's soft and hard
  deadlines if sessions are still running);
- a role's **capacity**: the offer is closed and reopened at the new size;
- a role a pool **stops serving**, or a role **removed** from `[roles]`: its offers
  close and drain;
- the `[drain]` deadlines for offers closed from then on.

What needs a rebuild and restart, and is refused by `apply` with the list: a role's
binding (`body`/`actor`), a new role, a role newly served by a pool (its build has no
code for it), a pool's hook, `caps`, `initiates`, `isolate`, hosts and labels (a node
reads its labels when it starts), pools added or removed. Stop the cluster and run
`forge run --processes` again.

Two `forge` invocations cannot reconcile the same project at once: a pass holds
`.forge/run/reconcile.lock`, and a second one reports who holds it. The running
cluster is recorded in `.forge/run/state.json` (pids, ports, reload sockets, each
node's status file) while `forge run --processes` lasts. Each node reports the digest it
applied, its offers and its running sessions to `.forge/run/<node>.status`
(`MARCH_TOPOLOGY_STATUS`); a node that has not reported yet is never signalled, since a
process with no watcher would die of the SIGHUP.

Outside forge, the same works by hand: write the digest to the file the node was started
with (`MARCH_TOPOLOGY_FILE`) and send it SIGHUP.

## Deploying

A topology whose overlay says `[backend] kind = "ssh"` is deployed to the overlay's
hosts by `forge deploy`, one reconciliation pass per run, with `forge` on your machine as
the reconciler (there is no daemon).

```toml
# topology.prod.toml
[pool.back]
hosts = [{ host = "root@back-1", labels = ["db"] }, "root@back-2"]

[pool.front]
hosts = ["root@front-1"]

[backend]
kind = "ssh"
```

**Once per host: `forge host init --env prod`.** Over ssh, idempotently (a second run
changes nothing):

- the `march` system user and `/opt/march/<project>` (code), `/var/lib/march/<project>`
  (the service's HOME: its CAS root keeps the persisted patch stack, and `run/` holds the
  reload socket and the status file), `/etc/march/<project>` (configuration);
- `/etc/systemd/system/march-<pool>.service` from the `systemd` generator, with this
  host's `Environment=`: node name (`<pool>-<host>`), labels, cluster port and advertised
  address, the other nodes as seeds, the reload socket, the status and topology files,
  `MARCH_DEPLOY_POLICY`; enabled where systemd runs;
- the deploy public key; the cluster secret (generated once per environment, in the
  pool's env file, mode 0640), or, when an operator key exists (`forge cluster keygen`;
  `.forge/cluster/operator.key` or `--operator-key`), a node certificate per node, issued
  for the roles the pool offers and initiates and reused until 30 days before it
  expires;
- the node's capability policy (`<pool>.policy`, the admission gate's
  `MARCH_DEPLOY_POLICY`) from the pool's written `caps`, else the compiler's derived ones;
  the gate also applies it to each patched function's own capabilities;
- the pool's ufw rules (applied when ufw is installed; `--no-firewall` only writes them),
  and the DigitalOcean firewall JSON locally in `.forge/hosts/prod/`;
- each host's target (`uname -sm`), recorded in `.forge/hosts/prod.json`.

One pool per host: a host listed in two pools is refused.

**Every deploy: `forge deploy --env prod`.** It builds each build (the shared one, each
isolated pool's) for each target its hosts recorded, compares it with what was last
deployed there (`.forge/deploy/prod/`), prints the plan, asks, and carries it out.
`--plan` prints the plan and stops:

```
forge deploy --plan (env prod)

1. What changed
  build shared (pools back, front): 1 function(s) changed, 0 added, 0 removed
    changed: Back.scale

2. Mechanism and why
  pool back (build shared, 1 host): hot patch
    1 function(s) changed, 0 added, 0 removed
  ...

3. Order and splits
  1. pool back (hot patch)
  ...

4. Drains
  none

5. What may be lost
  nothing

6. Authority and derived values
  no capability widens
  pool back: caps IO.Console; initiates (none)
  ...
```

Per pool, the mechanism is the strongest that applies:

| Mechanism | When |
|---|---|
| blocked | a state change with no `migrate_state` under its `@compat`, a `migrate_msg` for the wrong old type, a widening capability without `--grant-cap` |
| restart | nothing deployed yet; a pool hook changed (hooks run once, at start); the C runtime, HCR ABI or target changed; a binding, a new role or pool, hosts or labels changed; code the running base cannot swap; compaction |
| hot patch + protocol drain | a protocol's wire fingerprint changed: its offers close and drain |
| hot patch + migration | an actor's state changed and `migrate_state` exists |
| hot patch | functions changed |
| topology push | only placement or capacity changed |

A choice that gains a branch is safe when every receiver of the choice runs the new
version before its chooser does, so pools that receive it go first. When one build both
chooses and receives it (a replicated monolith), no order works within one deploy: the
plan splits it in two (D21). Deploy one activates everything except the chooser role's
functions; `forge deploy` stops there, and running it again does deploy two. The finer
rule, which (role, version) pairs may share a session over wire tags, comes with the
protocol compatibility table. The plan also names the unlabelled messages a new branch
would renumber.

`forge topology status --env prod` and `forge topology apply --env prod` work over ssh
too: status reads each node's report, its reload server (code versions, pins, what its
last start restored, the patch stack's size, its target) and says whether the node runs
what forge last deployed; apply pushes a placement-only change, the signed `TOPOLOGY`
verb on each node's reload socket, then the digest file and a SIGHUP to its unit, and
refuses a change that needs `forge deploy`.

`forge deploy --compact` rebuilds each build's base image from the current version and
restarts its hosts onto it, clearing their persisted patch stacks; `[hot-reload]
compact_after = N` in `forge.toml` does it when a node's stack grows past `N`.

ssh is plain `ssh` from `PATH` (your `~/.ssh/config` applies); `FORGE_SSH_CONFIG=<file>`
adds `-F <file>`. Scripts run as root, or through `sudo -n`.

## Testing an upgrade

```bash
forge test --upgrade-from v1.4.0     # any git ref
```

An upgrade test runs the **old** version of the app as local processes, drives traffic
through it, hot-deploys the working tree into those processes, and checks what the
deploy did:

1. `git worktree add` at the ref under `.forge/upgrade/<ref>` (the directory ignores
   itself), built with hot reload and started like `forge run --processes`, each process
   with a reload socket;
2. every `test/upgrade_*.march` of the working tree is compiled and started as one more
   node of that cluster. It is the traffic: it opens sessions, sends actors messages, and
   makes its own checks. It is given `MARCH_UPGRADE_SOCKETS` (the reload sockets),
   `MARCH_UPGRADE_READY` (a file it creates once its pre-upgrade traffic is running) and
   `MARCH_UPGRADE_DEPLOYED` (a file forge creates once the new code is live), and it
   exits 0 when its checks pass;
3. the working tree is deployed into every process through the same path as
   `forge deploy hot`, on the local socket;
4. forge waits for the tests to finish and for the drain, then reads each process's
   `PINS`.

The test passes when every test file exited 0, every old process is still running, and
the counters show **nothing dropped**, nothing killed by a hard drain deadline and no
epoch marker lost. A dropped message is the typical broken upgrade: an actor whose
message type changed while old code (a task started before the deploy, another node)
still sends it the old format, with no `<actor>_migrate_msg` to convert it. The report
names it:

```
upgrade from HEAD FAILED:
  app-1 dropped 255 message(s): an actor's message type changed and old code still
  sent it the old format, with no migrate_msg for it (write one: forge hot-reload
  migrate-msg-stub <Actor>)
```

Actors that hold their epoch for an unfinished session, or sit in a nested `receive`,
and units that are not actors (tasks) stay on the old epoch until a hard drain deadline,
which is off by default; the report lists them, and `MARCH_UPGRADE_STRICT_DRAIN=1` makes
them a failure. `MARCH_UPGRADE_DRAIN_S` (60) bounds the wait for the drain,
`MARCH_UPGRADE_TEST_S` (180) the wait for the test files.

A test file declares the protocols it drives itself (a protocol's wire identity is its
name, roles and steps, so a copy interoperates with the app's), starts its node with
`Topology.config_from_env()`, and initiates sessions as the app's own initiators would.
[forge/test/fixtures/upgrade](https://github.com/march-language/march/tree/main/forge/test/fixtures/upgrade)
holds a complete one: `v1` (the old version and its `test/upgrade_traffic.march`),
`good` (an upgrade that passes) and `drops` (one that drops messages and fails).
