---
layout: docs
title: "division_by_zero"
permalink: /docs/errors/division_by_zero/
---

# `division_by_zero`: a division in a `cap no_panic` module may divide by zero

A module that declares `cap no_panic` promises none of its code panics, and
integer `/` and `%` panic on a zero divisor. So every division there must be
provably by a non-zero value: a non-zero literal, a parameter refined to rule
out zero, or a value an enclosing `if` or match guard has already checked. The
message names the divisor and, when the solver finds one, a value that breaks
it.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  cap no_panic

  type Stats = Stats(Int, Int)

  fn average(s : Stats) : Int do
    match s do
      Stats(total, count) -> total / count
    end
  end

  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(average(Stats(10, 2))))
  end
end
```

`count` comes out of a pattern, so nothing says it is not zero.

## The fix

Guard the division. The checker reads `if` conditions, so the `else` side is
proved:

```march
mod Main do
  needs IO.Console
  cap no_panic

  type Stats = Stats(Int, Int)

  fn average(s : Stats) : Int do
    match s do
      Stats(total, count) -> if count == 0 do 0 else total / count end
    end
  end

  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(average(Stats(10, 2))))
  end
end
```

When the divisor is a function parameter, refining the parameter works too:
`fn ratio(n : Int, d : {v : Int | v != 0}) : Int do n / d end`, and each caller
must then prove its argument is not zero. To keep the zero case as a value
instead, call `Math.checked_div` or `Math.checked_mod`, which return
`Option(Int)`.

## Why the rule exists

`cap no_panic` is a guarantee a caller relies on, so it is checked, not
trusted. A division the checker cannot prove safe is a panic the module
promised not to have.

See also: [refinement types](../refinement-types.md).
