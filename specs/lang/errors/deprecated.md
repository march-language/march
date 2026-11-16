---
layout: docs
title: "deprecated"
permalink: /docs/errors/deprecated/
---

# `deprecated`: a use of a function its author has deprecated

A function marked `@[deprecated("...")]` still works. Every use of it from
outside the module that declares it gets this warning, which carries the
author's message: usually the name of the replacement. A warning does not
change the exit status, so the program still compiles and runs.

## A program that triggers it

```march
mod Main do
  mod Temperature do
    @[deprecated("use `Temperature.to_fahrenheit` instead")]
    fn c_to_f(c : Int) : Int do
      to_fahrenheit(c)
    end

    fn to_fahrenheit(c : Int) : Int do
      c * 9 / 5 + 32
    end
  end

  fn main() : Int do
    Temperature.c_to_f(100)
  end
end
```

## The fix

Do what the message says. Here that is calling the replacement:

```march
mod Main do
  mod Temperature do
    @[deprecated("use `Temperature.to_fahrenheit` instead")]
    fn c_to_f(c : Int) : Int do
      to_fahrenheit(c)
    end

    fn to_fahrenheit(c : Int) : Int do
      c * 9 / 5 + 32
    end
  end

  fn main() : Int do
    Temperature.to_fahrenheit(100)
  end
end
```

## What counts as a use

Any reference to the function from outside its module: a call, a pipe into it,
passing it as a value, and a call through a name brought in with `use` or
`alias`. Each use gets its own warning, at the use.

A use inside the declaring module, or inside a module nested in it, does not
warn. The module that deprecates a function usually still has to call it, and
the old name is often implemented in terms of the new one or the other way
round.

## Marking a function deprecated

The attribute takes one string, the message, and goes directly above the `fn`
or `pfn` (after a `doc` string, if there is one):

```march
mod Temperature do
  doc "Converts Celsius to Fahrenheit."
  @[deprecated("use `Temperature.to_fahrenheit` instead")]
  fn c_to_f(c : Int) : Int do
    to_fahrenheit(c)
  end

  fn to_fahrenheit(c : Int) : Int do
    c * 9 / 5 + 32
  end
end
```

The message is required. Write what the caller should do instead, since it is
the whole text of the warning they see. `@[deprecated]` marks functions only;
on a `type` or a `mod` it is a parse error.

## Why the rule exists

Removing a function breaks every caller at once. Deprecating it first gives
them a release in which their code still builds and the compiler tells them
what to change. The compatibility policy says how long a deprecated function
stays before it can be removed.

See also: [the compatibility policy](../compatibility.md).
