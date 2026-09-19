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
5. **Tier 2's induction hypothesis trusts component NAMES.** `structural_subvars`
   (`refine_encode.ml`) collects pattern binders by name over the whole body, and
   `refine_post.ml`'s Tier 2 consumer uses the set as is. The element-return
   hypothesis now drops every parameter name and every name bound more than
   once (`Refine_param.ambiguous_names`, found in review of the 2026-09-18
   work: `match zs do Cons(_, t) -> h(t, t)` inside `match xs do Cons(_, t)`);
   Tier 2 should apply the same filter, or track components per lexical scope.
6. **Abstract refinements**, so `filter` can produce `List({Int | p})` from a
   predicate. A new mechanism in the logic, not plumbing; its own design.
