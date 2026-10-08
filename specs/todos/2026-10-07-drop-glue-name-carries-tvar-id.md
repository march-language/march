# Drop glue names still carry a typechecker type-variable id

**Logged:** 2026-10-07, while landing B1 (structural names,
`specs/progress/2026-10-07-b1-structural-names.md`).

`Drop` names an aggregate's drop function `__drop$<Drop.mangle ty>`, and
`Drop.mangle` spells a residual type variable by its typechecker id:
`__drop$List_V_53272`. The id depends on how much was inferred before, so
the symbol can change after an unrelated edit, exactly the cascade B1
removed for every other minted name. The IR oracle showed it move
(`__drop$List_V_53272` vs `__drop$List_V_53278`) between two builds of the
same program.

B1 left it alone because the mangled text is also the dedupe key
(`env.names`): renumbering the variables by position would map
`List(V_1)` and `List(V_2)` to one key and merge their drop functions,
which changes the emitted function set, not just names. `hr_slot_hashes`
renumbers `V_<id>` in its canon so hot-reload hashes are unaffected.

## Fix

Decide whether two drop functions that differ only in a residual
variable's id are interchangeable (both treat the element as erased, so
probably yes). If so, canonicalise `Drop.mangle`'s variables by first
appearance (as `Mono.mangle_name` now does) in both `Drop` and
`Llvm_calls` (which recomputes the name), accept the merge, and drop the
`V_<id>` renumbering from `hr_slot_hashes`. Check with
`scripts/ir-oracle.sh` that only drop glue changed.
