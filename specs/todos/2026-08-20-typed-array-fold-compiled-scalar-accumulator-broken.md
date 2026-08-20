# `TypedArray` + scalar values: wrong result and SIGSEGV in the compiled backend

Filed 2026-08-20, found while building the fold-accumulator leak probe
(`specs/progress/2026-08-20-fold-accumulator-chain-leak-fix.md`). Two symptoms,
almost certainly one root: a scalar (Int/Float) crossing the `TypedArray`
generic boundary is not represented consistently in compiled code. **The
interpreter is correct in every case below**, so this is compiled-only.

## Symptom 1 — `typed_array_fold` with an Int accumulator returns the wrong value

```march
let arr = typed_array_create(5, 7)
println(typed_array_fold(arr, 0, fn (acc, x) -> acc + x))
```

* interpreted: `35` (correct — five 7s)
* `--compile --opt 2`: **`15`**

15 is `(7 << 1) | 1`, i.e. the wire-tagged form of a single element — so the
accumulator is picking up a tagged value that never gets untagged, rather than
summing.

## Symptom 2 — a Float element or a Float accumulator SIGSEGVs

```march
let arr = typed_array_create(5, 1.0)
println(float_to_int(typed_array_fold(arr, 0.0, fn (acc, x) -> acc +. x)))
```

* interpreted: `5`
* `--compile --opt 2`: **SIGSEGV (exit 139)**

The same crash occurs with an Int-element array and a Float accumulator
(`typed_array_fold(arr, 0.0, fn (acc, x) -> acc +. int_to_float(x))`), so the
accumulator side alone is enough to trigger it.

## Not affected

* A **heap** accumulator works: `typed_array_fold(arr, some_string, ...)`
  returns correct results, and `typed_array_from_list` / `typed_array_get` over
  Strings behave.
* All four in-tree stdlib callers (`stdlib/dataframe.march`'s `col_null_count`)
  use `typed_array_fold` over a **Bool** bitmap with an **Int** accumulator.
  Given symptom 1, those results are worth re-checking as part of this item —
  `col_null_count` may be returning wrong null counts in compiled builds.

## Why it was not caught

There is no `test/native` golden for `typed_array_*` with scalar payloads. The
DataFrame tests that exercise `col_null_count` appear not to run compiled, or
not to assert on a value that would expose it.

## Guard to add with the fix

A `test/native/typed_array_scalar.march` compiled/interpreted parity golden
covering: Int element + Int accumulator, Int element + Float accumulator, Float
element + Float accumulator, and `typed_array_get`/`typed_array_to_list`
round-trips for both scalar types. Plus a compiled assertion on
`DataFrame.col_null_count`.
