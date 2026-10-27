---
layout: docs
title: "termination_unproved"
permalink: /docs/errors/termination_unproved/
---

# `termination_unproved`: a `@[decreases]` metric is not shown to fall

A function marked `@[decreases(...)]` promises a metric: a number that stays at
least 0 and falls at every recursive call. The checker asks the solver to prove
that at each recursive call, with the guards on the way to the call and the
parameters' refinements as facts. This diagnostic names a call where it could
not, and gives a value of the parameters it could not rule out.

It is a warning, and an error in a `cap verified` module. Recursion without
`@[decreases]` is never warned about; `--termination-report` lists it.

## A program that triggers it

```march
mod Main do
  @[decreases(n)]
  fn down(n : Int) : Int do
    if n == 0 do 0 else down(n - 1) end
  end

  fn main() do
    down(3)
  end
end
```

`down(-1)` calls `down(-2)`, and so on forever: the exit `n == 0` is never
reached from below, and the metric `n` goes negative.

## The fix

Make the exit cover every value the metric must not go below:

```march
mod Main do
  @[decreases(n)]
  fn down(n : Int) : Int do
    if n <= 0 do 0 else down(n - 1) end
  end

  fn main() do
    down(3)
  end
end
```

Refining the parameter to `{Int | _ >= 0}` works too: then every caller must
pass a value that is at least 0, and the recursive call `down(n - 1)` is checked
to pass one.

## Why the rule exists

A metric that can go below 0 proves nothing: any value can fall forever.
That is why every metric component must stay at least 0 where it falls, and why
several components (`@[decreases(m, n)]`) are compared left to right. The
proof is what will let the refinement checker assume a recursive function's
return refinement at its own recursive calls (the termination design,
`specs/2026-10-26-termination-checking-design.md`).

See also: [the language reference](../refinement-types.md), `invalid_decreases`.
