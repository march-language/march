---
layout: docs
title: "spawn_not_actor"
permalink: /docs/errors/spawn_not_actor/
---

# `spawn_not_actor`: `spawn` names something that is not an actor

`spawn(A)` starts a new instance of the actor declared as `actor A do … end`,
and a supervise block's child line `A field` does the same for a supervisor.
The name must be an actor's. A function, a type's constructor or one of an
actor's messages is rejected, saying what the name is instead.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  actor Counter do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { state with n: state.n + k } end
  end

  fn main(_c : Cap(IO.Console)) do
    let p = spawn(Bump)
    send(p, Bump(1))
  end
end
```

## The fix

Spawn the actor, and send it the message:

```march
mod Main do
  needs IO.Console

  actor Counter do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { state with n: state.n + k } end
  end

  fn main(_c : Cap(IO.Console)) do
    let p = spawn(Counter)
    send(p, Bump(1))
  end
end
```

## Why the rule exists

Both backends start an actor from its declaration, chosen by name when the
program is compiled; there is no actor value to compute at run time. A name
that is not an actor has no declaration to start.

See also: [the language reference](../actors.md).
