`[P2]` M3 + H3: migration is a simulation, for `@compat(simulation)` actors

Phase F of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.4 H3, §6 M3, §7).
The law: handling a message on the deployed code and then migrating gives the same state as
migrating first and handling it on the new code, so a deploy marker's position is harmless.

## Decisions (the design's open questions 1 and 2)

- **Opt-in**, as `@compat(simulation)`: the `full` shape policy plus the law (forge's
  `check_compat` treats an unknown policy as `full`, so no grammar or forge change). Most
  deploys change behaviour on purpose.
- **Where the old handlers come from: their source, in the sidecar.** A `--hot-reload` build
  of a simulation actor writes `"steps": [{"msg", "params", "body"}]` into `.schemas.json`,
  each body printed by `March_format.Format.expr_inline` (which re-parses since #1174/#1175)
  and JSON-escaped by `Schema_migration.json_string` (OCaml's `%S` writes decimal escapes
  JSON rejects). The next build's driver parses them back (`load_simulation_baseline`,
  beside the M11 baseline, before desugar).

## What

`lib/desugar/desugar_simulation.ml` (after the rollback pass; never in the stdlib), per
message both builds handle with the same arity, when no `migrate_msg` is declared:

- `@[hcr_logic] fn <a>__old_step__<M>(state : Old, p…) : Old` (the deployed body, its
  parameters renamed to the current handler's) and `<a>__new_step__<M>` (the current body):
  the handlers as functions of the state (M3). A call in statement position is dropped; a
  parameter (or `state`) the body no longer reads is named `_…`, so no lint fires on
  generated code (an unused-binding fix on it spanned the whole actor).
- `@[lemma] fn <a>_simulates__<M>(old_state : Old, p…) : {Unit | new_step(mig(old_state), p…)
  == mig(old_step(old_state, p…))}`, `mig` being `<a>_migrate_state` or, for an unchanged
  field set, the identity.
- Carried only when both bodies stay inside a grammar that typechecks the same in any build
  (literals, `state` and its fields, parameters, `let`, `if`, records, operators, list and
  option constructors, standard-library module calls); otherwise the message is reported
  `Not_checked` with the reason. A handler the deployed build lacks is `New_handler`.
- Erasure: `Lemma_erase.drop_unreferenced` removes `hcr_logic` declarations; the unknown-
  attribute lint skips `hcr_logic`. `Refine_anon.lifts_all` covers the generated names, so
  their anonymous records reflect (H5's machinery).
- `--guarantees`: a `simulation` line, one verdict per message (from the ledger or
  `Refine_call.lemma_refuted`).

## Tests

`test_refinecheck` suite `hcr-simulation`, end to end (v1 built with `--compile-so
--hot-reload`, v2 checked against its sidecar): the sidecar records steps; an unchanged
handler commutes and a new one is trivially fine; a changed handler is refuted (`n = 7719`,
`old_state = { count: 0 }`); a state that gained a field with a `migrate_state` commutes; a
body calling the program's function is `not checked` with the reason. RED: the sidecar
writer off turns all five red; the desugar pass off turns 1-4 red. Also checked by hand: v2
compiled (`--compile`) against a real v1 sidecar has no diagnostics, runs, and contains no
generated symbol.

## Residual

- A deploy that changes the message type (`migrate_msg`) is not carried: the law then runs
  through the conversion (an `Option`), which needs the old message type's constructors.
- Handlers that call the program's own functions are not carried: the deployed build's
  definitions would have to travel too (the design's D17-hashed templates).
- `match` in a handler body is not carried yet.
- `<Actor>.step` is internal; a user cannot yet name a handler in a hand-written lemma (todo
  `2026-11-06-actor-inductive-invariants`).
- A failure's theorem text names the generated functions (`tally__new_step__Bump`).
