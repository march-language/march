`[P2]` DataFrame: widening inference stores nulls as 0 / 0.0 / false / "" (2026-11-11)

`builder_push_widen` pushes the type default when a `NullVal` arrives in a typed builder. An empty CSV cell in an Int column reads back as `IntVal(0)`, so missing data is indistinguishable from a real zero and changes sums and means. The CSV/JSON readers, joins, group_by, pivot and melt all go through this path. Documented, but nullable columns exist and could be used.

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
  println(show(DataFrame.from_csv_string("id,score\n1,5\n2,\n3,7")))
  let r = DataFrame.from_csv_string("id,score\n1,5\n2,\n3,7")
  match r do
  Ok(df) -> println(to_string(DataFrame.col_value_at_by_name(df, "score", 1)))
  Err(e) -> println(e)
  end
end
end
```

Expected: row 2 score is `NullVal`.

Actual (interpreted / compiled): `IntVal(0)` (interpreted).

Source: `builder_push_widen` in `stdlib/dataframe.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
