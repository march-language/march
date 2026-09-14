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
