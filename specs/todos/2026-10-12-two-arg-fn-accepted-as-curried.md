# `[P2]` A two-argument function typechecks where a curried one is expected

**Found** 2026-10-12 while writing a leak probe for the sanitizer sweep.

```march
mod Cur do
  needs IO.Console

  pfn ap2(f, x, y) do
    let g = f(x)
    g(y)
  end
  pfn add(a : Int, b : Int) : Int do a + b end

  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(ap2(add, 1, 2)))
  end
end
```

`march --check` accepts it. The interpreter then fails with
`arity mismatch: expected 2 args, got 1` at `f(x)`, and the compiled binary
dies with `march: fatal SIGSEGV si_code=2 addr=0x13` (it calls the two-argument
`add` through the one-argument closure ABI, then calls the returned garbage).

The realistic way to hit it is the stdlib's curried comparators:
`Map.insert(m, k, v, cmp)` documents `cmp : k -> k -> Bool` and calls
`cmp(a)` then the result (`Map.cmp_eq`), but passing
`pfn lt(a : Float, b : Float) : Bool do a < b end` typechecks and crashes the
compiled program on the first insert.

So `a -> (b -> c)` and the two-parameter function type unify somewhere in
`lib/typecheck/typecheck.ml`. Which type a `pfn f(a, b)` gets, and how an
annotation `A -> B -> C` parses (`(A, B) -> R` is a one-TUPLE-argument type),
needs pinning down before a fix; it is a typechecker soundness question, not a
codegen one.
