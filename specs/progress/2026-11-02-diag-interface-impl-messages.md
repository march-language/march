`[P3]` Diagnostics for interfaces: `missing_impl` points at the enclosing fn (even `fn main()`) instead
of the `<`/`+` that needed the impl; no `derive` fix for derivable interfaces; no constraint-origin chain
through generic code. specs/plans/2026-11-02-diagnostics-depth-plan.md §F6.

2026-11-03: done (§F6).
- Each pending constraint carries its use site (`constraint_site`: the instantiated variable's span
  and name), so `missing_impl` points at `a < b` / `x == target` / the call `same(..)` instead of the
  enclosing declaration, with a second line "`<` needs it here." / "The call to `same` needs it here."
- For a type declared in the file and a derivable interface (`Eq`, `Ord`, `Show`, `Hash`), the fix
  inserts `derive I for T` after the type (`FInsert`); the corpus checks it compiles (missing_impl_4,
  missing_impl_5 reach exit 0; 2 and 3 are partial because `main` also lacks a grant).
- Constraint origin: a generic function's `when I(a)` bound is labelled ("`same` requires `Eq`
  here"). Constraints inferred without a `when` are not generalized into the scheme today, so a chain
  through an unannotated generic function has nothing to show; not done.
