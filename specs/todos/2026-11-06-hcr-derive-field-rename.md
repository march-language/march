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
