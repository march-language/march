`[P2]` Derive `<actor>_rollback_state` for a derived (add-only) migration

Builds on M11 (`Desugar_migrate_derive`, progress `2026-11-06-hcr-derived-state-migrations`)
and H5 (`Desugar_rollback`, progress `2026-11-08-hcr-rollback-roundtrip`).

When the compiler derives `<actor>_migrate_state` because a state only gained fields (KEEP
copies the deployed fields, ADD gives each new field its `init` value), the reverse is
mechanical too: copy back every kept field and drop the added ones. Today a developer who
wants a checked rollback for such a deploy still writes `<actor>_rollback_state` by hand.

## Goal

- `Desugar_migrate_derive` also writes `<actor>_rollback_state(new : New) : Old` beside a
  derived migration (only when the user wrote neither function), with the same synthetic
  spans and `origins` bookkeeping, so a diagnostic points at the declared fields.
- `Desugar_rollback` then generates `<actor>_rollback_roundtrip` as for a written pair, so the
  round trip is proved on every build, not trusted. For KEEP/ADD it holds by construction
  (each kept field is copied there and back), so the lemma should prove with no fuel.
- The sidecar records that the rollback was derived (as `migrate_derived` does), and
  `forge deploy hot` / the deploy plan name it, so a rollback deploy can reuse it as its
  `migrate_state` without the developer writing anything.
- `--guarantees`: `rollback round trip (derived)  proved`.

## Done when

- The hcr-rollback suite gains a case: an add-only deploy with no hand-written functions gets
  a derived rollback whose round trip proves; RED with the derivation off (no line, no lemma).
- A written `rollback_state` still wins over a derived one.
- Docs: `docs/hot-code-reload.md` "Schema baselines and rollback".

Open question: whether a rollback deploy should pick up the derived reverse automatically
(forge pairing by schema hash, design §3.4 H5), or only offer it in the deploy plan.

## Resolution — 2026-11-15

Landed on `feat/hcr-derived-rollback`.

- `Desugar_migrate_derive`: an add-only derivation (KEEP + ADD with at least one added
  field) also writes `<actor>_rollback_state(rollback_new__ : New) : Old`, copying back
  every deployed field, unless the user wrote one ([rollbacks]; respanned like the forward
  function, with `origins`). `Desugar_rollback` then generates the round-trip lemma, which
  proves by unfolding both functions.
- The sidecar records `"rollback_derived": [<fields it returns to>]`.
  `Schema_migration.load_rollback_baseline` reads the deployed one, parsing the types of the
  fields that rollback drops.
- The rollback deploy: a state that only LOST fields, exactly matching the deployed
  `rollback_derived` (same remaining field set, every removed field one it drops, nothing
  changed or added), derives a drop-only `migrate_state` whose parameter is the deployed
  record's full type. The sidecar records `"migrate_derived_drops"`, forge's
  `Schema_diff.derived_drops` parses it, and `derived_note` says "derived as the running
  version's proved rollback (drops …)". Any other removed field still refuses with
  "it removes …".
- `--guarantees`: `rollback round trip (derived)`, `migrate_state (derived rollback)`.

Two fixes the derivation needed, each also a fix for written rollbacks:

- `Refine_reflect.pre_of`: an unfolding's guard translates a parameter's field refinement
  (`_.count >= 0`) through the record selector. Before, a function with such a refinement had
  no equations, so the round trip of any actor with a refined state field was a skip (the
  baseline's strengthening gives every migration that refinement).
- `Hcr_baseline.strengthen_fn` / `actor_of_migration`: the generated
  `<actor>_rollback_roundtrip` lemma's parameter gets the deployed hypotheses, as the
  migration's does; otherwise the migration's guarded unfolding never fired.

Also corrected: `docs/hot-code-reload.md` said a `String` field leaves the round trip
`not proved`; that was fixed on 2026-11-09 (progress `2026-11-09-reflect-records-with-string-fields`).

Tests: `test_refinecheck` suite `hcr-derived-rollback` (5, end to end through real sidecars:
the derived rollback proved and recorded; a written rollback wins; the old source redeploys
with a derived drop-only migration; without the record a removed field is still not derived;
a rollback to another shape is not derived), `hcr-rollback` case 2 (refined-parameter
unfolding, proved and refuted), `guarantees` case 5 now pins the derived rollback line, and
forge `hcr-cap-gate` 53 (the drops note). RED: the derived rollback off turns derived-rollback
0 and 2 red; drop-only off turns 2 red; the `pre_of` field resolver off turns hcr-rollback 2
red; the lemma strengthening off turns guarantees 5 red.

## Residual

- A rollback deploy picks the derived migration only from a sidecar that recorded
  `rollback_derived`; a baseline from before this change derives nothing (as before).
- Field renames (todo `2026-11-06-hcr-derive-field-rename`) can now reuse this for their
  reverse.
