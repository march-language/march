# Capability rows miss references spelled through `import` / `alias` (2026-11-22)

Found by the ocap phase 6 Task 3 review (fix round 3). `Cap_rows.solve` (and
`reaches_unknown`, `cap_reach_chain`) resolve a reference only by the owner's
module prefix and the raw name (`Cap_rows.resolve_ref`). A call written through
an `import` (`import Shout` then `log(..)`) or an `alias` (`alias Shout, as: S`
then `S.log(..)`) contributes no edge, so the caller's row is truncated.

The dependency-grant check (`Typecheck.check_dep_grants`) no longer relies on
these rows. It walks each reach with its own import- and alias-aware resolver
(`full_reach`), counts an unresolved non-builtin reference as unknown, and both
`dep_grant_exceeded` and `Dep_grants.proven` use that walk. The shared rows still
feed `check_fn_bounds` (`needs` clauses, interface bounds), `check_restrict_reach`,
`check_main_grant` and the module ceiling, so each of those under-reports a
capability reached only through an import or alias.

What to do: record each module's imports and aliases unconditionally (today
`env.grant_module_scopes` is filled only under a grants file) and resolve through
them in `Cap_rows.resolve_ref`'s callers. Check the types and refine oracles, and
expect new diagnostics on programs that import a capability-using module by short
name.
