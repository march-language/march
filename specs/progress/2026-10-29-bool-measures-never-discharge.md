`[P2]` A `@[measure]` returning `Bool` never discharges anything.

Fact F5 of `specs/2026-10-29-refinement-reflection-design.md` (§0.3 rows c2, c2b, c2c; pinned by
`test/refine/reflect/c2_bool_measure.march`, `c2b_bool_measure.march`, `c2c_bool_measure_eq.march`).

- The result sort of every non-set measure is hard-coded to `Int`: the `define-fun … Int` of
  `measure_definition` and the `| None -> "Int"` of the instance declarations in
  `lib/refinecheck/refine_encode.ml`. So `all_pos(_)` is an `Int` term in a Bool position.
- Every use skips: `float-sort-gate` (c2, c2b) or `sort-conflict` for `pos_nat(_) == true` (c2c).
  Nothing is reported as wrong; the predicate is silently unchecked.
- The reference says a measure returns "an `Int` (or `Bool`)", and no test has a Bool measure.
- Fixed by phase 1 of the reflection design (§3.2: a reflected function's `Bool` result has sort
  `Bool`, and D2 merges `@[measure]` into reflection). Until then the reference should not promise
  Bool measures.

**Closed 2026-10-30** by reflection phase 1a (`specs/progress/2026-10-30-reflection-phase1a.md`).
