---
layout: docs
title: "invalid_reflect"
permalink: /docs/errors/invalid_reflect/
---

# `invalid_reflect`: a `@[reflect]` that cannot hold

The refinement checker reflects every function it can: pure, total, terminating and first-order.
It doesn't need to be asked. `@[reflect]` does not turn reflection on. It **asserts** that the
function is reflected, so a later edit that breaks that (a `println`, a `panic`, a call of
something that isn't reflected) is an error here, not a quiet loss of every proof that used it.

`@[reflect(fuel: N)]` also sets how far the checker follows chains of this function's calls when a
proof needs more than one step (the default is 2). `N` is between 1 and 8.

This error is reported when:
- the function is not reflected, and the message names the first reason;
- the fuel is outside 1 to 8 (`@[opaque]`, not fuel 0, is how a function is kept out of the logic);
- the attribute has an argument other than `fuel: N`.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  @[reflect]
  fn noisy(n : Int) : Int do
    println("computing")
    n + 1
  end

  fn main(_cap : Cap(IO.Console)) : Int do
    noisy(1)
  end
end
```

`noisy` prints, so it has an effect, and a function with an effect cannot be part of the logic.

## The fix

Remove the effect, or remove `@[reflect]` if the function is not meant to be used in proofs:

```march
mod Main do
  @[reflect]
  fn inc(n : Int) : Int do
    n + 1
  end

  fn main() : Int do
    inc(1)
  end
end
```

## Why the rule exists

Reflection is automatic, so a function can stop being reflected without anyone noticing, and every
proof that used its definition then turns into a skip. `@[reflect]` lets the author say "this must
stay in the logic", and the compiler holds the code to it.

See also: [the language reference](../refinement-types.md), [the lemmas guide](../lemmas.md), `invalid_measure`, `reflect_conflict`.
