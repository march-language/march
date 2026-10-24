# `[P3]` A return that is a `let`-bound call result is not proved from the callee's return

Filed 2026-10-24 from `specs/progress/2026-10-24-refine-demand-chains.md` (C1's second form).

```march
fn a(x : {Int | _ > 0}) : {Int | _ > 0} do x + 1 end
fn b(x : {Int | _ > 0}) : {Int | _ > 0} do
  let r = a(x)
  r
end
```

The bare tail `a(x)` proves since 2026-10-24. This form stays `solver-undecided`:
`check_fn_post_verdict_core` (`lib/refinecheck/refine_post.ml`) builds the post scope from
the parameters only, so `r` is an unconstrained constant. Needs the block's `let`s ahead of
a tail in the post scope, or `inline_lets`-style substitution that falls back to the written
tail when the inlined one fails to reflect, so no proved verdict turns into a skip.
