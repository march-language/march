`[P3]` Propose the `migrate` clause when a deploy looks like a rename

Follow-up of progress `2026-11-15-hcr-derive-field-rename` (design point 4). When a deploy
removes exactly one state field and adds exactly one of the same type, the derivation is
refused ("it removes count"), and the user has to know the clause exists.

Goal: the refusal (the `migrate_not_derived` reason, `forge deploy hot --plan`, and a
`march --check --hcr-baseline` diagnostic) proposes `migrate old -> { total: old.count }` as
a machine fix that `forge fix` applies. Never applied on a guess: the user runs the fix.
The fix inserts the clause after `init` (after `mailbox`, if any).
