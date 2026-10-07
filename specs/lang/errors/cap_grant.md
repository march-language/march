---
layout: docs
title: "cap_grant"
permalink: /docs/errors/cap_grant/
---

# `cap_grant`: `main` performs IO but declares no grant

The program performs IO (here, printing), but `main` takes no capability
parameter. In March a program is granted exactly the capabilities `main`
declares as parameters; a `main` with none is granted nothing, so any IO
reached from it is an error.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  fn main() do
    println("hello")
  end
end
```

## The fix

Give `main` a parameter for the capability the program actually uses. The
compiler's `help:` line names it, and `forge fix` can insert it. Granting the
whole lattice with `fn main(cap : Cap(IO))` also works, but the narrow grant
documents (and bounds) what the program can do.

```march
mod Main do
  needs IO.Console
  fn main(_console : Cap(IO.Console)) do
    println("hello")
  end
end
```

## Why the rule exists

The grant on `main` is a ceiling on the whole program: a dependency that
tries to open a socket in a program granted only `IO.Console` is rejected at
compile time. That only means something if a program with no grant really
can do nothing, so undeclared IO is an error rather than an implicit `Cap(IO)`.

See also: [the language reference](../capabilities.md).
