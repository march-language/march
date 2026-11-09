`[P3]` Diagnostics for refinements: no internal binder names, guard suggestions over the real argument,
the solver's counterexample printed, and a label on where the failing value came from. specs/plans/2026-11-02-diagnostics-depth-plan.md §F4.

**Done 2026-11-05**, plus one step past §F4: the violating call is run.

What a `refinement_violated` call-site diagnostic (`lib/refinecheck/refine_call.ml`,
`check_call_stage`'s violation arm) now says:

1. **No binder names.** The predicate is read over the parameter's name in the note
   (`b != 0`) and over the call's own actuals in the label and guard (`len(ys) > 0`). Every
   other callee parameter the predicate names is read at its actual too (`_ < len(xs)` →
   `i < len(items)`; before, the guard kept the callee's `xs`). A pass-site counterexample no
   longer prints `(cb_x) = -1` ("for example, when `take_n` is given `-1`").
2. **Guards over the call.** `note: guard the call (e.g. `if d != 0 do safe_div(10, d) else …
   end`) …`, the call quoted from source. A closed argument gets "`0 - 5` can never satisfy
   `n > 0`" (or "`-3 >= 0` is never true" when the parameter has no name of its own).
3. **Counterexample.** "for example, when `d` is `0` and …" on its own line, replacing the
   inline `(e.g. d = 0)`. Witness-confirmed values when `Witness.confirm_precond` agrees, the
   raw model otherwise (as before; an element obligation's `$elem` reads "an element is `5`").
4. **Origin labels.** The argument label names the value (`` `n` is `-5` here ``) for a closed
   argument. Each name the argument is built from gets a label at its binding (`rctx.binds`),
   with what the scope knows of it when it is refined ("`ys` comes from here, where
   `len(ys) >= 0` is known"), and every source-written path condition that names it gets
   "the call is reached only when this is true/false". A fact derived from a `match` arm is
   not labelled: its span is the scrutinee's, not a condition the user wrote.
5. **The call is run** (`Refine_check.add_run_note`, `Witness.run_call`). The stage-1
   confirmation already ran counterexamples (`Witness.confirm_precond` evaluates the
   predicate, `confirm_precond_reachable` / `confirm_post` run functions); this reuses its
   harness. When every argument evaluates (closed, or from the confirmed assignment kept per
   call span in `Witness.examples`) and the callee is a module-level function (not a local or
   alias), it is applied once through `call_fn_classified`: the effect veto, the reduction
   fuel, no wall-clock. A user panic, failed `assert`, unmatched `match`, Int overflow or
   division by zero becomes one note: `running `safe_div(10, 0)` panics: division by zero`.
   A return, fuel out, a refused effect or any other evaluator error adds nothing. A definite
   `return_refinement_violated` now goes through the existing `emit_witness_error` when
   `confirm_post` confirms the model (`but bad(-1) returns -1.`).

**Verdicts cannot move.** Every new execution is display-only and runs under
`Witness.uncharged`, which builds the module environment first (charged, exactly as the first
charged execution would) and then restores `wall_budget`, so a later promotion sees the
budget it always did. `scripts/oracle-base.sh refine types --base origin/main`: refine
IDENTICAL (8261 lines over 574 fixtures); types tier 1's 31 changed fixtures differ only in
diagnostic message text (no AST or verdict change), and the 177 tier-2 lines are the wording,
labels and run lines above.

Corpus: `refinement_violated_18` (open argument: example, guard, origin and branch labels,
run), `_19` (multi-parameter guard over `items`; no run, `items` has no value), `_20`
(callee reads the clock: no run line), `_21` (call through a refined function-typed
parameter: guard over `k`, never `_`); every existing `refinement_violated_*` and
`return_refinement_violated_1` regenerated. Explain page: `specs/lang/errors/refinement_violated.md`
gained "Reading the message".

Still open (not this item): the `refinement_violated` / `refinement_unverified` headline
still fails the house-style `capital`/`period` rules (`style-allowlist.txt`); rewording
"refinement violation: …" touches ~40 `EXPECT-ERROR` lines and the z3-backed suite, so it is
its own change. The interpreter carries no source position, so the run line has no
"(line N)".
