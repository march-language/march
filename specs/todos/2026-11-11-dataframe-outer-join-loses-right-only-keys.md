`[P2]` DataFrame.outer_join returns Null key columns for right-only rows (2026-11-11)

The key columns of the result are taken from the left frame only. A right row with no match keeps its non-key columns but its key values are replaced by Null, so the row cannot be identified. Documented, but it is data loss in a full outer join.

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
  let l = DataFrame.from_csv_string("k,lv\n1,10\n2,20")
  let r = DataFrame.from_csv_string("k,rv\n2,200\n3,300")
  match (l, r) do
  (Ok(ld), Ok(rd)) ->
    let j = DataFrame.collect(DataFrame.outer_join(DataFrame.lazy(ld), rd, ["k"]))
    println(show(j))
    match j do
    Ok(jd) -> println("key of the right-only row (expected IntVal(3)): " ++ to_string(DataFrame.col_value_at_by_name(jd, "k", 2)))
    Err(e) -> println(e)
    end
  _ -> println("setup failed")
  end
end
end
```

Expected: third row `3,,300`.

Actual (interpreted / compiled): third row `,,300`; key is `NullVal` (interpreted and compiled).

Source: `apply_outer_join` in `stdlib/dataframe.march`. Coalescing the left and right key per row would fix it.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
