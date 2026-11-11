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

**The same conflation reaches the backend** (round-4 review, probe `ctor-review4/ct3.march`): a
user `type CancelToken = Tok(Int)` is merged with the typechecker's built-in `CancelToken` (named
only in builtin signatures such as `task_cancel_token_new`), so
`match Some(task_cancel_token_new()) do Some(Tok(_)) -> …` typechecks; interpreted it reaches the
wrong arm, and `--compile` emits invalid LLVM (`march: clang failed (exit 1)`). A user type named
like any type the base environment produces (`Typecheck_builtins.builtin_type_names`) should be
rejected or kept distinct by the typechecker.

## 2026-11-09: nested-module collisions fixed; built-in and stdlib collisions still open

Two variant types of one short name declared in two modules of the checked program
(`A.T` / `B.T`, the `q1.march` probe) now have their own identities
(`lib/typecheck/typecheck_nominal.ml`;
`specs/progress/2026-10-13-same-short-name-nested-types-unify.md`). What remains open here:

- a user type named like a type the base environment produces (`type CancelToken`,
  `type DownReason`, `type Option`; `Typecheck_builtins.builtin_type_names`), and
- a user type named like a stdlib type.

Stdlib declarations are excluded from the collision count on purpose: they reach a check
through the cached stdlib env, whose signatures are bare, which is what sank the archived
"cut (b)" (`specs/plans/archive/2026-07-17-fqn-type-ctor-identity.md`). The mechanism extends
by counting those names as declared at a pseudo path and giving a colliding entry-level user
type a non-bare identity (e.g. `Main.CancelToken`). Before doing that, audit the tests and
examples that declare a type with a built-in name on purpose (they rely on the conflation
today), and decide whether rejecting such a declaration is the better answer.

The refinement checker's skip rule (every datatype whose short name two declarants share
resolves no constructor) can be relaxed for nested-module pairs now.

## 2026-11-10: the function-name half is fixed; this type half needs its own mechanism

The two sibling todos (a user `fn show` vs the `Show` method, an entry `mod List` vs the stdlib
`List`) were one TIR symbol for two definitions, and lowering now names the user's definition
distinctly (`specs/progress/2026-11-10-user-stdlib-name-collisions.md`). That does not reach this
item: a type's identity is decided by the typechecker (unification on the bare `TCon` name), before
lowering, so a user `type CancelToken` is already the built-in one by the time TIR names anything.
The fix is still the one sketched above (count built-in and stdlib type names as declared at a
pseudo path in `Typecheck_nominal` and give a colliding entry-level user type a non-bare identity,
or reject the declaration), after auditing the tests and examples that rely on the conflation.
