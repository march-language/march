# Distributed deploys, build step 7: the topology file, static half

**DONE 2026-09-22.** Step 7 of
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md)
(section 4, 4.2, II.6; D6, D7, D18, D22, D25, D26). What is deferred stays in
[../todos/2026-09-22-dd-step07-topology-file.md](../todos/2026-09-22-dd-step07-topology-file.md).
Builds on G4 (`Toml` line numbers, `check_keys`, `_at` accessors) and G5
(`Project.entry`).

## What landed

- **`forge/lib/topology.ml`.** `load ~root ?env ()` parses `topology.toml` and
  merges `topology.<env>.toml` (tables deep-merge, inline tables included; arrays
  replace); every key keeps its file and line through the merge, so a diagnostic
  names the overlay when the key came from there. `read` types the merged document:
  `[roles]` (`body`/`actor`, `capacity`, `place = { on, count }`, `set`),
  `[pool.*]` (`start`, `serves` incl. `"*"` expanded, `initiates`, `caps`,
  `isolate`, `public`, `main`, `replicas`, `hosts` as strings or
  `{ host, labels }`), `[drain]`, `[backend]` (`kind`, `port`). Unknown keys and
  sections are errors with `file:line`, as are wrong value shapes.
- **`check ~index t`** against `index_project ~root`, the parse of every non-test
  `.march` under the root (the same walk `forge cap query` does, kept local to
  avoid a `Cmd_build` cycle): bindings resolve to a declared fn/actor; role names
  are real `Protocol.Role`s (protocol found by short or qualified name); every
  served role is bound and every bound role served; `place.on` labels exist and
  `place.count` fits the (labelled) hosts once an overlay supplies hosts; isolated
  pools share no role; a written `initiates` is an upper limit on the derived one
  (D22); `main` warns; D25 warns per protocol with unlabelled steps (a choice
  branch's head counts as labelled, mirroring `annotate`).
- **Derived `initiates`.** `<P>_Run.initiate_<R>` references in code reachable
  (by call references, resolved as written or under the caller's enclosing
  modules) from the hook and the served roles' bodies/actors. The parser turns a
  module-qualified call head into a nullary constructor (`ECon`), which the
  first walker missed; the smoke test caught it (`"initiates": []`).
- **Digest** `.forge/topology.json`, `version: 1`; `read_digest` refuses other
  versions. **Export** adds `derived`, `connectivity` (the `peers_of` rule from
  `lib/desugar/desugar_endpoints.ml`, undirected, self-edges kept) and
  `cluster_port`. Schema in the module comment and `specs/features/topology.md`.
- **Generators** (`Gen`): `systemd`, `ufw`, `do-firewall`, `compose` from
  templates under `forge/templates/topology/` embedded by the dune idiom
  (`forge/lib/dune`), `{{key}}` substitution; else `forge-topology-<target>` on
  PATH via `Cli_ext.external_subcommand`, fed the export on stdin.
- **CLI:** `forge topology check|export --json|gen <target> [--out DIR]`, all
  taking `--env`; registered in `known_builtin_names`. **Gate:** `Topology.gate` in
  `Cmd_build.build`, `Cmd_run.run` (the non-build paths) and both hot-deploy
  entry points (`--env` picks the overlay when it exists).
- **Compiler:** `march --topology <json>` (`bin/flags.ml`, `bin/main.ml`) reads
  the digest before the import merge (entry decls flat under the entry's name,
  imports as `DMod`) and exits 1 on a bad version or an unbound name. Nothing
  else yet.
- Docs: `docs/topology.md` (hand-written page, like `docs/hot-code-reload.md`),
  `specs/features/topology.md`, a pointer in `docs/tooling.md`, CHANGELOG.

## Tests

- `forge/test/test_topology.ml`, 29 cases (own `(test)` stanza; in-process, no
  toolchain): parse; overlay merge (arrays replace, inline tables deep-merge,
  missing overlay); unknown keys at every site and in the overlay with lines;
  malformed TOML line; value shapes; each check; `serves = "*"`; derived
  initiates through a helper and the connectivity edge; digest/export round
  trips; `read_digest` version gate; `unresolved_names`; the gate (no-op without a
  file, env fallback, failure message); four generator goldens under
  `forge/test/topology_golden/` (`UPDATE_TOPOLOGY_GOLDEN=<dir>` regenerates);
  a `forge-topology-echo` plugin on a private PATH receiving the export.
- `test/test_topology_flag.ml`, 5 cases in the compiler suite: valid digest exits
  0 with no topology output; an actor binding; an unbound body and hook (in an
  imported sibling) name both; version 2 refused; missing file refused.
