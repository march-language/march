---
layout: docs
title: "codec_missing"
permalink: /docs/errors/codec_missing/
---

# `codec_missing`: a value crosses the wire without a JSON codec

Sending a value to another node (`Node.send`, a remote actor's message) encodes
it as JSON. Its type needs a codec, which `derive Json for T` provides. This
error names the type that has none.

## A program that triggers it

```march
mod Main do
  needs IO.Console
  needs IO.NetConnect
  needs IO.Mut

  type Job = { id : Int }

  -- A `Peer` comes from the cluster layer; user code cannot build one.
  fn ship(peer : Peer) do
    let job : Job = { id: 7 }
    let _ = Node.send(peer, GlobalPid.make("w", 1, 1), job)
    ()
  end

  fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect), _m : Cap(IO.Mut)) do
    ()
  end
end
```

## The fix

Derive the codec next to the type's declaration:

```march
mod Main do
  needs IO.Console
  needs IO.NetConnect
  needs IO.Mut

  type Job = { id : Int }
  derive Json for Job

  -- A `Peer` comes from the cluster layer; user code cannot build one.
  fn ship(peer : Peer) do
    let job : Job = { id: 7 }
    let _ = Node.send(peer, GlobalPid.make("w", 1, 1), job)
    ()
  end

  fn main(_c : Cap(IO.Console), _n : Cap(IO.NetConnect), _m : Cap(IO.Mut)) do
    ()
  end
end
```

## Why the rule exists

The receiver decodes with the same codec, and the codec fixes the wire format
both sides agree on. Picking an encoding implicitly would make a type's
representation change silently when its definition does.

See also: [the language reference](../clustering.md).
