`[P2]` Derived migrations: move data between fields in one deploy (rename, split, merge)

`Desugar_migrate_derive` (M11, progress `2026-11-06-hcr-derived-state-migrations`) derives a
`migrate_state` only when a state gained fields with constant `init` values. Moving data
(`{ count }` → `{ total }`) still needs a hand-written migration, because the schema diff
cannot tell a rename from a removal plus an addition, and guessing would silently reset live
data. Goal: one deploy that adds the new field, moves the data and drops the old field, with
the migration written by the compiler.

Design (agreed 2026-11-06):

1. **A partial migration clause on the actor**, naming only what is not mechanical:

   ```march
   actor Counter do
     state { total : Int }
     init { total: 0 }
     migrate old -> { total: old.count }
   end
   ```

   The compiler writes the whole `counter_migrate_state`: the named fields from the clause,
   kept fields copied (KEEP), other added fields from `init` (ADD). Parser change:
   `actor_def` gains the clause; extend `tree-sitter-march/grammar.js` in the same PR.
2. **A COPY rule**, proved once like KEEP/ADD in `test_refinecheck` suite
   `hcr-derived-migration`: a bare `old.f` assigned to a new field of the same type carries
   the deployed refinement of `f` as the hypothesis for the new field. Any other expression
   (`old.count * 100`) is checked like a written migration.
3. **Removal**: a removed field read by the clause is dropped with no extra consent (its
   value moved). A removed field nothing reads needs `forge deploy hot --drop Actor.field`,
   recorded in the deploy audit log like `--accept-unproved`.
4. **The suggestion**: when a deploy removes exactly one field and adds one of the same type,
   the refusal proposes the clause as a machine fix (`forge fix`). Never applied on a guess.
5. **Derived rollback**: the reverse of a COPY is the copy back (`count := total`), so
   rolling back loses nothing. Since 2026-11-08 this need not be trusted: emit it as
   `<actor>_rollback_state` and the generated `<actor>_rollback_roundtrip` lemma (H5,
   progress `2026-11-08-hcr-rollback-roundtrip`) proves it on every build. Shares the
   mechanism with todo `2026-11-08-hcr-derive-rollback-state` (the add-only case); do that
   one first.

Also open from M11: actors in nested modules are matched by exact schema name
(`Outer__Actor`) and so are not derived.

## Resolution (2026-11-15)

Design points 1, 2, 3 (the read case) and 5 are done; 3's `--drop` consent and 4's
machine-fix suggestion are filed separately (see Residual).

- **Clause.** `migrate old -> { total: old.count }` after `init` (`Ast.actor_migrate`).
  `mailbox` and `migrate` share one `list(actor_clause)` in `parser.mly`, each at most once,
  in either order: two `option(...)`s both starting with a contextual `lower_name` would be
  an LR(1) conflict (the grammar's conflict count is unchanged, 7 on main and after).
  `tree-sitter-march/grammar.js` gains `migrate_clause` (corpus case "Actor migrate
  clause"); `specs/lang/grammar.md` §9.1 gains `actor_clause`, with corpus program
  `parse/p48_actor_migrate_clause.march`. The formatter prints the clause.
- **Derivation** (`Desugar_migrate_derive.derive`). Each new field's source is `Keep`
  (deployed, same type), `Copy g` (the clause's bare `old.g`, same type), `Clause` (any other
  clause expression) or `Init`. A removed field must be read by the clause; a changed-type
  field must be given by it. Removed and converted fields' parameter types come from the
  deployed schema, parsed by the driver (`baseline_tys`, `Schema_migration.load_derive_baseline`).
  The generated parameter is the clause's own binder.
- **COPY** needs no code: `Hcr_baseline.strengthen` already gives the parameter's fields the
  deployed refinements, which is what KEEP rests on. Pinned in `hcr-derive-rename` case 1 (a
  tightened refinement on the renamed field is refused, at the clause).
- **Reverse.** When every deployed field comes back by a bare copy, `derive_rollback`
  writes `<actor>_rollback_state` (H5 proves the round trip). The sidecar records
  `rollback_derived_moves` (field returned to, new field), and the rollback deploy (the old
  source, no clause) copies the value back: `deployed_rollback.moves`. Also recorded:
  `migrate_clause`, `migrate_derived_moves`; forge's `derived_note` names renames, computed
  fields and copied-back fields.
- **Diagnostics.** `migrate_clause_invalid` (ACTOR; explain page): a malformed clause is an
  error in every build (not a record literal, a non-state field, a field given twice). Against
  a baseline, a clause that does not derive warns at the clause with the reason, and a clause
  reading a field the deployed state lacks (written for an earlier deploy) is ignored with a
  warning. The derived-migration counterexample note now mentions the clause.
- `--guarantees` labels the line `migrate_state (derived, migrate clause)`.

RED evidence (each perturbation turned the named `hcr-derive-rename` case red, then
restored): reverse off → case 0; clause reads ignored for removal consent → case 0; stale
check off → case 6; rollback moves ignored → case 5; clause validation off → case 7;
formatter not printing the clause → case 8.

## Residual

- `forge deploy hot --drop Actor.field` for a removed field nothing reads:
  `specs/todos/2026-11-15-hcr-deploy-drop-consent.md`.
- The refusal proposing the clause as a machine fix:
  `specs/todos/2026-11-15-hcr-migrate-clause-suggestion.md`.
- Actors in nested modules are still not derived (exact schema name `Outer__Actor`), as M11.
