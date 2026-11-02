`[P1]` The typechecker treats two types of one SHORT name as one type: `A.Tq` and `B.Tq` (or a user
type and a built-in, `type DownReason`, `type Option`) unify, so a value of one is accepted where
the other is expected. A type-system soundness hole: a `match` on a `B.Tq` value may list `A.Tq`'s
constructors, and a function of `A.T` accepts a `B.T`.

Found by the round-2 soundness review of the refinement checker's constructor registry
(`specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md`). Probes (round-2 review
scratch area `ctor-review2/`):

- `q1.march`: `mod A do type T = KA(Int) | ZA ... fn g(x : T) end`, `mod B do type T = KB | ZB end`;
  `A.g(B.ZB)` and `A.g(B.mk())` typecheck and run.
- `c2diff.march`: the same program with B's type renamed `Tb` is rejected (`expected Tb but got
  Tq`), so it is the shared short name, not structural typing, that admits it.

Cause (as read): a constructor's `ci_type` and a type's `TCon` name are the BARE type name
(`Typecheck` registers `ci_type = name.txt`), so two declarations of one short name are one nominal
type to unification.

The refinement checker now works around it (every datatype whose short name two declarants share,
the typechecker's built-in types included, resolves no constructor), at the cost of proofs over
such types (`module-qualified-measure-and-sort`). Fixing the typechecker (qualified nominal types)
would let that rule be relaxed.
