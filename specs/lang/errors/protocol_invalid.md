---
layout: docs
title: "protocol_invalid"
permalink: /docs/errors/protocol_invalid/
---

# `protocol_invalid`: a protocol is not well formed

Some protocols can be written but not run. A step after a `loop` at the
same level can never be reached, because the loop repeats forever. A step
after `stop` inside a loop can never be reached either. A `stop` outside any
loop has no effect. A role cannot send a message to itself. Each of these is
this error. The message says which rule the step breaks and, for a loop, shows
the loop that never ends.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Ticker do
    loop do
      Server -> Client : Int
    end
    Client -> Server : Bool
  end

  fn main() do () end
end
```

The `loop` repeats forever, so `Client -> Server : Bool` after it can
never run.

## The fix

Decide how the loop ends. Here `Client` chooses on each round whether to
go on or stop, and `stop` leaves the loop:

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Ticker do
    loop do
      Server -> Client : Int
      choose by Client:
        more -> Client -> Server : Bool
        done -> Client -> Server : Bool
                stop
      end
    end
  end

  fn main() do () end
end
```

The same holds inside a `choose`. The steps written after a `choose` run at
the end of EVERY branch, so when one branch ends in a `loop` (or `stop`), they
can never run in that branch. The message names the branches that can reach
them; move the steps there, after each one's last step. A branch with several
steps lists them on the lines after its label, indented, with no `do`/`end`:

```
  choose by S:
    more -> loop do S -> C : Int end
    done ->
      S -> C : Bool
      C -> S : Bool
  end
```

## Why the rule exists

A protocol is a contract both sides are checked against. A step that can
never run is either dead or a sign the loop was meant to end. Accepting it
would let each side believe the conversation continues past a point it never
reaches.

See also: [repetition: `loop`](../session-types.md#repetition-loop).
