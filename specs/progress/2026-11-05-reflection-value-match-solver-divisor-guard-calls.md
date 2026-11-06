Reflection: a value-position `match`, solver-only divisors, and guard calls

Three more gaps of `specs/todos/2026-10-31-reflection-encoder-gaps.md`.

**A `match` in value position.** `tr_val` translated a `match` (or a block of `let`s) only
when it had one case. Several cases now become an `ite` chain: each case's guards already
exclude the cases before it, and R5 makes the cases cover, so the last needs no test. At most
`max_let_cases` (16) cases. So `plus1(match l do Ez -> 0  Cz(x, _) -> x end)` unfolds.

**A divisor only the solver shows non-zero.** `divisions_defined` falls back to
`solver_nonzero` when its structural reading finds no fact: z3 is asked `d != 0` under the
facts that are arithmetic over the function's `Int` parameters (anything else is dropped,
which only weakens the assumptions). `b : {Int | b * b > 0}` now reflects; `b * b >= 0` does
not.

**Guard calls.** At depth >= 1 a call is unfolded only once its arm is decided, and a guard
calling a reflected function (`if pos(n) ...`) was never decided: the guard's own call was
produced only by unfolding the call it guards. `unfold`'s rounds now queue the reflected calls
in an undecided call's guards at the same level, so what they learn can decide it. The queue is
bounded by the query budget, since a chain of guards need not unfold anything.

Tests (`test/test_refine_lemma.ml`): `match_value`, `match_value_red`, `div_solver`,
`div_solver_red`, `guard_call`, `guard_call_red` (an undecided guard, `wrap(x)` for any `x`,
stays unproved).
