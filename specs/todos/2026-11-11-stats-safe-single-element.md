`[P3]` `Stats.variance_safe([x])` is `Ok(0.0)` but `Stats.std_dev_safe([x])` is `Err` (2026-11-11)

The two `_safe` functions disagree on a one-element sample although standard deviation is the square
root of the same variance. The doc strings describe the difference. The unsafe `variance([x])` and
`std_dev([x])` both return `0.0`.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Stats.variance_safe([5.0])))
  println(to_string(Stats.std_dev_safe([5.0])))
end
end
```

Expected: both `Err` (sample variance needs two elements) or both `Ok(0.0)`.

Actual (interpreted / compiled): interpreted and compiled agree: `Ok(0.)` and `Err(Stats.std_dev_safe: need at least 2 elements)`.

Source: `variance_safe`, `std_dev_safe` in `stdlib/stats.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
