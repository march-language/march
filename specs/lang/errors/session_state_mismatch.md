---
layout: docs
title: "session_state_mismatch"
permalink: /docs/errors/session_state_mismatch/
---

# `session_state_mismatch`: a channel operation at the wrong step of its protocol

A session channel from `Chan.new(P)` follows protocol `P` from one side. Its type
is the step that side is at, and each `Chan.send`, `Chan.recv`, `Chan.choose`,
`Chan.offer` and `Chan.close` moves it one step on. Calling an operation the
protocol does not allow at that step, such as a second send where the protocol
says receive, or a close before the last message, is this error. It says what
the call tries, what the channel must do instead, the steps left on the
channel, and which protocol and role the channel follows.

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
    let cc2 = Chan.send(cc, 42)
    let cc3 = Chan.send(cc2, 43)
    Chan.close(cc3)
    Chan.close(sc)
  end
end
```

After its one send, `Client` must receive the server's reply. It sends again
instead, and `sc` is closed before the server has received or replied.

## The fix

Take each side's steps in the protocol's order:

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

Each side of a session must agree on whose turn it is. A send the peer is not
waiting for, or a close while the peer still expects a message, would deadlock or
lose data at run time. Typing the channel by its protocol step catches the
mismatch at the call that goes out of order.

See also: [the language reference](../choreography.md).
