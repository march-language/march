`[P2]` A parameter list that binds one name twice means different things interpreted and compiled

Filed 2026-10-21 by the multi-arg review fixes
(`specs/progress/2026-10-21-abstract-multiarg-review-fixes.md`, finding C3). The
typechecker accepts a parameter list that names one binder twice, and the two
backends disagree about which argument the body's name is:

```march
mod Dup do
  needs IO.Console
  fn two(a : Int, a : Int) : Int do a end
  fn main(_c : Cap(IO.Console)) : () do
    let h = fn (a, a) -> a
    println(int_to_string(h(1, 2)))     -- interpreter 1, compiled 2
    let g = fn a -> fn a -> a
    let g1 = g(1)
    println(int_to_string(g1(2)))       -- 2 in both (the inner `a` shadows)
    println(int_to_string(two(1, 2)))   -- interpreter 1, compiled 2
  end
end
```

Measured 2026-10-21 at `591160909`: `march dup.march` prints `1 2 1`; `march
--compile -o dupc dup.march && ./dupc` prints `2 2 2`.

The refinement checker no longer reads such a list as a predicate or a
postcondition (it declines: `abstract-refinement-uninstantiated` "binds `x` twice",
and `postcond_of_declared` lends no fact for a relational return naming a doubled
formal), so no proof depends on either answer. The language should pick one: most
likely a hard error, "`a` is bound twice in this parameter list", at least for an
uncurried list (a curried chain's shadowing is ordinary lexical scope). Then the
checker's declines become unreachable for the uncurried case.
