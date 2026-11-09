`[P3]` Diagnostics for linearity: say which branch/arm/loop consumed the value first; name the early
return for `linear_never_used`; no linearity error on a poisoned binder. specs/plans/2026-11-02-diagnostics-depth-plan.md §F5.

2026-11-04: done (§F5).

What landed:
- `lin_entry` has three new fields, used only for diagnostics: `le_where`, `le_exit` and
  `le_poisoned`. None of them changes which programs are accepted.
- Paths for `linear_used_twice`: `join_linear_paths` is the branch join that `match` arms, `if`
  branches and `match do` bodies share. It now records which arm or branch each consuming use sits
  on, and the "already consumed here" label names it: "…, in the `Some(v)` arm" or "…, in the `else`
  branch". When every path consumes the value, the label adds "(every arm consumes it)" or "(both
  branches consume it)". If constructs nest, the innermost description wins. An arm is named by its
  pattern (`show_arm_pattern`); a pattern over 40 characters gives "the arm on line N" instead.
  March has no loop syntax, so the repeated position is a closure body (`check_captures`). Its label
  reads "…, inside a closure that can run more than once (each iteration consumes it)".
- Exits for `linear_never_used`: the join can find a linear value that is consumed only on paths that
  diverge (end in `panic`). The error then reads "was never used on a path that returns". One label
  points at the consumption ("but this path never returns") and one at the arm or branch that returns
  without consuming the value. Early `let?` returns were already reported by
  `linear_unconsumed_early_return` and are unchanged.
- Poison: an `EApp`, `ECon` or `EField` can report an error inside itself and come out `TError`. A
  linear value that is a direct operand of it (`clsoe(c)`, `c.foo`) is then marked `le_poisoned`.
  No `linear_used_twice`, `linear_never_used`, `linear_mixed_consumption` or
  `linear_unconsumed_early_return` error follows on that value. Only direct operands count. In
  `sink(t) + "x"` the call `sink(t)` checked fine, so a later double use of `t` is still reported.
- Corpus: four new cases. linear_used_twice_28 covers the arm path, _29 the closure iteration and
  _30 poison (only the naming error remains). linear_never_used_26 covers the exit. Two cases were
  regenerated with label-text changes only: linear_captured_4 and linear_mixed_consumption_1. The
  explain pages linear_used_twice and linear_never_used were updated.
