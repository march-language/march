`[P1]` Per-function `needs` bounds, phase 2: interface method bounds — DONE 2026-11-02

Plan: `specs/plans/2026-11-02-interface-needs-bounds.md`. Road to 1.0 decision 2.

- Syntax: `fn m : t needs A.B, C` (or `needs ()`) in an interface body, before an optional
  default. `Ast.method_decl.md_needs`; parser (conflicts still 7), formatter, tree-sitter.
- Check: an impl method with no bound of its own, and the interface's default body, get a
  bound point from the interface (`Typecheck_env.fn_bound`, origin `Iface_method`), held
  by phase 1's `check_fn_bounds`. An impl's own bound must lie within the interface's
  (`cap_bound_iface`). An interface's bound need not lie within its own module's `needs`.
  No capability threading: the bound is not part of a type or a `when` constraint, and
  callers are still charged the impls' union.
- A violation reached only through another violating impl (a generic impl reaching an
  impure one through the dispatch node) is reported once, at the impure one: bounds are
  judged against rows solved without edges into violating impls.
- Built-ins: `Show`, `Eq`, `Ord`, `Hash` are bounded by `needs ()`, decided 2026-11-02
  after measuring zero rejections (`2026-11-02-interface-needs-bounds-measurement.md`).
  Errors against a built-in are reported at the impl.
- Fixed in passing: an impl method or default body in a NESTED module was charged nothing
  for local helpers, in every capability check, because its key
  `<scope>.<Iface>$<Ty>.<m>` was scoped by its last `.`. All resolvers now share
  `Cap_rows.ref_prefix` with an explicit `fn_scopes` entry for such keys.
- Tests: `test/test_cap_fn_bounds.ml` (35 cases, accept/reject pairs).
