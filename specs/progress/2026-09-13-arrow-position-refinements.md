# `[P3]` Arrow positions: the domain is enforced but audited as not; the codomain is not enforced

Filed 2026-09-13. Design: `specs/2026-09-13-refinement-p3-designs.md` §1.
Hole fixture: `test/refine_audit/holes/arrow_domain.march`, the last one in
the audit's non-vacuity set.

## Two halves

**Domain (audit precision only).** `fn apply(f : ({Int | _ > 0}) -> Int, x :
Int)`: a call `f(x)` inside `apply` IS checked through the callback env, and
passing a callable to `apply` IS checked at the pass site (contravariance).
`--refine-audit` nonetheless reports the `Arrow_domain` site Unenforced,
because `classify`'s nesting rule fires before anything looks at the arrow.

**Codomain (a real gap, both sides).** `fn apply(f : Int -> {Int | _ > 0})`:
`callback_sig_of_ty` leaves `ret = None`, so `let y = f(x)` inside `apply`
learns nothing about `y`; and nothing at the pass site asks whether the
passed callable's own return satisfies `_ > 0`. `apply(fn n -> 0, 1)` is
accepted in silence.

## Repro (codomain)

```march
mod ArrowCodomain do
  cap verified
  fn need(k : {Int | k > 0}) : Int do k end
  fn apply(f : Int -> {Int | _ > 0}, x : Int) : Int do need(f(x)) end   -- need(f(x)) is a skip today
  fn main() : Int do apply(fn n -> 0, 1) end                            -- accepted in silence today
end
```

## Where a fix would land

`lib/refinecheck/refine_audit.ml` (`classify`, before rule 1) for the
domain; `lib/refinecheck/refine_scope.ml` (`callback_sig_of_ty`'s `ret`),
`refine_resolve.ml` (`postcond_of` consulting the callee env) and
`refine_check.ml` (`pass_site_obligation`'s codomain half) for the codomain.
The design spec has the full plan, the soundness pairing (no assumption
without the pass-site obligation), and the test list.

## 2026-09-13: the DOMAIN half is closed (P3 design §1a)

`Refine_audit.classify` reports an `Arrow_domain` site at a function or
lambda parameter Enforced when `callback_sig_of_ty` accepts the declared
arrow (a single-argument arrow with a refined domain), which is exactly the
set the callback env checks calls through and the pass-site check obliges
callers at. The `arrow_domain` hole fixture is retired (replaced in the
audit's non-vacuity set by `type_arg_two_layers`). This file stays open for
the CODOMAIN half (§1b/§1c).

## 2026-09-13: the CODOMAIN half is closed too (P3 design §1b/§1c)

**Assumption (§1b).** `Refine_scope.callback_sig_of_ty` fills `ret` /
`ret_sort` from a refined codomain (through `return_refine_sorted` on a
stand-in definition), and `Refine_resolve.postcond_of ?cb` consults the
callee env after name resolution, so `let y = f(x)` inside `apply(f : Int
-> {Int | _ > 0})` learns `y > 0`. The same plumbing consumes a local `fn`'s
and a `let`-bound lambda's PROVED return (closing phase 1's "honest but not
yet consumed" note). The three helpers with no callee env in scope
(`check_let_annotation`, `check_elements`, the actor state literal) keep
name resolution only.

**Obligation (§1c).** `check_pass_sites` gained a covariant half: when the
expected arrow's codomain is refined, a named function or local with a
proved return refinement is checked by implication on a fresh `$r`
(subject `Callback_codomain`, the definite-failure rule), an inline lambda
by `check_fn_post_verdict` on its synthesised definition with the expected
codomain as its return type, and anything else is a recorded skip. `apply(fn
n -> 0, 1)` is rejected; `apply(nn_fn, 1)` with `nn_fn : … -> {Int | _ >= 0}`
is refuted (`>= 0` does not imply `> 0`); `apply(pos_fn, 1)` proves;
`apply(plain_fn, 1)` files a skip.

`Refine_audit.classify` reports `Arrow_codomain` at a function or lambda
parameter Enforced. Tests: `test/test_refinecheck.ml`, group
`arrow-codomain` (assumption + control, named implication both ways, inline
lambda both ways, recorded skip). Both halves of this file are closed.
