`[P2]` The `@[measure]` soundness gate does not look at the measure's callees.

Fact F7 of `specs/2026-10-29-refinement-reflection-design.md` (§0.3 rows c3b and h2; pinned by
`test/refine/reflect/c3_measure_effect_callee.march`, `c3b_measure_effect_callee.march`,
`h2_measure_show.march`).

- `measure_gate_errors` (`lib/refinecheck/refine_encode.ml`) rejects `spawn`, `send`, `dbg`,
  `assert`, direct `panic`/`todo`/`unreachable`/`exit`, possibly-zero `/` and `%`, non-structural
  self-calls and a non-exhaustive match on the parameter, in the measure's OWN body only.
- A measure whose arm calls a user function that prints (`noisy`), panics (`boom`) or loops (`spin`),
  or calls `show` / builds `"${h}"` over a user `impl Show`, passes the gate with no
  `invalid_measure`; the use skips `solver-undecided`.
- Harmless today only because such an arm fails to translate, so the measure falls back to an
  uninterpreted symbol. It stops being harmless the moment the body translator grows.
- Fixed by phase 1 of the reflection design: D2 makes `@[measure]` assert reflection, so the gate
  becomes the R1-R11 fixpoint of `lib/refinecheck/refine_reflect.ml`, which follows callees and
  dispatch edges (`--reflect-report` already shows the blocker for each of these).
