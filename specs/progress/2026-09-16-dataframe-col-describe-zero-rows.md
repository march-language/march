# `DataFrame.col_describe` panicked on a frame with columns and zero rows

Fixed 2026-09-16.

## Symptom

```march
let df    = DataFrame.make_df([IntCol("x", native_int_arr_from_list([1, 2]))])
let empty = DataFrame.head(df, 0)      -- 1 column, 0 rows
DataFrame.col_describe(empty)
-- panic: Stats.mean: empty list
```

`summarize`, which goes through `col_describe`, panicked identically. A zero-row
frame is not exotic: `head(df, 0)` produces one, and so does any filter that
matches nothing.

## Cause

`col_describe_column`'s `IntCol` and `FloatCol` arms materialised the column as a
`List(Float)` and handed it straight to `Stats.mean`, `Stats.std_dev`,
`Stats.min_val`, `Stats.max_val`, `Stats.percentile` and `Stats.median`. Those all
declare `{List(Float) | len(_) > 0}` and panic on an empty list. There was no
emptiness guard.

No type change was needed: `ColStats` already carries `Option(Float)` for every
statistic, and the `StrCol` / `BoolCol` / nullable arms already pass `None` for all
of them.

## Fix

`stdlib/dataframe.march`: both numeric arms of `col_describe_column` now test
`List.length(...) == 0` and return `ColStats(name, type, n, None, ..., None)` in
that case, leaving the populated path byte-identical. The guard is on the list
actually passed to `Stats.*` (not on `col_len`), so the refinement checker can
relate it to `len(_) > 0` directly.

Only `IntCol` and `FloatCol` compute statistics; every other arm — `StrCol`,
`BoolCol`, and the four nullable variants via the catch-all — already returned all
`None`, so they needed no change.

## Tests

`test/stdlib/test_dataframe.march`, new `describe "col_describe on zero-row frames"`
(6 tests, 220 -> 226 in that file):

- zero-row `IntCol` via `head(df, 0)`: row count 0, `ColStats` count 0, all seven
  statistics `None`;
- the same for a zero-row `FloatCol`;
- zero rows reached through a `LazyFrame` filter that matches nothing;
- `summarize` on a zero-row frame: one row, `count` 0, no panic;
- two controls on populated `IntCol` / `FloatCol` frames pinning the real
  mean/min/median/max, proving the guard did not touch the populated path.

This file runs through a dune rule (`test/dune`: `march test
stdlib/test_dataframe.march`), not through `test_stdlib_march.exe` — it is in that
runner's `known_unregistered_stdlib_test_files` list, so `scripts/run-tests.sh
stdlib_march` does not exercise it. Run it with
`cd test && ../_build/default/bin/main.exe test stdlib/test_dataframe.march`, or
via a full `dune build --root .`.

Red control: with the pre-fix `stdlib/dataframe.march` swapped back in, the four
zero-row tests fail with `panic: Stats.mean: empty list`; perturbing a control's
expected mean to `Some(999.0)` fails it, proving the new cases actually run.

## Refinement-checker effect

`--check --refine-report stdlib/dataframe.march`, CAS and VC caches cleared:

| | before | after |
|---|---|---|
| user code: proved | 4 | 14 |
| user code: skipped (unconstrained-subject) | 18 | 8 |
| `Stats.*` "NOT verified here" hints | 16 | 6 |

All ten `col_describe_column` obligations (lines 2661-2672 pre-fix: `mean`,
`std_dev`, `min_val`, `max_val`, two `percentile`, `median`, over both numeric
arms) moved from `unconstrained-subject` to **proved** — the guard discharges
them outright, they did not merely move buckets.

The six remaining `Stats.*` hints are in `col_z_score` and `col_normalize`, which
have the same unguarded shape and the same latent panic on a zero-row column.
That is untouched here and tracked in
`specs/todos/2026-09-16-dataframe-col-z-score-normalize-zero-rows.md`.

## Out of scope, observed in passing

- `summarize` renders an all-null numeric stat column as `StrVal("")` rather than
  `NullVal`: the column widening turns a column of nothing but nulls into a
  string column. Pre-existing and not specific to zero-row frames — a String-only
  frame has always done this.
- `==` on `DataFrame.Value` is not structural: `StrVal("x") == StrVal("x")`
  evaluates to `false`, and the assertion failure prints `left: StrVal("x")` /
  `right: StrVal("x")`, which reads as a compiler bug. Every test in the file
  destructures Values instead; the new tests follow suit.
