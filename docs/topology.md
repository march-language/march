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

This page covers the **static** half that exists today (build step 7 of the
[distributed-deploys plan](https://github.com/march-language/march/blob/main/specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md)).
The generated `main` that opens offers from the topology, placement at run time,
derived capabilities and `forge deploy --plan` are later steps; until they land, a
topology file is checked and exported, but a program still runs its hand-written `main`.

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
| | `caps` | Capabilities the pool's user code may use. Written: an upper limit. Derivation is the compiler's job and is not implemented yet. |
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
- **`count = n`:** offered on n of the pool's live members (at run time, chosen by
  rendezvous hashing over cluster membership; not implemented yet).
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

The compiler side, `march --topology .forge/topology.json`, reads the digest, refuses
any schema version but 1, and checks that every bound name exists in the modules it
loaded. It does nothing else yet.

## `forge topology export --json`

Prints the digest plus the derived facts:

- `derived.<pool>.initiates`: what the pool's reachable code initiates (`caps` is
  `null` until the compiler derives it);
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
| `systemd` | One `march-<pool>.service` per pool: `MARCH_POOL`, `MARCH_TOPOLOGY`, an `EnvironmentFile` for per-host settings, `TimeoutStopSec` from `[drain] hard_ms`. |
| `ufw` | One `ufw-<host>.sh` per host: its pool's public ports from anywhere, the cluster port only from the hosts of the pools it talks to. |
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
