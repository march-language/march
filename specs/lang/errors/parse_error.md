---
layout: docs
title: "parse_error"
permalink: /docs/errors/parse_error/
---

# `parse_error`: a construct is written in a shape the grammar does not accept

The parser recognised a specific mistake: one of the grammar's error
productions fired and chose both the position and the message. The caret
is on the token the message is about; the note under it usually shows the
correct shape. (Contrast `syntax_error`, where the parser could not say what
went wrong.)

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

Rewrite the construct in the shape the note shows. Here: March's `if` uses
`do … else … end`, never `then`.

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

March borrows ML and Elixir syntax, so a few constructs from those
languages (`then`, `elif`, `;` separators, `module`) are common slips. The
grammar has explicit productions for the known ones so the message names
the fix instead of reporting a generic parse failure.

See also: [the language reference](../surface-syntax.md).
