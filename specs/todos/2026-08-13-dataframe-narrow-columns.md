# DataFrame: narrow-width (F32/I32) column storage — deferred

Filed 2026-08-13, as part of the SIMD follow-ups sweep (Task 3 of
`.superpowers/sdd/2026-08-13-simd-followups/`). Recorded here rather than
attempted: the migration touches too much surface for an incidental change,
and — unlike the Min/Max native-loop work — **storage width is NOT gated on
the index-loop overhead work**; it is an independent, larger effort that can
proceed on its own schedule.

## What exists today

`Column` (`stdlib/dataframe.march:38-47`) has exactly 8 variants, all storing
`Int`/`Float` at full 64-bit width (via `NativeIntArr`/`NativeFloatArr`) or
boxed `TypedArray`:

```march
type Column =
    IntCol(String, NativeIntArr)
  | FloatCol(String, NativeFloatArr)
  | StrCol(String, TypedArray(String))
  | BoolCol(String, TypedArray(Bool))
  | NullableIntCol(String, NativeIntArr, TypedArray(Bool))
  | NullableFloatCol(String, NativeFloatArr, TypedArray(Bool))
  | NullableStrCol(String, TypedArray(String), TypedArray(Bool))
  | NullableBoolCol(String, TypedArray(Bool), TypedArray(Bool))
```

There is no `F32Col` / `I32Col` (or nullable variants of either). Every
numeric column pays full 8-byte-per-element storage even when the data would
fit narrower, which matters for cache footprint and for feeding the SIMD
kernels (`Simd.*`) that this branch's other two tasks work on — those kernels
operate on 4-lane `f32x4`/native-width vectors, so an `F32Col` would let a
column feed them without a per-element widen/narrow pass.

## Why this is a real migration, not a variant add

Adding `F32Col`/`I32Col` is not additive: `Column` is matched exhaustively
throughout `stdlib/dataframe.march`, and the compiler's exhaustiveness check
means every one of the following **35 pattern-matching functions** would need
a new arm (or an explicit widening fallback) the moment a narrow variant
exists:

`col_name:81`, `col_len:95`, `col_value_at:109`, `col_to_value_list:127`,
`filter_col_by_indices:153`, `filter_col_by_mask:187`, `col_is_nullable:210`,
`col_null_count:221`, `col_to_nullable:232`, `builder_to_column:522`,
`get_int_col:736`, `get_float_col:749`, `get_string_col:762`,
`get_bool_col:775`, `float_list:788`, `col_native_sum:808`,
`col_native_min_max:833`, `col_native_moments:863`, `rename_col:1025`,
`eval_col_expr:1360`, `apply_filter:1734`, `values_to_column:1772`,
`col_from_idx_opts:2315`, `col_describe_column:2654`, `col_z_score:2684`,
`col_normalize:2709`, `summarize:2746`, `train_test_split:2814`,
`col_add_float:2829`, `col_mul_float:2846`, `col_add_col:2867`,
`col_has_null_at:2904`, `fill_null:2951`, `fill_null_forward:3023`,
`fill_null_backward:3094`, `window:3198`.

## The dynamic-inference problem

`make_builder` (`stdlib/dataframe.march:533`) picks the column's storage type
from the **first non-null `Value`** seen while building a column from
row-oriented data:

```march
fn make_builder(name : String, val : Value) : ColumnBuilder do
  match val do
  IntVal(_)  -> IntBuilder(name, Nil)
  FloatVal(_) -> FloatBuilder(name, Nil)
  StrVal(_)  -> StrBuilder(name, Nil)
  BoolVal(_) -> BoolBuilder(name, Nil)
  NullVal    -> NullBuilder(name, 0)
  end
end
```

There is no `Value` variant carrying a narrower numeric type (only `IntVal`/
`FloatVal`, both full-width), so nothing in the current `Value`/inference path
could ever choose `F32Col`/`I32Col` on its own — inference would need either a
new `Value` case, an explicit width hint from the caller, or a post-hoc
downcast pass over a finished full-width column. And a column built entirely
from nulls silently becomes `StrCol` today: `builder_to_column`'s
`NullBuilder` arm (`stdlib/dataframe.march:528`) finalizes into
`StrCol(name, typed_array_create(n, ""))` — an all-null numeric-looking column
gets no numeric type at all under the current builder, and a narrow-width
migration inherits that same ambiguity for any new numeric variant.

## Two candidate scopings

1. **Opt-in `F32Col` with widening fallbacks.** Add `F32Col`/nullable variant
   only, require it to be constructed explicitly (`DataFrame.from_columns`
   with a caller-built `F32Col`, not through row-wise inference), and give
   every one of the 35 match sites a fallback arm that widens to `Float`
   before doing its normal work — i.e. `F32Col` degrades to `FloatCol`
   semantics everywhere except the SIMD-fed hot paths that are taught to
   recognize it directly. Smallest surface change; `I32Col` deferred further.
2. **Full three-width migration with an inference story.** `I32Col`/`F32Col`
   as first-class as `IntCol`/`FloatCol`, each of the 35 sites gets a real
   arm (not a widen-then-fallback), and `make_builder`/row-wise construction
   gains an explicit width parameter or heuristic (e.g. bounds-check `IntVal`
   payloads against `i32` range) instead of silently defaulting to 64-bit.
   Much larger: every native-array helper (`native_int_arr_*`) needs an `i32`
   sibling, and the nullable cross product doubles the variant count again.

Neither scoping was attempted here — this file exists so the choice, and the
35-site cost, is visible before someone reaches for it.

## Related

- `Simd.*` builtins and `test/native/simd_leak_probe.march` /
  `test/native/simd_vector_escape_arg.march` — the SIMD kernels a narrow
  `F32Col` would eventually feed directly.
- `specs/todos/2026-08-12-simd-nontco-vector-param-leak.md` — the other open
  SIMD item from this same investigation; unrelated to storage width.
