# An `if`-shaped `let` RHS pushes a disjunctive fact

**Landed 2026-09-16.** Plan: `specs/plans/2026-09-16-refinement-precision-plan.md`
(Part A, phase A1). Census that sized it:
`specs/progress/2026-09-16-refine-skip-census.md`.

## What changed

`let n = <rhs>` pushed the path fact `n == rhs` only for an admitted RHS
shape, and `if` was excluded with the note "its encoding is a separate
decision". It is now encoded, as the disjunction

```
(g && n == a) || (not g && n == b)
```

which is what `let c = if x < 1 do 1 else x end` needs: `c` is at least 1
whichever arm ran, and no flat equality can say that.

Both arms must be admitted and the **guard must translate**, or nothing is
pushed. A dropped guard would leave `n == a || n == b` — the value is one of
two things under no condition at all — which is worse than silence.

## The bare-variable arm, and why it needed the typechecker

`let_equality_rhs` excludes a bare variable deliberately: the path translator
reflects a variable at the INTEGER sort, so aliasing an ADT-typed name
(`let u = o` with `o : Option(Int)`) mixes sorts in one VC and the
sort-conflict gate drops the **whole** VC, unrelated obligations included.

But a bare variable is exactly what an `if` arm wants (`if c < 1 do 1 else c
end` is the shape the stdlib writes). `if_arm_admitted` therefore admits one
only when the typechecker's span table says the binder is `Int`. No table and
no recorded binding span both answer "not admitted" — conservative in the
direction that costs a proof rather than soundness.

That makes this the rare case where the fixtures must use `typed_ledger`:
`Refine_check.check_module` always gets the table in production, but most unit
fixtures leave it out, so an untyped fixture would silently test nothing. A
REJECT fixture with two `Option(Int)` arms pins that `sort-conflict` never
appears.

## Measurements

- `stdlib/list.march`, user-code slice: 15 proved / 2 skipped -> **16 proved /
  1 skipped**. The remaining one is `nth`'s `partial-conjunct`, a different
  cause. Whole ledger: 41 proved / 43 skipped -> **42 proved / 42 skipped**.
- CI skip ceiling lowered 43 -> 42.
- Coverage audit unchanged: 114 enforced, 0 unenforced.
- Cold check: 0.39 s, unchanged. The disjunction is a case split, a different
  cost class from the existing conjunctive equalities, so this was measured
  rather than assumed.
- `test_refinecheck.exe`: 895/895. Two of the five new `let-if` cases are RED
  without the arm.

## Scope, stated honestly

This closes **one** stdlib site. The plan predicted `unconstrained-subject`
was the largest bucket and inferred that local-value flow was the
highest-value work; the census disproved the inference (20 of 42 are missing
declared contracts, 18 are two real bugs). The phase was kept because it is
small, self-contained and the shape recurs in user code — not because it moved
the number that motivated it.
