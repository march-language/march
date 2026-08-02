# `forge search --callers NAME` — reverse-reference search

Landed 2026-08-01.

**What shipped.** `forge search --callers NAME` finds every resolved call,
constructor use, or qualified type reference to a declaration, using the
typechecker's own name resolution rather than textual/grep matching. Given a
bare or `Mod.name`-qualified target, it reports every `caller` that resolved
against it during typechecking, with file/line.

**How it works.** The typechecker (`lib/typecheck/typecheck.ml`) now records
a `ref_record` (`callee`, `caller`, `` `Call``/`` `Ctor``/`` `TypeRef``, file,
line) at each of three resolution hooks: function calls (`Ast.EVar`/`EApp`
qualified-name resolution — same-module, cross-module, and interface-method
dispatch all funnel through `qual_fn_names`), constructor application
(`Ast.ECon`, both bare and explicitly-qualified `Mod.Ctor`), and qualified
type annotations (`Ast.TyCon` in `surface_ty`). `check_module_with_refs`
exposes the accumulated list alongside the existing diagnostics/type-map
return values. `March_search.Search.index` gained a `references` field (a
`callee -> ref_entry list` table, built by `references_of_list`) that
persists to and rehydrates from the on-disk JSON cache (`index_to_json`/
`index_from_json` tolerate old caches with no `references` key — empty
table, not an error). `Search.callers_of`/`search_callers` look up a target
by bare or qualified name, merging matches across modules when the query is
bare (`search_callers idx "helper"` returns callers of every module's
`helper`). `forge search --callers NAME` (`forge/cmd_search.ml`) is the CLI
entry point.

**Known gap, tracked separately.** A qualified type reference that appears
*only* inside an `interface` method signature or an `impl`/`when`-constraint
header is not recorded at all — there is no enclosing function to name as
`caller` for those positions. See
`specs/todos/2026-08-01-forge-search-callers-interface-impl-typeref-gap.md`
for the detail; deliberately scoped out of this v1 rather than fixed.

**Regression coverage added in the final task.** Two more cases in
`test/test_search.ml`'s `references` group:

- `test_ambiguous_ctor_ref_prefers_current_module` — guards the class of bug
  on record in project memory (`lookup_ctor`'s current-module preference: two
  modules sharing a bare constructor name at different tags previously
  miscompiled because module preference wasn't applied). Proves
  reference-tracking inherits the same current-module preference: two
  modules each declaring `type Status = Active | Done`, only the second
  (`Y`) using bare `Active`, must resolve and record `Y.Active`, never
  `X.Active`. Verified RED (temporarily neutering `lookup_ctor`'s
  current-module filter *and* `add_ctor`'s recency front-loading, since
  either alone still recovers the right answer through the other
  mechanism) before confirming GREEN against the shipped code.
- `test_no_references_is_empty_not_error` — an unreferenced declaration
  (`A.unused`) returns zero callers, not an error, matching the "no results"
  UX used elsewhere in `forge search`. Verified RED by temporarily stubbing
  `Search.callers_of` to always return a nonempty list.

At landing: `test_search` 38 tests (was 36, +2). Full project suite
(`scripts/run-tests.sh`, non-`-q`) green; see the task-7 report for the exact
run output.
