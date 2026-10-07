# Refinement: an `Int` alias `let b = a` carries `a`'s facts

Landed 2026-10-06. Found while re-checking the refinement frontier against
main: `let b = a + 0` proved `take_pos(b)` but `let b = a` skipped it
(`unconstrained-subject`), including when `a` was a refined parameter.

## Cause

`Refine_scope.let_equality_rhs` rejects a bare `A.EVar` right-hand side
outright. That was the fix for finding 2 of
`2026-09-02-refinement-precision-lets-and-arms.md`: an `Option(Int)` alias
pushed `u == o` at the integer sort beside `o`'s datatype-sort tester facts,
and the sort-conflict gate dropped the whole VC. The rule was wider than the
cause. The `if`-shaped `let` work (2026-09-16) had already written the narrow
rule for `if` arms, `if_arm_admitted`: admit a bare variable only when the
typechecker's span table says its binder is `Int`.

## Fix

`if_arm_admitted` is renamed `let_rhs_admitted` and now gates the flat
`let n = e` arm too (`lib/refinecheck/refine_check.ml`). No new channel and no
new query; the self-mention guard and `path_shadow` retirement are unchanged,
so rebinding `a` retires `b == a`.

## Tests

`let-equality-alias` in `test/test_refinecheck.ml`, all on `typed_ledger`
(the table is what admits the alias):

- IA1 refined-parameter alias proves; IA2 literal chain proves (both red
  before: `(0, 0, 1)`);
- IA3 a violating value is reported through the alias (`(0, 1, 0)`), so IA2
  is not passing on an equality that constrains nothing;
- IA4 rebinding the aliased name never yields a false violation;
- IA5 OA1 rerun WITH the type table: the `Option` alias is still not admitted
  and no `sort-conflict` skip appears.

## Docs

`specs/lang/refinement-types.md`: the two "a local `let` does not carry a fact
forward, for any type" passages were stale since 2026-09-02 and now state the
admitted `Int` shapes; the element-refinements bullet saying a non-linear
lambda result (`y * y + 1`) does not prove was stale since #573 and is removed.
