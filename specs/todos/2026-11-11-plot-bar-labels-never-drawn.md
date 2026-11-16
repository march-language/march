`[P3]` Plot.bar_series / quick_bar ignore the label strings (2026-11-11)

`bar_series(labels, values)` uses only the number of labels. The strings are never rendered, and the x axis shows numeric ticks instead of category names. Documented in the doc string, but the argument is otherwise pointless.

Repro:
```march
mod A do
needs IO.Console
fn show(r : Result(DataFrame.DataFrame, String)) : String do
  match r do
  Ok(df) -> DataFrame.to_csv_string(df)
  Err(e) -> "Err: " ++ e
  end
end
fn main(_c : Cap(IO.Console)) do
  let svg = Plot.quick_bar(["apples", "pears"], [3.0, 5.0])
  println("svg contains 'apples': " ++ to_string(string_contains(svg, "apples")))
  println("svg contains 'pears': " ++ to_string(string_contains(svg, "pears")))
end
end
```

Expected: the SVG contains `apples` and `pears`.

Actual (interpreted / compiled): both `false` (interpreted).

Source: `bar_series`, `render_x_axis` in `stdlib/plot.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
