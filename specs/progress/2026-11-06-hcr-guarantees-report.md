`[P2]` The guarantee report: `march --check --guarantees` / `forge hot-reload check` (lemmas B)

Phase B of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§1.2, §7): one
labelled line per actor and protocol, so no stated guarantee is silent about whether it was
checked.

## Before

A user could learn what a build proved only by reading `--refine-report-sites` rows and
knowing which callee was an actor, which span was a migration, and which annotations nothing
checks. `@invariant` looked like a checked actor invariant and was not (see below).

## Fix

- `bin/guarantees.ml` (new). After the check, it reads the obligation ledger
  (`Obligation.all`) and the decls, and prints per actor:
  - state refinements: precondition obligations whose callee is the actor (the state record
    built in `init` and handlers);
  - `@invariant`: `not checked`;
  - handler contracts: precondition obligations on the actor's message constructors, or
    `proved` with no site when a refined handler is never sent to;
  - `migrate_state` (written: by span containment in `<actor>_migrate_state`; derived: by
    the synthetic `<none>` file `Desugar_derive.respan_derived_decl` gives its body, since
    its outer span is the actor's), against the deployed build or its parameter type, with
    the `--accept-unproved` consequence of a `not proved`;
  - `migrate_msg`; messages from other nodes (`assumed`, `@[remote]` actors).
  Per protocol: projection `checked (compiler)`, deadlock freedom `not checked`. A
  `runtime: assumed` block when there are actors. A block's header is its weakest line,
  `assumed` aside; a block of only `assumed` lines is `assumed`.
- `bin/main.ml` / `bin/flags.ml`: `--guarantees` (implies `--check`), printed at both
  check sites after the refinement reports, and it bypasses the early check cache.
- `forge hot-reload check` (`Cmd_deploy_hot.run_check`): `march --check --guarantees` on
  the project entry under the project's `MARCH_LIB_PATH`, with `--hcr-baseline` set to
  `.march/<name>_hot.so.schemas.json.prev` when it exists; exits with march's code.
- Docs: `docs/hot-code-reload.md`, "What a build guarantees: `forge hot-reload check`".

## Found

`@invariant` is never checked on `init` or handler results, only across a hot deploy: todo
`2026-11-06-invariant-unchecked-on-init-and-handlers` (P1). The report labels it
`not checked` meanwhile.

## Tests

`test_refinecheck` suite `guarantees` (7 cases, through the CLI): proved state with an
unchecked `@invariant` and an assumed runtime; a clean actor is `proved`; a violated `init`
is `violated` with `--check`'s exit code unchanged; a written migration with no deployed
build; two- and three-role protocols; a derived migration against a baseline counts its own
site and leaves the actor's sites to the state line; nothing to report.

## Not covered

The model labels (`proved (model) · tested (runtime)`, `proved (spec) · validated
(compiler)`) arrive with phases C and D. Actors in nested modules are listed under their
short name.
