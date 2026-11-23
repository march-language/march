# A library module's `let` naming its own function compiles

Found by ocap phase 6, Task 6 (`grant_module_level_closure`). A module-level
`let own = own_check` in a module loaded from `MARCH_LIB_PATH` (or a nested
module's `let` naming a parent's function) lowered to a zero-arg function whose
body kept the bare name, so clang and node failed on an undefined `own_check`.
The interpreter was right. A module's `DFn` bodies were already qualified by
`Lower_decls.rename_scoped_vars`; the module-let paths
(`Lower_decls.lower_stdlib_mod_decls` and the nested-module path in
`Lower.lower_module`) now apply it too.

Test: `test/test_dep_grants.ml`, group `frames`, "a library let naming its own
fn builds (no grants)" (native, JS, interpreter); it fails without the fix.
