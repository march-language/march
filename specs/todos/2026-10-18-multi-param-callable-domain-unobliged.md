`[P2]` Refinement: a multi-parameter named function passed as a callback has its preconditions obliged nowhere

Found 2026-10-18 while checking the other routes of the named-callback fix (review of the
fold-accumulator invariants phase 1; `specs/progress/2026-10-18-fold-invariants-phase1.md`,
"Review follow-up"). The pass-site domain check (`pass_site_obligation`,
`lib/refinecheck/refine_check.ml`) covers a callable of exactly ONE parameter: passing
`dec(k : {Int | _ > 100})` where `a -> {Int | _ > 0}` is expected is a violation
(`ap(n, dec)`, `Option.map(o, dec)`), the contravariance stance. A callable of two or more
parameters gets no obligation at all (`List.length gsg.param_names <> 1 -> None`):

```march
mod K do
  cap verified
  fn dec2(a : {Int | _ > 100}, _x : Int) : {Int | _ > 0} do a - 50 end
  fn go(ys : List(Int)) : Int do List.fold_left(ys, 1, dec2) end   -- 0 obligations; accepted
  fn ap2(x : a, y : a, f : a -> a -> Int) : Int do f(x, y) end
  fn go2(n : Int) : Int do ap2(n, n, dec2) end                      -- 0 obligations; accepted
end
```

`dec2`'s precondition is never obliged, so its "proved" return `> 0` does not hold of the
value `go([5])` computes (-49). No false PROOF follows any more: the demand route
(`need_pos(List.fold_left(ys, 1, dec2))`) now checks the named step's preconditions itself
and is a skip. But a contract is silently unenforced under `cap verified`. Fix direction:
extend `pass_site_obligation` to an arrow chain of the callable's arity, one symbolic
argument per position (`{base | true}` over an unrefined or type-variable domain, the
declared domain when refined), and check every refined parameter against them; then run the
refine oracle and the stdlib sweep, since stdlib code passing a two-parameter named function
with refined parameters to a fold becomes obliged (expected violations or skips there are
real findings, not regressions).
