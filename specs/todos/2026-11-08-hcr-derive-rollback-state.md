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
