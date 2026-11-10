---
layout: docs
title: "old_misuse"
permalink: /docs/errors/old_misuse/
---

# `old_misuse`: `old` where there is no "before"

`old(e)` means `e` read of the state an actor's message arrived with. It has that meaning
only in a handler's guarantee, `on Msg(…) ensures P do … end`, where there is a state
before the handler runs and one after. This error reports:
- `old(…)` in any other refinement: an `@invariant`, a state field's type, a message
  parameter's type, or a function's parameter or result type;
- `old` in a guarantee written without exactly one argument: `old`, `old()`, `old(a, b)`.

## A program that triggers it

```march
mod Main do
  @invariant(count >= old(count))
  actor Counter do
    state { count : Int }
    init { count: 0 }
    on Inc() do { count: state.count + 1 } end
  end
end
```

## The fix

Say it of the handler that changes the state, as a guarantee:

```march
mod Main do
  actor Counter do
    state { count : Int }
    init { count: 0 }
    on Inc() ensures count >= old(count) do { count: state.count + 1 } end
  end
end
```

An `@invariant` is about every state the actor can hold, one at a time, so it has no
"before". A function's type has no state at all; to relate a result to an argument, name
the argument: `fn inc(x : Int) : {Int | _ > x}`.

## Why the rule exists

Read anywhere else, `old(e)` could only mean `e` itself or nothing, and either reading
would let a contract say less than it appears to. Outside refinements `old` is an ordinary
name, and a program that defines its own function `old` can still call it in refinements.

See also: [Handler guarantees](../actors.md#handler-guarantees-ensures-and-old).
