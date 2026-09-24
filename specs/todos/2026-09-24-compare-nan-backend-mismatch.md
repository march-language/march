# `[P2]` `compare` on NaN disagrees between backends, and compiled NaN "equals" everything

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
