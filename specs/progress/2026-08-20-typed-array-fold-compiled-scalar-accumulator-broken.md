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


---

# Fixed 2026-08-20

Root cause was NOT in `march_typed_array_fold` (which is uniformly
pointer-width and always was correct) but at the CALL SITE: the whole
`typed_array_*` family was missing from
`Llvm_builtins.builtin_boxed_generic_params_tbl`.

That table already existed for exactly this hazard — its own comment describes
`RingBuf.push(rb, 7)` storing 7 raw so "the erased-i64 conditional untag then
read odd 7 back as 3" — and the general builtin call path deliberately does NOT
coerce scalar->ptr by default, because several builtins declare a `ptr`
parameter for an opaque native handle whose March type is a plain Int and which
must stay raw (the csv/file-handle regression documented at the coercion site in
`llvm_emit.ml`). So the table is an opt-in allowlist keyed on
(builtin, param_idx), and `typed_array_create` / `_set` / `_fold` were simply
never added.

Three entries fix the family:

    typed_array_create(i64 %len, ptr %default_val)  -> [1]
    typed_array_set(ptr %arr, i64 %i, ptr %val)     -> [2]
    typed_array_fold(ptr %arr, ptr %acc, ptr %f)    -> [1]

## Why every operation was wrong, not just fold

The corruption is transitive. `get`/`map`/`filter` never handle a raw scalar
themselves — they read back whatever `create`/`set` stored — so fixing the three
storing builtins fixes the readers for free:

| | before | after | interpreted |
|---|---|---|---|
| `create(3, 7)` then `get(0)` | 3 | 7 | 7 |
| `set(a,1,42)` then `get(1)` | 42 | 42 | 42 |
| `fold(c, 0, (+))` | 48 | 56 | 56 |
| `map(a, (+1))` then `get(0)` | 4 | 8 | 8 |
| Float accumulator | **SIGSEGV** | 5 | 5 |

The `42` row is the tell: an EVEN value survives a raw store untouched, because
the conditional untag only shifts ODD values. That is why the family looked
half-working, and why the regression fixture deliberately keeps both an odd and
an even element — a test using only even values passes against the bug.

The Float leg is the same defect one representation later: raw double bits reach
`march_unbox_float` as a pointer and segfault.

## Regression test

`test/native/typed_array_scalar_repr.march` + a `runtest` diff rule, covering
create/set/get/fold/map at odd, even and Float elements. Non-vacuity confirmed by
reverting only the table (file-copy swap, not `git stash`): the golden goes RED
with `create/get odd : 3` against an expected `7`, plus four further mismatches.

## Scope note

Only the slots verified broken were added. The same declare-signature shape
(`ptr` parameter, scalar March argument) appears on many other builtins —
`vault_put_new`, `chan_send`, `record_put`, `march_send` and others — but adding
a slot whose `ptr` is an opaque handle actively CORRUPTS it, so the remaining
candidates need the same empirical check one at a time rather than a blanket
sweep.
