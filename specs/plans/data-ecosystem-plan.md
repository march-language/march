# March Data Ecosystem — TDD Implementation Plan

**Status:** Design proposal
**Priority:** P2 (Major milestone — "Rust for data" story)
**Date:** 2026-03-23
**Related:** `specs/todos.md`, `specs/progress.md`, `specs/design.md`

---

## Table of Contents

1. [Overview & Motivation](#1-overview--motivation)
2. [Dependency Graph](#2-dependency-graph)
3. [Feature 1: FFI (extern declarations)](#3-feature-1-ffi-extern-declarations)
4. [Feature 2: Stats module](#4-feature-2-stats-module)
5. [Feature 3: Random module](#5-feature-3-random-module)
6. [Feature 4: DataFrame type](#6-feature-4-dataframe-type)
7. [Feature 5: Parquet reader](#7-feature-5-parquet-reader)
8. [Feature 6: Plotting (SVG output)](#8-feature-6-plotting-svg-output)
9. [Effort Summary](#9-effort-summary)
10. [Cross-cutting concerns](#10-cross-cutting-concerns)

---

## 1. Overview & Motivation

March's current stdlib gives you fast, correct programs with good concurrency. What it
lacks is the data manipulation stack that makes a language genuinely useful for
analytics, science, and machine-learning pipelines. The six features in this plan close
that gap and together form March's "Rust for data" story:

- **FFI** unlocks calling any C library, making the rest achievable without
  re-implementing decades of C work.
- **Stats** gives pure-March descriptive statistics and hypothesis testing.
- **Random** gives a reproducible, purely-functional PRNG for simulations, shuffling,
  and Monte Carlo methods.
- **DataFrame** brings columnar, lazy-evaluated tabular data — the lingua franca of
  data work.
- **Parquet** lets March read the dominant binary columnar format without any foreign
  tool.
- **Plotting** closes the loop: produce publication-quality charts as SVG strings,
  with no external GUI dependencies.

All six are designed to compose naturally:

```march
-- A complete data-science snippet in March:
let df = DataFrame.from_csv("measurements.csv")
let col = DataFrame.get_column(df, "value")
let stats = Stats.describe(col)
let rng = Random.seed(42)
let (sample, _) = Random.sample(rng, col, 1000)
let plot = Plot.histogram(sample, bins: 20)
    |> Plot.set_title("Value distribution")
Plot.save(plot, "dist.svg")
```

---

## 2. Dependency Graph

```
FFI (Feature 1)
  └── Parquet FFI path (Feature 5 path B)

Stats (Feature 2)          [no deps — pure March on List/Array]
  └── DataFrame.describe   (Feature 4 depends on Stats)
  └── Plot.histogram       (Feature 6 depends on Stats)

Random (Feature 3)         [no deps — pure March PRNG]
  └── DataFrame.sample     (Feature 4 depends on Random)

DataFrame (Feature 4)
  ├── Stats (for describe, z_score normalization)
  ├── Random (for sample operation)
  ├── CSV stdlib (already exists: stdlib/csv.march)
  └── Stream fusion (already implemented: lib/tir/fusion.ml)
      → lazy plan evaluation collapses map/filter chains for free

Parquet (Feature 5)
  ├── Path A (pure March): no deps beyond File module
  └── Path B (FFI):  FFI (Feature 1), caps system

Plotting (Feature 6)
  ├── Stats (axis scaling, histogram bins)
  └── DataFrame (plot from column directly)
```

**Recommended implementation order:**

```
Phase A (no deps):  Stats → Random
Phase B (FFI core): FFI
Phase C (tabular):  DataFrame
Phase D (I/O):      Parquet (pure path first), then Plotting
Phase E (FFI path): Parquet FFI path (if needed for performance)
```

---

## 3. Feature 1: FFI (extern declarations)

### 3.1 Motivation

March's eval.ml currently silently ignores `DExtern` blocks (`DExtern _ -> env`).
The typecheck pass already validates that `extern` declarations require a matching
`needs` capability, and registers the function types in the environment. The missing
pieces are:

1. An eval-level dispatch that calls real C functions (via `dlopen`/`dlsym`)
2. An LLVM IR emission path that emits a `declare` for the foreign symbol
3. A safe wrapper pattern in the standard library
4. Marshalling rules for compound types

The AST already has the right shape (`extern_def`, `extern_fn` in `lib/ast/ast.ml`,
lines 306–318). The parser already accepts `extern "libc" : Cap(LibC) do ... end`
syntax. This feature is primarily about making the existing skeleton actually work.

### 3.2 Design Decisions

#### 3.2.1 Declaration syntax (already decided in AST)

```march
-- Declare a foreign function from libc
extern "c" : Cap(LibC) do
  def sin(x : Float) -> Float
  def sqrt(x : Float) -> Float
  def malloc(size : Int) -> Ptr(Byte)
  def free(p : linear Ptr(Byte)) -> Unit
end
```

The `extern "c"` string names the link library. The capability `Cap(LibC)` is the
unforgeable token that callers must hold. The `def` keyword (not `fn`) marks a
declaration without a body. The compiler emits an LLVM `declare` for each `def`.

**Alternative considered:** A flat `@[extern "sin"]` attribute on regular `fn`
declarations (Rust-style). Rejected because it scatters capability requirements across
the file instead of grouping them. The block form makes it obvious which functions
come from which library and ties them to a single capability.

#### 3.2.2 Opaque pointer types

```march
-- Opaque pointer: the value IS the C pointer, RC does not apply
type Ptr(a) = OpaquePtr    -- compiler-magic type

-- Pointer to foreign struct (no RC)
extern "sqlite3" : Cap(SQLite) do
  def sqlite3_open(path : String) -> Ptr(DB)
  def sqlite3_close(db : linear Ptr(DB)) -> Int
end
```

`Ptr(a)` is a first-class March type. The type parameter `a` is phantom (just for
documentation/type-checking; no runtime value). `linear Ptr(a)` enforces that the
pointer must be explicitly freed — the linear type system ensures no double-free.

The Perceus RC pass must be taught to skip `Ptr(a)` values entirely: no
`incref`/`decref` is emitted. The only way a `Ptr` disappears is via an explicit call
to a foreign `free`-equivalent.

#### 3.2.3 Marshalling rules

| March type | C type | Direction | Notes |
|------------|--------|-----------|-------|
| `Int` | `int64_t` | both | zero-extension for C `int` |
| `Float` | `double` | both | IEEE 754, no conversion |
| `Bool` | `int` (0/1) | both | |
| `String` | `const char*` | March→C | march_string_cstr() gives NUL-terminated copy |
| `String` | `const char*` | C→March | march_string_from_cstr() copies into GC heap |
| `Byte` | `uint8_t` | both | |
| `Ptr(a)` | `void*` | both | raw pointer, no RC |
| compound types | — | — | not auto-marshalled; user must extract fields |

Compound types (records, ADTs, tuples) are **not** automatically marshalled. The user
must write a March wrapper that calls FFI functions on primitives and reconstructs
March values. This avoids the complexity of a full ABI mapping and is explicit about
the boundary.

#### 3.2.4 RC interaction

The Perceus pass (`lib/tir/perceus.ml`) must be extended with a rule:

> If a value has type `Ptr(a)` (or any type whose definition is tagged `[@@foreign]`),
> do not emit any RC operations for it. It is entirely the programmer's responsibility.

A helper `unsafe_borrow : Ptr(a) -> Ptr(a)` (identity function) will be provided so
that users can explicitly pass a pointer to a function without consuming it (affine
semantics would normally consume it).

#### 3.2.5 Linking strategy

- **Interpreter (eval.ml):** Use `dlopen(NULL, ...)` (the process image) + `dlsym` for
  libc symbols. For other libraries, respect `ext_lib_name` to load
  `lib<name>.so` / `lib<name>.dylib`. The `jit_stubs.c` already provides `dlopen`/`dlsym`
  wrappers — reuse them.
- **LLVM backend (llvm_emit.ml):** Emit `declare <ret> @<sym>(<args>)` for each
  `extern_fn`. The clang linker invocation (already in `bin/main.ml`) must pass `-l<name>`
  for each extern block's library.

#### 3.2.6 Safe wrapper pattern

All FFI functions should be wrapped in a March module that:
1. Takes a capability proof argument
2. Does all marshalling explicitly
3. Returns `Result(a, FfiError)` for functions that can fail
4. Uses `linear Ptr(a)` for resource-owning pointers

```march
mod LibM do
  -- Safe wrapper around extern sin
  pub fn sin(cap : Cap(LibC), x : Float) : Float do
    __extern_sin(x)    -- the raw extern, not exported
  end
end
```

### 3.3 Implementation Phases

#### Phase 1.1 — Parse and AST (already done; verify coverage)

Tests:
```
test: parse_extern_block_single_fn
  input: extern "c" : Cap(LibC) do def sqrt(x : Float) -> Float end
  expect: DExtern { ext_lib_name="c"; ext_fns=[{ef_name="sqrt"; ...}] }

test: parse_extern_block_multiple_fns
  input: extern "m" : Cap(LibM) do
           def sin(x : Float) -> Float
           def cos(x : Float) -> Float
           def pow(base : Float, exp : Float) -> Float
         end
  expect: 3 extern_fn entries

test: parse_extern_with_ptr_type
  input: extern "c" : Cap(LibC) do
           def malloc(n : Int) -> Ptr(Byte)
           def free(p : linear Ptr(Byte)) -> Unit
         end
  expect: Ptr constructor parsed in return type; linear qualifier on param

test: parse_extern_missing_cap_error
  input: extern "c" do def sqrt(x : Float) -> Float end
  expect: parse error — ": Cap(...)" required
```

#### Phase 1.2 — Typecheck (partially done; complete coverage)

Tests:
```
test: typecheck_extern_requires_needs_decl
  input: extern "c" : Cap(LibC) do def sqrt(x : Float) -> Float end
         fn main() do sqrt(2.0) end
  expect: error — Cap(LibC) not in needs list

test: typecheck_extern_with_needs_passes
  input: [needs Cap(LibC)]
         extern "c" : Cap(LibC) do def sqrt(x : Float) -> Float end
         fn main() : Float do sqrt(2.0) end
  expect: sqrt inferred as Float -> Float, no errors

test: typecheck_extern_fn_wrong_arg_type
  input: [needs Cap(LibC)]
         extern "c" : Cap(LibC) do def sqrt(x : Float) -> Float end
         fn main() : Float do sqrt(42) end
  expect: type error — Int not compatible with Float

test: typecheck_ptr_type_not_rc
  input: [needs Cap(LibC)]
         extern "c" : Cap(LibC) do def malloc(n : Int) -> Ptr(Byte) end
         fn main() do let p = malloc(64) end
  expect: type of p is Ptr(Byte), no RC annotations on it

test: typecheck_linear_ptr_must_be_consumed
  input: [needs Cap(LibC)]
         extern "c" : Cap(LibC) do
           def malloc(n : Int) -> linear Ptr(Byte)
           def free(p : linear Ptr(Byte)) -> Unit
         end
         fn main() do
           let p = malloc(64)
           -- p never freed
         end
  expect: linearity error — linear value p consumed 0 times
```

#### Phase 1.3 — Eval dispatch (new work)

The eval.ml `DExtern` case currently returns `env` unchanged. Extend it:

```ocaml
(* In eval.ml, eval_decl *)
| Ast.DExtern (edef, _sp) ->
    List.fold_left (fun env (ef : Ast.extern_fn) ->
      let stub = VForeign (edef.ext_lib_name, ef.ef_name.txt) in
      Env.bind env ef.ef_name.txt stub
    ) env edef.ext_fns
```

`VForeign (lib, sym)` is a new value variant. When applied, it uses `dlsym` to find
and call the symbol. Marshalling of Int/Float/Bool/String follows the table in §3.2.3.

Tests:
```
test: eval_extern_sqrt_via_dlsym
  march source: [needs Cap(LibC)]
                extern "c" : Cap(LibC) do def sqrt(x : Float) -> Float end
                fn main() : Float do sqrt(4.0) end
  expect: 2.0

test: eval_extern_sin
  march source: [needs Cap(LibM)]
                extern "m" : Cap(LibM) do def sin(x : Float) -> Float end
                fn main() : Float do sin(0.0) end
  expect: 0.0

test: eval_extern_string_arg
  march source: [needs Cap(LibC)]
                extern "c" : Cap(LibC) do def puts(s : String) -> Int end
                fn main() : Int do puts("hello") end
  expect: some non-negative int (C puts returns chars written), "hello\n" on stdout

test: eval_extern_ptr_roundtrip
  -- malloc then immediately free, no crash
  march source: [needs Cap(LibC)]
                extern "c" : Cap(LibC) do
                  def malloc(n : Int) -> Ptr(Byte)
                  def free(p : Ptr(Byte)) -> Unit
                end
                fn main() do
                  let p = malloc(64)
                  free(p)
                end
  expect: no crash, no leak

test: eval_extern_unknown_lib_error
  extern "nonexistent_lib_xyz" : Cap(X) do def foo() -> Int end
  expect: runtime error — cannot dlopen nonexistent_lib_xyz
```

#### Phase 1.4 — LLVM IR emission (new work)

In `llvm_emit.ml`, handle `DExtern` by emitting a `declare` for each foreign function:

```llvm
; For: extern "c" : Cap(LibC) do def sqrt(x : Float) -> Float end
declare double @sqrt(double)
```

The clang invocation in `bin/main.ml` must add `-lm`, `-lc`, etc. based on the
library name map.

Tests:
```
test: llvm_extern_declare_emitted
  compile extern "c" : Cap(LibC) do def sqrt(x : Float) -> Float end
  verify: emitted .ll contains "declare double @sqrt(double)"

test: llvm_extern_call_instruction
  compile fn main() : Float do sqrt(4.0) end (with extern sqrt declared)
  verify: emitted .ll contains "call double @sqrt(double"

test: llvm_extern_ptr_as_i8ptr
  compile extern fn malloc(n : Int) -> Ptr(Byte)
  verify: emitted .ll declares "declare ptr @malloc(i64)"

test: llvm_extern_string_marshalling
  compile extern fn puts(s : String) -> Int, called with string literal
  verify: emitted .ll calls march_string_cstr before @puts
```

### 3.4 Dependencies

- Builds on existing: `lib/ast/ast.ml` (extern_def already there), typecheck (partial
  DExtern handling at line 4007), `lib/jit/jit_stubs.c` (dlopen/dlsym wrappers)
- Blocks: Parquet FFI path (Feature 5 Path B)
- Related: `runtime/march_runtime.c` — add `march_string_cstr()` and
  `march_string_from_cstr()` marshalling helpers

### 3.5 Estimated Effort

- Phase 1.1 (parse): 0.5 days (already parses; add ~4 tests to verify edge cases)
- Phase 1.2 (typecheck): 1 day (Ptr type, linear Ptr, needs enforcement)
- Phase 1.3 (eval dispatch): 2 days (VForeign value, dlsym dispatch, marshalling)
- Phase 1.4 (LLVM emit): 1.5 days (declare emission, call sites, string marshalling)
- Total: **~5 days**

---

## 4. Feature 2: Stats module

### 4.1 Motivation

March has `stdlib/math.march` for transcendental functions and `stdlib/list.march` for
map/filter/fold. What is missing is a coherent statistics library. Statistics is the
primary use case driving the "Rust for data" story: users should be able to load data,
run a t-test, compute percentiles, and fit a linear regression — all in idiomatic March
without reaching for Python.

The Stats module is intentionally **pure March** — no FFI, no platform dependencies.
This makes it portable, testable, and inspectable. All functions operate on
`List(Float)` or `Array(Float)`.

### 4.2 Design Decisions

#### 4.2.1 Input type: List(Float) vs Array(Float) vs both

The module will accept `List(Float)` as the primary input type because:
- List is the default collection type in March
- The existing list operations (map, filter, fold) compose naturally
- Conversion from Array to List is O(n) and explicit

Functions that naturally need indexed access (percentile, median) will internally
convert to a sorted array using `Sort.sort`. The user-facing API always accepts lists.

**Alternative considered:** Accept `Iterable(Float)` (the iterable interface). Deferred
— the Iterable interface exists but adding a Stats dependency on an interface complicates
the stdlib dependency order. Keep Stats concrete for now.

#### 4.2.2 Sample vs population variants

By default, functions compute the **sample** statistic (denominator n-1). Population
variants are suffixed `_pop`:

```march
Stats.variance(xs)       -- sample variance (divides by n-1)
Stats.variance_pop(xs)   -- population variance (divides by n)
Stats.std_dev(xs)        -- sample std dev
Stats.std_dev_pop(xs)    -- population std dev
```

`t_test` and `chi_squared` are inherently sample-based (no `_pop` variant needed).

#### 4.2.3 Return types for aggregate results

`linear_regression` returns a record `{slope: Float, intercept: Float, r_squared: Float}`.
`histogram` returns `List({lo: Float, hi: Float, count: Int})`.
`describe` returns a summary record.

#### 4.2.4 Error handling

For degenerate inputs (empty list, division by zero in correlation), return
`Result(Float, StatsError)` where:

```march
type StatsError = EmptyInput | InsufficientData(Int) | Undefined
```

Most functions return `Result` to force callers to handle degenerate cases.
`mean`, `sum`, `min_val`, `max_val` return `Result(Float, StatsError)`.

**Alternative considered:** Panic on empty input (like Python's statistics module).
Rejected — March's error model is explicit. Callers should handle degenerate inputs.

### 4.3 API Surface

```march
mod Stats do

  type StatsError = EmptyInput | InsufficientData(Int) | Undefined

  -- Descriptive statistics
  pub fn sum(xs : List(Float)) : Float
  pub fn mean(xs : List(Float)) : Result(Float, StatsError)
  pub fn median(xs : List(Float)) : Result(Float, StatsError)
  pub fn mode(xs : List(Float)) : Result(Float, StatsError)     -- most frequent

  -- Spread
  pub fn variance(xs : List(Float)) : Result(Float, StatsError)      -- sample
  pub fn variance_pop(xs : List(Float)) : Result(Float, StatsError)  -- population
  pub fn std_dev(xs : List(Float)) : Result(Float, StatsError)
  pub fn std_dev_pop(xs : List(Float)) : Result(Float, StatsError)

  -- Order statistics
  pub fn min_val(xs : List(Float)) : Result(Float, StatsError)
  pub fn max_val(xs : List(Float)) : Result(Float, StatsError)
  pub fn range(xs : List(Float)) : Result(Float, StatsError)    -- max - min
  pub fn percentile(xs : List(Float), p : Float) : Result(Float, StatsError)
                                                  -- p in [0.0, 100.0]
  pub fn quartiles(xs : List(Float)) : Result((Float, Float, Float), StatsError)
                                      -- (Q1, Q2, Q3)

  -- Standardization
  pub fn z_score(xs : List(Float)) : Result(List(Float), StatsError)
  pub fn normalize(xs : List(Float)) : Result(List(Float), StatsError)  -- [0,1]

  -- Bivariate
  pub fn covariance(xs : List(Float), ys : List(Float))
      : Result(Float, StatsError)
  pub fn correlation(xs : List(Float), ys : List(Float))
      : Result(Float, StatsError)    -- Pearson r

  -- Regression
  type RegressionResult = {
    slope : Float,
    intercept : Float,
    r_squared : Float,
  }
  pub fn linear_regression(xs : List(Float), ys : List(Float))
      : Result(RegressionResult, StatsError)

  -- Binning
  type Bin = { lo : Float, hi : Float, count : Int }
  pub fn histogram(xs : List(Float), bins : Int)
      : Result(List(Bin), StatsError)

  -- Hypothesis tests
  type TTestResult = { t_stat : Float, p_value : Float, df : Float }
  pub fn t_test_one_sample(xs : List(Float), mu : Float)
      : Result(TTestResult, StatsError)
  pub fn t_test_two_sample(xs : List(Float), ys : List(Float))
      : Result(TTestResult, StatsError)

  type ChiSquaredResult = { chi_stat : Float, p_value : Float, df : Int }
  pub fn chi_squared(observed : List(Float), expected : List(Float))
      : Result(ChiSquaredResult, StatsError)

  -- Summary
  type Summary = {
    count : Int,
    mean : Float,
    std_dev : Float,
    min_val : Float,
    p25 : Float,
    p50 : Float,
    p75 : Float,
    max_val : Float,
  }
  pub fn describe(xs : List(Float)) : Result(Summary, StatsError)

end
```

### 4.4 Implementation Phases

#### Phase 2.1 — Basic aggregates

Tests (all values computed by hand or via Python scipy):
```
test: stats_sum_empty   sum([]) == 0.0
test: stats_sum_ints    sum([1.0, 2.0, 3.0]) == 6.0
test: stats_mean_simple mean([1.0,2.0,3.0,4.0,5.0]) == Ok(3.0)
test: stats_mean_empty  mean([]) == Err(EmptyInput)
test: stats_min_val     min_val([3.0, 1.0, 4.0, 1.0, 5.0]) == Ok(1.0)
test: stats_max_val     max_val([3.0, 1.0, 4.0, 1.0, 5.0]) == Ok(5.0)
test: stats_range       range([1.0, 5.0]) == Ok(4.0)
test: stats_sum_single  sum([42.0]) == 42.0
test: stats_mean_single mean([42.0]) == Ok(42.0)
```

#### Phase 2.2 — Order statistics (median, percentile, quartiles)

Tests:
```
test: stats_median_odd    median([1.0,3.0,2.0]) == Ok(2.0)
test: stats_median_even   median([1.0,2.0,3.0,4.0]) == Ok(2.5)
test: stats_median_single median([7.0]) == Ok(7.0)
test: stats_median_empty  median([]) == Err(EmptyInput)
test: stats_percentile_50 percentile([1.0,2.0,3.0,4.0,5.0], 50.0) == Ok(3.0)
test: stats_percentile_0  percentile([1.0,2.0,3.0], 0.0) == Ok(1.0)
test: stats_percentile_100 percentile([1.0,2.0,3.0], 100.0) == Ok(3.0)
test: stats_percentile_25 percentile([1.0..100.0], 25.0) ≈ Ok(25.75)
test: stats_quartiles     quartiles([1.0..100.0]) checks Q1≈25.75, Q2≈50.5, Q3≈75.25
test: stats_percentile_out_of_range percentile(xs, 101.0) == Err(Undefined)
```

#### Phase 2.3 — Variance and standard deviation

Tests:
```
test: stats_variance_sample  variance([2.0,4.0,4.0,4.0,5.0,5.0,7.0,9.0])
                             == Ok(4.571428...)   -- known value
test: stats_variance_pop     variance_pop([2.0,4.0,4.0,4.0,5.0,5.0,7.0,9.0])
                             == Ok(4.0)           -- known value
test: stats_std_dev_sample   std_dev([2.0,4.0,4.0,4.0,5.0,5.0,7.0,9.0])
                             ≈ Ok(2.138)
test: stats_std_dev_pop      std_dev_pop([2.0,4.0,4.0,4.0,5.0,5.0,7.0,9.0])
                             == Ok(2.0)
test: stats_variance_single  variance([42.0]) == Err(InsufficientData(1))
                              -- n-1 = 0, undefined
test: stats_variance_empty   variance([]) == Err(EmptyInput)
test: stats_z_score          z_score([2.0,4.0,4.0,4.0,5.0,5.0,7.0,9.0])
                             == Ok([-1.5, -0.5, -0.5, -0.5, 0.0, 0.0, 1.0, 2.0])
                             (approximately, using pop std_dev = 2.0)
test: stats_normalize        normalize([0.0, 5.0, 10.0]) == Ok([0.0, 0.5, 1.0])
```

#### Phase 2.4 — Mode and histogram

Tests:
```
test: stats_mode_unique   mode([1.0,2.0,3.0,3.0,4.0]) == Ok(3.0)
test: stats_mode_tie      mode([1.0,1.0,2.0,2.0]) is Ok with either value
test: stats_mode_empty    mode([]) == Err(EmptyInput)
test: stats_histogram_3bins
  histogram([1.0,1.5,2.0,3.0,3.5,4.0,4.5,5.0], 3)
  == Ok([{lo=1.0,hi=2.333,count=3},
         {lo=2.333,hi=3.666,count=2},
         {lo=3.666,hi=5.0,count=3}])  (approximately)
test: stats_histogram_empty   histogram([], 5) == Err(EmptyInput)
test: stats_histogram_zero_bins histogram(xs, 0) == Err(Undefined)
```

#### Phase 2.5 — Bivariate statistics

Tests:
```
test: stats_covariance_positive
  covariance([1.0,2.0,3.0], [2.0,4.0,6.0]) == Ok(1.0)
test: stats_covariance_zero
  covariance([1.0,2.0,3.0], [3.0,2.0,1.0]) ... negative cov
test: stats_correlation_perfect_pos
  correlation([1.0,2.0,3.0], [2.0,4.0,6.0]) ≈ Ok(1.0)
test: stats_correlation_perfect_neg
  correlation([1.0,2.0,3.0], [3.0,2.0,1.0]) ≈ Ok(-1.0)
test: stats_correlation_zero
  correlation([1.0,2.0,3.0], [5.0,5.0,5.0]) == Ok(0.0)  (constant ys → undefined)
  actually Err(Undefined) since std_dev(ys) = 0
test: stats_correlation_length_mismatch
  correlation([1.0,2.0], [1.0,2.0,3.0]) == Err(InsufficientData)
```

#### Phase 2.6 — Linear regression

Tests:
```
test: stats_linreg_perfect_line
  linear_regression([1.0,2.0,3.0,4.0,5.0], [2.0,4.0,6.0,8.0,10.0])
  == Ok({slope=2.0, intercept=0.0, r_squared=1.0})

test: stats_linreg_with_intercept
  linear_regression([0.0,1.0,2.0,3.0], [1.0,3.0,5.0,7.0])
  == Ok({slope=2.0, intercept=1.0, r_squared=1.0})

test: stats_linreg_noisy
  -- y = 2x + 1 + noise; expect slope ≈ 2.0, intercept ≈ 1.0, r_squared < 1.0
  linear_regression([0.0,1.0,2.0,3.0,4.0], [1.1,2.9,5.2,6.8,9.1])
  r_squared > 0.99

test: stats_linreg_single_point
  linear_regression([1.0], [2.0]) == Err(InsufficientData(1))
```

#### Phase 2.7 — Hypothesis tests

Tests:
```
test: stats_ttest_one_sample_zero
  -- H0: mean == 0, data mean == 0
  t_test_one_sample([0.0, 0.0, 0.0], 0.0) → t_stat ≈ 0.0 (undefined: std=0)
  result is Err(Undefined) since std_dev of all-zeros is 0

test: stats_ttest_one_sample_known
  t_test_one_sample([2.0,3.0,4.0,5.0,6.0], 3.0)
  t_stat ≈ 2.0, p_value from t-distribution (df=4)

test: stats_ttest_two_sample
  xs = [1.0,2.0,3.0,4.0,5.0]
  ys = [2.0,3.0,4.0,5.0,6.0]
  t_test_two_sample(xs, ys) → t_stat should reflect 1-unit mean difference

test: stats_chisquared_uniform
  observed = [10.0,10.0,10.0,10.0]
  expected = [10.0,10.0,10.0,10.0]
  chi_squared(observed, expected) → chi_stat ≈ 0.0

test: stats_chisquared_extreme
  observed = [20.0,0.0,0.0,0.0]
  expected = [5.0,5.0,5.0,5.0]
  chi_squared(observed, expected) → large chi_stat
```

#### Phase 2.8 — describe

Tests:
```
test: stats_describe_basic
  describe([1.0,2.0,3.0,4.0,5.0]) == Ok({
    count=5, mean=3.0, std_dev≈1.581, min_val=1.0,
    p25=2.0, p50=3.0, p75=4.0, max_val=5.0
  })
test: stats_describe_empty   describe([]) == Err(EmptyInput)
```

### 4.5 Dependencies

- `stdlib/list.march` (sort, map, filter, fold, length, zip) — already exists
- `stdlib/math.march` (sqrt, abs) — already exists
- No FFI needed

### 4.6 Estimated Effort

- Phase 2.1–2.2: 1 day
- Phase 2.3–2.4: 1 day
- Phase 2.5–2.6: 1 day
- Phase 2.7–2.8: 1 day (t-distribution CDF is the hard part — can use Lanczos approximation)
- Total: **~4 days**

---

## 5. Feature 3: Random module

### 5.1 Motivation

March has no source of randomness in the stdlib. For data work, you need:
- Reproducible simulations (same seed → same results)
- Random sampling from datasets
- Random number generation for Monte Carlo methods
- Normally-distributed random variables for statistics

The key design constraint is **functional purity**: the Rng state is passed explicitly
and returned updated. This is idiomatic March (no mutable state) and makes programs
deterministic given a seed.

### 5.2 Design Decisions

#### 5.2.1 Algorithm: xoshiro256**

xoshiro256** (Blackman & Vigna, 2019) is the algorithm chosen because:
- High statistical quality (passes all BigCrush tests)
- Very fast (4 shifts, 3 XORs, 1 rotation per output)
- Simple state (4 × 64-bit integers)
- Well-specified — any March program seeded with the same value will produce the
  same sequence on any platform

**Alternative considered:** Mersenne Twister. Larger state (624 × 32-bit words), slower
initialization. MT was the standard but xoshiro256** is strictly better for all use cases
that don't need cryptographic security.

**Alternative considered:** PCG. Also excellent, slightly more complex to implement.
xoshiro256** is simpler and the reference implementation is public domain.

#### 5.2.2 Seeding

`seed(n : Int) -> Rng` constructs an Rng from an integer seed using the SplitMix64
algorithm to expand the seed into 4 independent state words. This prevents bad seeds
(e.g., 0) from producing degenerate sequences.

#### 5.2.3 Opaque Rng type

`Rng` is an opaque type — callers cannot inspect or construct state directly:

```march
mod Random do
  type Rng = { s0 : Int, s1 : Int, s2 : Int, s3 : Int }
  -- Only 'seed' and the generation functions create or update Rng values
end
```

The fields are private to the module; external code only sees `Rng`.

#### 5.2.4 Functional API: threading state explicitly

Every function that generates a value takes an `Rng` and returns `(value, Rng)`:

```march
let rng0 = Random.seed(42)
let (x, rng1) = Random.next_int(rng0)
let (y, rng2) = Random.next_float(rng1)
```

**Alternative considered:** Use March actors to hold mutable Rng state (an `RngActor`
that you send messages to). Rejected for this module — the pure API is simpler, works
outside the actor runtime, and is easier to test. An actor wrapper can be built on top.

**Alternative considered:** Monadic threading via a `State(Rng, a)` type. March doesn't
have do-notation so monadic style is verbose. Explicit tuple threading is more readable
in March.

#### 5.2.5 Normal distribution: Box-Muller transform

`normal(rng, mean, std) -> (Float, Rng)` uses Box-Muller:
- Draw two uniform floats u1, u2 from (0, 1)
- Compute z = sqrt(-2 * ln(u1)) * cos(2 * pi * u2)
- Return mean + std * z

Box-Muller generates pairs; for simplicity, discard the second value. The Ziggurat
algorithm is faster but much more complex to implement.

### 5.3 API Surface

```march
mod Random do

  type Rng  -- opaque

  -- Construction
  pub fn seed(n : Int) : Rng
  pub fn from_entropy() : Rng   -- uses /dev/urandom; fallback to timestamp

  -- Primitive generators (return updated Rng)
  pub fn next_int(rng : Rng) : (Int, Rng)
  pub fn next_float(rng : Rng) : (Float, Rng)   -- uniform [0.0, 1.0)
  pub fn next_bool(rng : Rng) : (Bool, Rng)

  -- Ranged generators
  pub fn range_int(rng : Rng, lo : Int, hi : Int) : (Int, Rng)
      -- uniform integer in [lo, hi]
  pub fn range_float(rng : Rng, lo : Float, hi : Float) : (Float, Rng)
      -- uniform float in [lo, hi)

  -- Distributions
  pub fn normal(rng : Rng, mean : Float, std : Float) : (Float, Rng)
  pub fn exponential(rng : Rng, lambda : Float) : (Float, Rng)
  pub fn bernoulli(rng : Rng, p : Float) : (Bool, Rng)

  -- Collection operations
  pub fn shuffle(rng : Rng, xs : List(a)) : (List(a), Rng)
      -- Fisher-Yates shuffle
  pub fn sample(rng : Rng, xs : List(a), n : Int) : (List(a), Rng)
      -- draw n items without replacement
  pub fn sample_with_replacement(rng : Rng, xs : List(a), n : Int) : (List(a), Rng)
  pub fn choose(rng : Rng, xs : List(a)) : (Option(a), Rng)
      -- pick one uniformly at random

  -- Utilities
  pub fn split(rng : Rng) : (Rng, Rng)
      -- produce two independent RNGs from one (for parallel use)

end
```

### 5.4 Implementation Phases

#### Phase 3.1 — Core xoshiro256** state machine

Tests (computed from the reference C implementation):
```
test: random_seed_42_first_int
  seed(42) |> next_int |> fst
  == <specific value from xoshiro256** with SplitMix64 seeding of 42>
  -- compute this from reference C impl; lock it in as a regression test

test: random_seed_deterministic
  let (v1, _) = seed(99) |> next_int
  let (v2, _) = seed(99) |> next_int
  v1 == v2

test: random_seed_different
  let (v1, _) = seed(1) |> next_int
  let (v2, _) = seed(2) |> next_int
  v1 != v2

test: random_sequence_ten
  -- generate 10 values from seed 0, verify they match reference implementation
  -- this locks in the algorithm correctness
  [10 known values from xoshiro256** seeded with SplitMix64(0)]

test: random_next_float_range
  -- all 1000 generated floats from seed 7 are in [0.0, 1.0)
  let floats = generate_n(seed(7), next_float, 1000)
  List.all(fn x -> x >= 0.0 && x < 1.0, floats)
```

#### Phase 3.2 — Range and collection operations

Tests:
```
test: random_range_int_bounds
  -- all 10000 values in [lo, hi]
  let rng = seed(123)
  let vals = generate_n(rng, fn r -> range_int(r, 10, 20), 10000)
  List.all(fn v -> v >= 10 && v <= 20, vals)

test: random_range_int_lo_eq_hi
  range_int(seed(1), 5, 5) |> fst == 5

test: random_range_float_bounds
  all range_float(rng, -1.0, 1.0) values in [-1.0, 1.0)

test: random_shuffle_length_preserved
  let xs = [1, 2, 3, 4, 5]
  let (shuffled, _) = shuffle(seed(42), xs)
  List.length(shuffled) == 5

test: random_shuffle_contains_all
  -- shuffled list is a permutation of the original
  let xs = [1, 2, 3, 4, 5]
  let (shuffled, _) = shuffle(seed(42), xs)
  List.sort(shuffled) == List.sort(xs)

test: random_shuffle_different_seed
  -- same list, different seeds → different shuffles (probabilistically)
  let (s1, _) = shuffle(seed(1), [1..10])
  let (s2, _) = shuffle(seed(2), [1..10])
  s1 != s2

test: random_sample_count
  let (samp, _) = sample(seed(0), [1..100], 10)
  List.length(samp) == 10

test: random_sample_no_duplicates
  let (samp, _) = sample(seed(0), [1..100], 10)
  List.length(samp) == List.length(List.unique(samp))

test: random_sample_n_exceeds_list
  sample(seed(0), [1,2,3], 10) → entire list (no replacement; returns [1,2,3])
```

#### Phase 3.3 — Statistical distributions

Tests:
```
test: random_normal_distribution
  -- Generate 10000 normal(0.0, 1.0) values; check empirical mean ≈ 0, std ≈ 1
  let vals = generate_n(seed(0), fn r -> normal(r, 0.0, 1.0), 10000)
  let m = Stats.mean(vals)
  let s = Stats.std_dev(vals)
  abs(m) < 0.05   -- within 5% of 0
  abs(s - 1.0) < 0.05   -- within 5% of 1

test: random_normal_shifted
  -- normal(5.0, 2.0) → mean ≈ 5.0, std ≈ 2.0
  let vals = generate_n(seed(1), fn r -> normal(r, 5.0, 2.0), 10000)
  abs(Stats.mean(vals) - 5.0) < 0.1

test: random_exponential_distribution
  -- exponential(2.0) → mean ≈ 0.5 (E[X] = 1/lambda)
  let vals = generate_n(seed(2), fn r -> exponential(r, 2.0), 10000)
  abs(Stats.mean(vals) - 0.5) < 0.05

test: random_bernoulli_proportion
  -- bernoulli(0.3) → ~30% True
  let vals = generate_n(seed(3), fn r -> bernoulli(r, 0.3), 10000)
  let trues = List.count(fn b -> b, vals)
  abs(trues / 10000.0 - 0.3) < 0.02

test: random_split_independence
  -- two RNGs from split produce different sequences
  let (r1, r2) = split(seed(42))
  let (v1, _) = next_int(r1)
  let (v2, _) = next_int(r2)
  v1 != v2
```

#### Phase 3.4 — Uniformity / chi-squared test

```
test: random_uniform_chi_squared
  -- bin 100000 integers from range_int(0, 9) into 10 buckets
  -- chi-squared test against uniform → p-value > 0.01
  This is a statistical test; it should pass with extremely high probability
  for any correct PRNG. Run from seed 0; if it fails, the PRNG is broken.
```

### 5.5 Dependencies

- `stdlib/math.march` (`sqrt`, `log`, `cos`) — already exists
- `stdlib/list.march` — already exists
- Stats module (for Phase 3.3 distribution tests) — should be implemented first
- No FFI needed (xoshiro256** is pure integer arithmetic)

### 5.6 Estimated Effort

- Phase 3.1 (core algorithm): 1.5 days
- Phase 3.2 (range + collections): 1 day
- Phase 3.3 (distributions): 1 day
- Phase 3.4 (uniformity test): 0.5 days
- Total: **~4 days**

---

## 6. Feature 4: DataFrame type

### 6.1 Motivation

The DataFrame is the lingua franca of data work. Pandas, Polars, R's data.frame —
every data ecosystem converges on this abstraction: a table where each column has a
name and a type, rows share the same schema, and operations are expressed as
transformations on the whole structure rather than loops over rows.

March's DataFrame is distinguished by two things:
1. **Lazy evaluation** — operations build a query plan; data materializes only on
   `collect()`. The existing stream fusion pass (`lib/tir/fusion.ml`) already
   deforests `map`/`filter`/`fold` chains. The DataFrame lazy plan is a
   higher-level version of the same idea.
2. **Type-level column names** — if March's type-level nat solver can be extended to
   support symbol constraints, column access can be checked at compile time. For v1,
   use runtime-checked column access with descriptive errors; defer compile-time column
   name checking to a later type system extension.

### 6.2 Design Decisions

#### 6.2.1 Columnar storage

Columns are stored as `Array(a)` (the persistent vector from `stdlib/array.march`), not
`List(a)`. This gives O(1) indexed access for join/sort operations. The `Column(a)` type
wraps an `Array(a)` with a name:

```march
type Column(a) = { name : String, data : Array(a) }
```

#### 6.2.2 Schema representation

A `DataFrame` has a schema mapping column names to value arrays:

```march
type Value = VInt(Int) | VFloat(Float) | VString(String) | VBool(Bool) | VNull

type DataFrame = {
  schema : List(String),         -- ordered column names
  columns : Map(String, Array(Value)),
  row_count : Int,
}
```

The dynamic `Value` ADT allows heterogeneous columns without dependent types.
Type-specific accessors (`get_int_column`, `get_float_column`) extract typed columns
with `Result` error handling for type mismatches.

#### 6.2.3 Lazy evaluation with query plan

```march
type Plan =
  | Source(DataFrame)
  | Select(Plan, List(String))
  | Filter(Plan, fn(Row) -> Bool)
  | MapColumn(Plan, String, fn(Value) -> Value)
  | GroupBy(Plan, List(String), Agg)
  | Join(Plan, Plan, List(String), JoinKind)
  | SortBy(Plan, List(String), Bool)
  | Limit(Plan, Int)
  | Offset(Plan, Int)

type Agg = Sum | Mean | Count | Min | Max | Std | First | Last

type JoinKind = Inner | Left | Right | Outer
```

`collect(plan) -> DataFrame` materializes the plan. The stream fusion pass can
potentially collapse adjacent `Filter`/`MapColumn` operations.

#### 6.2.4 Row type

Rows are `Map(String, Value)` for ergonomic access by column name. This is slower than
indexed access but simpler for the initial implementation. A future optimization can use
index-based rows after schema is known.

#### 6.2.5 CSV integration

`from_csv(path : String) -> Result(DataFrame, Error)` uses the existing `stdlib/csv.march`
parser. Column types are inferred: try Int → try Float → String.

#### 6.2.6 JSON integration

`from_json(s : String) -> Result(DataFrame, Error)` accepts an array of objects,
inferring column names from keys. `to_json(df : DataFrame) -> String` emits a JSON
array of objects.

March has no JSON stdlib yet. A minimal JSON parser/emitter will be implemented as part
of this feature (or extracted to `stdlib/json.march` for reuse).

### 6.3 API Surface

```march
mod DataFrame do

  type Value = VInt(Int) | VFloat(Float) | VString(String) | VBool(Bool) | VNull
  type Row = Map(String, Value)
  type DataFrame  -- opaque
  type Column(a) = { name : String, data : Array(Value) }

  -- Construction
  pub fn empty() : DataFrame
  pub fn from_rows(rows : List(Row)) : DataFrame
  pub fn from_columns(cols : List((String, Array(Value)))) : DataFrame
  pub fn from_csv(path : String) : Result(DataFrame, String)
  pub fn from_json(s : String) : Result(DataFrame, String)

  -- Inspection
  pub fn schema(df : DataFrame) : List(String)
  pub fn row_count(df : DataFrame) : Int
  pub fn col_count(df : DataFrame) : Int
  pub fn head(df : DataFrame, n : Int) : DataFrame
  pub fn tail(df : DataFrame, n : Int) : DataFrame
  pub fn slice(df : DataFrame, start : Int, len : Int) : DataFrame

  -- Column access
  pub fn get_column(df : DataFrame, name : String) : Result(Array(Value), String)
  pub fn get_float_column(df : DataFrame, name : String) : Result(List(Float), String)
  pub fn get_int_column(df : DataFrame, name : String) : Result(List(Int), String)
  pub fn get_string_column(df : DataFrame, name : String) : Result(List(String), String)
  pub fn add_column(df : DataFrame, name : String, data : Array(Value)) : DataFrame
  pub fn drop_column(df : DataFrame, name : String) : DataFrame
  pub fn rename_column(df : DataFrame, old : String, new : String) : DataFrame

  -- Lazy query building
  pub fn select(df : DataFrame, cols : List(String)) : Plan
  pub fn filter(df : DataFrame, pred : fn(Row) -> Bool) : Plan
  pub fn map_column(df : DataFrame, col : String, f : fn(Value) -> Value) : Plan
  pub fn sort_by(df : DataFrame, cols : List(String), asc : Bool) : Plan
  pub fn limit(df : DataFrame, n : Int) : Plan
  pub fn offset(df : DataFrame, n : Int) : Plan

  -- Plan chaining
  pub fn then_select(plan : Plan, cols : List(String)) : Plan
  pub fn then_filter(plan : Plan, pred : fn(Row) -> Bool) : Plan
  pub fn then_map_column(plan : Plan, col : String, f : fn(Value) -> Value) : Plan
  pub fn then_sort_by(plan : Plan, cols : List(String), asc : Bool) : Plan
  pub fn then_limit(plan : Plan, n : Int) : Plan

  -- Materialization
  pub fn collect(plan : Plan) : DataFrame
  pub fn to_rows(df : DataFrame) : List(Row)

  -- Grouping and aggregation
  pub fn group_by(df : DataFrame, cols : List(String)) : GroupedDf
  pub fn agg(gdf : GroupedDf, ops : List((String, Agg))) : Plan

  -- Joins
  pub fn join(left : DataFrame, right : DataFrame, on : List(String), kind : JoinKind) : Plan

  -- Export
  pub fn to_csv(df : DataFrame) : String
  pub fn to_json(df : DataFrame) : String

  -- Statistics
  pub fn describe(df : DataFrame) : DataFrame  -- summary stats per column
  pub fn value_counts(df : DataFrame, col : String) : DataFrame

end
```

### 6.4 Implementation Phases

#### Phase 4.1 — Column and row types, basic construction

Tests:
```
test: dataframe_empty
  empty() |> row_count == 0
  empty() |> col_count == 0

test: dataframe_from_rows_basic
  let rows = [{"a"=>VInt(1), "b"=>VFloat(1.5)},
              {"a"=>VInt(2), "b"=>VFloat(2.5)}]
  let df = from_rows(rows)
  row_count(df) == 2
  schema(df) == ["a", "b"]

test: dataframe_from_columns
  from_columns([("x", Array.of_list([VInt(1), VInt(2), VInt(3)])),
                ("y", Array.of_list([VFloat(1.0), VFloat(2.0), VFloat(3.0)]))])
  |> row_count == 3

test: dataframe_get_column_exists
  let df = from_columns([("x", data)])
  get_column(df, "x") == Ok(data)

test: dataframe_get_column_missing
  get_column(df, "nonexistent") == Err("column 'nonexistent' not found")

test: dataframe_get_float_column_type_mismatch
  let df = from_columns([("name", [VString("alice"), VString("bob")])])
  get_float_column(df, "name") == Err("column 'name' is not Float")

test: dataframe_add_drop_column
  let df2 = add_column(df, "z", Array.of_list([VBool(True)]))
  col_count(df2) == col_count(df) + 1
  let df3 = drop_column(df2, "z")
  col_count(df3) == col_count(df)
```

#### Phase 4.2 — Head/tail/slice, lazy select/filter

Tests:
```
test: dataframe_head
  let df = from_rows([row1, row2, row3, row4, row5])
  head(df, 3) |> collect |> row_count == 3

test: dataframe_tail
  tail(df, 2) |> collect |> row_count == 2

test: dataframe_slice
  slice(df, 1, 2) |> collect |> row_count == 2
  -- rows at indices 1 and 2

test: dataframe_select_subset
  let df = from_columns([("a", ...), ("b", ...), ("c", ...)])
  select(df, ["a", "c"]) |> collect |> schema == ["a", "c"]

test: dataframe_select_missing_column
  select(df, ["nonexistent"]) |> collect → error OR empty column

test: dataframe_filter
  let df = from_rows([{"x"=>VInt(1)}, {"x"=>VInt(2)}, {"x"=>VInt(3)}])
  filter(df, fn row -> get_int(row, "x") > 1) |> collect |> row_count == 2

test: dataframe_filter_all_pass
  filter(df, fn _ -> True) |> collect |> row_count == row_count(df)

test: dataframe_filter_none_pass
  filter(df, fn _ -> False) |> collect |> row_count == 0

test: dataframe_map_column
  let df = from_columns([("x", [VInt(1), VInt(2), VInt(3)])])
  map_column(df, "x", fn v -> match v do | VInt(n) -> VInt(n * 2) | _ -> v end)
  |> collect |> get_int_column("x") == Ok([2, 4, 6])
```

#### Phase 4.3 — Sort, limit, chaining

Tests:
```
test: dataframe_sort_by_asc
  let df = from_columns([("x", [VInt(3), VInt(1), VInt(2)])])
  sort_by(df, ["x"], True) |> collect |> get_int_column("x") == Ok([1,2,3])

test: dataframe_sort_by_desc
  sort_by(df, ["x"], False) |> collect |> get_int_column("x") == Ok([3,2,1])

test: dataframe_limit
  limit(df, 2) |> collect |> row_count == 2

test: dataframe_offset
  offset(df, 2) |> collect → rows from index 2 onward

test: dataframe_chain_filter_then_select
  -- lazy chain: filter rows, then select columns
  filter(df, pred)
  |> then_select(["a", "b"])
  |> collect
  -- verify both operations applied
```

#### Phase 4.4 — GroupBy and aggregation

Tests:
```
test: dataframe_groupby_count
  let df = from_rows([
    {"cat"=>VString("a"), "val"=>VInt(1)},
    {"cat"=>VString("a"), "val"=>VInt(2)},
    {"cat"=>VString("b"), "val"=>VInt(3)},
  ])
  group_by(df, ["cat"]) |> agg([("val", Count)]) |> collect
  -- "a" group → count=2, "b" group → count=1

test: dataframe_groupby_sum
  group_by(df, ["cat"]) |> agg([("val", Sum)]) |> collect
  -- "a" → 3, "b" → 3

test: dataframe_groupby_mean
  group_by(df, ["cat"]) |> agg([("val", Mean)]) |> collect
  -- "a" → 1.5, "b" → 3.0

test: dataframe_groupby_min_max
  group_by(df, ["cat"]) |> agg([("val", Min), ("val", Max)]) |> collect
```

#### Phase 4.5 — Joins

Tests:
```
test: dataframe_inner_join
  left = from_rows([{"id"=>1,"x"=>10}, {"id"=>2,"x"=>20}, {"id"=>3,"x"=>30}])
  right = from_rows([{"id"=>2,"y"=>200}, {"id"=>3,"y"=>300}, {"id"=>4,"y"=>400}])
  join(left, right, ["id"], Inner) |> collect |> row_count == 2
  -- only ids 2 and 3 match

test: dataframe_left_join
  join(left, right, ["id"], Left) |> collect |> row_count == 3
  -- all left rows; non-matching right columns are VNull

test: dataframe_outer_join
  join(left, right, ["id"], Outer) |> collect |> row_count == 4
  -- all rows from both sides

test: dataframe_join_schema_merged
  join result contains columns from both left and right (except duplicated join keys)
```

#### Phase 4.6 — CSV and JSON I/O

Tests:
```
test: dataframe_from_csv_basic
  -- write a temp CSV, read it back
  let csv_text = "name,age,score\nalice,30,95.5\nbob,25,88.0"
  write to /tmp/test_df.csv
  from_csv("/tmp/test_df.csv") |> schema == ["name", "age", "score"]
  row_count == 2
  get_string_column(df, "name") == Ok(["alice", "bob"])

test: dataframe_from_csv_type_inference
  Int columns parsed as VInt, Float as VFloat, others as VString

test: dataframe_to_csv_roundtrip
  from_csv("x.csv") |> to_csv |> (write to /tmp/out.csv) |> from_csv == df
  (modulo float precision)

test: dataframe_from_json_basic
  let json = "[{\"x\":1,\"y\":2.0},{\"x\":3,\"y\":4.0}]"
  from_json(json) |> row_count == 2
  get_int_column(df, "x") == Ok([1, 3])

test: dataframe_to_json_roundtrip
  from_json(json_str) |> to_json → valid JSON array of objects

test: dataframe_from_json_missing_keys
  -- rows with different keys → VNull for missing
  from_json("[{\"a\":1},{\"b\":2}]") |> get_column(df, "a")
  -- first row has VInt(1), second has VNull
```

#### Phase 4.7 — describe and value_counts

Tests:
```
test: dataframe_describe
  let df = from_columns([("x", [VFloat(1.0), VFloat(2.0), VFloat(3.0)])])
  let desc = describe(df)
  -- desc has rows: count, mean, std, min, 25%, 50%, 75%, max
  -- for column "x": count=3, mean=2.0, std≈1.0, min=1.0, max=3.0

test: dataframe_value_counts
  let df = from_columns([("color", [VString("red"), VString("blue"), VString("red")])])
  value_counts(df, "color") |> row_count == 2
  -- "red" → 2, "blue" → 1
```

### 6.5 Dependencies

- `stdlib/array.march` (persistent vector) — already exists
- `stdlib/map.march` (HAMT-backed Map) — already exists
- `stdlib/csv.march` — already exists
- Stats module (for `describe`) — Feature 2
- Random module (for `sample`) — Feature 3
- Stream fusion (`lib/tir/fusion.ml`) — already implemented; will automatically
  optimize lazy plan chains

### 6.6 Estimated Effort

- Phase 4.1–4.2: 2 days
- Phase 4.3–4.4: 2 days
- Phase 4.5 (joins): 1.5 days
- Phase 4.6 (I/O + JSON parser): 2 days
- Phase 4.7 (describe, value_counts): 0.5 days
- Total: **~8 days**

---

## 7. Feature 5: Parquet reader

### 7.1 Motivation

CSV is ubiquitous but inefficient: no compression, no types, slow to parse. Parquet is
the dominant binary columnar format in production data engineering. A March Parquet
reader allows reading DataFrames from any modern data warehouse without format
conversion.

Two implementation paths exist with different tradeoffs:

| | Path A: Pure March | Path B: Arrow C FFI |
|--|--|--|
| Dependencies | None | FFI (Feature 1) + Apache Arrow C library |
| Feature coverage | Read-only, INT32/INT64/FLOAT/DOUBLE/BYTE_ARRAY | Full Parquet (all types, nested, snappy/gzip/zstd) |
| Implementation complexity | High (Thrift decoding, column encoding, RLE) | Lower (thin wrapper around arrow-c) |
| Portability | Runs anywhere March runs | Requires Arrow installed |
| Performance | March-speed column decoding | Near-native via Arrow |
| Timeline for v1 | ~5 days | ~2 days after FFI is working |

**Recommendation:** Implement Path A first (pure March, read-only, basic types, no
compression). This is maximally portable and exercises the language. Add Path B as an
opt-in when Arrow is available.

### 7.2 Parquet Format Overview (for implementors)

A Parquet file has this structure:

```
[4 bytes magic "PAR1"]
[Row group 0]
  [Column chunk 0.0] [Column chunk 0.1] ... [Column chunk 0.n]
[Row group 1]
  ...
[Row group k]
[File Footer (Thrift-encoded FileMetaData)]
[4 bytes footer length (little-endian int32)]
[4 bytes magic "PAR1"]
```

The footer contains `FileMetaData` which includes schema (column names, types) and
offsets for all column chunks. The Thrift encoding uses a compact binary protocol.

Column encoding types relevant for v1:
- `PLAIN` — raw bytes (INT32: 4 bytes LE, INT64: 8 bytes LE, FLOAT: 4 bytes IEEE754,
  DOUBLE: 8 bytes IEEE754, BYTE_ARRAY: 4-byte length prefix + UTF-8)
- `RLE_DICTIONARY` — dictionary + run-length encoded references
- `DELTA_BINARY_PACKED` — delta-encoded integers (defer to v2)

Definition levels and repetition levels (for nested/nullable columns) require separate
parsing. For v1, assume flat (non-nested) columns with no nulls.

### 7.3 Design Decisions

#### 7.3.1 Path A: Pure March Parquet reader

```march
mod Parquet do

  type ParquetError =
    | InvalidMagic
    | UnsupportedEncoding(String)
    | UnsupportedType(String)
    | ThriftDecodeError(String)
    | IoError(String)

  type Schema = {
    columns : List(ColumnMeta),
    num_rows : Int,
  }

  type ColumnMeta = {
    name : String,
    physical_type : PhysicalType,
    encoding : Encoding,
  }

  type PhysicalType =
    | INT32 | INT64 | FLOAT | DOUBLE | BYTE_ARRAY | BOOLEAN
    -- FIXED_LEN_BYTE_ARRAY and INT96 deferred

  type Encoding =
    | Plain
    | RleDictionary
    | DeltaBinaryPacked  -- deferred

  pub fn read_file(path : String) : Result(DataFrame, ParquetError)
  pub fn read_schema(path : String) : Result(Schema, ParquetError)
  pub fn read_column(path : String, col : String) : Result(Array(Value), ParquetError)

end
```

#### 7.3.2 Thrift compact protocol in pure March

Thrift compact protocol is a tag-value encoding:
- Field header: (delta_field_id << 4) | type_id — one byte if delta fits in 4 bits
- Varint encoding: 7 bits per byte, LSB-first, high bit = more bytes

For v1, hand-decode the minimal subset of `FileMetaData`, `SchemaElement`, `RowGroup`,
and `ColumnChunk` needed. The full Thrift IDL has ~50 message types; we need ~10.

#### 7.3.3 Path B: Apache Arrow C FFI wrapper

After FFI (Feature 1) is working, Path B wraps the Arrow C Data Interface:

```march
[needs Cap(Arrow)]
extern "arrow" : Cap(Arrow) do
  def arrow_read_parquet(path : String, ptr : Ptr(ArrowSchema)) -> Int
  def arrow_array_at(ptr : Ptr(ArrowArray), col : Int) -> Ptr(ArrowArray)
  -- etc.
end

mod Parquet do
  pub fn read_file_arrow(path : String) : Result(DataFrame, String) do
    -- call arrow_ FFI functions and convert ArrowArray to DataFrame columns
  end
end
```

### 7.4 Implementation Phases

#### Phase 5.1 — File structure validation (magic bytes, footer parsing)

Tests (requires a real `.parquet` file in `test/fixtures/`):
```
test: parquet_invalid_magic
  read_file("/dev/null") == Err(InvalidMagic)

test: parquet_valid_magic_detected
  read_file("test/fixtures/simple.parquet") != Err(InvalidMagic)

test: parquet_footer_length_parsed
  -- Verify footer length field is correctly read from last 8 bytes
  read_schema("test/fixtures/simple.parquet") is Ok(_)
```

The test fixture `test/fixtures/simple.parquet` should be a minimal Parquet file
with 3 rows, columns `id:Int64`, `value:Double`, `label:String`. Generate it once
with Python's `pyarrow`:

```python
import pyarrow as pa, pyarrow.parquet as pq
t = pa.table({"id":[1,2,3],"value":[1.5,2.5,3.5],"label":["a","b","c"]})
pq.write_table(t, "test/fixtures/simple.parquet",
               compression="none", use_dictionary=False)
```

This creates a plain-encoded, uncompressed, single-row-group file — the simplest
possible case.

#### Phase 5.2 — Thrift footer decoding

Tests:
```
test: parquet_schema_column_count
  read_schema("test/fixtures/simple.parquet")
  == Ok({columns: 3 entries, num_rows: 3})

test: parquet_schema_column_names
  let Ok(schema) = read_schema("test/fixtures/simple.parquet")
  List.map(fn c -> c.name, schema.columns) == ["id", "value", "label"]

test: parquet_schema_column_types
  types == [INT64, DOUBLE, BYTE_ARRAY]

test: parquet_thrift_varint_decode
  -- Unit test the Thrift varint decoder directly
  decode_varint([0x05]) == (5, 1)             -- 5, 1 byte consumed
  decode_varint([0x80, 0x01]) == (128, 2)    -- 128, 2 bytes consumed
  decode_varint([0xFF, 0x7F]) == (16383, 2)
```

#### Phase 5.3 — Column data reading (INT64, DOUBLE)

Tests:
```
test: parquet_read_int64_column
  read_column("test/fixtures/simple.parquet", "id")
  == Ok([VInt(1), VInt(2), VInt(3)])

test: parquet_read_double_column
  read_column("test/fixtures/simple.parquet", "value")
  == Ok([VFloat(1.5), VFloat(2.5), VFloat(3.5)])
```

#### Phase 5.4 — String column (BYTE_ARRAY), full DataFrame read

Tests:
```
test: parquet_read_string_column
  read_column("test/fixtures/simple.parquet", "label")
  == Ok([VString("a"), VString("b"), VString("c")])

test: parquet_read_file_full
  let Ok(df) = read_file("test/fixtures/simple.parquet")
  row_count(df) == 3
  schema(df) == ["id", "value", "label"]
  get_int_column(df, "id") == Ok([1, 2, 3])

test: parquet_read_larger_file
  -- a 10000-row file with all supported types; verify row_count and spot-check values
```

#### Phase 5.5 — RLE dictionary encoding (common case for strings)

Tests:
```
test: parquet_read_rle_dict_string
  -- a Parquet file with dictionary-encoded string column (the default)
  generate with: pq.write_table(t, "test/fixtures/dict.parquet")
                 -- no use_dictionary=False this time
  read_column("test/fixtures/dict.parquet", "label") == Ok([...correct values...])

test: parquet_rle_decode_unit
  -- Unit test the RLE/bit-packing decoder
  -- Input: 2 runs of length 3 and 2 with values 0 and 1
  decode_rle(bytes, bit_width=1) == [0,0,0,1,1]
```

#### Phase 5.6 — Multiple row groups

Tests:
```
test: parquet_multi_row_group
  -- a file with 3 row groups of 100 rows each
  read_file("test/fixtures/multi_rg.parquet") |> row_count == 300
  -- rows are correctly concatenated in order
```

#### Phase 5.7 — Path B: Arrow FFI wrapper (deferred; requires Feature 1)

```
test: parquet_arrow_ffi_read_same_result
  -- read same file with both Path A and Path B
  read_file(path_a) == read_file_arrow(path_b)  -- same DataFrame
```

### 7.5 Dependencies

- Path A: `stdlib/file.march` (binary file reading) — may need to add
  `File.read_bytes` (raw byte array) if not already present
- Path B: FFI (Feature 1) + Apache Arrow C library
- DataFrame (Feature 4) — both paths return `DataFrame`

### 7.6 Estimated Effort

- Phase 5.1–5.2 (magic + Thrift footer): 2 days
- Phase 5.3–5.4 (column data + full read): 2 days
- Phase 5.5 (RLE dict): 1 day
- Phase 5.6 (multi row group): 0.5 days
- Phase 5.7 (Arrow FFI, optional): 1.5 days (after FFI done)
- Total Path A: **~5.5 days**; Path B (additional): **~1.5 days**

---

## 8. Feature 6: Plotting (SVG output)

### 8.1 Motivation

The data pipeline is useless without visualization. Most plotting libraries require a
GUI, Python, or JavaScript. March's plotting module generates self-contained SVG
strings — pure computation, no external dependencies, renderable in any browser or
embedded in HTML. This matches March's "pure computation" philosophy and the existing
pattern where `to_svg(plot)` is just a string transformation.

### 8.2 Design Decisions

#### 8.2.1 Output format: SVG only

SVG is the right v1 choice because:
- Self-contained (single string output)
- No binary encoding required
- Readable/debuggable (it's XML)
- Renderable in browsers, Inkscape, `display` (ImageMagick)
- Can be embedded in HTML, Markdown (GitHub renders SVG)

PDF and PNG are deferred. A PNG backend could use FFI to `libpng`/`stb_image_write`.

#### 8.2.2 Coordinate system and scaling

All chart elements are computed in "data space" (actual data units) then scaled to
"screen space" (SVG pixel coordinates). The scale functions are:

```
screen_x = margin + (data_x - x_min) / (x_max - x_min) * plot_width
screen_y = margin + plot_height - (data_y - y_min) / (y_max - y_min) * plot_height
```

Axis ticks are computed with a "nice numbers" algorithm (Scott's algorithm or the
Wilkinson method): choose tick intervals from {1, 2, 5} × 10^k that produce 4–10
ticks.

#### 8.2.3 Style system

```march
type Color = { r : Int, g : Int, b : Int }   -- 0–255 per channel
type Style = {
  line_color : Color,
  fill_color : Color,
  line_width : Float,
  point_radius : Float,
  font_size : Float,
  opacity : Float,
}
```

A default color palette cycles through a tasteful set of colors (similar to
matplotlib's default `tab10`).

#### 8.2.4 Chart types

| Chart type | Description |
|--|--|
| Line | Connected data points; one or more series |
| Scatter | Unconnected data points |
| Bar | Vertical or horizontal bars |
| Histogram | Uses Stats.histogram to bin, then renders as bar chart |
| Heatmap | 2D grid of colored cells; used for correlation matrices |

Pie charts are deliberately excluded (hard to read, rarely useful for analysis).

#### 8.2.5 Multi-series support

A `Plot` holds a list of `Series`. Each series has its own style and can be named for
the legend.

```march
let plot = Plot.new()
    |> Plot.add_series(Series.line(xs, ys1, label: "Control"))
    |> Plot.add_series(Series.line(xs, ys2, label: "Treatment"))
    |> Plot.set_title("Comparison")
    |> Plot.set_xlabel("Time (s)")
    |> Plot.set_ylabel("Response")
```

### 8.3 API Surface

```march
mod Plot do

  type Color = { r : Int, g : Int, b : Int }

  type Style = {
    line_color : Color,
    fill_color : Color,
    line_width : Float,
    point_radius : Float,
    font_size : Float,
    opacity : Float,
  }

  type SeriesKind = Line | Scatter | Bar | HistogramSeries | HeatmapSeries

  type Series = {
    kind : SeriesKind,
    xs : List(Float),
    ys : List(Float),
    label : Option(String),
    style : Style,
  }

  type Axis = {
    label : Option(String),
    min : Option(Float),
    max : Option(Float),
    tick_count : Int,
    log_scale : Bool,
  }

  type Plot = {
    title : Option(String),
    series : List(Series),
    x_axis : Axis,
    y_axis : Axis,
    width : Int,
    height : Int,
    margin : Int,
    show_legend : Bool,
    show_grid : Bool,
  }

  -- Construction
  pub fn new() : Plot
  pub fn new_sized(width : Int, height : Int) : Plot

  -- Series factories
  pub fn line_series(xs : List(Float), ys : List(Float)) : Series
  pub fn scatter_series(xs : List(Float), ys : List(Float)) : Series
  pub fn bar_series(labels : List(String), values : List(Float)) : Series
  pub fn histogram_series(values : List(Float), bins : Int) : Series

  -- Plot building (fluent API via pipes)
  pub fn add_series(plot : Plot, s : Series) : Plot
  pub fn add_labeled_series(plot : Plot, s : Series, label : String) : Plot
  pub fn set_title(plot : Plot, t : String) : Plot
  pub fn set_xlabel(plot : Plot, l : String) : Plot
  pub fn set_ylabel(plot : Plot, l : String) : Plot
  pub fn set_x_range(plot : Plot, lo : Float, hi : Float) : Plot
  pub fn set_y_range(plot : Plot, lo : Float, hi : Float) : Plot
  pub fn set_size(plot : Plot, w : Int, h : Int) : Plot
  pub fn with_grid(plot : Plot) : Plot
  pub fn with_legend(plot : Plot) : Plot

  -- Rendering
  pub fn to_svg(plot : Plot) : String
  pub fn save(plot : Plot, path : String) : Result(Unit, String)

  -- Convenience: one-call chart creation
  pub fn quick_line(xs : List(Float), ys : List(Float)) : String
      -- returns SVG directly
  pub fn quick_scatter(xs : List(Float), ys : List(Float)) : String
  pub fn quick_bar(labels : List(String), values : List(Float)) : String
  pub fn quick_histogram(values : List(Float), bins : Int) : String

  -- Heatmap (2D data)
  pub fn heatmap(matrix : List(List(Float)),
                 row_labels : List(String),
                 col_labels : List(String)) : Plot

end
```

### 8.4 Implementation Phases

#### Phase 6.1 — SVG primitive generators

These are pure string-building functions. No chart logic yet.

```march
-- Internal helpers (not exported):
fn svg_rect(x, y, w, h, fill, stroke, stroke_width) : String
fn svg_circle(cx, cy, r, fill, stroke) : String
fn svg_line(x1, y1, x2, y2, stroke, stroke_width) : String
fn svg_polyline(points : List((Float, Float)), stroke, stroke_width) : String
fn svg_text(x, y, text, font_size, anchor) : String
fn svg_wrap(width, height, content : List(String)) : String
```

Tests:
```
test: svg_rect_output
  svg_rect(10, 20, 100, 50, "#ff0000", "#000000", 1.0)
  == "<rect x=\"10\" y=\"20\" width=\"100\" height=\"50\" fill=\"#ff0000\" stroke=\"#000000\" stroke-width=\"1.0\"/>"

test: svg_line_output
  svg_line(0.0, 0.0, 100.0, 100.0, "#000000", 1.0)
  == "<line x1=\"0.0\" y1=\"0.0\" x2=\"100.0\" y2=\"100.0\" stroke=\"#000000\" stroke-width=\"1.0\"/>"

test: svg_text_output
  svg_text(50.0, 50.0, "Hello", 12.0, "middle")
  contains "<text" and "Hello" and "middle"

test: svg_wrap_valid_xml
  svg_wrap(800, 600, ["<rect/>"])
  starts with "<svg" and ends with "</svg>"
  contains "width=\"800\"" and "height=\"600\""

test: svg_polyline_empty_points
  svg_polyline([], "#000", 1.0) is a valid SVG element or empty string
```

#### Phase 6.2 — Coordinate system and axis computation

Tests:
```
test: scale_linear_basic
  let s = make_scale(0.0, 10.0, 0.0, 500.0)
  s(0.0) == 0.0
  s(5.0) == 250.0
  s(10.0) == 500.0

test: scale_linear_inverted_y
  -- SVG y-axis is top-down; data y-axis is bottom-up
  let s = make_y_scale(0.0, 10.0, 400.0, 50.0)  -- screen 50..400, data 0..10
  s(0.0) == 400.0   -- low data value → high screen y (bottom)
  s(10.0) == 50.0   -- high data value → low screen y (top)

test: nice_ticks_basic
  nice_ticks(0.0, 100.0, 5) generates ~5 ticks: [0,20,40,60,80,100] or similar

test: nice_ticks_fractional
  nice_ticks(0.0, 1.0, 5) generates [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

test: nice_ticks_small_range
  nice_ticks(1.234, 1.238, 4) generates ticks with 4-significant-figure precision

test: auto_range_with_padding
  -- infer range from data with 5% padding each side
  auto_range([1.0, 5.0, 3.0]) gives (lo, hi) slightly below 1.0 and above 5.0
```

#### Phase 6.3 — Axis rendering (SVG ticks, grid lines, labels)

Tests:
```
test: render_x_axis
  let svg = render_x_axis(axis, scale, y_bottom=350.0, plot_w=600)
  -- SVG contains tick marks, tick labels, axis label
  contains_count(svg, "<line") >= 4  -- at least 4 ticks
  String.contains(svg, axis.label)   -- axis label present

test: render_y_axis
  similar to x_axis test but for vertical axis

test: render_grid_lines
  let svg = render_grid(x_axis, y_axis, x_scale, y_scale, plot_w, plot_h)
  contains "<line" elements for each tick position
  -- grid lines are dashed and light gray
  String.contains(svg, "stroke-dasharray")

test: axis_no_label_when_not_set
  let axis = { label=None, ... }
  String.contains(render_x_axis(axis, ...), "<text") == False
  -- no text element when label is absent
```

#### Phase 6.4 — Line and scatter charts

Tests:
```
test: line_chart_svg_structure
  let p = new() |> add_series(line_series([1.0,2.0,3.0], [1.0,4.0,9.0])) |> to_svg
  String.contains(p, "<polyline") or String.contains(p, "<path")
  String.contains(p, "<svg")
  String.contains(p, "</svg>")

test: line_chart_point_count
  -- a line series with N points has N-1 segments or 1 polyline with N points
  let n = 5
  let p = new() |> add_series(line_series(range(n), range(n))) |> to_svg
  -- verify N coordinate pairs in polyline points attribute

test: scatter_chart_circle_count
  let n = 3
  let p = new() |> add_series(scatter_series([1.0,2.0,3.0],[1.0,4.0,9.0])) |> to_svg
  count_occurrences(p, "<circle") == n

test: line_chart_title
  let p = new() |> set_title("My Chart") |> add_series(...) |> to_svg
  String.contains(p, "My Chart")

test: line_chart_axis_labels
  let p = new() |> set_xlabel("X") |> set_ylabel("Y") |> add_series(...) |> to_svg
  String.contains(p, ">X<") and String.contains(p, ">Y<")

test: line_chart_two_series
  let p = new()
    |> add_labeled_series(line_series(xs, ys1), "A")
    |> add_labeled_series(line_series(xs, ys2), "B")
    |> with_legend
    |> to_svg
  String.contains(p, ">A<") and String.contains(p, ">B<")
```

#### Phase 6.5 — Bar chart

Tests:
```
test: bar_chart_rect_count
  let labels = ["Q1", "Q2", "Q3", "Q4"]
  let values = [10.0, 25.0, 18.0, 32.0]
  let p = new() |> add_series(bar_series(labels, values)) |> to_svg
  count_occurrences(p, "<rect") >= 4  -- one bar per label

test: bar_chart_labels_present
  String.contains(p, "Q1") and String.contains(p, "Q4")

test: bar_chart_negative_values
  -- bars below the x-axis extend downward
  let p = new() |> add_series(bar_series(["a","b"], [-5.0, 5.0])) |> to_svg
  -- both bars present; one extends above, one below the baseline
  count_occurrences(p, "<rect") >= 2

test: bar_chart_zero_baseline
  -- x-axis is drawn at y=0 even when all values positive
  String.contains(to_svg(bar_chart_from(values)), "<line")  -- baseline present
```

#### Phase 6.6 — Histogram chart

Tests:
```
test: histogram_chart_bins
  let data = generate_n(seed(0), fn r -> normal(r, 0.0, 1.0), 1000)
  let p = new() |> add_series(histogram_series(data, 20)) |> to_svg
  count_occurrences(p, "<rect") == 20  -- one rect per bin

test: histogram_chart_from_stats
  -- verify that histogram_series uses Stats.histogram internally
  -- spot-check: central bins have more rects height than tail bins
  -- (hard to test automatically; visual inspection in dev)

test: quick_histogram_returns_svg
  let svg = quick_histogram([1.0,2.0,3.0,2.0,1.0,2.0], 3)
  String.starts_with(svg, "<svg")
```

#### Phase 6.7 — Heatmap

Tests:
```
test: heatmap_cell_count
  let matrix = [[1.0,2.0,3.0],[4.0,5.0,6.0]]  -- 2 rows, 3 cols
  let p = heatmap(matrix, ["R1","R2"], ["C1","C2","C3"]) |> to_svg
  count_occurrences(p, "<rect") == 6  -- 2×3 cells

test: heatmap_color_range
  -- min value → one color extreme, max value → other color extreme
  -- cells with value 1.0 have one fill color, cells with 6.0 have different fill

test: heatmap_labels_present
  String.contains(to_svg(p), "R1") and String.contains(to_svg(p), "C3")

test: heatmap_correlation_matrix
  -- end-to-end: compute correlation matrix from DataFrame, render as heatmap
  let df = DataFrame.from_csv("test/fixtures/simple.parquet")
  -- compute pairwise correlations
  -- render: all values in [-1, 1], diagonal should be all 1.0
```

#### Phase 6.8 — File saving and quick_ helpers

Tests:
```
test: plot_save_creates_file
  let path = "/tmp/test_plot.svg"
  save(new() |> add_series(line_series([1.0],[1.0])), path)
  File.exists(path) == True
  String.starts_with(File.read(path), "<svg")

test: quick_line_is_valid_svg
  quick_line([1.0,2.0,3.0],[1.0,4.0,9.0]) |> String.starts_with("<svg")

test: quick_bar_is_valid_svg
  quick_bar(["a","b","c"],[10.0,20.0,15.0]) |> String.starts_with("<svg")

test: quick_scatter_is_valid_svg
  quick_scatter([1.0,2.0,3.0],[3.0,1.0,2.0]) |> String.starts_with("<svg")
```

### 8.5 Dependencies

- `stdlib/math.march` (log10 for nice ticks, sqrt for axis scaling) — already exists
- `stdlib/list.march` (map, zip, fold) — already exists
- `stdlib/file.march` (File.write for save) — already exists
- Stats module (for histogram_series bins computation) — Feature 2
- DataFrame (for plot-from-column convenience, heatmap correlation) — Feature 4

### 8.6 Estimated Effort

- Phase 6.1–6.2 (SVG primitives + scaling): 1.5 days
- Phase 6.3 (axis rendering): 1 day
- Phase 6.4 (line + scatter): 1.5 days
- Phase 6.5 (bar chart): 1 day
- Phase 6.6 (histogram): 0.5 days
- Phase 6.7 (heatmap): 1 day
- Phase 6.8 (file save + quick_ helpers): 0.5 days
- Total: **~7 days**

---

## 9. Effort Summary

| Feature | Phases | Est. Days | Priority |
|---------|--------|-----------|----------|
| 1. FFI (extern) | 1.1–1.4 | 5 | P1 — unlocks Parquet FFI path |
| 2. Stats | 2.1–2.8 | 4 | P1 — needed by DataFrame + Plotting |
| 3. Random | 3.1–3.4 | 4 | P2 — needed by DataFrame.sample |
| 4. DataFrame | 4.1–4.7 | 8 | P2 — central data type |
| 5. Parquet (Path A) | 5.1–5.6 | 5.5 | P3 — requires DataFrame |
| 6. Plotting | 6.1–6.8 | 7 | P3 — requires Stats + DataFrame |
| 5. Parquet (Path B FFI) | 5.7 | +1.5 | P4 — requires FFI + DataFrame |
| **Total** | | **~34 days** | |

**Recommended sprint order:**

```
Sprint 1 (1 week):  Stats + Random    (pure March, no deps, fast to verify)
Sprint 2 (1 week):  FFI phases 1.1–1.3 (eval dispatch; LLVM deferred)
Sprint 3 (2 weeks): DataFrame (core operations + I/O)
Sprint 4 (1 week):  Plotting (SVG generators + line/bar/histogram)
Sprint 5 (1 week):  Parquet Path A + FFI LLVM emit (Phase 1.4)
Sprint 6 (3 days):  Parquet Path B (Arrow FFI, if needed)
```

---

## 10. Cross-cutting concerns

### 10.1 Test infrastructure

Each feature's tests live in a dedicated test group:

```
test/test_march.ml  →  stats, random, dataframe, parquet, plotting groups
test/fixtures/      →  simple.parquet, multi_rg.parquet, sample.csv, etc.
```

Test fixtures for Parquet must be generated once with Python/pyarrow and committed
to the repository as binary files. They are small (< 50 KB) and deterministic.

### 10.2 Stdlib organization

New modules are added to `stdlib/` following the existing naming convention:

```
stdlib/stats.march      -- Feature 2
stdlib/random.march     -- Feature 3
stdlib/dataframe.march  -- Feature 4 (or stdlib/dataframe/*.march if large)
stdlib/parquet.march    -- Feature 5
stdlib/plot.march       -- Feature 6
stdlib/json.march       -- needed by Feature 4 (JSON I/O)
```

Each module follows the existing `mod Name do ... end` pattern with `pub` exports.

### 10.3 Stream fusion interaction

The DataFrame lazy evaluation plan (Feature 4) should naturally interact with the
existing stream fusion pass (`lib/tir/fusion.ml`). When `collect()` lowers a plan to
a sequence of `map`/`filter`/`fold` operations on the underlying arrays, the fusion
pass should collapse adjacent map/filter/fold chains into single loops.

No changes to `fusion.ml` are required — the DataFrame implementation just needs to
produce TIR that the existing pass recognizes as fuseable. Verify with benchmarks:

```
bench/dataframe_query.march  -- filter + map_column + group_by on 1M rows
```

### 10.4 FFI safety conventions

The FFI module (Feature 1) establishes conventions that Parquet Path B must follow:

1. Every FFI module is gated behind a `Cap(LibName)` capability
2. Foreign pointer types use `linear Ptr(a)` so they cannot be leaked or double-freed
3. No compound March types are passed through FFI boundaries — only primitives and Ptr
4. Wrapper functions always return `Result(a, FfiError)` when the C function can fail

These conventions are documented in `specs/features/ffi.md` (to be created when Feature 1
is implemented).

### 10.5 Performance expectations

| Feature | Expected perf target |
|---------|----------------------|
| Stats | O(n log n) for sorted operations; O(n) for linear scans |
| Random | > 500M integers/second (xoshiro256** is extremely fast) |
| DataFrame | Filter + map 1M rows < 10 ms (comparable to Polars on warm cache) |
| Parquet | Read 1M row, 5-column file < 500 ms (pure March path) |
| Plotting | to_svg for 10K-point scatter < 100 ms |

The DataFrame perf target requires that stream fusion fires on the generated TIR.
If it doesn't, the DataFrame lazy plan execution will be slow due to intermediate
list allocations.

### 10.6 Documentation

Each module should have:
- Top-level `doc` comments on every `pub fn`
- At least one runnable example in the module header (as a `-- Example:` comment block)
- An entry in `specs/features/` describing the design decisions and source pointers

Following the existing pattern in `stdlib/math.march` and `stdlib/list.march`.
