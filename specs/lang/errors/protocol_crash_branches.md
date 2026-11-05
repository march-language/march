---
layout: docs
title: "protocol_crash_branches"
permalink: /docs/errors/protocol_crash_branches/
---

# `protocol_crash_branches`: a protocol with crash branches used as a plain channel

A protocol can say that a role `may crash` and give an `or crash do ...
end` branch for what happens then. Only `@[endpoints]` protocols can run those
branches: the generated role modules watch for the crash and take the branch.
A plain session channel, from `Chan.new` or written as `Chan(Role,
Protocol)`, has no way to notice a crash. Using a protocol with crash branches
that way is this error.

## A program that triggers it

```march
mod Main do
  type L = L
  type I = I
  type C = C

  protocol Logging do
    may crash C
    L -> I : Int
    C -> I : String
      or crash do
        I -> L : String
      end
    I -> L : String
  end

  fn listen(_ch : Chan(I, Logging)) do () end

  fn main() do () end
end
```

`Logging` says `C` may crash, and `listen` takes it as a plain
`Chan(I, Logging)` channel, which cannot run the crash branch.

## The fix

Either drop the crash branches and keep the plain channel, as here, or keep
them, mark the protocol `@[endpoints]`, and write each role with the generated
role modules:

```march
mod Main do
  type L = L
  type I = I
  type C = C

  protocol Logging do
    L -> I : Int
    C -> I : String
    I -> L : String
  end

  fn listen(_ch : Chan(I, Logging)) do () end

  fn main() do () end
end
```

## Why the rule exists

A crash branch is a promise that the receiver handles the sender's crash.
A plain channel cannot keep that promise: it would just wait for a message
that never comes. Refusing the combination keeps the protocol's promise
honest.

See also: [when a role may crash](../choreography.md#when-a-role-may-crash).
