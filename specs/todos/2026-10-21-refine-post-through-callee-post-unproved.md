# `[P3]` A return refinement that holds via a callee's proved return is not proved

Filed 2026-10-21 from the inference-lite design (§0, row C1; §3.3 demand chains).

```march
fn a(x : {Int | _ > 0}) : {Int | _ > 0} do x + 1 end
fn b(x : {Int | _ > 0}) : {Int | _ > 0} do a(x) end
```

`a`'s post proves and `need_pos(a(3))` proves, but `b`'s post skips: `unreflectable-subject` for the
tail `a(x)`, `solver-undecided` for `let r = a(x); r`. The post engine does not lend a callee's
proved postcondition to a tail call. Inference's demand chains reach `b` and stop there.
