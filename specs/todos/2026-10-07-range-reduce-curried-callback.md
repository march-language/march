# `Range.reduce` passes a curried callback to `List.fold_left`: wrong result compiled, panic interpreted

**Logged:** 2026-10-07. Found by the TIR verifier's check 2 (type
consistency, `lib/tir/tir_verify.ml`) on its first corpus sweep: a
`Hof_spec` clone of `List.fold_left` calls `Range.reduce`'s lambda's apply
function with 3 arguments when it takes 2.

## Repro

```march
mod RR do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let r = Range.new(1, 5)
    println(int_to_string(Range.reduce(r, 0, fn (acc, x) -> acc + x)))
  end
end
```

- `march --check`: clean.
- interpreted: `arity mismatch: expected 1 args, got 2` at `Range.reduce()`.
- compiled (`--opt 2` and `--no-opt`): prints a pointer-sized integer
  (`4826536673616`), not `15`.
- `MARCH_VERIFY_TIR=1 march --emit-llvm` on any program that instantiates
  `Range.reduce` (a main-less module roots the whole stdlib, so
  `test/native/mainless_prunes_stdlib.march` does): exits 3 with
  `call to $lam…$apply$… passes 3 argument(s); it takes 2`.

## Cause

`stdlib/range.march:116`:

```march
fn reduce(r : {start: Int, stop: Int, step: Int}, acc : b, f : b -> Int -> b) : b do
  List.fold_left(to_list(r), acc, fn a -> fn x -> f(a, x))
end
```

`fold_left` calls its callback with two arguments; this passes a curried
one-argument lambda that returns a lambda. The declared `f : b -> Int -> b`
is curried too, yet the call site passes `fn (acc, x) -> …` and `f(a, x)`
calls it with two arguments.

## Two fixes

1. The stdlib: `f : (b, Int) -> b` and `List.fold_left(to_list(r), acc, fn (a, x) -> f(a, x))`
   (or pass `f` directly). Add a doctest that sums a range.
2. The typechecker accepted all three mismatches because function types are
   curried internally (`TArrow` chains), so `b -> Int -> b` unifies with a
   two-argument callback. The arity check that already rejects wrong-arity
   calls of known functions does not cover a lambda against an expected
   function type. File separately if fixing (1) first.
