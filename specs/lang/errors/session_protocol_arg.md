---
layout: docs
title: "session_protocol_arg"
permalink: /docs/errors/session_protocol_arg/
---

# `session_protocol_arg`: `Chan.new` or `MPST.new` is not given a protocol name

`Chan.new(P)` and `MPST.new(P)` take the name of a protocol, written bare:
`Chan.new(Echo)`. Any other argument, such as a number or a computed value, is
this error.

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
    let (cc, sc) = Chan.new(1)
    ()
  end
end
```

`1` is not a protocol name.

## The fix

Pass the protocol by name:

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

The compiler reads the protocol at compile time to type each endpoint by
its role. It can only do that when the argument names the protocol directly.

See also: [the `Chan` API](../session-types.md#the-chan-api).
