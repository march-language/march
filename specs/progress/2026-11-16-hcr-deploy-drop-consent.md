`[P3]` `forge deploy hot --drop Actor.field`: consent to drop a field nothing reads

Follow-up of progress `2026-11-15-hcr-derive-field-rename` (design point 3). A derived
migration drops a removed state field only when a `migrate` clause reads it (its value moved)
or when the deploy is the running version's proved rollback. Dropping a field whose data is
simply no longer wanted still needs a hand-written `<actor>_migrate_state`.

Goal: `forge deploy hot --drop Counter.history` lets the derivation drop `history`, recorded
in the deploy audit log like `--accept-unproved`. The flag has to reach the build that
derives (the driver's baseline load, `Desugar_migrate_derive.derive`'s `unread` check) and
the sidecar, so the plan shows "drops history (--drop)". A `--drop` naming a field the
deploy does not remove is an error, not a no-op.

## Resolution (2026-11-16)

- Compiler flag `--hcr-drop Actor.field[,…]` (`Desugar_migrate_derive.consented_drops`): a
  removed field nothing reads is dropped by the derived migration when consented, recorded
  per actor in `consented` and in the sidecar as `migrate_drops_consented`. It keys the CAS
  (`hdrop:` in `Schema_migration.baseline_cas_tag`): it changes the derived code and the
  signed schemas. A consented drop leaves that field without a way back, so no reverse is
  derived.
- `forge deploy hot --drop` (repeatable or comma-separated) is passed to the build as
  `--hcr-drop`, threaded like `--accept-unproved`. After the build,
  `Schema_diff.unused_drops` aborts the deploy for a `--drop` the patch's schemas do not
  record (a typo, a kept or clause-read field, a pre-built patch without it). The plan note
  says `drops history by --drop`; a removal refusal now ends with the `--drop` hint.
- The server's audit line for an activation copies the image's `migrate_drops_consented` as
  `"dropped"` (`schema_dropped_for`, `runtime/march_reload_schemas.h`), next to
  `accepted_unproved`. Pinned in `test/test_reload_activate4.c` with the stub image's schema.
- Tests: `test_refinecheck` suite `hcr-drop-and-suggest` cases 0–1; forge
  `test_drop_consent`.

RED evidence (each perturbation turned its test red, then restored): consent ignored →
`hcr-drop-and-suggest` 0; `unused_drops` always empty → forge `test_drop_consent`; the audit
copy removed → `test_reload_activate4`.

Not RED: removing the `hdrop:` CAS tag. Case 0 builds the same file without and then with
the flag, and measured by hand (same file, same output, same HOME) a build with the tag
removed still is not served the other build's entry: the key already differs, the derived
`migrate_state` being part of what it hashes. The tag stays as the explicit statement that
the flag is a build input (it also changes the signed schemas); case 0 pins the behaviour
either way.
