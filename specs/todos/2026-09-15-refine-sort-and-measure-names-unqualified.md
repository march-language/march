# `[P2]` Refinement checker: datatype sort and measure names are not module-qualified

Filed 2026-09-15 while landing Phase 4 of the set refinements strengthening.

`adt_sort_name` maps a March type to `M_<bare name>` and a `@[measure]` to its
bare function name. A program sees the whole stdlib, so names collide:

- `stdlib/ordered_map.march` and `stdlib/sorted_set.march` both declare
  `type Tree`, registered as one `M_Tree` whose constructors are whichever
  registered last. A user `type Tree` joins the same sort.
- Two `@[measure]`s with one name each emitted a `declare-fun`, and z3 rejected
  every query that attached the measure preamble. Since 2026-09-15 duplicate
  measure names are excluded from axiomatisation (`check_module`), which turns
  that into skips, and SortedSet's measure is `sorted_set_elts` to stay out of
  the way.

Direction: qualify both by module path (`M_SortedSet$Tree`,
`SortedSet$sorted_set_elts` or similar) at registration, and resolve a
predicate's measure name through the same scope rules as a call. A user fixture
with its own `type Tree` and a `tree_elts` measure, checked with the stdlib
prepended, should prove exactly what it proves in the test harness.
