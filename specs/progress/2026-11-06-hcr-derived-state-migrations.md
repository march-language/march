`[P2]` Derived state migrations: adding a field needs no `migrate_state` (M11)

Phase A2 of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.3, "Fewer
migrations to prove"; table row M11): "Derive [mechanical migrations] from the schema diff …
Prove each derivation rule once, in the compiler's own test suite."

## Before

Any state change needed a hand-written `<actor>_migrate_state`, or the deploy gate refused it
(`@compat(full) violated: field added: …`). The common case, a new field with a starting
value, made the user write and prove a function that copies every old field.

## Fix

- `lib/desugar/desugar_migrate_derive.ml` (new). With the deployed layout known
  (`baseline`, actor to `(field, schema type string)`), an actor whose state differs from it
  only by added fields, each with a constant `init` value, gets
  `fn <actor>_migrate_state(migrate_old__ : { kept… }) : { new… }` right after the actor:
  kept fields are `migrate_old__.f`, added ones the `init` expression. It runs before
  `Desugar_migrate` and `Desugar_migrate_check`, so the M10 live-data check is generated for
  it too. Never in a stdlib file.
  - Not derived, with the reason recorded in `report`: a removed field, a field whose type
    string changed (or a type `schema_str` cannot spell the way the driver's
    `ty_to_schema_str` does, so a doubt never derives), an added field whose `init` value is
    not a constant (`constant`: literals, constructors, tuples, records and calls of named
    functions; an `init` parameter is rejected), or an `init` that is not a record literal.
  - A written `<actor>_migrate_state` in the same declaration list always wins.
- Driver: `Schema_migration.load_derive_baseline` fills the layout from the same file
  `load_baseline` reads, before desugar. `baseline_cas_tag` puts the baseline's digest in the
  build and the `--check` cache keys (`hbase:`): the baseline now decides code, and it already
  decided diagnostics, which the check cache did not key on.
- `.schemas.json`: `"migrate_derived": [added fields]` or `"migrate_not_derived": "<why>"`.
  forge (`Schema_diff.derived_note` / `not_derived_note`) prints the derived line at deploy
  and appends the reason to the compat refusal in `forge deploy hot` and the deploy plan.
- Diagnostics: a counterexample to a derived migration (`Hcr_baseline.derived`, filled by the
  driver from the pass's `origins`) is reported at the actor's state field, as
  "A running `Counter` can hold a state this version rejects … but the running state
  { count: 0 } would become { … }", with notes that the migration was derived and that
  writing it is the way out. Before this it named a function the user never wrote and had no
  excerpt.

## The two rules, proved once

`test_refinecheck` suite `hcr-derived-migration` (9 cases):

- KEEP + ADD prove with nothing skipped, and each adds exactly one proof over the same
  program with no deploy known (so the assertion is about the derived function, not `init`).
- Neither is trusted: a tightened refinement on a kept field is refuted with the deployed
  state, and an added field whose `init` value breaks its refinement is an error.
- The control: without the deployed refinement as a hypothesis, the same derived migration
  has a counterexample (so KEEP's proof rests on the baseline, as claimed).
- Removed field, changed type, `init` parameter: not derived, each with its reason. A written
  migration is left alone. An unchanged state, or no baseline, derives nothing.

End to end: `test/two_node/hcr_derived_migration`. v2 adds two fields and has no
`migrate_state`; built against v1's schema it deploys over a live actor, the count survives
(5, then 6 after a v2 `Tick`) and the new fields hold their `init` values. The control is the
same source built with no baseline: its deploy is refused for the missing migration.

## Not covered

- Moving data between fields (a rename): it looks like a removal plus an addition, so the
  user has to say so. Designed as a partial `migrate` clause on the actor with a COPY rule:
  todo `2026-11-06-hcr-derive-field-rename`.
- An actor in a nested module: the schema names it `Outer__Actor`, and the match is by exact
  name (as `Hcr_baseline`'s is). Not derived; the deploy asks for a written migration.
- `migrate_msg`. It is needed only when a handler was removed or changed, which always needs
  a decision; `forge hot-reload migrate-msg-stub` already writes the identity arms.
- A non-counterexample diagnostic inside a derived function (an undecided obligation's hint)
  still has a generated-code span.
- An impure function called in an added field's `init` value fails the migrate-function
  IO check on the generated function, with a generated-code span.
