---
layout: docs
title: "send_wrong_actor"
permalink: /docs/errors/send_wrong_actor/
---

# `send_wrong_actor`: a message is sent to a pid of an actor that does not handle it

`send(pid, Msg(..))` must send a message the pid's actor has a handler for.
A pid's type records the actor it was spawned from, so sending `Poke` (a
message of actor `A`) to a pid spawned from actor `B` is rejected. The error
names the pid's actor and the messages it does handle.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  actor Counter do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { state with n: state.n + k } end
  end

  actor Log do
    state { lines : Int }
    init { lines: 0 }
    on Line(s : String) do { state with lines: state.lines + 1 } end
  end

  fn main(_c : Cap(IO.Console)) do
    let log = spawn(Log)
    send(log, Bump(1))
  end
end
```

## The fix

Send the message to a pid of the actor that handles it (or send this actor one
of its own messages):

```march
mod Main do
  needs IO.Console

  actor Counter do
    state { n : Int }
    init { n: 0 }
    on Bump(k : Int) do { state with n: state.n + k } end
  end

  actor Log do
    state { lines : Int }
    init { lines: 0 }
    on Line(s : String) do { state with lines: state.lines + 1 } end
  end

  fn main(_c : Cap(IO.Console)) do
    let counter = spawn(Counter)
    send(counter, Bump(1))
  end
end
```

## Why the rule exists

An actor drops a message it has no handler for. Without this check the send
would compile and the message would silently disappear at run time, which is
the hardest kind of bug to find in a message-passing program.

See also: [the language reference](../actors.md).
