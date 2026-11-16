# Refinement checker: Float operations by their IEEE meaning, and NaN vocabulary (2026-11-15)

Landed 2026-11-15 on `claude/refine-floats`.

## Why

No Float law could be proved. A reflected function's Float operations were opaque symbols
(reflection D9), so the checker could not see that `if a < b do a else b end` returns something
`<= a`, and a predicate had no way to say "not NaN", which almost every Float law needs
(`min(a, b) <= a` is false at `a = NaN`). Found while adding laws to `stdlib/math.march`, where
the Float functions were the uncovered half.

## What

1. **Float operators in a body are defined, not opaque.** Each `|r:float:op|` symbol is now a
   `define-fun` in the query preamble with its IEEE body (`Reflect_state.float_def`):
   `fp.add`/`fp.sub`/`fp.mul`/`fp.div` with `RNE`, `fp.neg`, and `fp.lt`/`fp.leq`/`fp.gt`/
   `fp.geq`. That is what the program runs: binary64, round-to-nearest-even, comparisons false on
   NaN, in the compiled code (`fcmp olt` and friends, no fast-math flags on these operators), the
   interpreter and the JS target. `==` at Float in a body stays the opaque program equality.
   The undeclared-symbol guard (`Refine_reflect.declared_logic_symbols`) accepts a `define-fun`.
2. **Bit-precise queries get the main resource limit.** A stage-2 query whose preamble defines a
   Float operator (`Solver.uses_fp_ops`) runs at the main rlimit (3M) instead of the stage-2 one
   (50k): `dbl(a) <= 5.0` from `a <= 1.0` needs about 500k steps (30 ms), and a comparison-only
   `min(a, b) <= b` ran out at 50k too.
3. **NaN vocabulary.** New SMT terms `FpNaN`/`FpInf` (`fp.isNaN`/`fp.isInfinite`). Predicate
   words `is_nan(x)`, `is_infinite(x)`, `is_finite(x)` (neither), and the program builtins
   `float_is_nan`/`float_is_infinite`, in predicates and in reflected bodies (both added to the
   reflection table, so a function that guards on them reflects).

## Tests

`test/test_refine_lemma.ml`, group `reflect-lemma`:
- `float_body_ieee`: `hk2(0.5) == 1` (a fact that depends on `0.5 < 1.0`) and
  `twice(f) <= 0.5` for `0 <= f <= 0.25` prove. Before, `float_body_red` asserted the first did
  NOT prove; that assertion pinned the opaque encoding and was replaced.
- `float_body_red`: `same(f, f)` (NaN), `twice(f) == twice(f)` (NaN), `hk2(1.5) == 1` (false)
  and `twice(f) > f` for `f >= 0` (false at 0) do not prove.
- `float_ieee_laws`: `min_f`, `clamp_f`, `abs_f` and a `float_is_nan` guard prove under
  `!is_nan`/`is_finite` hypotheses; `float_ieee_red`: the same laws without them do not, nor does
  `is_finite(x)` from `!is_nan(x)` (an infinity is not NaN).
- `float_ieee_callsite`: `need_fin(1.5)` and a bounded `y` are proved finite, `need_inf(2.0)` is
  reported violated, and `!is_nan` follows from `_ <= 1.0`.

## Not done

- Arithmetic inside a predicate (`{Float | _ +. 1.0 > 0.0}`) is still skipped (the user chose
  to do the body encoding and the vocabulary first).
- A theorem false only at NaN is reported unproved, not false: the counterexample is not
  confirmed by execution, so the definite-failure stance keeps it quiet.
- `==` between computed Floats in a body is still opaque; it could be `fp.eq` (the runtime's
  `fcmp oeq` and OCaml's float `=` agree with it).
- The stdlib `Math` Float functions (`abs`, `min_float`, `max_float`, `clamp_float`, `sqrt`) can
  now carry laws; not added here.
