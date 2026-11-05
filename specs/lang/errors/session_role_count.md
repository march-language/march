---
layout: docs
title: "session_role_count"
permalink: /docs/errors/session_role_count/
---

# `session_role_count`: `Chan.new` or `MPST.new` used with the wrong number of roles

`Chan.new` is for protocols with exactly two roles and returns two
endpoints. `MPST.new` is for protocols with three or more and returns one
endpoint per role. Calling one with a protocol that has a different number of
roles is this error. The message says how many roles the protocol has and
which function to use.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server
  type Logger = Logger

  protocol Relay do
    Client -> Server : String
    Server -> Logger : String
    Logger -> Client : Int
  end

  fn main() do
    let (cc, sc) = Chan.new(Relay)
    ()
  end
end
```

`Relay` has three roles, `Client`, `Logger` and `Server`, but
`Chan.new` only makes two endpoints.

## The fix

Use `MPST.new`. It returns one endpoint per role, in alphabetical order
of the role names, and `MPST.send` and `MPST.recv` name the other role at each
step:

```march
mod Main do
  type Client = Client
  type Server = Server
  type Logger = Logger

  protocol Relay do
    Client -> Server : String
    Server -> Logger : String
    Logger -> Client : Int
  end

  fn main() do
    let (cc, lc, sc) = MPST.new(Relay)
    let cc2 = MPST.send(cc, Server, "hello")
    let (msg, sc2) = MPST.recv(sc, Client)
    let sc3 = MPST.send(sc2, Logger, msg)
    let (_text, lc2) = MPST.recv(lc, Server)
    let lc3 = MPST.send(lc2, Client, 1)
    let (_n, cc3) = MPST.recv(cc2, Logger)
    MPST.close(cc3)
    MPST.close(sc3)
    MPST.close(lc3)
  end
end
```

## Why the rule exists

Two endpoints from a three-role protocol would not be duals of each other,
and the third role would have no endpoint at all. Refusing the call keeps each
endpoint matched to a role.

See also: [the `Chan` API](../session-types.md#the-chan-api).
