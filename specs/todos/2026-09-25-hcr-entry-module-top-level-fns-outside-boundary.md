`[P2]` The entry module's top-level functions are never on the hot-reload boundary

Filed 2026-09-25 while closing `2026-09-25-hcr-dispatch-callee-only-rule.md`.

Lowering strips the entry module's name from every declaration in the entry
file, so with `--hot-reload UpgradeApp` a top-level `fn serve_one` in
`src/upgrade_app.march` is named `serve_one` (module `""`), which
`Hot_reload.is_reloadable` never matches; only the file's nested modules (now
carried as `includes`, see `hr_entry_nested` in bin/main.ml) and actor
handlers (included unconditionally) are on the boundary. A forge topology app
whose role bodies are top-level functions of the entry file therefore gets
"No hot-deployable changes detected" from `forge deploy hot` when it changes
one, which is silent-looking and wrong: nothing tells the user the body could
never have been deployed.

Two ways out, either of which needs care because `main` (and `<Mod>.main`)
must stay OFF the boundary (`is_entry_fn` in llvm_toplevel.ml: swapping the
running root frame corrupts the allocator):

1. Put bare-named non-`main` functions of the entry file on the boundary when
   the prefix names the entry module. The whole-program TIR has no record of
   which bare names came from the entry file versus lifted lambdas and actor
   handlers, so this needs a provenance mark from lowering.
2. Have forge (`forge new`, the topology gate) require role bodies in a lib
   module or a nested module, and say so when a body is a bare entry function.

Until then, `forge deploy hot` should at least say that a changed entry-module
function is not deployable rather than "no changes".
