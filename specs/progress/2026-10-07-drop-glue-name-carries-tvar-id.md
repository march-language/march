# DONE 2026-10-11: drop glue names no longer carry a typechecker type-variable id

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

## Fixed 2026-10-11

Yes, they are interchangeable: [Drop] treats every residual `TVar` alike (an
erased slot, `Kind.needs_rc_of` true, released by a bare `EDecRC`), so two
types that differ only by renaming such a variable get alpha-equivalent drop
functions. `Drop.mangle` now numbers a type's variables by first appearance
within that type (`List(a)` -> `List_V0`, `(b, a, b)` -> `T3_V0_V1_V0`).
`Llvm_calls.deep_drop_name` calls the same function, so it agrees. One
exception: lowering's placeholder `TVar "_"` keeps its old spelling `V_`,
because `Kind.borrowable_of` classifies it apart from named variables, so it
must never share a memo key with one. `hr_slot_hashes` (bin/main.ml) no longer
renumbers `V_<id>` in its canon; nothing id-shaped reaches a symbol now.

**IR oracle** (`scripts/ir-oracle.sh`, baseline from the commit before this
one, 447 programs): 321 programs change. After mapping every drop-glue name to
one placeholder and every digit run to `N`, 318 have exactly the same line set
as before. 50 of them define fewer drop functions (merged; e.g.
`array_sort_by`: 25 -> 17, `List_V_3108`/`List_V_3140`/`List_V_23577`/... all
became `List_V0`), and the rest only renumber Drop's and the inliner's local
temps (`$dx<n>`, `_i<n>`), whose counters advance less once fewer drop
functions are built. The other 3 (`actor_registry_basic`,
`actor_registry_restart`, `node_send_failed_msg`) define one extra drop
function: two single-use `__drop$Option_Pid_V_<id>` helpers that the inliner
used to inline and prune became one two-use `__drop$Option_Pid_V0`, which it
keeps. Its body is the one that was inlined, so behaviour is unchanged. No
program's drop-glue symbol spells a typechecker id any more.

**Test**: `run_codegen` "drop glue: name spells a residual type variable by
position" compiles a program with residual-variable drop glue twice in one
process (the second compile sees a later fresh-variable counter, the stand-in
for an unrelated edit) and requires the same drop symbols both times and no
`V_<digits>`. Before: `__drop$List_V_192` vs a later id. TIR snapshots are
unchanged.
