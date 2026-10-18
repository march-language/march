# `[P3]` Refinement: element-flow follow-ups the 2026-09-18 plan left out

Filed 2026-09-18 when the parametric element-flow plan landed
(`specs/plans/2026-09-18-parametric-element-flow-plan.md`, design §4.5). Each
is stated in `specs/lang/refinement-types.md` "What element refinements do
not do"; remove the bullet there when closing one.

1. ~~**A scalar demand on a single-element result.** `need_pos(Option.unwrap_or(o, 1))`
   and a `fold_left` result come through `check_call`, not `check_elements`, so
   `demand_flow` never sees them. Same judgment, a scalar entry point.~~
   **Closed 2026-10-18** by phase 2 of
   `specs/2026-10-18-element-flow-followups-design.md`; see
   `specs/progress/2026-10-18-element-flow-phase2-scalar-demands.md`. Closed
   demands only; a fold's accumulator still gets nothing (the
   fold-accumulator design).
2. ~~**Domain facts for multi-parameter lambdas.** `lambda_domain_params` admits
   one parameter.~~ **Closed 2026-10-18** by phase 1 of
   `specs/2026-10-18-element-flow-followups-design.md`; see
   `specs/progress/2026-10-18-element-flow-phase1-multiparam-lambda-domains.md`.
   The accumulator half (`fold_left`'s accumulator, where a demand on `b`
   acts as an invariant, its negative occurrence) is **closed 2026-10-18** by
   phases 1-2 of `specs/2026-10-18-fold-accumulator-invariants-design.md`
   (`specs/progress/2026-10-18-fold-invariants-phase1.md`,
   `specs/progress/2026-10-18-fold-invariants-phase2.md`): a scalar or
   container demand on the fold's result is assumed of `acc` while the step
   is checked. `acc` still gets no domain fact WITHOUT a demand (phase 4,
   the annotated accumulator).
3. ~~**A local `fn` with a container return** has no tail checks
   (`ret_elem_demand` is suspended inside it) and lends nothing at its call
   sites. Give it a demand and a gate like `visit_fn` / `gate_elem_returns`.~~
   **Closed 2026-10-18** by phase 3 of
   `specs/2026-10-18-element-flow-followups-design.md`; see
   `specs/progress/2026-10-18-element-flow-phase3-local-fn-returns.md`. Closed
   entries only, and no self-call hypothesis for a recursive local (both
   stated in `specs/lang/refinement-types.md`).
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
