`[P2]` A function of a registry-loaded module is typed as a fresh type variable (2026-11-17)

`Typecheck_env.load_module_into_env` binds each `ExFn`/`ExValue` export of a module loaded
through `Module_registry` (a lazily-loaded stdlib module, such as `lazy_niche_probe.march`) as
`Mono (fresh_var 0)` (lib/typecheck/typecheck_env.ml, the `ExFn | ExValue` arm), ignoring the
function's annotated signature. Any call then type-checks: in `march repl`,
`LazyNicheProbe.first_or(true, "x")` is accepted and segfaults the REPL (exit 139), and
`LazyNicheProbe.first_or([7, 8], 3)` prints `= 15`, the tagged word for 7, because the result
type is unknown. `let n = LazyNicheProbe.first_or([7, 8], 3)` fails with
`runtime error: unbound variable: LazyNicheProbe.first_or`.

`lazy_niche_probe.march` is the only file on `Stdlib_manifest.lazily_loaded_allowlist`, and it
is an internal compiler regression fixture kept lazy on purpose, so a user meets this only by
calling that fixture. The fix is to build the binding from the export's annotations where it
has them (and keep the fixture's codegen path covered, see its header comment).

Found while fixing specs/progress/2026-11-11-repl-int-result-printed-tagged.md.

## Fixed (2026-11-25)

A registry export of a function now carries its definition (`ex_fn` on
`Module_registry.export_entry`), and `load_module_into_env` binds it at the scheme
`prebind_fn_scheme` builds from its annotations (through `Typecheck_env.registry_fn_scheme`,
since that function is defined later). An unannotated or exotic signature keeps the fresh
variable.

After the fix: `march --check` refuses `LazyNicheProbe.first_or(true, "x")` with
"expected `List(Int)` but got `Bool`" (it exited 0 before), the REPL prints the same
error instead of exiting 139, and `LazyNicheProbe.first_or([7, 8], 3)` prints `= 7`.
`test/native/lazy_niche` (the fixture's codegen path) is unchanged.

Tests: `test/test_jit.ml`, "REPL: a registry-loaded module's function has its annotated
type" and "--check: an ill-typed call into a registry-loaded module is refused". Both were
written after the fix; the failures they pin were seen by hand first (`--check` exit 0).

Still open, with its own todo: `let n = LazyNicheProbe.first_or([7, 8], 3)` at the REPL
fails with `runtime error: unbound variable: LazyNicheProbe.first_or`
(`todos/2026-11-25-repl-let-of-lazily-loaded-module-call-unbound.md`).
