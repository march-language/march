# Lemmas: a false theorem is refuted; proof-backed rewrites in the LSP (2026-11-03)

## A false lemma is `refinement_violated`

A lemma goal (`Lemma_goal` in `lib/refinecheck/refine_call.ml`) took the `¬G` discharge
like any precondition, so a theorem false at some input but not all
(`{Unit | n + n >= n}`) was only `lemma_unproved`. Found by `--lemma-test`, which gave the
counterexample `n = -1` the checker did not.

- `Refine_call.lemma_counterexample` (set by `Refine_check`, which has the lemma
  definitions): the solver's model is decoded onto the lemma's parameters
  (`Witness.decode_model`), checked against their refinements (`Witness.admissible`), and
  the theorem is evaluated in the interpreter (`Witness.eval_classified`). A `false`
  there is a confirmed counterexample: a lemma claims its theorem at every input its
  parameters admit, wherever in the body the model came from. Running the theorem also
  covers stage 2, where an unfolded reflected call may be an uninterpreted symbol: the
  interpreter computes the real value.
- The confirmation is only recorded (`Refine_call.lemma_refuted`); the verdict is left as
  it was. The first version marked the obligation `Violated` during the gate's silent
  scratch walk, and the induction rounds then admitted `bad(n) : {Unit | false}` from its
  own hypothesis (no L4 error, exit 0). That case is pinned by `sound_lemma_ih`.
- The lemma pass reports a recorded lemma as `refinement_violated` ("the lemma `nn` is
  false: its theorem `twice(n) >= n` does not hold at n = -1") instead of
  `lemma_unproved`.
- A theorem false at every input (`{Unit | false}`) was already `refinement_violated`
  through the definite path, unchanged.

Tests (`reflect-lemma`): `lemma_refuted` (a direct and a stage-2 theorem refuted at
`n = -1`; a true lemma needing induction stays unproved; an input outside a refined
parameter does not count). `sound_lemma_ih`'s second case also accepts "refuted".

## Proof-backed rewrites (idea 5)

`lsp/lib/lemma_rewrite.ml`, added to `Server_state.code_actions_for`. A lemma of the open
file whose theorem is `lhs == rhs` is a rule `lhs -> rhs` over its parameters. The
smallest expression at the cursor that `lhs` matches (callee and constructor names equal or
one qualifying the other; a repeated variable must match the same text) is replaced by
`rhs` with each variable's text substituted (parenthesised when it is an operator
application). It is offered only when `Refine_diag.lemma_admitted` says the lemma is
admitted, and only left to right. Lemmas of other files (the stdlib's, once phase 3 lands)
are not yet rules.

Test: `lsp/test/test_lsp_refine.ml` "lsp_lemma_rewrite".

## Also

`test/test_properties.ml` "record-update converged": the interpreter run's bound is 120 s,
like the compile's, and a timeout (124) fails with its own message. The 10 s bound timed
out on a cold CI runner (#1068), and the 124 passed the `< 128` check, so it read as
"stderr does not mention the field".
