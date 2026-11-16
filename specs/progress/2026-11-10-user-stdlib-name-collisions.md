# User names that are also stdlib / interface names get their own TIR symbols

Landed 2026-11-10. Closes
`2026-10-15-actor-call-result-through-generic-fn-prints-ok-wrapper.md` and the last open shape of
`2026-10-30-interpreter-compiler-name-resolution-diverge.md` (both moved here). The type-level half
of `specs/todos/2026-11-02-typecheck-conflates-same-short-named-types.md` needs a different
mechanism and stays open there.

## The shared root cause

A user definition and a stdlib (or interface) definition came out of lowering as ONE TIR symbol,
so mono or the linker picked one meaning for every caller:

| Program | Interpreted | Compiled before |
|---|---|---|
| `fn show(r)` (generic), `println(show(mk(1)))` | `pos` | `Ok(pos)`: mono sent the user's own call to `Show$Result.show` |
| `fn show(r : Result(String, String))`, `println(mk(2))` | `Ok(pos)` | `pos`: the prelude's `println` -> `show(x)` ran the user's fn |
| `fn show(b : Box)` plus `impl Show(Box)`, `println(Box(2))` | `Box 2` | `user-show` |
| `fn compare(_a, _b) do 99 end`, `compare(1, 2)` | `99` | `-1`; same for `hash` |
| `mod Util do fn eq(a, b) do a != b end end`, `Util.eq(1, 1)` | `false` | `true`: lowering and mono both strip the module prefix to find interface methods |
| entry `mod List do fn sum_int(_ : List(Int)) : Int do 42 end end`, `List.sum_int([1, 2])` | `42` | `3`: one symbol `List.sum_int`, the stdlib's won |

Mono's interface-collision arm decided between the user fn and the method by comparing the user
fn's first-parameter type with the argument's, which is wrong in both directions, and it cannot be
fixed there: the user's call and the prelude's call are the same TIR call.

## The fix: lowering names the user's definition

Lowering already had the mechanism, for an entry fn named like a C-symbol builtin
(`Lower_state._entry_builtin_shadows`, `file_read` -> `file_read$u`): a table, in effect only while
lowering declarations written in the entry file, mapping a name to the distinct TIR name the user's
definition is lowered under. `Lower.lower_module` now also puts in it:

- an entry top-level fn named like an interface method (the built-in `eq`/`compare`/`show`/`hash`
  plus every method a stdlib or user `interface` declares);
- every fn of an entry-file module (at any depth) named like an interface method, keyed by its
  qualified name (`Util.eq` -> `Util.eq$u`);
- every fn of an entry-file module whose top-level name is also a stdlib module
  (`Module_registry.find_stdlib_file`) or a module from another file (`List.sum_int` ->
  `List.sum_int$u`).

A fn with default arguments is left out (it is lowered as `name$N`), as before.

Every reference that resolves to such a definition is mapped through the same table:
`Lower_state.resolve_use_alias` (names written in source, bare or qualified),
`Lower_decls.rename_tir_vars` (a bare sibling call the enclosing module qualifies), and the
`lower_mod_decls` definition site. `Lower_expr`'s interface-method redirect skips a name in the
table, since stripping `Util.` from `Util.eq` would find the `Eq` method. The stdlib, the prelude and
other files see an empty table, so their `show`/`List.sum_int` keep meaning the method / the stdlib
fn, and mono finds no user fn named `show` to confuse with the method.

## An interpreter bug the same tests found

Inside the user's `mod List`, a call to its own `sum_int` ran the stdlib's in the interpreter:
`Desugar.qualify_module_refs` rewrites the sibling call to `List.sum_int`, and `Eval.lookup` reads
the lexical env (which already bound the stdlib's `List.sum_int`) before the module registry. The
DMod arm of `Eval.eval_decl` now also binds the qualified name to the module's own fn when the env
already has that name.

## Tests

Six interpreter-vs-compiled parity tests in `test/test_codegen.ml`
(`newtype_derived_method_crash` group, after "a local fn shadows a later `use M.*`"), one per row
above; each failed before the fix.
