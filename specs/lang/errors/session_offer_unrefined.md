---
layout: docs
title: "session_offer_unrefined"
permalink: /docs/errors/session_offer_unrefined/
---

# `session_offer_unrefined`: a channel from `Chan.offer` is used before matching on the label

`Chan.offer(ch)` returns the peer's chosen label and the channel. When the
protocol's branches go on with different steps, the channel's next step
depends on that label. Using the channel before matching on the label is this
error, because the compiler cannot tell which branch's steps it follows.

## A program that triggers it

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Lookup do
    choose by Server:
      ok  -> Server -> Client : Int
      err -> Server -> Client : String
    end
  end

  fn main() do
    let (cc, sc) = Chan.new(Lookup)
    let sc2 = Chan.choose(sc, :ok)
    Chan.close(Chan.send(sc2, 7))
    let (lbl, cc2) = Chan.offer(cc)
    let (n, cc3) = Chan.recv(cc2)
    Chan.close(cc3)
  end
end
```

`cc2` came from `Chan.offer`. The `:ok` branch sends an `Int` and the
`:err` branch sends a `String`, so `Chan.recv(cc2)` cannot know which to
expect.

## The fix

Match on the label first, and use the channel inside each arm, where its
next step is known:

```march
mod Main do
  type Client = Client
  type Server = Server

  protocol Lookup do
    choose by Server:
      ok  -> Server -> Client : Int
      err -> Server -> Client : String
    end
  end

  fn main() do
    let (cc, sc) = Chan.new(Lookup)
    let sc2 = Chan.choose(sc, :ok)
    Chan.close(Chan.send(sc2, 7))
    let (lbl, cc2) = Chan.offer(cc)
    match lbl do
      :ok ->
        let (_n, cc3) = Chan.recv(cc2)
        Chan.close(cc3)
      :err ->
        let (_msg, cc3) = Chan.recv(cc2)
        Chan.close(cc3)
    end
  end
end
```

## Why the rule exists

Receiving with the wrong branch's type would read data as the wrong type
at run time. Matching on the label first lets each arm check the channel
against the branch the peer actually chose.

See also: [choice: `choose` and `offer`](../session-types.md#choice-choose-and-offer).
