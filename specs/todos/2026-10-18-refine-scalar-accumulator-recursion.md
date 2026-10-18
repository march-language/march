`[P3]` Refinement: a hand-written scalar accumulator recursion does not prove its return

Filed 2026-10-18 with phase 1 of `specs/2026-10-18-fold-accumulator-invariants-design.md`
(its row f19 and §7, "Hand-written accumulator recursion"). The fold rule covers a CALL to
a parametric fold; it says nothing about a function that is itself the loop:

```march
fn sum_nn(xs : List({Int | _ >= 0}), acc : {Int | _ >= 0}) : {Int | _ >= 0} do
  match xs do
    Nil -> acc
    Cons(h, t) -> sum_nn(t, acc + h)        -- postcondition: unreflectable-subject skip
  end
end
```

Measured on the phase 1 branch: the return is an `unreflectable-subject` skip; with
`let r = sum_nn(t, acc + h); r` it is `solver-undecided`. The `acc + h` precondition at the
recursive call proves. What is missing is a SCALAR self-call induction hypothesis on the
definition side: Tier 2's hypothesis (`post_induction_shape`, `lib/refinecheck/refine_post.ml`)
requires an ADT base, so a scalar return of a self-call is never assumed. Fix direction: for a
closed scalar return refinement, a structurally decreasing self-call's result may assume the
return refinement (the same induction Tier 2 runs for ADT returns), gated exactly like it
(structural argument, every precondition of the recursive call PROVED). It is the definition
-side counterpart of the fold rule and unrelated to callers. The stdlib's monomorphic
`go` loops (`List.sum_int`, `Enum.sum`, `Stats.sum`) are this shape (design §6).
