# `[P2]` Linearity: a lambda argument checked before its parameter's type is known can drop a linear value

Filed 2026-09-18 during the LinearMap work
([[2026-09-18-linear-map]]). A soundness hole; not touched by that change.

## Symptom

```march
always_linear type S1 = S1(Int)
fn ap2(f : a -> Int, linear x : a) : Int do f(x) end
...
ap2(fn s -> 0, S1(1))        -- accepted: the lambda drops S1(1)
```

`ap2(S1(1)` in the other order (value first, then the lambda) is rejected ("The
linear value `s` was never used"), because `a` is already `S1` when the lambda is
checked. With the lambda first, `s`'s type is an unbound variable when the lambda
body is checked, so it is bound as a pending entry, and the pending entry is not
reported once the later argument fixes `a` to `S1`.

The same shape appeared in `reject/t254`: `LinearMap.empty(fn a -> fn b -> false)`
under a `let m : LinearMap(S1, Int)` annotation reports nothing about `a` and `b`,
while `let f : S1 -> S1 -> Bool = fn a -> fn b -> false` does.

`LinearMap.drain(m, acc, f)` is not affected in practice: the map comes first, so
`v` is known when the callback is checked (`reject/t252`).

## Where to look

`judge_pending` runs at the lambda's scope close, while the parameter's type is still
unbound, so "One still unresolved is polymorphic, and is left alone." A pending entry
of a lambda passed as an argument needs judging again once the enclosing call is
solved (or at the enclosing function's close), as unannotated `fn` parameters are.

## Tests

Reject: `ap2(fn s -> 0, S1(1))`. Accept: the same with `fn s -> sink(s)`.
