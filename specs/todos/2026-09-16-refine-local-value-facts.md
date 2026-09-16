# `[P2]` Refinement checker: local values carry no facts forward

Filed 2026-09-16. **Plan:** `specs/plans/2026-09-16-refinement-precision-plan.md` (Part A).

`unconstrained-subject` is the largest skip bucket on `stdlib/list.march`
(42 of 46 user+stdlib, 4 of 5 in user code). A plain `let` records a binder
span but no fact: `let_equality_rhs` (`lib/refinecheck/refine_scope.ml:987`)
admits only int literals and `+`/`-`/`*` over variables and literals, and
excludes calls, `if`, floats and bare aliases by construction.

The four user-code sites are not one bug. `stdlib/list.march:321,363,395` are
`let t = pmap_threshold()`, a BUILTIN with no `fn_def`
(`lib/typecheck/typecheck_builtins.ml:764`), so no postcondition can be
computed — let-forwarding cannot close them. Only `:344`
(`let csize2 = if csize < 1 do 1 else csize end`) is a pure let-flow case, and
it needs `if`-RHS support specifically.

Direction: census the skips per site first (Part A0), then an `if`-shaped RHS
as a disjunctive path fact, then declared contracts on value-returning
builtins. Keep the self-mention guards and the bare-alias exclusion — both are
load-bearing and pinned (`test/test_refinecheck.ml:11798`).
