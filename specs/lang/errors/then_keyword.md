---
layout: docs
title: "then_keyword"
permalink: /docs/errors/then_keyword/
---

# `then_keyword`: `if … then` instead of `if … do`

March's `if` opens its first branch with `do`, never `then`. The caret is on
the `then`, and the fix replaces it with `do`.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  fn sign(n : Int) : Int do
    if n > 0 then 1 else 0 end
  end

  fn main(_console : Cap(IO.Console)) do
    println(int_to_string(sign(3)))
  end
end
```

## The fix

Replace `then` with `do`. `forge fix` and the editor's quick fix apply it.

```march
mod Main do
  needs IO.Console
  fn sign(n : Int) : Int do
    if n > 0 do 1 else 0 end
  end

  fn main(_console : Cap(IO.Console)) do
    println(int_to_string(sign(3)))
  end
end
```

## Why the rule exists

`then` is the ML/OCaml spelling. March uses one block form, `do … end`,
for every construct that takes a body, so an `if` branch is written the
same way as a function body or a `match` arm block. The grammar has an
explicit production for `then` so the message names the fix instead of
reporting a generic parse failure.

See also: [the language reference](../surface-syntax.md), `elif_keyword`.
