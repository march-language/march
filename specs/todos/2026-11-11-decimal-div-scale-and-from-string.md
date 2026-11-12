`[P3]` `Decimal.div` and `Decimal.div_round` disagree on result scale; `Decimal.from_string` maps bad input to zero (2026-11-11)

Two API inconsistencies, both now described in the doc strings. `div(a, b, p)` returns scale
`scale(a) + p` while `div_round(a, b, p)` returns scale `p`, so swapping one for the other changes the
number of digits. `from_string` reports no error: `"abc"`, `"12x"` and `""` give `0`, `"1.2.3"` gives
`0.000`. Silent zero for a mistyped amount is a risk in the money arithmetic the module is aimed at.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let a = Decimal.from_string("1.00")
  println(Decimal.to_string(Decimal.div(a, Decimal.from_int(3), 2)))
  println(Decimal.to_string(Decimal.div_round(a, Decimal.from_int(3), 2)))
  println(Decimal.to_string(Decimal.from_string("12x")))
end
end
```

Expected: the two quotients have the same scale; a parse failure is reported (an `Option` or `Result` returning parser beside `from_string`).

Actual (interpreted / compiled): interpreted and compiled agree: `0.3333`, `0.33`, `0`.

Source: `div`, `div_round`, `from_string` in `stdlib/decimal.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
