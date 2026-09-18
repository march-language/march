# Polymorphic combinators meet a demanded element refinement (the `map` rule)

**Landed 2026-09-18.** Design: `specs/2026-09-18-parametric-element-flow-design.md` §4. Plan: `specs/plans/2026-09-18-parametric-element-flow-plan.md`, Phase 3.

## What changed

- **`Refine_param.sources_of`**: where a value of a type variable can enter a
  function, by polarity over its declared parameter types: an element of a
  container argument (`Src_elem`, with its path), the argument itself
  (`Src_bare`), or the final result of a function argument, curried or not
  (`Src_cod`). A type variable in a function argument's domain is handed out,
  not received, unless it sits under a further arrow's domain
  (`consumer_only`). Anything untraceable (a tuple, a record, `Task(v)`)
  answers `None`.
- **§2c's `safe` is replaced by the source analysis** (`agreed_elem_slot`):
  every source must be an element source, and all must carry the same slot.
  `sort_by(pos, cmp)` now keeps `pos`'s refinement.
- **`demand_flow`**: when a call in an element position has no entry of its
  own, the callee's declared return is matched against the demanded entry and
  every source of each demanded variable is discharged (bare: scalar
  precondition; element: `check_elements`; codomain: the lambda's tails, or a
  named callable's proved return). The sources are checked in a scratch ledger
  with a throwaway error context and recorded as ONE obligation at the call:
  proved, or skipped with the new reason `Obligation.Parametric_source_unproved`
  (`parametric-source-unproved`), whose detail names the source. Never a
  violation.
- **Domain facts** (`lambda_domain_params`): a one-parameter lambda passed
  where the callee's function argument takes a type variable whose sources all
  agree on a slot assumes that slot, both in the demand check and in the
  ordinary walk of its body (`List.map(pos, fn y -> need(y))` proves).

## Deviations from the design

- Row l of the design (`List.map(ys, fn y -> y * y + 1)`) does **not** prove:
  an argument using non-linear arithmetic cannot be translated in any
  argument position (`need_pos(y * y + 1)` in a plain call is
  `unreflectable-subject` too; the 2026-09-16 widening covered predicates
  only). Filed as `specs/todos/2026-09-18-refine-nonlinear-argument-reflection.md`.
  The tests use `fn y -> if y > 0 do y else 1 end`.
- `sources_of` handles curried callbacks (`a -> a -> Bool`, `b -> a -> b`),
  which the design had left for later; only the lambda domain fact is still
  single-parameter.

## Tests

Group `demand-flow` (7 cases, user copies of `map`, `Option.map`,
`flat_map`, `sort_by`, a bare-source `put`): each accept fails on `HEAD` and
passes now; controls stay skips with the parametric reason; a refuted source is
a skip outside `cap verified` and an error under it; a tuple source is
untraceable.

Through the driver with the real stdlib, a probe of `List.map`,
`List.flat_map`, `List.filter_map`, `Option.map` and `List.sort_by` went from
0 proved / 10 skipped to 6 proved / 4 skipped, the four being the controls.
`stdlib/list.march` is unchanged (43 proved / 40 skipped).
