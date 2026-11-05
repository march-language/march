---
layout: docs
title: "session_not_closed"
permalink: /docs/errors/session_not_closed/
---

# `session_not_closed`: a finished session channel is dropped without `Chan.close`

When a channel has taken every step of its protocol, it must be passed to
`Chan.close`. A channel that reaches the end and is then never used again is
this error.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Notify do
    Client -> Server : Int
  end

  fn main() do
    let (cc, sc) = Chan.new(Notify)
    let cc2 = Chan.send(cc, 42)
    let (_n, sc2) = Chan.recv(sc)
    Chan.close(sc2)
  end
end
```

After its one send, `cc2` is at the end of `Notify`, but it is never
closed.

## The fix

Close the channel once its last step is done:

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Notify do
    Client -> Server : Int
  end

  fn main() do
    let (cc, sc) = Chan.new(Notify)
    let cc2 = Chan.send(cc, 42)
    Chan.close(cc2)
    let (_n, sc2) = Chan.recv(sc)
    Chan.close(sc2)
  end
end
```

## Why the rule exists

A session channel is linear: it must be used, not forgotten. Closing it
releases the endpoint and tells the runtime the conversation is over. Dropping
it would leak the endpoint.

See also: [the `Chan` API](../session-types.md#the-chan-api).
