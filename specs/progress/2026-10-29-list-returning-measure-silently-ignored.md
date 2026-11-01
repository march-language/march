`[P2]` A `@[measure]` that returns a list is accepted and silently ignored.

Fact F6 of `specs/2026-10-29-refinement-reflection-design.md` (§0.3 row c1; pinned by
`test/refine/reflect/c1_list_measure.march`).

- `@[measure] fn rev1(xs : List(Int)) : List(Int)` draws no diagnostic. The shape gate
  (`measure_shape_error`, `lib/refinecheck/refine_encode.ml`) checks the parameter count, not the
  result sort, and `build_measure_preamble` drops the measure from `axiom_measures` when an arm does
  not translate.
- A predicate over it (`{Unit | len(rev1(xs)) == len(xs)}`) skips `unreflectable-subject`, with no
  word that the attribute did nothing.
- Fixed by phase 1 of the reflection design: a list result has a datatype sort (§3.2), and under D2 a
  `@[measure]` that is not reflectable is an error (§5.2). A smaller interim fix is an
  `invalid_measure` for a result sort the axiom tier cannot encode.

**Closed 2026-10-30** by reflection phase 1a (`specs/progress/2026-10-30-reflection-phase1a.md`).
