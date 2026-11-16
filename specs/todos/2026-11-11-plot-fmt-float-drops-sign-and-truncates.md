`[P2]` Plot: tick labels in (-1, 0) lose their minus sign; coordinates truncate instead of rounding (2026-11-11)

`fmt_scaled` prints `scaled / 100` as the whole part. For a value in (-1, 0) that is integer 0, so the sign is lost and -0.5 is labelled `0.50`: an axis shows two `0.50` ticks. `fmt_float` also truncates toward zero via `float_to_int`, so 10.2 prints as `10.19`.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  -- y data in [-1, 1]: the y axis gets ticks at -1, -0.5, 0, 0.5, 1.
  println(Plot.quick_scatter([0.0, 1.0], [-1.0, 1.0]))
end
end
```

Expected: y tick labels `-1.0, -0.50, 0.0, 0.50, 1.0`, font-size `10.2`.

Actual (interpreted / compiled): labels `-1.0, 0.50, 0.0, 0.50, 1.0`, font-size `10.19` (interpreted and compiled).

Source: `fmt_float` and `fmt_scaled` in `stdlib/plot.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
