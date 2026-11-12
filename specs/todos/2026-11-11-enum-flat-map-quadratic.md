`[P3]` `Enum.flat_map` is quadratic in the output length (2026-11-11)

`flat_map` appends each `f(h)` onto the accumulated result with a local `append_list(acc, f(h))`, which
walks and rebuilds the whole accumulator every step. Total cost is O(output^2). Results are correct.

Repro:

```march
mod A do
needs IO.Console
needs IO.Clock
fn main(_c : Cap(IO.Console), _k : Cap(IO.Clock)) do
  let t0 = unix_time(())
  let ys = Enum.flat_map(List.range(0, 2000), fn x -> [x, x])
  println(to_string(List.length(ys)) ++ " in " ++ to_string(unix_time(()) -. t0) ++ " s")
end
end
```

Expected: time grows linearly with the output length.

Actual (interpreted / compiled): interpreted n = 250 / 500 / 1000 / 2000 inputs take 0.11 / 0.32 / 2.4 / 9.3 s; compiled n = 1000 / 2000 / 4000 / 8000 take 0.003 / 0.013 / 0.066 / 0.59 s (4x to 9x per doubling).

Source: `flat_map` (`go`, `append_list`) in `stdlib/enum.march`. One fix direction: accumulate reversed and reverse once.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
