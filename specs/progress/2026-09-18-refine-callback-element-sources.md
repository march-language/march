# Callback results, self-calls and lambda codomains as element sources

**Landed 2026-09-18.** Design: `specs/2026-09-18-parametric-element-flow-design.md` §3. Plan: `specs/plans/2026-09-18-parametric-element-flow-plan.md`, Phase 2.

## What changed

1. **`check_elements` sees the callback environment.** Its context used
   `postcond_of ctx defs` without `~cb`, so `need_pos(f(x))` proved while the
   same `f(h)` as an element (`Cons(f(h), …)`) was "could not be translated".
2. **Structural self-call hypothesis** (`elem_ret_hyp`, `Refine_param`).
   While `visit_fn` walks a function with a container return, a call to its own
   name whose argument at some parameter position is in `structural_subvars`
   of that parameter carries the declared entry: Tier 2's induction rule.
   Active only during the gating rounds or once the function is in
   `elem_ret_proved`, so a fact from an unproved hypothesis never discharges
   anything else. Because `structural_subvars` works by NAME over the whole
   body, a component is trusted only if its name is bound exactly once in the
   clause and is not a parameter (`ambiguous_names`). The first version
   filtered only `let` rebinds; review found that a later
   `match zs do Cons(_, t) -> h(t, t)` inside `match xs do Cons(_, t)` passed
   `zs`'s tail off as `xs`'s component (pinned by a test that goes RED without
   the filter).
3. **Container codomains** (`f : (Int) -> List({Int | p})`).
   `callback_sig_of_ty` now builds a signature for a codomain with a refinement
   inside it; `declared_elem_return` reads the entry for a callback parameter
   (and only for one: the `$cb_arg` marker excludes local `fn`s and
   aliases); `check_pass_site_elements` obliges every pass site first (an
   inline lambda's tails, a named callable's proved element return by
   implication, anything else a recorded skip).
4. **An inline lambda's codomain violation is reported.**
   `Witness.confirm_post` runs functions by name, so a lambda was never
   confirmed and `fn y -> y - 1` where `(Int) -> {Int | _ > 0}` is expected was
   `solver-undecided`. `Witness.with_lambda` makes the lambda under check
   runnable (`call_fn` evaluates it in the module environment), and an
   unannotated single parameter is declared at the expected domain so the
   model decodes. A lambda naming a local of its enclosing function
   (`ctx.locals`) is not made runnable and keeps the skip.

## Tests

Group `callback-elements` (6 cases): the refined `map_pos` proves end to end,
with controls for an unrefined codomain and a non-structural self-call; the
lambda codomain violation, with a capturing-lambda control; container codomain
obligation and assumption (lambda `[0]` rejected, `[1, 2]` accepted, named
proved/unproved callables). All but the two controls fail on `HEAD`.
Separately, removing `~cb` alone or disabling the hypothesis alone each turn
the `map_pos` case RED (measured).

Element violation messages no longer name the synthetic parameter: "an element
passed to `sum_pos`" instead of "argument `$elem` of `sum_pos`".
