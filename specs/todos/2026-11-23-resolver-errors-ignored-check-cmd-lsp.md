# `march check` and the LSP drop the resolver's errors (dep_module_conflict passes silently)

Logged 2026-11-23 by ocap phase 6, Task 2.

`Resolver.resolve_imports` returns its errors (an unresolved import, and under dependency
grants `dep_module_conflict`). The batch driver reports them (`bin/main.ml`,
`has_resolve_errors`), and since Task 2 `--check-json` prints them too. Two other callers
discard them:

- `run_check_cmd` (`march check FILE...`), `bin/main.ml` around line 7597:
  `let (_resolve_errors, extra_decls, user_files) = resolve_imports ...`;
- the LSP, `lsp/lib/analysis.ml` around line 2579:
  `let (_resolve_errors, extra_decls, _user_files) = ...`.

So under a grants file a module defined twice (app vs dep, dep vs dep, dep vs stdlib), or a
granted root nested in the project, is an error from `march --check` and from a build, but
`march check` and the editor show nothing, and the first module silently wins.

What to do: render the errors in both paths (`Resolver.diagnostic_of_error` gives the code and
notes), make them fatal in `march check`, and publish them as diagnostics in the LSP. Pin each
with a `dep_module_conflict` case.
