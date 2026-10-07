---
layout: docs
title: "type_mismatch"
permalink: /docs/errors/type_mismatch/
---

# `type_mismatch`: an expression has a different type than its context requires

The expression underlined has one type and the place it is used needs
another. The message reads "expected `A` but got `B`": `B` is what the
context requires, `A` what the expression produced. A note says where the
requirement comes from (a declared return type, a function argument, an
annotation) and a label points at it.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  fn label(n : Int) : String do
    "item " ++ n
  end

  fn main(_console : Cap(IO.Console)) do
    println(label(3))
  end
end
```

## The fix

Convert the value, or fix whichever side is wrong. For the common
`Int`/`String` case use `int_to_string` / `string_to_int`; March never
converts implicitly.

```march
mod Main do
  needs IO.Console
  fn label(n : Int) : String do
    "item " ++ int_to_string(n)
  end

  fn main(_console : Cap(IO.Console)) do
    println(label(3))
  end
end
```

## Why the rule exists

March has no implicit conversions and no overloading on return type, so
every value has one type and every use states the type it needs. The
mismatch is reported where the two meet, with the origin of the expected
side, so the fix is usually one call.

See also: [the language reference](../type-system.md).
