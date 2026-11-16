`[P3]` Propose the `migrate` clause when a deploy looks like a rename

Follow-up of progress `2026-11-15-hcr-derive-field-rename` (design point 4). When a deploy
removes exactly one state field and adds exactly one of the same type, the derivation is
refused ("it removes count"), and the user has to know the clause exists.

Goal: the refusal (the `migrate_not_derived` reason, `forge deploy hot --plan`, and a
`march --check --hcr-baseline` diagnostic) proposes `migrate old -> { total: old.count }` as
a machine fix that `forge fix` applies. Never applied on a guess: the user runs the fix.
The fix inserts the clause after `init` (after `mailbox`, if any).

## Resolution (2026-11-16)

- `Desugar_migrate_derive.rename_guess`: exactly one removed field, exactly one added field of
  the same schema type, nothing else changed, and no clause. The build then warns
  (`migrate_rename_suggested`, ACTOR, explain page) at the actor with an insert fix of
  `migrate old -> { new: old.gone }` after the `init` expression's last line, tier
  `Maybe_incorrect`: a guess, never applied unasked. The `migrate_not_derived` reason (and so
  the deploy refusal and plan) carries the same suggestion.
- `forge fix --only CODE` is the opt-in for a guess: `Cmd_fix.parse_fix_line ~opt_in` keeps a
  non-machine fix whose code is named. `--only` now works in project mode too (it was
  paths-only), where the compiler finds the deployed baseline in `.march/` by itself.
- Tests: `hcr-drop-and-suggest` cases 2–3 (the warning, the JSON fix, the refusal text; no
  suggestion for a type mismatch, a two-field addition, or a pure removal); forge
  `test_fix_only_opts_into_guesses`. Applying the fix's insert by hand gives a file whose
  derived migration and rollback round trip prove.

RED evidence: the guess disabled → `hcr-drop-and-suggest` 2; the opt-in ignored → forge
`test_fix_only_opts_into_guesses`.
