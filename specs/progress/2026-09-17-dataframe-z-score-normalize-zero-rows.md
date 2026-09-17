# `col_z_score` and `col_normalize` panicked on a zero-row column

Fixed 2026-09-17. Closes
`specs/todos/2026-09-16-dataframe-col-z-score-normalize-zero-rows.md`, the
remainder of `specs/progress/2026-09-16-dataframe-col-describe-zero-rows.md`:
the two `Stats.*` call sites in `stdlib/dataframe.march` that the
`col_describe_column` fix left unguarded.

## Symptom

```march
let df    = DataFrame.make_df([IntCol("x", native_int_arr_from_list([1, 2]))])
let empty = DataFrame.head(df, 0)      -- 1 column, 0 rows
DataFrame.col_z_score(get_column(empty, "x"))
-- panic: Stats.mean: empty list
```

Four arms, two panics: `col_z_score` reached `Stats.mean` / `Stats.std_dev` and
`col_normalize` reached `Stats.min_val` / `Stats.max_val`, on both the `IntCol`
and `FloatCol` paths. All four declare `{List(Float) | len(_) > 0}`.

## What it returns now, and why not `Err`

Both functions return `Result(Column, String)`, so an error was available and
the todo left the choice open. They return a **zero-row `FloatCol`** instead.

Each function already had a degenerate branch — `s == 0.0` for z-score,
`range_ == 0.0` for normalize — returning a same-length all-zeros column. An
empty column is the `n = 0` instance of exactly that branch, so returning it
continues an existing contract rather than introducing a new error string every
caller must now handle. And a zero-row frame is ordinary: `head(df, 0)` makes
one, and so does any filter that matches nothing.

## Fix

The guard is `List.length(...) == 0` on the list **actually passed to**
`Stats.*` — not on `col_len` — so the refinement checker can relate it to
`len(_) > 0` directly, the same shape the `col_describe_column` fix used. The
populated path is unchanged: the `Stats.*` calls simply moved inside the `else`.

## Verification

`test/stdlib/test_dataframe.march`, six new tests, RED against the parent
commit: the four zero-row tests fail with `panic: Stats.mean: empty list` and
`panic: Stats.min_val: empty list`, and the two populated-path controls pass in
both states. 233 tests in the file pass after the fix.
