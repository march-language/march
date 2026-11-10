---
layout: docs
title: "cap_result_unhandled"
permalink: /docs/errors/cap_result_unhandled/
---

# `cap_result_unhandled`: a capability operation's result is used as its value

Every capability operation (printing, reading the clock, an environment
variable, a file, opening a connection, spawning a task) returns
`Result(T, CapError)`: `Err` when the authority the code runs under refuses
it. This error reports a place that wants the `T` itself, for example a
function declared `: ()` whose last line is a `println`, or `unix_time_ms()`
used in arithmetic. The fix, which `forge fix` applies, follows from the
position: a line `()` after a unit result on a line of its own,
`Authority.ignore(...)` around a unit result anywhere else, and
`Authority.must(...)` around a value, which panics if the operation is refused.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  fn greet(name : String) : () do
    println("hello, " ++ name)
  end

  fn main(_c : Cap(IO.Console)) do
    greet("world")
  end
end
```

## The fix

Discard the result when the effect is all that matters (a call on its own
line already does; the declared `()` needs a `()` after it), or handle the
refusal:

```march
mod Main do
  needs IO.Console

  fn greet(name : String) : () do
    println("hello, " ++ name)
    ()
  end

  fn main(_c : Cap(IO.Console)) do
    greet("world")
  end
end
```

## Why the rule exists

Authority is given, not declared: code runs with what its caller allows, and an
operation outside that is refused as a value, never a crash or a silent no-op,
so a library that handles errors carries on. Using the value directly would
hide that the operation can be refused; the diagnostic makes the choice
explicit, and `forge fix` makes it for code written before.

See also: [the language reference](../capabilities.md).
