# `[P3]` Refinement checker: caller values of unknown sort are still declared `Int`

Filed 2026-09-14 while landing Phase 1 of the set refinements strengthening
(`specs/plans/set-refinements-strengthening-plan.md`, step 1.6).

Datatype terms now carry the instance their declared type gives, but a caller
variable passed to a parameter is still reflected at `Int` unless the callee
declared that parameter `Bool` or `Float`: `scalar_sort_of_param_ty` in
`lib/refinecheck/refine_scope.ml` and its `caller_scalar` consumer in
`lib/refinecheck/refine_call.ml` default everything else to `Int`, and
`scalar_sort_or_int` in `refine_encode.ml` does the same for markers. A value
of a datatype, `String` or set sort reflected there meets its real sort in
`resolve_sorts` as a conflict and the obligation is skipped, never reported.

No fixture in the suite shows a lost proof from it today. Retiring the default
needs the typechecker's span table (`check_module ~type_map`) consulted for an
unannotated caller value, per the plan's step 1.3 detail list: parameters,
`let` binders and pattern variables, call results, constructor payloads,
refinement binders. Each call site should land with a fixture that goes from
skipped to proved and an oracle diff explained line by line.
