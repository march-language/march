---
layout: docs
title: "duplicate_protocol"
permalink: /docs/errors/duplicate_protocol/
---

# `duplicate_protocol`: two protocols in one module share a name

A `protocol` declaration gives a name to a conversation. Each name may be
declared once per module. A second `protocol` with a name already in use is
this error, reported at the second declaration.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Echo do
    Client -> Server : Int
    Server -> Client : Int
  end

  protocol Echo do
    Client -> Server : String
    Server -> Client : String
  end

  fn main() do () end
end
```

Both declarations are called `Echo`. A `Chan.new(Echo)` or a `Chan(Client,
Echo)` annotation could mean either one.

## The fix

Give each protocol its own name. If the second one was meant to replace the
first, delete the first:

```march
mod Main do
  type Client = Client
  type Server = Server
  type Logger = Logger

  protocol Echo do
    Client -> Server : Int
    Server -> Client : Int
  end

  protocol Audit do
    Server -> Logger : String
    Logger -> Server : Bool
  end

  fn main() do () end
end
```

## Why the rule exists

A protocol name is how channels, annotations and generated role modules
refer to the conversation. Two protocols under one name would leave every one
of those references ambiguous, so the compiler refuses the second declaration
instead of picking one.

See also: [declaring a protocol](../session-types.md#declaring-a-protocol).
