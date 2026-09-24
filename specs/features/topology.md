# Topology file and digest (`forge topology`)

**Status:** static half landed 2026-09-22 (build step 7 of
`specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md`, section 4 and
II.6); level 0 landed 2026-09-23 (build step 3: the generated `main`, runtime
placement, `forge run` and `forge run --processes`). Implementation:
`forge/lib/topology.ml`; CLI in `forge/bin/main.ml` (`forge topology
check|export|gen`); `forge/lib/topology_run.ml` (`forge run` on a topology app and
the compiler-derived export values); compiler flag `--topology` in `bin/main.ml`
(`bin/flags.ml`, `bin/topology_gen.ml`) with the generated `main` in
`lib/desugar/desugar_topology.ml`; the runtime side in `stdlib/topology.march`;
generator templates under `forge/templates/topology/`. User documentation:
`docs/topology.md`.

## Files

| File | Owner | Role |
|---|---|---|
| `topology.toml` | developers (`[roles]`) and operators (`[pool.*]`, `[drain]`, `[backend]`) | The base file. |
| `topology.<env>.toml` | operators | An overlay: tables deep-merge, arrays replace. |
| `.forge/topology.json` | forge, written by `check` (and by the gate in `build`/`run`/`deploy hot`) | The digest the compiler and, later, the runtime read. |

## The digest: `.forge/topology.json`, schema version 1

Every reader checks `version` first. The compiler (`march --topology`) refuses any
other version; a future schema bumps the number and adds a migration in
`Topology.read_digest`.

```jsonc
{
  "version": 1,
  "env": "prod" | null,             // the overlay that was applied
  "sources": ["topology.toml", "topology.prod.toml"],
  "roles": [                        // file order
    {
      "name": "Checkout.Ledger",
      "protocol": "Checkout",
      "role": "Ledger",
      "body": "Shop.Ledger.serve_one" | null,   // exactly one of body / actor
      "actor": "Shop.ServerActor" | null,
      "capacity": 64 | null,
      "place": { "on": "gpu" | null, "count": 2 | null } | null,  // null: everywhere (D18)
      "set": false                              // reserved for role sets (D7)
    }
  ],
  "pools": [                        // file order
    {
      "name": "edge",
      "start": "Shop.Edge.start" | null,
      "serves": ["Checkout.Ledger"],            // "*" is already expanded
      "serves_all": false,
      "initiates": ["Quotes.Client"] | null,    // null: derived (D22)
      "caps": ["IO.FileWrite"] | null,          // null: derived (D22)
      "isolate": false,
      "public": [443],
      "main": "src/x_main.march" | null,        // the escape hatch (plan 4.1)
      "replicas": 3 | null,
      "hosts": [ { "host": "root@web-1", "labels": ["public"] } ]
    }
  ],
  "drain": { "soft_ms": 30000 | null, "hard_ms": 120000 | null } | null,
  "backend": { "kind": "ssh" | null, "port": 7946 | null } | null
}
```

Names (`body`, `actor`, `start`) are qualified from the file's top-level module:
`Shop.Ledger.serve_one` for `fn serve_one` in `mod Ledger` in `mod Shop`. A role name
is `Protocol.Role` with the protocol's short (declared) name.

## The export: `forge topology export --json`

The digest's fields plus:

```jsonc
{
  "derived": {
    "edge": {
      "initiates": ["Checkout.Client"],   // <P>_Run.initiate_<R> reachable from the hook
                                          // and the served roles (typed, by the compiler)
      "caps": ["IO.NetListen"],           // what the hook and roles reach (D22); null when
                                          // the compiler could not run
      "source": "compiler"                // or "names": the by-name fallback
    }
  },
  "connectivity": [
    { "from": "edge", "to": "ledger", "protocols": ["Checkout"] }
  ],
  "cluster_port": 7946
}
```

A connectivity edge joins two pools when a role one of them serves or initiates
exchanges a message with a role the other serves or initiates, by the rule of the
generated `peers_<Role>()` (`peers_of` in `lib/desugar/desugar_endpoints.ml`). Edges
are undirected with `from <= to`; a pool whose own roles talk to each other has an
edge to itself.

`forge topology gen <target>` feeds exactly this document to an external
`forge-topology-<target>` on its stdin.

## Checks

`Topology.read` (shape and unknown keys) and `Topology.check` (against the project's
parse, `Topology.index_project`) are listed on `docs/topology.md`. Everything reports
`file:line`; a key inside an inline table reports the line of the key that holds the
table, since the TOML parser records one line per top-level key.

`forge build`, `forge run` (interpreted and single-file compiled runs; the compiled
project run gates through `forge build`) and `forge deploy hot` call `Topology.gate`,
a no-op without a `topology.toml`.

## Derived facts: what is forge's and what is the compiler's (D22)

- **`initiates`** is derived by forge from the parse: every `<P>_Run.initiate_<R>`
  reference in code reachable, through call references, from the pool's `start` hook
  and the bodies/actors of the roles it serves. Reachability is by name resolution over
  the parse (a callee as written, else the name under each enclosing module of the
  caller), without types, so a call through a closure value or an interface method is
  not followed.
- **`caps`** derivation needs the typechecker's capability closure and is the
  compiler's. It is `null` in the export until `march --topology` grows the derivation
  (step 3/4). D26's widening gate (`--grant-cap` on a deploy) waits on the same.

## Tests

- `forge/test/test_topology.ml` (29 cases, in-process): parse, overlay merge
  semantics, every unknown-key site with its line, each check, digest and export
  round trips, the gate, one golden per built-in generator under
  `forge/test/topology_golden/` (`UPDATE_TOPOLOGY_GOLDEN=<dir>` regenerates), and a
  `forge-topology-echo` plugin on a private `PATH`.
- `test/test_topology_flag.ml` (compiler suite, `topology_flag` group): `march --check
  --topology` accepts a valid digest, resolves a body/actor/hook in the entry and in
  an imported sibling module, rejects an unbound name with its message, refuses
  schema version 2 and a missing file.

## The compiler's `topology` object

`march --topology <digest> --emit-core-ast <entry>` adds, after typechecking:

```jsonc
"topology": {
  "version": 1,
  "generated_main": true,                 // false: the entry has its own main
  "pools": {
    "edge": {
      "caps": ["IO"],                     // IO caps reached by the hook and the roles
      "reached_from": { "IO": "hook Shop.Edge.start" },
      "initiates": ["Checkout.Client"]
    }
  }
}
```

`forge topology export` (and `gen`) read `caps` and `initiates` from it
(`Topology_run.compiler_derived`). Without `--topology` the document has no such key.
