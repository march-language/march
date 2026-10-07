# `[P3]` Refinement: element-flow follow-ups the 2026-09-18 plan left out

Filed 2026-09-18 when the parametric element-flow plan landed
(`specs/plans/2026-09-18-parametric-element-flow-plan.md`, design §4.5). Each
is stated in `specs/lang/refinement-types.md` "What element refinements do
not do"; remove the bullet there when closing one.

1. **A scalar demand on a single-element result.** `need_pos(Option.unwrap_or(o, 1))`
   and a `fold_left` result come through `check_call`, not `check_elements`, so
   `demand_flow` never sees them. Same judgment, a scalar entry point.
2. **Domain facts for multi-parameter lambdas.** `lambda_domain_params` admits
   one parameter. `fold_left`'s accumulator is also where a demand on `b` would
   act as an invariant (its negative occurrence), a separate soundness argument.
3. **A local `fn` with a container return** has no tail checks
   (`ret_elem_demand` is suspended inside it) and lends nothing at its call
   sites. Give it a demand and a gate like `visit_fn` / `gate_elem_returns`.
4. **Relational element returns** (`: List({Int | _ < n})`) are not facts at a
   call site (`entry_is_closed`). Substitute the actuals as `postcond_of` does
   for a scalar relational return.
5. ~~**Tier 2's induction hypothesis trusts component NAMES.**~~ **Closed
   2026-09-21**: it was a live soundness bug (a false relational postcondition
   proved), fixed at the source in `structural_subvars` for all three
   consumers; see `specs/progress/2026-09-21-structural-components-trusted-by-name.md`.
6. ~~**Abstract refinements**, so `filter` can produce `List({Int | p})` from a
   predicate.~~ **Closed 2026-10-06** by phase 2 of
   `specs/2026-09-20-abstract-refinements-design.md`; see
   `specs/progress/2026-10-06-abstract-refinements-phase2.md`. Phases 3
   (named predicates, more stdlib) and 4 (sugar) remain, tracked by that
   design; arity > 1 by `2026-09-20-abstract-refinements-multi-arg-callbacks.md`.
