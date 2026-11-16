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
