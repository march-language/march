---
layout: docs
title: "protocol_same_participants"
permalink: /docs/errors/protocol_same_participants/
---

# `protocol_same_participants`: two protocols have the same roles

This is a hint, not an error. Two protocols in the module name exactly the
same roles. That can be on purpose, for example one protocol per direction.
Often, though, it means one conversation was split in two, and the order
between the two halves is no longer checked.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Login do
    Client -> Server : String
    Server -> Client : Bool
  end

  protocol Fetch do
    Client -> Server : Int
    Server -> Client : String
  end

  fn main() do () end
end
```

`Login` and `Fetch` are both between `Client` and `Server`. Nothing
says a client logs in before it fetches.

## The fix

If the two belong to one conversation, write them as one protocol, so the
order between them is part of the contract:

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Account do
    Client -> Server : String
    Server -> Client : Bool
    Client -> Server : Int
    Server -> Client : String
  end

  fn main() do () end
end
```

## Why the rule exists

A protocol only checks the order of the steps inside it. Two separate
protocols between the same roles can run in any order, or one without the
other. The hint asks you to confirm that is what you meant.

See also: [declaring a protocol](../session-types.md#declaring-a-protocol).
