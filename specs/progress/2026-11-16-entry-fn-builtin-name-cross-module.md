# A user fn named like a builtin no longer captures the stdlib's calls to it (2026-11-16)

## Symptom

`test/native/shadowed_negate_not.march` under `--target js` printed three extra `not` lines
before its expected output (PR #1274, CI run 43925557110). The fixture defines an entry-module
`fn not`; on JS the capability policy, the March module `stdlib/authority.march`, runs at
launch and calls the builtin `not(...)` bare, and those calls ran the user's `fn not`.

The hole was not JS-only. With an entry `fn not`, natively and on JS,
`Topology.labels_of("db, , public")` returned one label instead of two and
`VectorClock.compare(new(), a)` returned `Equal` instead of `Before`: every stdlib module's
bare `not(...)` became a call to the user's fn. The interpreter scopes a top-level fn to its
file and was right.

## Cause

`Lower.lower_module` (`lib/tir/lower.ml`, the `_entry_builtin_shadows` table) gives an entry
fn named like a builtin its own TIR name (`file_read$u`) only when the builtin has a C symbol
(`Llvm_builtins.has_c_mapping`) or is an interface method. A builtin the backends dispatch
on its bare name with no C symbol (`not`, `negate`, `string_length`, `int_xor`, ...) kept
the user fn's bare TIR name, the same name as the builtin, so after lowering a stdlib call to
the builtin and an entry call to the user fn were the same `EApp`. #1177 then made
`js_emit`'s `shadows_js_builtin` and `llvm_emit`'s `shadows_dispatched_builtin` route any
callee named in the module's top-level fns to the user fn, and `fold.ml`'s `has_user_not`
stop folding `not`, which is right for the entry module's calls and wrong for everyone else's.

## Fix

The same lowering table now also renames an entry fn whose name is any bare builtin the
typechecker knows (`Typecheck.prelude_collision_builtin_names`): `fn not` is lowered as
`not$u`, and every reference that resolves to it in the entry file is renamed with it, so the
stdlib's `not` stays the builtin on every backend. The backend shadow checks and the fold
guard stay for the REPL and `--jit`, which lower with `~shadow_builtins:false`.

## Tests

`test/native/shadowed_builtin_cross_module.march` (entry `fn not` and `fn string_is_empty`,
calling `Topology.labels_of` and `String.is_empty`), pinned interpreted, native and on
`--target js` by rules in `test/dune`. Without the fix, native printed three `user not` lines
and a count of 1, and JS six `user not` lines and a count of 1.

`--jit` has its own, older version of this hole (it lowers with `~shadow_builtins:false`):
`specs/todos/2026-11-16-jit-entry-fn-builtin-name.md`.
