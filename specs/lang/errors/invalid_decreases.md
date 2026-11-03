---
layout: docs
title: "invalid_decreases"
permalink: /docs/errors/invalid_decreases/
---

# `invalid_decreases`: a `@[decreases]` metric outside its fragment

`@[decreases(e1, ..., en)]` names a metric for a recursive function. Each
component must be an `Int` expression the solver can read: the function's own
parameters, `Int` literals, `+`, `-`, `*`, `/` by a positive literal, and
measures such as `len` applied to parameters. In a cycle of several functions,
every metric must have the same number of components.

## A program that triggers it

```march
mod Main do
  @[decreases(xs)]
  fn count(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + count(t)
    end
  end

  fn main() do
    count([1, 2, 3])
  end
end
```

`xs` is a list, not a number.

## The fix

Measure it:

```march
mod Main do
  @[decreases(len(xs))]
  fn count(xs : List(Int)) : Int do
    match xs do
      Nil -> 0
      Cons(_, t) -> 1 + count(t)
    end
  end

  fn main() do
    count([1, 2, 3])
  end
end
```

This particular function needs no metric at all: it recurses on a pattern
component of its list, which the checker proves without one.

## Why the rule exists

A metric is checked by the solver, at every recursive call, against the
caller's metric. A name that is not a parameter (a local, say) has no value at
the call to compare with, and a `Float` or a data structure has no order the
check can use.

See also: [the language reference](../refinement-types.md), `termination_unproved`.
