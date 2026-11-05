---
layout: docs
title: "session_type_mismatch"
permalink: /docs/errors/session_type_mismatch/
---

# `session_type_mismatch`: a channel at one protocol step is used where another step is expected

A session channel's type includes the step of the protocol it is at. When
a channel is passed where a different step is expected, such as to a function
whose parameter is the start of the protocol, the two do not match. The
message shows the step that was expected and the step the channel is at.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Echo do
    Client -> Server : Int
    Server -> Client : Int
  end

  fn ask(ch : Chan(Client, Echo)) : Int do
    let ch2 = Chan.send(ch, 1)
    let (n, ch3) = Chan.recv(ch2)
    Chan.close(ch3)
    n
  end

  fn main() do
    let (cc, sc) = Chan.new(Echo)
    let cc2 = Chan.send(cc, 42)
    let n = ask(cc2)
    ()
  end
end
```

`ask` takes a `Client` channel at the start of `Echo`, so it can send
first. `cc2` has already sent, so it is at the receive step.

## The fix

Pass the channel at the step the function expects. Here `ask` does both
the send and the receive, so give it the fresh channel:

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Echo do
    Client -> Server : Int
    Server -> Client : Int
  end

  fn ask(ch : Chan(Client, Echo)) : Int do
    let ch2 = Chan.send(ch, 1)
    let (n, ch3) = Chan.recv(ch2)
    Chan.close(ch3)
    n
  end

  fn main() do
    let (cc, sc) = Chan.new(Echo)
    let n = ask(cc)
    ()
  end
end
```

## Why the rule exists

A function that takes a channel takes over its remaining steps. Given a
channel further along, it would repeat a step the peer is not waiting for.
Matching the step at the call keeps both sides in order.

See also: [each role's view](../session-types.md#each-roles-view).
