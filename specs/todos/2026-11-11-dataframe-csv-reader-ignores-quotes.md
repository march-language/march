`[P2]` DataFrame.from_csv_string cannot read what to_csv_string writes when a cell holds a comma (2026-11-11)

`split_csv_line` splits on every delimiter and keeps quote characters. `to_csv_string` quotes a cell that contains a comma, so the round trip splits that cell in two, keeps the quote characters as data, and silently drops the last column (extra cells are truncated to the header width).

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
  let cells = DataFrame.split_csv_line("1,\"Smith, John\",3", ",")
  println("cells: " ++ to_string(List.length(cells)) ++ " (expected 3) -> " ++ String.join(cells, " | "))
  println(show(DataFrame.from_csv_string("id,name,n\n1,\"Smith, John\",3")))
  -- round trip of a frame whose cell holds a comma
  let df = DataFrame.from_rows([DataFrame.Row([("name", DataFrame.StrVal("Smith, John")), ("n", DataFrame.IntVal(3))])])
  let csv = show(df)
  println(csv)
  println(show(DataFrame.from_csv_string(csv)))
end
end
```

Expected: 3 cells; the round trip returns `Smith, John` and `3`.

Actual (interpreted / compiled): 4 cells; name becomes `"Smith`, n becomes `John"`, the 3 is dropped (interpreted).

Source: `split_csv_line`, `from_csv_string` in `stdlib/dataframe.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
