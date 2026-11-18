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
