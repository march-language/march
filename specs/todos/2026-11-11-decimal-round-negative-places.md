`[P2]` `Decimal.round` with negative `places` returns a value that `Decimal.to_string` prints wrongly (2026-11-11)

`round(d, places)` accepts any Int. For a negative `places` it builds `Decimal(coef, places)` with a
negative scale. Arithmetic treats that scale consistently (`add` gives the right sum), but `to_string`
prints the coefficient followed by a bare dot, so 1200 is shown as `12.`. `places` is not refined and
the doc string does not mention negative values.

Repro:

```march
mod A do
needs IO.Console
fn rt(s : String) : Int do
  match string_to_int(s) do
  Some(n) -> n
  None -> 0
  end
end
fn main(_c : Cap(IO.Console)) do
  let r = Decimal.round(Decimal.from_string("1234.5"), rt("-2"))
  println(Decimal.to_string(r))
  println(to_string(Decimal.scale(r)))
  println(Decimal.to_string(Decimal.add(r, Decimal.from_int(1))))
end
end
```

Expected: `1200`, a scale of 0 (or a refinement `places >= 0` that rejects the call), `1201`.

Actual (interpreted / compiled): interpreted and compiled agree: `12.`, `-2`, `1201`.

Source: `round` and `to_string` in `stdlib/decimal.march`. One fix direction: refine `places` to `>= 0`, or normalise a negative scale to 0 before returning.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
