# `[P3]` A return refinement that holds via a callee's proved return is not proved

Filed 2026-10-21 from the inference-lite design (§0, row C1; §3.3 demand chains).

```march
fn a(x : {Int | _ > 0}) : {Int | _ > 0} do x + 1 end
fn b(x : {Int | _ > 0}) : {Int | _ > 0} do a(x) end
```

`a`'s post proves and `need_pos(a(3))` proves, but `b`'s post skips: `unreflectable-subject` for the
tail `a(x)`, `solver-undecided` for `let r = a(x); r`. The post engine does not lend a callee's
proved postcondition to a tail call. Inference's demand chains reach `b` and stop there.

## Resolution (2026-10-24)

The tail-call form is fixed: `b`'s post proves from `a`'s proved return, across any number
of hops, and `--refine-infer` proposes both returns through its demand chain. The
`let r = a(x); r` form is still `solver-undecided`. It is filed separately as
`specs/todos/2026-10-24-refine-post-let-bound-call-tail.md`. Details:
`specs/progress/2026-10-24-refine-demand-chains.md`.
