---
layout: docs
title: "unknown_protocol"
permalink: /docs/errors/unknown_protocol/
---

# `unknown_protocol`: a protocol name that is not declared

`Chan.new(P)`, `MPST.new(P)` and a `Chan(Role, P)` annotation all name a
protocol. A name with no `protocol` declaration in scope is this error.

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
    let (cc, sc) = Chan.new(Ecko)
    ()
  end
end
```

There is no protocol called `Ecko`. The protocol is `Echo`.

## The fix

Use the name the protocol is declared with:

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

The compiler needs the protocol to type each endpoint. Without a
declaration it has no steps to check the channel against.

See also: [declaring a protocol](../session-types.md#declaring-a-protocol).
