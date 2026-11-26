`[P3]` Registry-loaded function exports are still untyped outside the lazily loaded stdlib (2026-11-26)

`Typecheck_env.load_module_into_env` binds a function export at its annotated signature
only for a module on `Stdlib_manifest.lazily_loaded_allowlist` (the fix in
`progress/2026-11-25-registry-loaded-module-fn-untyped.md`). Every other module that
reaches the typechecker through `Module_registry` still binds its functions as a fresh
type variable, so a call into it is not checked.

Doing it everywhere was tried and backed out (PR 1335, CI run on 2026-11-26):

- Nine compiler-suite cases (`cap_fn_bounds`, `cap_dict`, `cap_grant`, `cap_fn_grant`,
  `zero_arg_unit_callback`) type-check without the stdlib, so the whole stdlib comes
  through the registry. There `println` is the bare builtin returning `()`, and typed
  `Authority.ignore(println(...))` became "expected `Result(a, CapError)` but got `()`".
  The programs compile normally (`--check` with the stdlib accepts them).
- Five TIR snapshots moved, all a correction: `List.sum_int(...)` passed to `println` was
  typed `String` (the untyped binding unified with `println`'s argument), and the
  post-Perceus IR emitted `dec_rc` on that value, which is an `Int`.

Which real compiles use the registry route (MARCH_LIB_PATH dependencies, the
`--compile` / `--test` unit) is not established; find that first.

Fix: decide what a stdlib-less check should see for the capability-wrapped builtins
(`println` and the like), then drop the allowlist condition, regenerate the snapshots
(the `String`/`Int` correction above), and run the forge and dependency suites.
