# DataFrame: an all-null column no longer loses its nulls

Standalone bug from `specs/todos/2026-08-13-dataframe-narrow-columns.md` (the rest of that
todo stays parked).

`builder_to_column`'s `NullBuilder` arm (`stdlib/dataframe.march`) finalised a column whose
every value was `NullVal` into `StrCol(name, typed_array_create(n, ""))`: the null mask was
dropped, so every row read back as a real empty string (`StrVal("")`), and `is_null`-style
checks saw none. It now finalises into
`NullableStrCol(name, typed_array_create(n, ""), typed_array_create(n, true))`, every row
masked, so `col_value_at` returns `NullVal`. A column of nothing but nulls carries no value to
infer a numeric type from, so `String` storage is the only honest default; what changed is that
the nulls survive. This path serves `from_rows_widen` (CSV/JSON loading) and `values_to_column`
(so `summarize`'s all-null stat columns now read `NullVal`, the behaviour
`specs/progress/2026-09-16-dataframe-col-describe-zero-rows.md` called out as wrong).

Test: `from_rows_widen keeps an all-null column null` in `test/stdlib/test_dataframe.march`.
RED on origin/main's stdlib (`march test test/stdlib/test_dataframe.march`: 1/246 failed),
GREEN with the fix (246 passed).
