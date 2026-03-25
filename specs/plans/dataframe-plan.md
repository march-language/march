# March DataFrame — Comprehensive Implementation Plan

**Status:** Design proposal
**Priority:** P2 (part of "Rust for data" story — see `specs/plans/data-ecosystem-plan.md`, Feature 4)
**Date:** 2026-03-24
**Related:** `specs/plans/data-ecosystem-plan.md`, `stdlib/stats.march`, `stdlib/csv.march`, `stdlib/json.march`, `stdlib/hamt.march`, `stdlib/sort.march`, `stdlib/seq.march`

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Context](#2-architecture-context)
3. [Column Representation](#3-column-representation)
4. [DataFrame Core Type](#4-dataframe-core-type)
5. [LazyFrame and Query Plan Engine](#5-lazyframe-and-query-plan-engine)
6. [GroupBy and Aggregation](#6-groupby-and-aggregation)
7. [Joins](#7-joins)
8. [I/O — CSV and JSON](#8-io--csv-and-json)
9. [Stats Integration](#9-stats-integration)
10. [Implementation Phases](#10-implementation-phases)
11. [Test Plan](#11-test-plan)
12. [Benchmark Plan](#12-benchmark-plan)
13. [Open Design Questions](#13-open-design-questions)

---

## 1. Executive Summary

The March DataFrame module is a **columnar, lazy-evaluated tabular data library** written entirely in pure March, composing with the existing `Stats`, `Csv`, `Json`, `Sort`, and `Hamt` stdlib modules. Its design is inspired by Polars (lazy query plans, columnar storage, pipe-friendly API) while being idiomatic March.

**Design pillars:**

1. **Typed columns** — each column stores one type (`Int`, `Float`, `String`, `Bool`). No boxing inside the hot path.
2. **Lazy query plans** — `filter`, `select`, `with_column`, `sort_by`, `join` all build a `Plan` ADT. `collect()` materializes. This enables future optimization (predicate pushdown, projection elimination, common subexpression) without changing the user API.
3. **Pure March** — no FFI, no C bindings. Every function is inspectable, testable, and portable to any March backend (interpreter, JIT, compiled).
4. **Pipe-first API** — all operations return a new `LazyFrame` so they chain naturally with `|>`.
5. **Perceus-safe** — immutable column arrays are structurally shared under Perceus RC. Mutations (e.g., `with_column`) copy only the column list, not the column data, until a conflicting RC forces a copy.

**A complete data pipeline in March:**

```march
let df = DataFrame.read_csv!("sales.csv")
         |> DataFrame.filter(Gt(Col("revenue"), LitFloat(1000.0)))
         |> DataFrame.select(["region", "product", "revenue"])
         |> DataFrame.with_column("revenue_k", fn row ->
              FloatVal(row_get_float(row, "revenue") /. 1000.0))
         |> DataFrame.sort_by([("revenue_k", Desc)])
         |> DataFrame.collect()

let summary = DataFrame.group_by(df, ["region"])
              |> GroupedFrame.agg([
                   Agg.sum("revenue_k"),
                   Agg.mean("revenue_k"),
                   Agg.count()])
              |> DataFrame.collect()

DataFrame.write_csv!(summary, "summary.csv")
```

---

## 2. Architecture Context

### 2.1 March Primitives Available

| Feature | Available? | Notes |
|---------|-----------|-------|
| `Array(a)` | Yes (builtin) | Used for columnar storage. O(1) index, mutable under unique ownership |
| `List(a)` | Yes | Used for schema (column name list), small collections |
| `Map(k,v)` backed by HAMT | Yes (`stdlib/hamt.march`) | Used for GroupBy hash table, column name → index |
| `Sort.timsort_by`, `introsort_by` | Yes | Used for sort operations and sort-merge joins |
| `Seq(a)` | Yes | Church-encoded lazy sequences — used for streaming CSV reads |
| `Stats.*` | Yes | Used in `describe()`, `agg([mean, std_dev, ...])` |
| `Csv.each_row_with_header` | Yes | Streaming CSV parser for `read_csv` |
| `Json.parse`, `Json.to_string` | Yes | JSON I/O |
| Record types `{ field: T }` | Yes | Used for `Schema`, `DescribeResult` |
| Pattern matching | Yes | Used in Plan interpreter |
| Tail recursion | Yes (TCO guaranteed) | Safe for large column traversals |

### 2.2 What Does NOT Exist Yet

- **`Array` mutations**: March `Array` is currently immutable/persistent (HAMT-based or copy-on-write). For columnar performance we need a way to build arrays element-by-element during CSV ingestion. **Decision required** — see §13.
- **`Map(String, Int)`**: `stdlib/hamt.march` provides the engine. `stdlib/map.march` wraps it. Assumed available as `Map`.
- **Null values**: March has no `Option` in the Array type system. Nulls require explicit representation — see §3.3.

### 2.3 Dependency Order

```
Phase 1 (core):   DataFrame (column types, schema, empty frame, from_rows/from_columns)
Phase 2 (I/O):    CSV reader/writer, JSON reader/writer
Phase 3 (lazy):   LazyFrame, Plan ADT, collect() interpreter
Phase 4 (group):  GroupBy, aggregation expressions
Phase 5 (join):   inner/left/right/outer join
Phase 6 (stats):  describe(), value_counts(), z_score_column()
Phase 7 (bench):  dataframe benchmarks
```

Stats, Csv, Json, Sort, Hamt are prerequisites (all exist).

---

## 3. Column Representation

### 3.1 Design Decision: Typed Columns

**Option A — Dynamic (unboxed value type):**
```march
type Value = IntVal(Int) | FloatVal(Float) | StrVal(String) | BoolVal(Bool) | NullVal
type Column = { name: String, data: Array(Value) }
```
Pro: simple API (one column type), easy pattern matching.
Con: every integer is a heap-allocated ADT node. A column of 1M integers = 1M ADT allocations. Devastating for numeric workloads.

**Option B — Typed columns (recommended):**
```march
type Column =
    IntCol(String, Array(Int))
  | FloatCol(String, Array(Float))
  | StrCol(String, Array(String))
  | BoolCol(String, Array(Bool))
  | NullableIntCol(String, Array(Int), Array(Bool))    -- second array = null bitmap
  | NullableFloatCol(String, Array(Float), Array(Bool))
  | NullableStrCol(String, Array(String), Array(Bool))
  | NullableBoolCol(String, Array(Bool), Array(Bool))
```

Pro: integers stay as `Int`, floats stay as `Float`. A column of 1M floats is one `Array(Float)` — cache-line friendly, no boxing.
Con: more pattern matching arms in operations. Operations that mix types need an explicit type-coercion step.

**Decision: Use Option B** with a `Value` type used only at row boundaries (e.g., `from_rows`, `to_rows`, `with_column` expressions). Filter predicates use `ColExpr` for vectorized columnar evaluation — no row materialization. Internal operations always work on typed arrays.

### 3.2 Value Type (Row Boundary Only)

```march
pub type Value =
    pub IntVal(Int)
  | pub FloatVal(Float)
  | pub StrVal(String)
  | pub BoolVal(Bool)
  | pub NullVal
```

`Value` appears only in:
- `Row` (a `List((String, Value))` snapshot of one row)
- User-supplied `filter` predicates: `fn row -> Bool`
- User-supplied `with_column` expressions: `fn row -> Value`
- `from_rows` / `to_rows` conversion

### 3.3 Null Handling

Nulls are represented as a parallel boolean bitmap array. An element at index `i` is null if `null_bitmap[i] == true`. This is the same strategy used by Apache Arrow.

For the **initial implementation (Phase 1)**, skip nullable columns entirely — every column is non-nullable. The plan will note where null handling must be added. This avoids the null-bitmap complexity blocking progress on the rest of the system.

Nullable columns can be added in a later phase (Phase 6 or a separate Feature 4.1).

### 3.4 Column Name Convention

Column names are `String`. Names must be unique within a DataFrame. The schema is a `List(String)` (ordered, for stable column ordering). A `Map(String, Int)` index maps name → position for O(1) column lookup by name.

### 3.5 Array Growth Strategy for Construction

During CSV ingestion, columns grow one element at a time. March `Array` is persistent (copy-on-write). To avoid O(n²) copying:

**Strategy**: collect into `List` during construction, then convert to `Array` once at the end.

```march
-- Internal builder type (not public)
type ColumnBuilder =
    IntBuilder(String, List(Int))
  | FloatBuilder(String, List(Float))
  | StrBuilder(String, List(String))
  | BoolBuilder(String, List(Bool))
```

Builders use prepend (`Cons`) during row-by-row construction, then `List.reverse` + `array_from_list` on completion. Total: O(n) allocations, O(n) memory.

---

## 4. DataFrame Core Type

### 4.1 Type Definition

```march
mod DataFrame do

-- A non-nullable column: name + typed array of values
pub type Column =
    pub IntCol(String, Array(Int))
  | pub FloatCol(String, Array(Float))
  | pub StrCol(String, Array(String))
  | pub BoolCol(String, Array(Bool))

-- A row snapshot: used at API boundaries only
pub type Row = Row(List((String, Value)))

-- The DataFrame itself: an ordered list of columns
-- All columns must have the same length (= row_count).
pub type DataFrame = DataFrame(List(Column))
```

**Invariants:**
1. All columns have equal length.
2. Column names are unique.
3. Column order matches the schema list order.

### 4.2 Schema Operations

```march
-- Column name accessor
pub fn col_name(col : Column) : String do
  match col do
  | IntCol(name, _)   -> name
  | FloatCol(name, _) -> name
  | StrCol(name, _)   -> name
  | BoolCol(name, _)  -> name
  end
end

-- Length of a column
pub fn col_len(col : Column) : Int do
  match col do
  | IntCol(_, arr)   -> array_length(arr)
  | FloatCol(_, arr) -> array_length(arr)
  | StrCol(_, arr)   -> array_length(arr)
  | BoolCol(_, arr)  -> array_length(arr)
  end
end

-- Schema (ordered column names)
pub fn schema(df : DataFrame) : List(String) do
  match df do
  | DataFrame(cols) -> List.map(cols, fn c -> col_name(c))
  end
end

-- Row count
pub fn row_count(df : DataFrame) : Int do
  match df do
  | DataFrame(Nil) -> 0
  | DataFrame(Cons(c, _)) -> col_len(c)
  end
end

-- Column count
pub fn col_count(df : DataFrame) : Int do
  match df do
  | DataFrame(cols) -> List.length(cols)
  end
end
```

### 4.3 Construction

```march
-- Empty DataFrame with no rows and no columns
pub fn empty() : DataFrame do DataFrame(Nil) end

-- From a list of pre-built columns (validates equal lengths)
pub fn from_columns(cols : List(Column)) : Result(DataFrame, String) do
  match cols do
  | Nil -> Ok(DataFrame(Nil))
  | Cons(first, rest) ->
    let expected_len = col_len(first)
    let bad = List.find(rest, fn c -> col_len(c) != expected_len)
    match bad do
    | Some(c) ->
      Err("DataFrame.from_columns: column '" ++ col_name(c) ++ "' has length "
          ++ int_to_string(col_len(c)) ++ ", expected " ++ int_to_string(expected_len))
    | None -> Ok(DataFrame(cols))
    end
  end
end

-- From a list of rows (List((String, Value))).
-- Infers column types from the first row.
-- Errors if rows have inconsistent schemas or types.
pub fn from_rows(rows : List(Row)) : Result(DataFrame, String)
```

### 4.4 Column Access

```march
-- Get a column by name (O(n) in column count, usually small)
pub fn get_column(df : DataFrame, name : String) : Result(Column, String) do
  match df do
  | DataFrame(cols) ->
    let found = List.find(cols, fn c -> col_name(c) == name)
    match found do
    | None -> Err("DataFrame: no column named '" ++ name ++ "'")
    | Some(c) -> Ok(c)
    end
  end
end

-- Typed column extractors (for composing with Stats)
pub fn get_int_col(df : DataFrame, name : String) : Result(Array(Int), String)
pub fn get_float_col(df : DataFrame, name : String) : Result(Array(Float), String)
pub fn get_string_col(df : DataFrame, name : String) : Result(Array(String), String)
pub fn get_bool_col(df : DataFrame, name : String) : Result(Array(Bool), String)

-- Get a column as List(Float) for Stats functions
pub fn float_list(df : DataFrame, name : String) : Result(List(Float), String)
```

### 4.5 Structural Operations (Eager)

```march
-- Add a column (errors if name already exists or wrong length)
pub fn add_column(df : DataFrame, col : Column) : Result(DataFrame, String)

-- Drop a column by name (no-op if not found)
pub fn drop_column(df : DataFrame, name : String) : DataFrame

-- Rename a column
pub fn rename_column(df : DataFrame, old_name : String, new_name : String) : Result(DataFrame, String)

-- Reorder columns to match given list
pub fn select_columns(df : DataFrame, names : List(String)) : Result(DataFrame, String)

-- Slice rows [start, start+len)
pub fn slice(df : DataFrame, start : Int, len : Int) : DataFrame

-- First n rows
pub fn head(df : DataFrame, n : Int) : DataFrame

-- Last n rows
pub fn tail(df : DataFrame, n : Int) : DataFrame
```

### 4.6 Row Access

Row access is **not the primary API** — it is a slow path used at boundaries. DataFrame operations should stay columnar.

```march
-- Materialize row i as a Row snapshot (O(col_count))
pub fn get_row(df : DataFrame, i : Int) : Row

-- Iterate all rows (slow path — prefer columnar operations)
pub fn to_rows(df : DataFrame) : List(Row)

-- Access a field in a row by name
pub fn row_get(row : Row, name : String) : Option(Value)
pub fn row_get_int(row : Row, name : String) : Option(Int)
pub fn row_get_float(row : Row, name : String) : Option(Float)
pub fn row_get_string(row : Row, name : String) : Option(String)
pub fn row_get_bool(row : Row, name : String) : Option(Bool)
```

---

## 5. LazyFrame and Query Plan Engine

### 5.1 ColExpr — Column Expression Language

`ColExpr` is a typed expression ADT evaluated against a `DataFrame` column-by-column. It is used for `filter` (always a boolean expression) and future projection expressions. Evaluation is vectorized: each node produces a full column, not one value at a time.

```march
pub type ColExpr =
  -- Column reference: resolves to the named column
    Col(String)
  -- Scalar literals (broadcast to full column length)
  | LitInt(Int)
  | LitFloat(Float)
  | LitStr(String)
  | LitBool(Bool)
  -- Comparisons → BoolCol
  | Eq(ColExpr, ColExpr)
  | Neq(ColExpr, ColExpr)
  | Lt(ColExpr, ColExpr)
  | Lte(ColExpr, ColExpr)
  | Gt(ColExpr, ColExpr)
  | Gte(ColExpr, ColExpr)
  -- Boolean combinators → BoolCol
  | And(ColExpr, ColExpr)
  | Or(ColExpr, ColExpr)
  | Not(ColExpr)
  -- Arithmetic → IntCol or FloatCol (matching input types)
  | Add(ColExpr, ColExpr)
  | Sub(ColExpr, ColExpr)
  | Mul(ColExpr, ColExpr)
  | Div(ColExpr, ColExpr)
  -- String predicates → BoolCol
  | StrContains(ColExpr, String)
  | StrStartsWith(ColExpr, String)
  | StrEndsWith(ColExpr, String)
  -- Null checks (stubbed until nullable columns land in Phase 6)
  | IsNull(ColExpr)
  | IsNotNull(ColExpr)
```

**Evaluation model**: `eval_col_expr(df, expr) : Result(Column, String)` evaluates an expression bottom-up, producing a typed `Column` of the same length as `df`. Scalars (`LitInt`, etc.) are broadcast to the frame's row count. Type mismatches (e.g., `Gt` on two `StrCol`) return `Err`.

**Filter usage** — a filter expression must evaluate to a `BoolCol`. The vectorized filter then builds a kept-index list in one pass over the mask array, then rebuilds each column from those indices:

```march
fn apply_filter(df : DataFrame, expr : ColExpr) : Result(DataFrame, String) do
  match eval_col_expr(df, expr) do
  | Err(e) -> Err(e)
  | Ok(mask_col) ->
    match mask_col do
    | BoolCol(_, mask) ->
      let n = array_length(mask)
      fn build_indices(i : Int, acc : List(Int)) : List(Int) do
        if i >= n then List.reverse(acc)
        else if array_get(mask, i) then build_indices(i + 1, Cons(i, acc))
        else build_indices(i + 1, acc)
      end
      let kept = build_indices(0, Nil)
      match df do
      | DataFrame(cols) ->
        Ok(DataFrame(List.map(cols, fn col -> filter_col_by_indices(col, kept))))
      end
    | _ -> Err("filter: ColExpr must evaluate to a Bool column")
    end
  end
end
```

`eval_col_expr` dispatches on each node, delegating comparisons to typed helpers (`eval_comparison`, `eval_bool_op`, `eval_arith`) that handle Int/Float promotion and return typed errors for illegal combinations (e.g., dividing two `StrCol`s).

### 5.2 The Plan ADT

All transformation operations return a `LazyFrame` — a wrapper around a `Plan`. The Plan is an ADT representing a deferred computation tree:

```march
pub type LazyFrame = LazyFrame(Plan)

type Plan =
  -- Source: a fully-materialized DataFrame
    Source(DataFrame)
  -- Project columns
  | Select(Plan, List(String))
  -- Filter rows using a vectorized column expression
  | Filter(Plan, ColExpr)
  -- Add or replace a column computed from each row (row API: arbitrary March expressions)
  | WithColumn(Plan, String, fn(Row) -> Value)
  -- Sort by a list of (column_name, :asc | :desc) pairs
  | SortBy(Plan, List((String, SortDir)))
  -- Limit to first n rows
  | Limit(Plan, Int)
  -- Skip first n rows
  | Offset(Plan, Int)
  -- Rename one column
  | Rename(Plan, String, String)
  -- Drop columns
  | DropCols(Plan, List(String))
  -- Hash join
  | Join(Plan, Plan, List(String), JoinKind)
  -- GroupBy (terminal node; aggregation is a separate step)
  | GroupBy(Plan, List(String), List(AggExpr))

pub type SortDir = Asc | Desc

pub type JoinKind = Inner | Left | Right | Outer
```

**Why an ADT plan?**
- Future: a query optimizer can rewrite the plan tree (push `Filter` before `Join`, push `Select` before expensive ops). Because `Filter` now holds a transparent `ColExpr` (not an opaque closure), the optimizer can inspect and rewrite predicates — e.g., splitting `And(p1, p2)` and pushing each sub-predicate independently.
- Present: the interpreter simply evaluates the tree bottom-up.
- The user API never exposes `Plan` directly — only `LazyFrame`.

### 5.3 LazyFrame API

```march
-- Wrap a materialized DataFrame in a lazy frame
pub fn lazy(df : DataFrame) : LazyFrame do
  LazyFrame(Source(df))
end

-- Select a subset of columns
pub fn select(lf : LazyFrame, cols : List(String)) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(Select(plan, cols)) end
end

-- Filter rows using a column expression (vectorized, no row materialization)
pub fn filter(lf : LazyFrame, expr : ColExpr) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(Filter(plan, expr)) end
end

-- Add or replace a column
pub fn with_column(lf : LazyFrame, name : String, f : fn(Row) -> Value) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(WithColumn(plan, name, f)) end
end

-- Sort
pub fn sort_by(lf : LazyFrame, keys : List((String, SortDir))) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(SortBy(plan, keys)) end
end

-- Limit / offset
pub fn limit(lf : LazyFrame, n : Int) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(Limit(plan, n)) end
end

pub fn offset(lf : LazyFrame, n : Int) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(Offset(plan, n)) end
end

-- Rename a column
pub fn rename(lf : LazyFrame, old_name : String, new_name : String) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(Rename(plan, old_name, new_name)) end
end

-- Drop columns
pub fn drop(lf : LazyFrame, cols : List(String)) : LazyFrame do
  match lf do | LazyFrame(plan) -> LazyFrame(DropCols(plan, cols)) end
end

-- Materialize: evaluate the plan and return a DataFrame
pub fn collect(lf : LazyFrame) : Result(DataFrame, String) do
  match lf do | LazyFrame(plan) -> eval_plan(plan) end
end
```

**The pipe-friendly pattern** (all transformations chain with `|>`):
```march
let result =
  DataFrame.lazy(df)
  |> DataFrame.filter(And(Gt(Col("age"), LitFloat(18.0)),
                          Eq(Col("active"), LitBool(true))))
  |> DataFrame.select(["name", "age", "score"])
  |> DataFrame.sort_by([("score", Desc)])
  |> DataFrame.limit(100)
  |> DataFrame.collect()
```

Common ColExpr patterns:
```march
-- Single comparison
filter(Gt(Col("price"), LitFloat(9.99)))

-- Compound: price > 9.99 AND category = "books"
filter(And(Gt(Col("price"), LitFloat(9.99)), Eq(Col("category"), LitStr("books"))))

-- Arithmetic in filter: (revenue - cost) > 0
filter(Gt(Sub(Col("revenue"), Col("cost")), LitFloat(0.0)))

-- String predicate
filter(StrStartsWith(Col("name"), "Alice"))
```

Note: for `read_csv` specifically, it makes sense to return a `LazyFrame` directly so the I/O and transformations are all lazy (Phase 3 optimization). For Phase 1, `read_csv` returns `Result(DataFrame, String)` and the caller wraps it in `lazy()`.

### 5.4 Plan Interpreter (`eval_plan`)

```march
-- Private: evaluate a Plan tree to a DataFrame
fn eval_plan(plan : Plan) : Result(DataFrame, String) do
  match plan do
  | Source(df) -> Ok(df)

  | Select(child, cols) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> select_columns(df, cols)
    end

  | Filter(child, expr) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> apply_filter(df, expr)
    end

  | WithColumn(child, name, f) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> apply_with_column(df, name, f)
    end

  | SortBy(child, keys) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> apply_sort(df, keys)
    end

  | Limit(child, n) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> Ok(head(df, n))
    end

  | Offset(child, n) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> Ok(drop_rows(df, n))
    end

  | Rename(child, old_name, new_name) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> rename_column(df, old_name, new_name)
    end

  | DropCols(child, cols) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> Ok(List.fold_left(df, cols, fn (d, c) -> drop_column(d, c)))
    end

  | Join(left, right, on_cols, kind) ->
    match eval_plan(left) do
    | Err(e) -> Err(e)
    | Ok(ldf) ->
      match eval_plan(right) do
      | Err(e) -> Err(e)
      | Ok(rdf) -> apply_join(ldf, rdf, on_cols, kind)
      end
    end

  | GroupBy(child, group_cols, agg_exprs) ->
    match eval_plan(child) do
    | Err(e) -> Err(e)
    | Ok(df) -> apply_group_by(df, group_cols, agg_exprs)
    end
  end
end
```

### 5.5 Core Plan Operations

#### Filter (vectorized via ColExpr)

`apply_filter` evaluates the `ColExpr` against the DataFrame to produce a `BoolCol` mask, then does a single pass to collect kept indices, then rebuilds each column. No `Row` is ever materialized.

```march
fn apply_filter(df : DataFrame, expr : ColExpr) : Result(DataFrame, String) do
  match eval_col_expr(df, expr) do
  | Err(e) -> Err(e)
  | Ok(mask_col) ->
    match mask_col do
    | BoolCol(_, mask) ->
      let n = array_length(mask)
      fn build_indices(i : Int, acc : List(Int)) : List(Int) do
        if i >= n then List.reverse(acc)
        else if array_get(mask, i) then build_indices(i + 1, Cons(i, acc))
        else build_indices(i + 1, acc)
      end
      let kept = build_indices(0, Nil)
      match df do
      | DataFrame(cols) ->
        Ok(DataFrame(List.map(cols, fn col -> filter_col_by_indices(col, kept))))
      end
    | _ -> Err("filter: ColExpr must evaluate to a Bool column")
    end
  end
end
```

`filter_col_by_indices` builds a new `Array` from the kept index list — O(n) per column, one pass. Total filter cost: O(n × col_count) reads + O(k × col_count) writes where k = kept rows.

**Optimization unlocked by ColExpr**: because `Filter(plan, And(p1, p2))` is a transparent ADT, the optimizer can split it into `Filter(Filter(plan, p1), p2)` and then push each sub-predicate independently toward the source. This is impossible with opaque `fn(Row)->Bool` closures.

#### WithColumn (columnar)

```march
fn apply_with_column(df : DataFrame, name : String, f : fn(Row) -> Value) : Result(DataFrame, String) do
  let n = row_count(df)
  -- Compute new column values as a list of Values
  fn build_values(i : Int, acc : List(Value)) : List(Value) do
    if i >= n then List.reverse(acc)
    else do
      let row = get_row(df, i)
      build_values(i + 1, Cons(f(row), acc))
    end
  end
  let values = build_values(0, Nil)
  -- Infer type from first non-null value
  -- Build typed column from values list
  let new_col = values_to_column(name, values)
  match new_col do
  | Err(e) -> Err(e)
  | Ok(col) ->
    -- Replace if name already exists; otherwise append
    let df2 = drop_column(df, name)
    add_column(df2, col)
  end
end
```

#### SortBy

```march
fn apply_sort(df : DataFrame, keys : List((String, SortDir))) : Result(DataFrame, String) do
  -- Build a list of (row_index, sort_key_values) pairs
  -- Sort by the composite key using Sort.timsort_by
  -- Reconstruct each column using the sorted row index permutation
  let n = row_count(df)
  -- Extract sort key columns for comparison
  -- Build indexed row list
  fn build_indexed(i : Int, acc : List(Int)) : List(Int) do
    if i >= n then List.reverse(acc)
    else build_indexed(i + 1, Cons(i, acc))
  end
  let indices = build_indexed(0, Nil)
  -- Comparator: compare two row indices by the sort key list
  let cmp = fn (a : Int, b : Int) -> compare_rows_by_keys(df, a, b, keys)
  let sorted_indices = Sort.timsort_by(indices, cmp)
  -- Rebuild each column in sorted index order
  match df do
  | DataFrame(cols) -> Ok(DataFrame(List.map(cols, fn col -> reorder_col(col, sorted_indices))))
  end
end
```

---

## 6. GroupBy and Aggregation

### 6.1 AggExpr Type

```march
pub type AggExpr =
    Sum(String)                  -- sum of a numeric column
  | Mean(String)                 -- mean of a numeric column
  | Min(String)                  -- minimum value
  | Max(String)                  -- maximum value
  | Count                        -- row count per group
  | CountDistinct(String)        -- distinct values in column
  | Std(String)                  -- sample standard deviation
  | Variance(String)             -- sample variance
  | First(String)                -- first value in group
  | Last(String)                 -- last value in group
  | Median(String)               -- median (uses Stats module)
  | AggAs(AggExpr, String)       -- rename the output column
```

### 6.2 GroupedFrame Type

```march
pub type GroupedFrame = GroupedFrame(DataFrame, List(String))

-- Entry point
pub fn group_by(df : DataFrame, group_cols : List(String)) : GroupedFrame do
  GroupedFrame(df, group_cols)
end

-- Aggregate and collect in one step
pub fn agg(gf : GroupedFrame, exprs : List(AggExpr)) : Result(DataFrame, String) do
  match gf do
  | GroupedFrame(df, group_cols) -> apply_group_by(df, group_cols, exprs)
  end
end
```

### 6.3 Hash GroupBy Algorithm

```march
-- Structural group key: a list of typed Values, one per group column.
-- Compared by value equality, hashed by combining per-Value hashes.
type GroupKey = GroupKey(List(Value))

fn group_key_hash(gk : GroupKey) : Int do
  match gk do
  | GroupKey(vals) ->
    -- FNV-inspired polynomial mixing: hash each Value, combine
    List.fold_left(2166136261, vals, fn (acc, v) ->
      int_xor(int_mul(acc, 16777619), value_hash(v)))
  end
end

fn group_key_eq(a : GroupKey, b : GroupKey) : Bool do
  match a do
  | GroupKey(av) ->
    match b do
    | GroupKey(bv) -> values_list_eq(av, bv)
    end
  end
end

fn apply_group_by(df : DataFrame, group_cols : List(String), agg_exprs : List(AggExpr))
    : Result(DataFrame, String) do
  -- Step 1: Build a HAMT Map(GroupKey, List(Int)) mapping group_key -> row_indices
  --   Uses group_key_hash and group_key_eq as custom hash/eq functions
  --   O(n log n) total (HAMT insert is O(log n) amortized)
  -- Step 2: For each group, reconstruct a sub-DataFrame from the row index list
  -- Step 3: Evaluate each AggExpr over the sub-DataFrame using Stats.*
  -- Step 4: Build result DataFrame: group_cols + one output column per AggExpr
  ...
end
```

**Key helper — group key construction:**

```march
fn make_group_key(df : DataFrame, row_idx : Int, group_cols : List(String)) : GroupKey do
  let vals = List.map(group_cols, fn col_name ->
    get_value_at(df, col_name, row_idx))
  GroupKey(vals)
end
```

This is type-safe, handles all `Value` variants (including strings with any byte values), and plugs directly into the HAMT engine's custom `hash_fn`/`eq_fn` parameters.

**Aggregation dispatch:**

```march
fn eval_agg(sub_df : DataFrame, expr : AggExpr) : (String, Value) do
  match expr do
  | Count ->
    ("count", IntVal(row_count(sub_df)))
  | Sum(col) ->
    let xs = float_list_or_panic(sub_df, col)
    (agg_col_name("sum", col, expr), FloatVal(Stats.sum(xs)))
  | Mean(col) ->
    let xs = float_list_or_panic(sub_df, col)
    (agg_col_name("mean", col, expr), FloatVal(Stats.mean(xs)))
  | Min(col) ->
    let xs = float_list_or_panic(sub_df, col)
    (agg_col_name("min", col, expr), FloatVal(Stats.min_val(xs)))
  | Max(col) ->
    let xs = float_list_or_panic(sub_df, col)
    (agg_col_name("max", col, expr), FloatVal(Stats.max_val(xs)))
  | Std(col) ->
    let xs = float_list_or_panic(sub_df, col)
    (agg_col_name("std", col, expr), FloatVal(Stats.std_dev(xs)))
  | Variance(col) ->
    let xs = float_list_or_panic(sub_df, col)
    (agg_col_name("variance", col, expr), FloatVal(Stats.variance(xs)))
  | Median(col) ->
    let xs = float_list_or_panic(sub_df, col)
    (agg_col_name("median", col, expr), FloatVal(Stats.median(xs)))
  | First(col) ->
    (agg_col_name("first", col, expr), get_value_at(sub_df, col, 0))
  | Last(col) ->
    let n = row_count(sub_df)
    (agg_col_name("last", col, expr), get_value_at(sub_df, col, n - 1))
  | CountDistinct(col) ->
    (agg_col_name("n_distinct", col, expr), IntVal(count_distinct(sub_df, col)))
  | AggAs(inner, alias) ->
    let (_, v) = eval_agg(sub_df, inner)
    (alias, v)
  end
end
```

Note: `Stats.mean` and `Stats.min_val` in the current implementation panic on empty list. GroupBy sub-DataFrames are never empty (you can't have a group with zero rows), so this is safe. However, see §13 for the error handling design question.

### 6.4 Aggregation Output Column Names

Default naming convention (following Polars):

| Expression | Output Column Name |
|-----------|-------------------|
| `Sum("revenue")` | `"revenue"` |
| `Mean("age")` | `"age"` |
| `Count` | `"count"` |
| `Std("score")` | `"score"` |
| `AggAs(Sum("revenue"), "total_revenue")` | `"total_revenue"` |

This avoids name collisions when groupby columns and agg columns differ. If the user needs custom names, they use `AggAs`.

---

## 7. Joins

### 7.1 Join Strategy: Hash Join

March has no array random-access that is efficient for sort-merge join on linked-list columns (sort-merge requires interleaving two sorted streams). Hash join is simpler and more natural on March's data structures.

**Hash Join algorithm:**
1. **Build phase**: for each row in the **right** table, compute the join key hash and insert `(key, row_index)` into a `Map(String, List(Int))`.
2. **Probe phase**: for each row in the **left** table, compute the join key, look up matching right row indices, emit output rows.
3. **Join kind** determines which unmatched rows are included.

```march
fn apply_join(left : DataFrame, right : DataFrame, on_cols : List(String), kind : JoinKind)
    : Result(DataFrame, String) do
  -- Validate: on_cols must exist in both left and right
  -- Build hash table: right_key -> List(Int) of right row indices
  let right_hash = build_join_hash(right, on_cols)
  -- Probe: for each left row, find matching right rows
  let output_rows = probe_join(left, right, on_cols, right_hash, kind)
  -- Reconstruct DataFrame from output rows
  from_rows(output_rows)
end
```

**Output schema for joins:**
- Inner join: all left columns + all right columns that are NOT in `on_cols` (to avoid duplicating join key columns).
- Left join: same as inner + left rows with null for unmatched right columns (when nullable columns are supported; pre-null phase: omit unmatched left rows, effectively inner join behavior with a TODO comment).
- Right join: symmetric to left.
- Outer join: all rows from both, with nulls for missing sides.

**Pre-nullable-columns strategy**: For Phase 5 (joins without nulls), implement inner join fully and left/right/outer as stubs that return `Err("left/right/outer joins require nullable column support")`. This is honest and unblocking.

### 7.2 Join API

```march
pub fn inner_join(lf : LazyFrame, right : DataFrame, on : List(String)) : LazyFrame
pub fn left_join(lf : LazyFrame, right : DataFrame, on : List(String)) : LazyFrame
pub fn right_join(lf : LazyFrame, right : DataFrame, on : List(String)) : LazyFrame
pub fn outer_join(lf : LazyFrame, right : DataFrame, on : List(String)) : LazyFrame

-- Convenience: join two lazy frames
pub fn join(lf : LazyFrame, right_lf : LazyFrame, on : List(String), kind : JoinKind) : LazyFrame
```

---

## 8. I/O — CSV and JSON

### 8.1 CSV Reader

Uses `Csv.each_row_with_header` (streaming) to avoid loading the full file into memory as strings before parsing.

```march
pub fn read_csv(path : String) : Result(DataFrame, String) do
  -- Phase 1: read all rows into List(List(String)) with header separated
  -- Phase 2: infer column types (try Int → Float → String for each column)
  -- Phase 3: parse each column into typed Array
  -- Return DataFrame
  ...
end

-- Type inference: for a list of string values in one column,
-- infer the most specific type that parses all values.
fn infer_col_type(values : List(String)) : ColType do
  -- Try all-Int, then all-Float, then fall back to String
  let all_int = List.all(values, fn s -> string_to_int(s) != None)
  if all_int then IntType
  else do
    let all_float = List.all(values, fn s -> string_to_float(s) != None)
    if all_float then FloatType
    else StrType
  end
end
```

**Column type inference precedence:** `Int > Float > String`. Bool detection ("true"/"false") can be added later.

**Header handling**: First row is always treated as column names. An option `read_csv_no_header(path, names)` can be added for headerless files.

### 8.2 CSV Writer

```march
pub fn write_csv(df : DataFrame, path : String) : Result(Unit, String) do
  -- Write header row
  -- Write each data row
  -- All values serialized via value_to_string
  -- RFC 4180: quote fields containing comma, newline, or quote
  ...
end

-- Convenience: return CSV as String (for testing / small frames)
pub fn to_csv_string(df : DataFrame) : String
```

### 8.3 JSON Reader

Accepts a JSON array of objects. Column names are inferred from keys of the first object. Subsequent objects must have the same keys (missing keys → error in Phase 1; missing keys → null in nullable phase).

```march
pub fn read_json(s : String) : Result(DataFrame, String) do
  match Json.parse(s) do
  | Err(e) -> Err("DataFrame.read_json: JSON parse error: " ++ e)
  | Ok(jv) ->
    match jv do
    | Array(items) -> json_array_to_df(items)
    | _ -> Err("DataFrame.read_json: expected JSON array of objects")
    end
  end
end
```

### 8.4 JSON Writer

```march
pub fn to_json_string(df : DataFrame) : String do
  -- Emit: [{"col1": val1, "col2": val2}, ...]
  let rows = to_rows(df)
  let json_rows = List.map(rows, fn row ->
    let kvs = List.map(row_pairs(row), fn (k, v) ->
      (k, value_to_json(v)))
    Json.Object(kvs))
  Json.to_string(Json.Array(json_rows))
end
```

### 8.5 Read/Write File Helpers

Since file I/O in March requires capability passing, the public API uses a `!` suffix convention for effectful functions (consistent with March I/O conventions):

```march
-- These are the primary public API (require file capability)
pub fn read_csv!(path : String) : Result(DataFrame, String)
pub fn write_csv!(df : DataFrame, path : String) : Result(Unit, String)

-- String-based (pure, for testing)
pub fn from_csv_string(s : String) : Result(DataFrame, String)
pub fn to_csv_string(df : DataFrame) : String
pub fn from_json_string(s : String) : Result(DataFrame, String)
pub fn to_json_string(df : DataFrame) : String
```

---

## 9. Stats Integration

### 9.1 `describe()` — Summary Statistics Per Column

```march
pub type ColStats = {
  name    : String,
  col_type: String,   -- "Int", "Float", "String", "Bool"
  count   : Int,
  nulls   : Int,      -- always 0 in Phase 1
  mean    : Option(Float),
  std     : Option(Float),
  min     : Option(Float),
  p25     : Option(Float),
  median  : Option(Float),
  p75     : Option(Float),
  max     : Option(Float)
}

-- Returns one ColStats per column, ordered by schema
pub fn describe(df : DataFrame) : List(ColStats)
```

For `IntCol` and `FloatCol`: compute all numeric stats using `Stats.*`.
For `StrCol` and `BoolCol`: `mean/std/min/max/percentiles` are `None`.

### 9.2 `value_counts()`

```march
-- Count frequency of each distinct value in a column.
-- Returns a new DataFrame with columns ["value", "count"] sorted by count descending.
pub fn value_counts(df : DataFrame, col_name : String) : Result(DataFrame, String)
```

Implementation: uses a HAMT-backed `Map` (via `Hamt.insert`, `Hamt.lookup`) keyed by `value_to_string`. O(n log n) where n = row count.

### 9.3 Column Math Operations

Convenience operations that return a new `Column`:

```march
pub fn col_add_float(col : Column, scalar : Float) : Result(Column, String)
pub fn col_mul_float(col : Column, scalar : Float) : Result(Column, String)
pub fn col_add_col(a : Column, b : Column) : Result(Column, String)
pub fn col_z_score(col : Column) : Result(Column, String)  -- uses Stats.std_dev, Stats.mean
pub fn col_normalize(col : Column) : Result(Column, String) -- scale to [0, 1]
```

### 9.4 Sampling

```march
-- Random sample of n rows (without replacement)
-- Uses the existing Random module
pub fn sample(df : DataFrame, n : Int, rng : Random.Rng) : Result((DataFrame, Random.Rng), String)

-- Stratified split into (train, test) by fraction
pub fn train_test_split(df : DataFrame, test_frac : Float, rng : Random.Rng)
    : Result(((DataFrame, DataFrame), Random.Rng), String)
```

---

## 10. Implementation Phases

### Phase 1: Core Column Types and DataFrame Construction
**Deliverables:**
- `stdlib/dataframe.march` with `Column`, `Value`, `DataFrame`, `Row` types
- `empty()`, `from_columns()`, `from_rows()`, `schema()`, `row_count()`, `col_count()`
- `get_column()`, `get_int_col()`, `get_float_col()`, `get_string_col()`, `get_bool_col()`
- `add_column()`, `drop_column()`, `rename_column()`, `select_columns()`
- `head()`, `tail()`, `slice()`, `get_row()`, `to_rows()`
- `values_to_column()` (type inference from `List(Value)`)

**Complexity:** Medium. No laziness, no I/O. Pure data structure work.
**Dependencies:** `stdlib/list.march`, `stdlib/array.march` (Array builtin)
**Tests:** ~20 unit tests (see §11.1)
**Estimated effort:** 3–4 days

### Phase 2: CSV and JSON I/O
**Deliverables:**
- `from_csv_string()`, `read_csv!()` — column type inference, streaming read
- `to_csv_string()`, `write_csv!()`
- `from_json_string()`, `to_json_string()`

**Complexity:** Medium. String parsing, type inference heuristics.
**Dependencies:** Phase 1, `stdlib/csv.march`, `stdlib/json.march`
**Tests:** ~15 tests including round-trip tests
**Estimated effort:** 3 days

### Phase 3: LazyFrame and Plan Interpreter
**Deliverables:**
- `LazyFrame`, `Plan` ADT, `SortDir`, `JoinKind` types
- `lazy()`, `select()`, `filter()`, `with_column()`, `sort_by()`, `limit()`, `offset()`, `rename()`, `drop()`, `collect()`
- `eval_plan()` interpreter
- `apply_filter()`, `apply_with_column()`, `apply_sort()`

**Complexity:** Medium-high. Recursive interpreter, columnar filter/sort logic.
**Dependencies:** Phase 1, `stdlib/sort.march`
**Tests:** ~25 tests covering each plan node and chained plans
**Estimated effort:** 4–5 days

### Phase 4: GroupBy and Aggregation
**Deliverables:**
- `AggExpr` type, `GroupedFrame` type
- `group_by()`, `agg()`
- `apply_group_by()` with hash grouping via HAMT `Map`
- `eval_agg()` dispatcher using `Stats.*`
- `value_counts()` (uses same hash grouping logic)

**Complexity:** High. Hash grouping, HAMT Map usage, Stats integration.
**Dependencies:** Phase 1, Phase 3, `stdlib/stats.march`, `stdlib/hamt.march`
**Tests:** ~20 tests
**Estimated effort:** 4–5 days

### Phase 5: Joins
**Deliverables:**
- `inner_join()` (full implementation)
- `left_join()`, `right_join()`, `outer_join()` (stubs returning `Err` until nullable columns exist)
- `join()` convenience function
- Integration into `eval_plan()` for the `Join` node

**Complexity:** Medium. Hash join build + probe phases.
**Dependencies:** Phase 1, Phase 3, `stdlib/hamt.march`
**Tests:** ~15 tests for inner join; integration tests for chained filter → join → group_by
**Estimated effort:** 3–4 days

### Phase 6: Stats Integration and Describe
**Deliverables:**
- `describe()` — full summary statistics per column
- `col_z_score()`, `col_normalize()`, `col_add_float()`, `col_mul_float()`, `col_add_col()`
- `sample()`, `train_test_split()`

**Complexity:** Low-medium. Mostly composing existing Stats and Random modules.
**Dependencies:** Phase 1, `stdlib/stats.march`, `stdlib/random.march`
**Tests:** ~15 tests
**Estimated effort:** 2–3 days

### Phase 7: Benchmarks
**Deliverables:**
- `bench/dataframe_csv_read.march` — 1M row CSV read
- `bench/dataframe_filter_select.march` — filter + select on 1M rows
- `bench/dataframe_groupby.march` — group_by + agg on 1M rows
- `bench/dataframe_join.march` — inner join of two 100k row tables
- `bench/dataframe_pipeline.march` — end-to-end TPC-H inspired query
- Competitor scripts (Python, DuckDB, Polars) in `bench/competitors/`
- `bench/run_dataframe_benchmarks.sh`

**Complexity:** Low (mostly infrastructure).
**Dependencies:** Phases 1–6
**Estimated effort:** 2 days

### Phase 8: Missing Data Operations ✅
**Deliverables:**
- `col_has_null_at(col, i)` — internal null-at-index check
- `drop_nulls(df)` — remove rows with any null
- `drop_nulls_in(df, names)` — remove rows with null in specified columns
- `fill_null(col, val)` — fill nullable column with scalar (typed, errors on mismatch)
- `fill_null_df(df, col_name, val)` — in-place column replacement
- `fill_null_forward(col)` — forward-fill: propagate last non-null down
- `fill_null_backward(col)` — backward-fill: propagate next non-null up

**Design notes:**
- `fill_null_forward` uses a single left-fold with a `(acc, last)` accumulator; result is reversed at the end.
- `fill_null_backward` reverses the column, forward-fills, then leverages the Cons-prepend property to return in the correct order without a second reverse.
- Non-nullable columns pass through `fill_null_forward`/`fill_null_backward` unchanged.

**Complexity:** Low.
**Dependencies:** Phase 1 (nullable column types)
**Tests:** 6 tests in `test_dataframe.march` (drop_nulls, fill_null scalar, type mismatch, fill_null_df, forward/backward fill)
**Implemented:** 2026-03-24

### Phase 9: Window Functions ✅
**Deliverables:**
- `WindowExpr` ADT: `RowNum | Rank(col, dir) | DenseRank(col, dir) | RunningSum(col) | RunningMean(col) | Lag(col, n, fill) | Lead(col, n, fill)`
- `window(df, expr, out_col)` — applies window function, appends column
- `sort_pairs_asc(pairs)` — internal helper for index-rank sorting

**Design notes:**
- `RowNum`: trivial `List.range(0, n)`.
- `Rank`/`DenseRank`: sort row indices by the key column, walk sorted order detecting ties via `compare_rows_by_keys(...) == 0`, emit `(original_row_idx, rank)` pairs, then sort by row index to reconstruct original-order rank column.
- `RunningSum`/`RunningMean`: single left-fold with `(acc, running_value)` state; O(n).
- `Lag`/`Lead`: materialize source column via `col_to_value_list`, then build result list with index arithmetic; uses `values_to_column` for widening type inference on the result.
- No partitioning in Phase 9 (all rows form a single partition). Partitioned windows are deferred.

**Complexity:** Medium.
**Dependencies:** Phase 1, Phase 3 (`compare_rows_by_keys`, `col_to_value_list`, `values_to_column`)
**Tests:** 6 tests: RowNum, Rank (gaps), DenseRank (no gaps), RunningSum, RunningMean, Lag n=1, Lead n=1
**Implemented:** 2026-03-24

### Phase 10: Pivot / Melt ✅
**Deliverables:**
- `melt(df, id_vars, value_vars, var_col, val_col)` — wide → long (unpivot)
- `pivot(df, index_col, cols_col, vals_col)` — long → wide

**Design notes:**
- `melt`: for each input row × each value_var, emit one output row with id_vars + (var_col=vname, val_col=value). Uses `from_rows_widen` for type inference on the output.
- `pivot`: collects distinct values of `cols_col` (new column names) and `index_col` (new row keys) in first-appearance order. For each (index_val, col_val) cell, does a linear scan to find the first matching row. Missing cells → `NullVal`. Uses `from_rows_widen` for output.
- Pivot is O(n × rows × cols) due to linear lookup; suitable for small-to-medium DataFrames. A hash-join optimization (building a `Map((index_val, col_val) → val)`) can be added in a future phase.

**Complexity:** Medium.
**Dependencies:** Phase 1 (`from_rows_widen`, `col_value_at_by_name`, `values_equal`, `value_to_string`)
**Tests:** 5 tests: melt row count, melt id_vars preserved, pivot column count, pivot cell values, pivot missing column error
**Implemented:** 2026-03-24

**Total estimated effort (Phases 1–10): ~30–36 days**

---

## 11. Test Plan

### 11.1 Phase 1 — Core Column Types

```
test: empty_df_has_zero_rows
  DataFrame.empty() |> row_count == 0

test: from_columns_equal_lengths_ok
  from_columns([IntCol("a", [1,2,3]), FloatCol("b", [1.0,2.0,3.0])]) == Ok(...)

test: from_columns_unequal_lengths_error
  from_columns([IntCol("a", [1,2]), FloatCol("b", [1.0,2.0,3.0])]) == Err(...)

test: schema_order_preserved
  schema of DataFrame with columns ["b","a","c"] returns ["b","a","c"]

test: get_column_by_name_found
  get_column(df, "score") == Ok(FloatCol("score", ...))

test: get_column_by_name_not_found
  get_column(df, "nonexistent") == Err(...)

test: add_column_appends
  add_column(df, FloatCol("new", [...])): col_count increases by 1

test: add_column_duplicate_name_error
  add_column(df, IntCol("existing", [...])): returns Err

test: drop_column_removes_it
  drop_column(df, "score") |> schema does not contain "score"

test: drop_nonexistent_column_is_noop
  drop_column(df, "nonexistent") |> row_count == row_count(df)

test: rename_column_updates_name
  rename_column(df, "score", "points") |> schema contains "points", not "score"

test: head_returns_first_n_rows
  head(df, 3) |> row_count == 3

test: tail_returns_last_n_rows
  tail(df, 3) |> row_count == 3

test: slice_returns_correct_rows
  slice(df, 2, 3) has rows at original indices 2, 3, 4

test: get_row_returns_correct_values
  get_row(df, 0) returns Row with all first-row values

test: from_rows_round_trip
  from_rows(to_rows(df)) == Ok(df)

test: select_columns_reorders
  select_columns(df, ["b","a"]) gives DataFrame with "b" first

test: select_columns_missing_name_error
  select_columns(df, ["a","missing"]) returns Err

test: empty_df_from_rows_empty
  from_rows([]) == Ok(empty())

test: single_row_single_col
  from_rows([Row([("x", IntVal(42))])]) |> row_count == 1
```

### 11.2 Phase 2 — I/O

```
test: from_csv_string_infers_int_column
  "name,age\nAlice,30\nBob,25" → IntCol("age", [30, 25])

test: from_csv_string_infers_float_column
  "x,y\n1.0,2.5\n3.14,0.0" → FloatCol("x", ...), FloatCol("y", ...)

test: from_csv_string_fallback_to_string
  "tag\nhello\nworld\n123x" → StrCol("tag", ...)

test: csv_round_trip
  to_csv_string(from_csv_string(s)) parses to same data

test: from_csv_string_quoted_fields
  handles RFC 4180 quoting and embedded commas

test: from_csv_string_empty_file_error
  "" → Err

test: from_csv_string_header_only
  "a,b,c" → DataFrame with 0 rows, 3 columns

test: from_json_string_array_of_objects
  "[{\"x\":1,\"y\":2.5},{\"x\":3,\"y\":4.0}]" → DataFrame with IntCol("x"), FloatCol("y")

test: to_json_string_round_trip
  from_json_string(to_json_string(df)) == Ok(df)

test: from_json_string_non_array_error
  from_json_string("{\"x\":1}") == Err

test: to_csv_string_quotes_commas
  StrVal("hello, world") gets quoted in output

test: csv_header_order_matches_schema
  header row in to_csv_string matches schema(df) order
```

### 11.3 Phase 3 — LazyFrame

```
test: filter_keeps_matching_rows
  filter(fn row -> row_get_int(row, "age") > 25) on 3-row df keeps correct rows

test: filter_empty_result
  filter that matches nothing → 0-row DataFrame

test: select_reduces_columns
  select(["a","b"]) on 4-col df → 2-col df

test: select_missing_column_collect_error
  select(["nonexistent"]) |> collect → Err

test: with_column_adds_new_column
  with_column("doubled", fn row -> IntVal(row_get_int(row,"x") * 2)) adds "doubled"

test: with_column_replaces_existing
  with_column("x", fn row -> IntVal(0)) replaces all "x" values with 0

test: sort_by_asc
  sort_by([("score", Asc)]) → rows in ascending score order

test: sort_by_desc
  sort_by([("score", Desc)]) → rows in descending score order

test: sort_by_multiple_keys
  sort_by([("dept", Asc), ("salary", Desc)]) → stable multi-key sort

test: limit_n
  limit(3) on 10-row df → 3-row df

test: limit_larger_than_df
  limit(100) on 5-row df → 5-row df

test: offset_skips_rows
  offset(2) on 5-row df → 3-row df (rows 2,3,4)

test: chained_filter_select
  filter(...) |> select([...]) → correct subset

test: chained_filter_sort_limit
  filter → sort_by → limit pipeline produces correct result

test: rename_in_pipeline
  rename("old","new") |> select(["new"]) works

test: collect_source_is_identity
  lazy(df) |> collect == Ok(df)

test: drop_in_pipeline
  drop(["x","y"]) |> schema does not contain "x" or "y"

test: nested_plans_evaluate_correctly
  filter inside select inside sort: all three nodes evaluated correctly
```

### 11.4 Phase 4 — GroupBy

```
test: group_by_count
  group_by(["dept"]) |> agg([Count]) → one row per dept with count column

test: group_by_sum_float
  group_by(["region"]) |> agg([Sum("revenue")]) → correct sums per region

test: group_by_mean
  group_by(["category"]) |> agg([Mean("price")]) → correct means

test: group_by_multiple_keys
  group_by(["dept","level"]) groups on composite key correctly

test: group_by_single_group
  all rows same group → one output row with agg over all rows

test: group_by_each_row_distinct_group
  every row is its own group → n output rows, count=1 each

test: agg_as_renames_output
  AggAs(Sum("revenue"), "total") → output column named "total"

test: value_counts_returns_sorted_by_count
  value_counts on ["A","B","A","C","A"] → A:3, B:1, C:1 (desc)

test: value_counts_single_unique
  all same value → one row with count = row_count

test: group_by_std_dev
  agg([Std("score")]) uses Stats.std_dev correctly

test: group_by_min_max
  agg([Min("x"), Max("x")]) returns correct min and max

test: group_by_first_last
  agg([First("name"), Last("name")]) returns first and last values in group

test: group_by_count_distinct
  agg([CountDistinct("tag")]) counts unique values per group
```

### 11.5 Phase 5 — Joins

```
test: inner_join_matching_rows_only
  left=[1,2,3], right=[2,3,4] join on "id" → rows with id 2,3

test: inner_join_no_matches_empty
  no matching keys → empty DataFrame

test: inner_join_all_match
  identical key sets → cross-product of matching rows

test: inner_join_schema_no_key_duplication
  result has join key once, not twice

test: inner_join_many_to_one
  multiple left rows match one right row → all left rows included

test: inner_join_one_to_many
  one left row matches multiple right rows → multiple output rows

test: join_then_filter_pipeline
  inner_join → filter → collect works correctly

test: join_then_group_by_pipeline
  inner_join → group_by → agg produces correct result

test: left_join_stub_returns_error
  left_join on current implementation returns Err (until nullable support)
```

### 11.6 Phase 6 — Stats Integration

```
test: describe_float_col_all_fields
  describe returns correct mean, std, min, p25, median, p75, max

test: describe_int_col_numeric
  Int column gets full numeric stats (values cast to Float)

test: describe_string_col_no_numeric
  String column has None for mean/std/min/max/percentiles

test: describe_single_row
  one row: count=1, std=0.0, mean=value, min=value, max=value

test: col_z_score_mean_zero_std_one
  z_score of column → mean ≈ 0.0, std_dev ≈ 1.0

test: col_normalize_range_zero_to_one
  normalize(col) → min=0.0, max=1.0

test: col_add_float_shifts_values
  col_add_float(col, 5.0) → each value +5

test: col_mul_float_scales_values
  col_mul_float(col, 2.0) → each value doubled

test: sample_returns_n_rows
  sample(df, 50, rng) → 50-row DataFrame

test: sample_larger_than_df_error
  sample(df, 1000, rng) on 100-row df → Err

test: train_test_split_sizes
  train_test_split(df, 0.2, rng) → 80% train, 20% test (approximately)
```

### 11.7 Integration Tests

```
test: end_to_end_csv_to_group_by
  read CSV string → filter → with_column → group_by → agg → to CSV string
  Verify output exactly matches expected CSV.

test: end_to_end_join_pipeline
  Two CSV inputs, inner join, filter, sort, limit, write CSV.

test: large_csv_stress (1000 rows)
  Read 1000-row generated CSV string.
  Filter to ~500 rows.
  group_by on string key (10 groups).
  agg sum + mean.
  Verify row counts and aggregate values.

test: type_coercion_in_pipeline
  CSV with mixed numeric columns → with_column adds Float column from Int column
  → sort → collect

test: idempotent_lazy_collect
  lazy(df) |> collect |> Result.unwrap |> lazy |> collect == Ok(df)
```

### 11.8 Edge Cases

```
test: empty_df_filter
  filter on empty df → empty df

test: empty_df_group_by
  group_by on empty df → empty df

test: single_row_sort
  sort_by on 1-row df → same 1-row df

test: single_column_df
  DataFrame with one column works correctly for all operations

test: very_long_string_column
  StrCol with 10k-character strings → no overflow

test: column_with_all_same_value
  sort, group_by, value_counts on a constant column

test: group_by_key_with_null_byte
  (once nullable support exists) key contains the separator character

test: zero_limit
  limit(0) → 0-row df

test: zero_offset
  offset(0) → same as original

test: schema_with_special_chars_in_name
  column named "col with spaces" → works in all operations
```

---

## 12. Benchmark Plan

### 12.1 March Benchmark Files

All benchmarks live in `bench/`. Pattern follows existing files: no external deps, `fn main()` entry point, prints timing or result to stdout.

#### `bench/dataframe_csv_read.march`
```march
-- Read a 1M-row synthetic CSV from a pre-generated file.
-- Tests: CSV parse speed, type inference, columnar construction.
-- The CSV has 5 columns: id(Int), x(Float), y(Float), label(String), flag(Bool-ish: "0"/"1")
-- Expected: print row_count and first/last values to verify correctness.

mod DataframeCsvRead do
fn main() : Unit do
  match DataFrame.read_csv!("bench/data/1m_rows.csv") do
  | Err(e) -> println("ERROR: " ++ e)
  | Ok(df) ->
    println("rows: " ++ int_to_string(DataFrame.row_count(df)))
  end
end
end
```

#### `bench/dataframe_filter_select.march`
```march
-- Load 1M rows, filter ~50%, select 3 of 5 columns, collect.
-- Tests: filter predicate evaluation, columnar reconstruction.

mod DataframeFilterSelect do
fn main() : Unit do
  match DataFrame.read_csv!("bench/data/1m_rows.csv") do
  | Err(e) -> println("ERROR: " ++ e)
  | Ok(df) ->
    let result =
      DataFrame.lazy(df)
      |> DataFrame.filter(Gt(Col("x"), LitFloat(0.0)))
      |> DataFrame.select(["id", "x", "label"])
      |> DataFrame.collect()
    match result do
    | Err(e) -> println("ERROR: " ++ e)
    | Ok(r) -> println("rows: " ++ int_to_string(DataFrame.row_count(r)))
    end
  end
end
end
```

#### `bench/dataframe_groupby.march`
```march
-- Load 1M rows with 10 distinct "label" values.
-- group_by("label"), agg sum("x") + mean("y") + count.
-- Tests: hash grouping, Stats function calls, result construction.

mod DataframeGroupby do
fn main() : Unit do
  match DataFrame.read_csv!("bench/data/1m_rows.csv") do
  | Err(e) -> println("ERROR: " ++ e)
  | Ok(df) ->
    let result =
      DataFrame.group_by(df, ["label"])
      |> GroupedFrame.agg([
           DataFrame.Sum("x"),
           DataFrame.Mean("y"),
           DataFrame.Count])
      |> DataFrame.collect_agg()
    match result do
    | Err(e) -> println("ERROR: " ++ e)
    | Ok(r) -> println("groups: " ++ int_to_string(DataFrame.row_count(r)))
    end
  end
end
end
```

#### `bench/dataframe_join.march`
```march
-- Inner join two 100k-row tables on "id" (matching ~80% of rows).
-- Tests: hash join build + probe phases.

mod DataframeJoin do
fn main() : Unit do
  match DataFrame.read_csv!("bench/data/100k_left.csv") do
  | Err(e) -> println("ERROR: " ++ e)
  | Ok(left) ->
    match DataFrame.read_csv!("bench/data/100k_right.csv") do
    | Err(e) -> println("ERROR: " ++ e)
    | Ok(right) ->
      let result =
        DataFrame.lazy(left)
        |> DataFrame.inner_join(right, ["id"])
        |> DataFrame.collect()
      match result do
      | Err(e) -> println("ERROR: " ++ e)
      | Ok(r) -> println("joined rows: " ++ int_to_string(DataFrame.row_count(r)))
      end
    end
  end
end
end
```

#### `bench/dataframe_pipeline.march`
```march
-- TPC-H-inspired end-to-end query:
--   FROM orders (1M rows: order_id, customer_id, region, amount, date_year)
--   WHERE amount > 100.0
--   GROUP BY region
--   AGG sum(amount) AS total, count AS n_orders
--   ORDER BY total DESC
--   LIMIT 10
-- Tests full pipeline: filter → group_by → sort → limit.

mod DataframePipeline do
fn main() : Unit do
  match DataFrame.read_csv!("bench/data/orders_1m.csv") do
  | Err(e) -> println("ERROR: " ++ e)
  | Ok(orders) ->
    let filtered =
      DataFrame.lazy(orders)
      |> DataFrame.filter(Gt(Col("amount"), LitFloat(100.0)))
      |> DataFrame.collect()
    match filtered do
    | Err(e) -> println("ERROR: " ++ e)
    | Ok(f) ->
      let result =
        DataFrame.group_by(f, ["region"])
        |> GroupedFrame.agg([
             DataFrame.AggAs(DataFrame.Sum("amount"), "total"),
             DataFrame.Count])
        |> DataFrame.collect_agg()
        |> Result.and_then(fn r ->
             DataFrame.lazy(r)
             |> DataFrame.sort_by([("total", DataFrame.Desc)])
             |> DataFrame.limit(10)
             |> DataFrame.collect())
      match result do
      | Err(e) -> println("ERROR: " ++ e)
      | Ok(r) -> DataFrame.print_table(r)
      end
    end
  end
end
end
```

### 12.2 Benchmark Data Generation

```bash
# bench/generate_bench_data.py
# Generates deterministic synthetic datasets used by all DataFrame benchmarks.
# Run once before benchmarking: python3 bench/generate_bench_data.py

import random, csv, os
random.seed(42)
os.makedirs("bench/data", exist_ok=True)

# 1M rows: id, x, y, label, flag
with open("bench/data/1m_rows.csv", "w") as f:
    w = csv.writer(f)
    w.writerow(["id", "x", "y", "label", "flag"])
    labels = ["A","B","C","D","E","F","G","H","I","J"]
    for i in range(1_000_000):
        w.writerow([i, random.uniform(-1,1), random.uniform(0,100),
                    labels[i % 10], i % 2])
```

### 12.3 Competitor Benchmarks

#### Python Pandas

```python
# bench/competitors/pandas_pipeline.py
import pandas as pd, time

t0 = time.perf_counter()
df = pd.read_csv("bench/data/orders_1m.csv")
t_read = time.perf_counter() - t0

t0 = time.perf_counter()
result = (df[df["amount"] > 100.0]
          .groupby("region")["amount"]
          .agg(total="sum", n_orders="count")
          .sort_values("total", ascending=False)
          .head(10))
t_query = time.perf_counter() - t0

print(f"read: {t_read:.3f}s, query: {t_query:.3f}s")
print(result)
```

#### Python Polars (lazy)

```python
# bench/competitors/polars_pipeline.py
import polars as pl, time

t0 = time.perf_counter()
result = (pl.scan_csv("bench/data/orders_1m.csv")
            .filter(pl.col("amount") > 100.0)
            .group_by("region")
            .agg(pl.sum("amount").alias("total"), pl.count().alias("n_orders"))
            .sort("total", descending=True)
            .head(10)
            .collect())
print(f"total: {time.perf_counter()-t0:.3f}s")
print(result)
```

#### DuckDB

```sql
-- bench/competitors/duckdb_pipeline.sql
-- Run with: time duckdb -c "$(cat bench/competitors/duckdb_pipeline.sql)"

SELECT region,
       SUM(amount) AS total,
       COUNT(*) AS n_orders
FROM read_csv_auto('bench/data/orders_1m.csv')
WHERE amount > 100.0
GROUP BY region
ORDER BY total DESC
LIMIT 10;
```

#### Rust Polars

```rust
// bench/competitors/rust_polars/src/main.rs
// Run with: cargo build --release && time ./target/release/bench_polars
use polars::prelude::*;
use std::time::Instant;

fn main() -> Result<(), PolarsError> {
    let t = Instant::now();
    let result = LazyFrame::scan_csv("bench/data/orders_1m.csv", Default::default())?
        .filter(col("amount").gt(lit(100.0)))
        .group_by(["region"])
        .agg([sum("amount").alias("total"), count().alias("n_orders")])
        .sort(["total"], Default::default())
        .limit(10)
        .collect()?;
    println!("total: {:.3}s", t.elapsed().as_secs_f64());
    println!("{}", result);
    Ok(())
}
```

#### Elixir Explorer

```elixir
# bench/competitors/explorer_pipeline.exs
# Run with: time elixir bench/competitors/explorer_pipeline.exs
require Explorer.DataFrame, as: DF
require Explorer.Series, as: S

{time_us, result} = :timer.tc(fn ->
  DF.from_csv!("bench/data/orders_1m.csv")
  |> DF.filter(amount > 100.0)
  |> DF.group_by("region")
  |> DF.summarise(total: sum(amount), n_orders: count(amount))
  |> DF.arrange(desc: total)
  |> DF.head(10)
end)

IO.puts("total: #{time_us / 1_000_000.0}s")
IO.puts(inspect(result))
```

### 12.4 Benchmark Runner Script

```bash
#!/usr/bin/env bash
# bench/run_dataframe_benchmarks.sh

set -e

echo "=== Generating benchmark data ==="
python3 bench/generate_bench_data.py

echo ""
echo "=== Building March DataFrame benchmarks ==="
dune build bench/dataframe_csv_read.exe bench/dataframe_filter_select.exe \
           bench/dataframe_groupby.exe bench/dataframe_join.exe \
           bench/dataframe_pipeline.exe

echo ""
echo "=== March DataFrame ==="

echo "--- CSV Read (1M rows) ---"
hyperfine --warmup 2 --runs 5 './bench/dataframe_csv_read.exe'

echo "--- Filter + Select ---"
hyperfine --warmup 2 --runs 5 './bench/dataframe_filter_select.exe'

echo "--- GroupBy + Agg ---"
hyperfine --warmup 2 --runs 5 './bench/dataframe_groupby.exe'

echo "--- Inner Join ---"
hyperfine --warmup 2 --runs 5 './bench/dataframe_join.exe'

echo "--- End-to-End Pipeline ---"
hyperfine --warmup 2 --runs 5 './bench/dataframe_pipeline.exe'

echo ""
echo "=== Python Pandas ==="
hyperfine --warmup 1 --runs 3 'python3 bench/competitors/pandas_pipeline.py'

echo ""
echo "=== Python Polars ==="
hyperfine --warmup 1 --runs 3 'python3 bench/competitors/polars_pipeline.py'

echo ""
echo "=== DuckDB ==="
hyperfine --warmup 1 --runs 3 \
  "duckdb -c \"\$(cat bench/competitors/duckdb_pipeline.sql)\""

echo ""
echo "=== Elixir Explorer (if installed) ==="
if command -v elixir &>/dev/null; then
  hyperfine --warmup 1 --runs 3 'elixir bench/competitors/explorer_pipeline.exs'
else
  echo "(elixir not found, skipping)"
fi

echo ""
echo "=== Rust Polars (if built) ==="
if [ -f bench/competitors/rust_polars/target/release/bench_polars ]; then
  hyperfine --warmup 2 --runs 5 \
    'bench/competitors/rust_polars/target/release/bench_polars'
else
  echo "(run 'cargo build --release' in bench/competitors/rust_polars first)"
fi
```

### 12.5 Realistic Performance Expectations

| Benchmark | March (list-based) | Pandas | Polars (Python) | DuckDB | Rust Polars |
|-----------|-------------------|--------|-----------------|--------|-------------|
| CSV read 1M | ~3–8s | ~1s | ~0.3s | ~0.2s | ~0.1s |
| Filter+select | ~0.5–2s | ~0.05s | ~0.01s | ~0.01s | ~0.005s |
| GroupBy | ~1–3s | ~0.1s | ~0.02s | ~0.01s | ~0.005s |
| Join 100k | ~0.3–1s | ~0.05s | ~0.01s | ~0.01s | ~0.005s |
| Pipeline | ~4–10s | ~1.5s | ~0.35s | ~0.25s | ~0.1s |

**Why March will be slower**: March uses linked lists for column construction (pointer-chasing vs cache-friendly arrays), Perceus RC adds overhead on every allocation, and the tree-walking interpreter adds dispatch overhead vs compiled columnar kernels.

**Why March is still worth it**: correctness, zero external dependencies, composability with the type system, and the lazy plan structure enables future optimizations (LLVM backend, stream fusion) that can close the gap significantly.

**The honest story**: March DataFrame is not the fastest option for pure data crunching today. It is the best option for March users who want data manipulation that composes with the rest of the March ecosystem, has no Python runtime, and is auditable in the same language as their application.

---

## 13. Open Design Questions

### Q1: Array Mutability
**Problem**: Column construction requires appending N elements one at a time. March's `Array` is persistent (copy-on-write). Naive append is O(n²).
**Current plan**: build via `List` (prepend + reverse at end). O(n) time, O(2n) peak memory (list + final array).
**Alternative**: Add a `ArrayBuilder(a)` builtin type to March (a mutable growable buffer). This would be faster and simpler. **Decision: start with List-based approach; add ArrayBuilder in Phase 6 if profiling shows it's a bottleneck.**

### Q2: Null Handling
**Problem**: Real-world data has nulls. CSV files have empty fields. Joins produce nulls for unmatched rows.
**Decision: nullable columns are required — real data is sparse.** The null bitmap approach (`NullableIntCol(String, Array(Int), Array(Bool))`) is adopted. Implementation schedule:
- Phase 1: non-nullable columns only, empty CSV fields → `Err` during ingestion
- Phase 2: add nullable variants to the `Column` type; update CSV reader to emit `NullVal` for empty fields → `NullableStrCol`; update `to_rows`/`from_rows`
- Phase 5 (joins): left/right/outer joins require nullable columns — this is now unblocked
- Phase 6: Stats null-skipping variants (`mean_skip_nulls`, etc.) needed for `describe()` and `agg()`

The nullable column variants are parallel to the non-nullable ones:
```march
| NullableIntCol(String, Array(Int), Array(Bool))
| NullableFloatCol(String, Array(Float), Array(Bool))
| NullableStrCol(String, Array(String), Array(Bool))
| NullableBoolCol(String, Array(Bool), Array(Bool))
```
A `true` in the bool array at index `i` means row `i` is null.

### Q3: Filter Predicate API
**Decision: ColExpr ADT from Phase 3, upfront.** `Filter(Plan, ColExpr)` — no row materialization, vectorized evaluation, optimizer-transparent. See §5.1 for the full `ColExpr` type and `eval_col_expr` interpreter. The `fn(Row) -> Bool` closure API is dropped entirely for filter; `with_column` retains `fn(Row) -> Value` for user-supplied projection expressions where arbitrary March computation is desirable.

### Q4: GroupBy Key Serialization
**Decision: structural `GroupKey(List(Value))` with custom `group_key_hash`/`group_key_eq` passed to the HAMT engine.** This is the standard approach in Polars, DuckDB, and Pandas — typed per-column values, no string serialization, no separator escape issues. See §6.3 for the implementation.

### Q5: GroupBy Output Column Naming
**Decision: preserve the base column name as default; auto-suffix when the same column appears in multiple agg expressions.** Rules:
- Single `Sum("revenue")` → output column `"revenue"`
- `[Sum("revenue"), Mean("revenue")]` → auto-renamed `"revenue_sum"`, `"revenue_mean"` (detected at `agg()` call time, before evaluation)
- `AggAs(expr, name)` → always uses the provided name, overrides all heuristics
- `Count` → always `"count"` (no source column)

This matches Polars behavior for the single-agg case, and adds an explicit heuristic for the ambiguous multi-agg case rather than silently overwriting.

### Q6: `Stats` Error Handling
**Decision: fix `Stats` to return `Result(Float, StatsError)` before implementing DataFrame aggregation.** This is a prerequisite, not a deferral. The current `stats.march` panics on empty input — acceptable for direct use, not acceptable inside `agg()` where the error should propagate as `Err` not a crash. Do the Stats fix as part of Phase 4 setup (before writing `eval_agg`). The `data-ecosystem-plan.md` §4.2.4 already specifies the `Result`-returning API.

### Q7: Write-CSV Delimiter Options
**Decision: implement `write_csv_opts` with options type from the start.** Adding it later requires touching all call sites. Define:
```march
pub type CsvWriteOpts = { delimiter: String, quote_char: String, write_header: Bool }
pub fn default_csv_opts() : CsvWriteOpts do { delimiter: ",", quote_char: "\"", write_header: true } end
pub fn write_csv!(df : DataFrame, path : String) : Result(Unit, String)  -- uses default_csv_opts
pub fn write_csv_opts!(df : DataFrame, path : String, opts : CsvWriteOpts) : Result(Unit, String)
```

### Q8: JSON Records vs JSON Array-of-Objects
**Problem**: Some JSON APIs return `{"col1": [1,2,3], "col2": [4,5,6]}` (columnar JSON) instead of `[{"col1":1,"col2":4}, ...]` (row-oriented JSON).
**Solution**: Support both via `read_json_columnar(s)` and `read_json_rows(s)`. `read_json` defaults to rows.
**Decision: implement row-oriented first (more common). Add columnar as `read_json_columnar` in Phase 6.**

### Q9: `from_rows` Type Inference Strategy
**Decision: split by use case.**
- `from_rows` (programmatic construction): **error on mismatch** — caller controls the types, a type mismatch is a bug, not data variance. Error message: `"from_rows: column 'x' has type Int but row 3 has FloatVal"`.
- `read_csv` / `read_json` (inferred from data): **widen automatically** — Int + Float in the same column → the column becomes Float. Int/Float + String → the column becomes String. This matches Pandas and Polars behavior for I/O. Widening order: `Bool < Int < Float < String`. Never narrow.

The rule is: `from_rows` is strict because the caller knows what they're doing; I/O functions are lenient because real-world data is messy.

### Q10: Plan Optimization
**Problem**: The current interpreter is bottom-up with no reordering. Common patterns like `filter → group_by` on large tables should push `filter` as early as possible (before expensive join build phases).
**Future work**: A `optimize_plan(plan : Plan) : Plan` function that applies rewrite rules:
- Push `Filter` before `Join` if the filter only references left or right columns
- Push `Select` (projection) as early as possible to reduce column count
- Merge consecutive `Filter` nodes into one `Filter` with `And`-combined predicates

**Decision: implement `optimize_plan` as a no-op stub in Phase 3. Fill in rules after Phase 7 benchmarks identify the actual bottlenecks.** The ColExpr ADT (Q3) already makes predicate rewriting possible — the infrastructure is there, we just need the data to know which rewrites matter most.

---

## Appendix A: File Layout

```
stdlib/
  dataframe.march          -- main module (all phases)
bench/
  dataframe_csv_read.march
  dataframe_filter_select.march
  dataframe_groupby.march
  dataframe_join.march
  dataframe_pipeline.march
  generate_bench_data.py
  run_dataframe_benchmarks.sh
  competitors/
    pandas_pipeline.py
    polars_pipeline.py
    duckdb_pipeline.sql
    explorer_pipeline.exs
    rust_polars/
      Cargo.toml
      src/main.rs
  data/
    .gitkeep               -- actual CSV files are .gitignored (too large)
test/
  test_march.ml            -- existing alcotest suite; DataFrame tests added here
```

## Appendix B: Estimated Test Count

| Phase | New Tests | Cumulative Total |
|-------|-----------|-----------------|
| Phase 1 (core) | 20 | +20 |
| Phase 2 (I/O) | 15 | +15 |
| Phase 3 (lazy) | 25 | +25 |
| Phase 4 (groupby) | 13 | +13 |
| Phase 5 (join) | 9 | +9 |
| Phase 6 (stats) | 11 | +11 |
| Integration | 9 | +9 |
| Edge cases | 10 | +10 |
| **Total** | **112** | |

This will bring the test suite from its current count to roughly current+112.
