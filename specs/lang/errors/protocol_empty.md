---
layout: docs
title: "protocol_empty"
permalink: /docs/errors/protocol_empty/
---

# `protocol_empty`: a protocol with no steps

A `protocol` lists the messages its roles exchange. One with no steps
describes no conversation at all. This is a warning: the program still builds,
but the protocol cannot be used for anything.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Ping do
  end

  fn main() do () end
end
```

`Ping` names no messages, so there is nothing for a channel to follow.

## The fix

Write the messages the protocol is meant to carry, or delete it:

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Ping do
    Client -> Server : Int
    Server -> Client : Int
  end

  fn main() do () end
end
```

## Why the rule exists

An empty protocol is almost always a declaration that was started and
not finished. It also has no roles, so `Chan.new` and the generated role
modules would refuse it later with a less direct message. The warning points
at the declaration itself.

See also: [declaring a protocol](../session-types.md#declaring-a-protocol).
