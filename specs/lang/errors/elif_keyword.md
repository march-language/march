---
layout: docs
title: "elif_keyword"
permalink: /docs/errors/elif_keyword/
---

# `elif_keyword`: `elif` / `elsif` in an `if` chain

March has no `elif` (or `elsif`). An `else if` is an ordinary `if` nested in
the `else` branch, so each `if` in the chain closes with its own `end`.
There is no single text edit that repairs a chain safely (the extra `end`s
belong at its far end), so this diagnostic carries a note, not a fix.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  fn sign(n : Int) : Int do
    if n > 0 do
      1
    elif n < 0 do
      -1
    else
      0
    end
  end

  fn main(_console : Cap(IO.Console)) do
    println(int_to_string(sign(-3)))
  end
end
```

## The fix

Write `else if`, and close every `if`: a two-branch chain ends `end end`, a
three-branch chain `end end end`.

```march
mod Main do
  needs IO.Console
  fn sign(n : Int) : Int do
    if n > 0 do
      1
    else if n < 0 do
      -1
    else
      0
    end end
  end

  fn main(_console : Cap(IO.Console)) do
    println(int_to_string(sign(-3)))
  end
end
```

## Why the rule exists

Keeping `else if` as plain nesting means the grammar has one `if` form and
no chain-specific rule. The cost is the trailing `end end`, which is why
the parser names `elif` explicitly (it is a plain identifier elsewhere, so
`elif` as a variable still works) and why a chain one `end` short is
reported at the `if` that lacks it.

See also: [the language reference](../surface-syntax.md), `then_keyword`.
