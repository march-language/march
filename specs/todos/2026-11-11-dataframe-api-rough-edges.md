`[P3]` DataFrame: from_rows matches by position, sort reverses ties, Lag/Lead panic on negative n, compare_values is not an order for mixed types (2026-11-11)

Four documented rough edges. `from_rows` ignores field names after the first row, so a row with the same fields in another order silently lands in the wrong columns. `sort_by` is not stable and returns tied rows in reverse input order. `window` with `Lag(c, n, _)` or `Lead(c, n, _)` and negative `n` panics in `List.nth` instead of treating it as the opposite shift or returning `Err`. `compare_values` returns 1 in both directions for a mixed pair such as Int vs String, so sorting a mixed column has no consistent result.

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
  let r = DataFrame.from_rows([
    DataFrame.Row([("a", DataFrame.IntVal(1)), ("b", DataFrame.IntVal(10))]),
    DataFrame.Row([("b", DataFrame.IntVal(20)), ("a", DataFrame.IntVal(2))])
  ])
  println(show(r))
  println("expected row 2: a=2,b=20 (or an Err for the name mismatch)")
end
end
```
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
  let r = DataFrame.from_csv_string("k,tag\n1,a\n1,b\n1,c\n0,z\n1,d")
  match r do
  Ok(df) -> println(show(DataFrame.collect(DataFrame.sort_by(DataFrame.lazy(df), [("k", DataFrame.Asc)]))))
  Err(e) -> println(e)
  end
  println("stable sort expected tags: z,a,b,c,d")
end
end
```
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
  let r = DataFrame.from_csv_string("p\n1\n2\n3")
  match r do
  Ok(df) ->
    println(show(DataFrame.window(df, DataFrame.Lag("p", 1, DataFrame.IntVal(0)), "lag1")))
    println(show(DataFrame.window(df, DataFrame.Lag("p", -1, DataFrame.IntVal(0)), "lagm1")))
  Err(e) -> println(e)
  end
end
end
```
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
  let a = DataFrame.IntVal(1)
  let b = DataFrame.StrVal("x")
  println("compare(Int 1, Str x) = " ++ to_string(DataFrame.compare_values(a, b)))
  println("compare(Str x, Int 1) = " ++ to_string(DataFrame.compare_values(b, a)))
  println("compare(Bool true, Int 1) = " ++ to_string(DataFrame.compare_values(DataFrame.BoolVal(true), a)) ++ ", reverse = " ++ to_string(DataFrame.compare_values(a, DataFrame.BoolVal(true))))
end
end
```

Expected: row 2 is `2,20` or an Err; ties keep input order `a,b,c,d`; negative n gives a shifted column or `Err`; the two mixed comparisons have opposite signs.

Actual (interpreted / compiled): row 2 is `20,2`; ties come out `d,c,b,a`; `List.nth: index out of bounds` panic; `1` and `1` (interpreted; sort and Lag/Lead identical compiled).

Source: `from_rows`, `apply_sort`, `window`, `compare_values` in `stdlib/dataframe.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
