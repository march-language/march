# DONE 2026-09-25: `compare` on NaN agrees across backends (NaN == NaN, NaN < everything)

## Resolution

**Where the compiled path was.** `compare` on `Float` lowers to the synthetic
`Ord$Float.compare` (`lib/tir/lower.ml`, `ord_specs`), whose body is a call to the
C runtime's `march_compare_float` (`runtime/march_runtime.c`). The surface
builtin `compare_float` reaches the same symbol (`lib/tir/llvm_builtins.ml`). It
was `(x > y) - (x < y)`, which is 0 whenever either operand is NaN. A generic
(`TVar`) `compare` is monomorphized onto the same `Ord$Float.compare`, so
`fn gcmp(a, b) do compare(a, b) end` took the same path. The WASM runtime
(`runtime/march_runtime_wasm.c`) had its own copy with the same bug.

The only other runtime float ordering, `march_poly_compare` (erased operands),
is reached from codegen only by the erased relational operators
`<`/`<=`/`>`/`>=` (`lib/tir/llvm_emit_arith.ml`, `fallback_cmp`), never by
`compare`: surface `compare` has no `Ord` for `List`/tuples to route through it,
and derived `Ord` compares constructor indices only (documented in
`specs/lang/surface-syntax.md`). Its boxed-float arm and the SIMD lane compare
now call a new `static march_ieee_compare_double` (the old IEEE body), so their
behaviour is unchanged and an erased `nan < 1.0` cannot turn true.

**Fix.** `march_compare_float` (native and WASM) checks NaN first: if either
operand is NaN it returns `isnan(y) - isnan(x)`, i.e. NaN == NaN and NaN below
every other value; otherwise the old IEEE three-way result, so `-0.0` and `0.0`
still compare equal. This is OCaml's `Float.compare`, which the interpreter's
`compare` already used. The interpreter's `compare_float` builtin was IEEE (it
returned 0 for NaN, like the old compiled code), so it now uses `Float.compare`
too, and `compare_float` means the same thing as `compare` on `Float` on both
backends. `==`/`<` and friends are untouched: they lower inline to ordered
`fcmp` and stay IEEE.

**Evidence.** New golden `test/native/compare_nan.march` (+ `.expected`, two
`runtest` diffs in `test/dune`: interpreted AND compiled against one file) with
the table below, `compare_float`, NaN via a type variable (`gcmp`/`glt`/`gle`),
a lexicographic list compare over `compare`, and three `List.sort_by` runs with
a `compare`-based comparator.

- RED (runtime/march_runtime.c and lib/eval/eval_builtins.ml copied back from
  origin/main, rebuilt): compiled differs in 13 lines (every NaN `compare` is 0;
  the sorts leave the NaNs scattered, and re-sorting a sorted list changes it);
  interpreted differs in the 2 `compare_float` lines.
- GREEN: both diffs empty; `native_compare_builtins` still matches.

Not covered here, found while writing the test: compiled `Map` lookups ignore
the caller's comparator, because a parameter named `eq` lowers as the builtin
`==` (a NaN key is never found again). Filed as
`specs/todos/2026-09-24-param-named-eq-lowers-as-builtin.md`.

---

Original todo follows.

## Original title: `[P2]` `compare` on NaN disagrees between backends, and compiled NaN "equals" everything

Filed 2026-09-24. Noticed by the `NativeArray.sort_float` work
(`specs/progress/2026-09-24-native-array-sort-f64.md`), reproduced here.

## Reproduction

```march
mod N do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let nan = float_nan()
    println("compare(nan, 1.0) = " ++ int_to_string(compare(nan, 1.0)))
    println("compare(1.0, nan) = " ++ int_to_string(compare(1.0, nan)))
    println("compare(nan, nan) = " ++ int_to_string(compare(nan, nan)))
    println("nan == nan: " ++ bool_to_string(nan == nan))
    println("nan < 1.0: " ++ bool_to_string(nan < 1.0))
  end
end
```

| | interpreted | `--compile` |
|---|---|---|
| `compare(nan, 1.0)` | -1 | **0** |
| `compare(1.0, nan)` | 1 | **0** |
| `compare(nan, nan)` | 0 | 0 |
| `nan == nan` | false | false |
| `nan < 1.0` | false | false |

(Measured 2026-09-24 on a compiler at origin/main plus the unrelated sort_float change.
Note `0.0 / 0.0` is a "division by zero" runtime error in March; use `float_nan()`.)

## Why it matters

- The backends disagree, so a program's behaviour depends on whether it is compiled.
- Compiled, `compare(nan, x) = 0` for every `x`: NaN compares equal to every value, so
  `compare` is not a consistent ordering once a NaN is present. Anything built on
  `compare` — sorting by a comparator, `Map`/`Set` keyed by floats, `List.sort`,
  `max`/`min` helpers — can silently misplace, lose or duplicate entries. The
  interpreter's result (OCaml's `compare`: NaN below everything, equal to itself) is a
  proper total preorder.

## Recommended fix

Make the compiled `compare` on floats match the interpreter: NaN compares equal to NaN
and less than every non-NaN value (OCaml's `compare` semantics). This is the smallest
change that makes the backends agree and gives `compare` a total preorder. Find the float
case of the compiled comparison (the `compare` lowering in `lib/tir/`, and/or the C
runtime's float compare) and add the NaN handling; keep `==`/`<` IEEE (they are
correct and agree today).

Alternative considered: IEEE 754 `totalOrder` in both backends (what `sort_float` uses).
It also orders `-0.0 < +0.0`, which would make `compare(-0.0, 0.0) = -1` while
`-0.0 == 0.0` is true — a larger semantic change for `compare`'s users. Not recommended
unless `compare` is meant to be exactly the sort order.

## Acceptance

A test (native golden or codegen test) with the table above, run interpreted and
compiled, identical output; plus a `Map`/sort-with-comparator case containing a NaN key
that behaves the same on both backends. Document NaN ordering in the `compare` doc text
(`specs/lang/`, canonical).
