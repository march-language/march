---
layout: docs
title: "cap_param_retired"
permalink: /docs/errors/cap_param_retired/
---

# `cap_param_retired`: a `Cap(IO.X)` value outside `main`

Capability values for IO were retired (object capabilities, phase 7b): a
function no longer receives its authority as an argument, it uses the current
authority, which `main`'s `needs` clause asks for and each operation checks. A
`Cap(IO.X)` type anywhere, a parameter, a return type, a record field or an
annotation, is this error. So is `cap_narrow`, which narrowed such a value
(`cap_narrow_retired`), and a reference to `root_cap` (`root_cap_reference`).

## A program that triggers it

```march
mod Main do
  needs IO.Console

  fn greet(c : Cap(IO.Console), name : String) do
    println("hello " ++ name)
  end

  fn main(c : Cap(IO.Console)) do
    greet(c, "Ada")
  end
end
```

(`main`'s parameter is the deprecated form of its request,
[`deprecated_main_cap`](deprecated_main_cap.md); its fix and this one
together give the program below.)

## The fix

Remove the parameter, and the argument at each call (`forge fix` applies it
when the parameter belongs to a named function in the same file):

```march
mod Main do
  needs IO.Console

  fn greet(name : String) do
    println("hello " ++ name)
  end

  fn main() needs IO.Console do
    greet("Ada")
  end
end
```

To state what a function may use, give it a `needs` clause
(`fn greet(name : String) : () needs IO.Console do`); to run code under less
authority, wrap it in `restrict SCOPE do ... end`. `Cap(Actor.Introspect)`,
`Cap(Session.Live)` and a program's own proof capabilities are not IO
capabilities and stay.

## Why the rule exists

The value granted nothing: it was erased at run time, and whoever held one
could do exactly what the current authority allowed, no more and no less.
Keeping it in signatures suggested a control that did not exist.

See also: [the language reference](../capabilities.md).
