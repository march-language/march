---
layout: docs
title: "deprecated_main_cap"
permalink: /docs/errors/deprecated_main_cap/
---

# `deprecated_main_cap`: `main` asks for authority with `Cap` parameters

A program asks for the authority it runs with in `main`'s `needs` clause.
Before capability values were retired (object capabilities, phase 7b) it
asked with `Cap` parameters on `main`, such as `fn main(c : Cap(IO.Console))`.
That form still works for one release, with this warning, and asks for exactly
the same authority as the clause. It will be removed in the next release.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  fn main(c : Cap(IO.Console)) do
    println("hello")
  end
end
```

## The fix

Drop the parameters and name the same capabilities in a `needs` clause
(`forge fix` applies it):

```march
mod Main do
  needs IO.Console

  fn main() needs IO.Console do
    println("hello")
  end
end
```

A function that received one of `main`'s capabilities as an argument loses
that parameter too: see [`cap_param_retired`](cap_param_retired.md).

## Why the rule exists

A `Cap(IO.X)` value is erased at run time and grants nothing: since the
current authority replaced it, every operation checks what `main` asked for,
and `restrict` and grants narrow it. A parameter that looks like it carries
authority, but does not, misleads the reader.

See also: [the language reference](../capabilities.md).
