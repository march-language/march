---
layout: docs
title: "unknown_session_op"
permalink: /docs/errors/unknown_session_op/
---

# `unknown_session_op`: a `Chan.` or `MPST.` call that is not a channel operation

Session channels have a fixed set of operations: `Chan.new`, `send`,
`recv`, `choose`, `offer` and `close`, and for three or more roles
`MPST.new`, `send`, `recv` and `close`. A call to any other name under `Chan.`
or `MPST.`, or to one of these with the wrong number of arguments, is this
error. The message lists the operations.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Echo do
    Client -> Server : Int
    Server -> Client : Int
  end

  fn main() do
    let (cc, sc) = Chan.new(Echo)
    let cc2 = Chan.transmit(cc, 42)
    ()
  end
end
```

There is no `Chan.transmit`. Sending is `Chan.send`.

## The fix

Use the channel operation for the step:

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Echo do
    Client -> Server : Int
    Server -> Client : Int
  end

  fn main() do
    let (cc, sc) = Chan.new(Echo)
    let cc2 = Chan.send(cc, 42)
    let (n, sc2) = Chan.recv(sc)
    let sc3 = Chan.send(sc2, n)
    let (_m, cc3) = Chan.recv(cc2)
    Chan.close(cc3)
    Chan.close(sc3)
  end
end
```

## Why the rule exists

Each channel operation moves the channel's type one step along its
protocol, and the compiler checks each one specially. An operation it does
not know cannot be checked against the protocol.

See also: [the `Chan` API](../session-types.md#the-chan-api).
