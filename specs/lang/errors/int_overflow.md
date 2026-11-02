---
layout: docs
title: "int_overflow"
permalink: /docs/errors/int_overflow/
---

# `int_overflow`: Int arithmetic in a `cap no_panic` module is not shown to stay in range

`+`, `-`, `*` and unary `-` on `Int` panic when the result leaves
[-2^62, 2^62). A module declared `cap no_panic` promises none of its code can
panic, so the checker asks the solver to prove each such operator stays in
range, using the parameters' refinements, the guards on the way to it and the
`let` values in scope. This diagnostic names an operator where it could not,
and gives a value it could not rule out when the solver found one.

The checker already knows every `Int` the program holds is in range (a value
outside it would have panicked where it was computed), so `x - 1` under
`x >= 0` and `x + 1` under `x < n` need nothing more. Float arithmetic never
traps and is never reported.

## A program that triggers it

```march
mod Counter do
  cap no_panic

  fn next(n : Int) : Int do
    n + 1
  end
end
```

`next(4611686018427387903)` panics with `attempt to add with overflow`.

## How to fix it

Bound the operand, with a refinement or a guard:

```march
mod Counter do
  cap no_panic

  fn next(n : {v : Int | v < 1000000}) : Int do
    n + 1
  end

  fn next_below(n : Int, limit : Int) : Int do
    if n < limit do n + 1 else n end
  end
end
```

Or, when wrapping modulo 2^63 is what you want (a hash, a checksum), or the
value is bounded by something the checker cannot see (a byte offset into the
input), spell it with the wrapping builtin, which never panics:

```march
mod Counter do
  cap no_panic

  fn next(n : Int) : Int do
    int_wrapping_add(n, 1)
  end
end
```

`int_wrapping_sub` and `int_wrapping_mul` cover `-` and `*`;
`int_wrapping_sub(0, x)` is a wrapping negation. See
[Int width and overflow]({{ site.baseurl }}/docs/types/#int-width-and-overflow).
