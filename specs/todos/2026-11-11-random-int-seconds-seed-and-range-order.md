`[P3]` `Random.int` repeats within one second; `Random.range` with `hi < lo` panics or returns out-of-range values (2026-11-11)

`Random.int` seeds a fresh generator from `unix_time` truncated to whole seconds, so every call in the
same second returns the same number. `Random.range(rng, lo, hi)` with `hi == lo - 1` stops with
`int_mod: division by zero`, and a smaller `hi` returns a value outside both orders of the interval.
Both are described in the doc strings; neither argument is refined, so nothing warns at the call site.

Repro:

```march
mod A do
needs IO.Console
needs IO.Clock
fn rt(s : String) : Int do
  match string_to_int(s) do
  Some(n) -> n
  None -> 0
  end
end
fn main(_c : Cap(IO.Console), _k : Cap(IO.Clock)) do
  println(to_string(Random.int(1, 1000000) == Random.int(1, 1000000)))
  let (a, _) = Random.range(Random.seed(7), 10, rt("5"))
  println(to_string(a))
  let (b, _) = Random.range(Random.seed(7), 10, rt("9"))
  println(to_string(b))
end
end
```

Expected: two `Random.int` calls differ (with probability 1 - 10^-6); `range` with `hi < lo` is rejected by a `lo <= hi` precondition or a named panic.

Actual (interpreted / compiled): interpreted and compiled agree: `true`, `12` (not in 5..10), then run-time error `int_mod: division by zero`.

Source: `int`, `range` in `stdlib/random.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
