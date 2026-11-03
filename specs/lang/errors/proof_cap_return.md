---
layout: docs
title: "proof_cap_return"
permalink: /docs/errors/proof_cap_return/
---

# `proof_cap_return`: a function outside a proof capability's module returns one

`proof cap P` in module `Db` declares a capability that stands for a fact
`Db` has established (a migration ran, a token was checked). Only `Db`'s own
public functions may construct a `Cap(Db.P)`. A function in another module
that returns one, by minting it or by laundering another capability into it,
is rejected.

## A program that triggers it

```march
mod Main do
  needs IO
  mod Db do
    proof cap Ready
  end

  mod App do
    needs IO
    needs Db.Ready

    fn pretend(c : Cap(IO)) : Cap(Db.Ready) do mint_cap(c) end
  end

  fn main(_c : Cap(IO)) do
    ()
  end
end
```

## The fix

Get the proof from `Db`, which owns it, and pass it through:

```march
mod Main do
  needs IO
  mod Db do
    proof cap Ready
    needs IO

    fn open_db(c : Cap(IO)) : Cap(Db.Ready) do mint_cap(c) end
  end

  mod App do
    needs Db.Ready

    fn use_db(r : Cap(Db.Ready)) : Cap(Db.Ready) do r end
  end

  fn main(_c : Cap(IO)) do
    ()
  end
end
```

## Why the rule exists

A proof capability is only worth something if holding one means the fact is
true. If any module could return one, a caller could not tell a `Cap(Db.Ready)`
that `Db` issued after doing the work from one made up elsewhere.

See also: [the language reference](../capabilities.md).
