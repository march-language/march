# `[P3]` A `Deque(a[p])` element fact does not survive `Deque.to_list`

Filed 2026-10-21 from the inference-lite evaluation (rediscovery row `Deque.filter`).

```march
fn dfilter(d : Deque.Deque(a), pred : a -> Bool[p]) : Deque.Deque(a[p]) do Deque.filter(d, pred) end
fn go(d : Deque.Deque(Int)) : Int do sum_pos(Deque.to_list(dfilter(d, fn y -> y > 0))) end
```

Even with the hand-written abstract refinement, `sum_pos(...)` stays
`parametric-source-unproved`: `Deque.to_list : Deque(a) -> List(a)` does not hand the element
entry of its `Deque` argument to its `List` result. So the `Deque.filter` rediscovery row is
out of reach for the checker, not only for the v1 K6 shape grammar (List, Option and 2-tuples
of lists), which does not cover `Within`-field containers either.
