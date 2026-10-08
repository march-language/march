# `[P2]` A curried lambda type-checks where a two-argument callback is expected

**Logged:** 2026-10-08, split out of
`specs/progress/2026-10-07-range-reduce-curried-callback.md`.

Function types are curried internally (`TArrow` chains), so `b -> a -> b` (the
stdlib's spelling for a two-argument callback, e.g. `List.fold_left`'s `f`) also
unifies with a one-argument lambda that returns a lambda, `fn a -> fn x -> e`.
The interpreter and the compiled code do not curry: the callee calls the
callback with two arguments. `Range.reduce` shipped this way and printed a
pointer compiled and panicked interpreted (`arity mismatch: expected 1 args,
got 2`), with `march --check` clean.

The arity check that rejects a wrong-arity call of a known function does not
cover a lambda checked against an expected function type.

## Repro

```march
mod CL do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(List.fold_left(Cons(1, Cons(2, Nil)), 0, fn a -> fn x -> a + x)))
  end
end
```

Expected: a type error at the lambda (it takes 1 argument where 2 are passed).

## Fix

When a lambda is checked against an expected `TArrow` chain at a position whose
arity is known (a declared parameter's annotation), compare the lambda's
parameter count with the arity the callee will apply, and report the mismatch.
Watch for code that relies on the current leniency: run the stdlib and the
corpus before landing.
