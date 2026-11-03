---
layout: docs
title: "cap_deserialize"
permalink: /docs/errors/cap_deserialize/
---

# `cap_deserialize`: a capability is serialized or decoded

A `Cap(..)` value cannot go through `to_json`, `from_json` or a derived codec,
directly or inside a record, variant or message. Decoding one would make
authority out of bytes; encoding one would hand it to whoever reads them.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  fn main(c : Cap(IO.Console)) do
    println(to_json(c))
  end
end
```

## The fix

Keep the capability out of the data. Serialize the values you need, and pass
the capability itself as a parameter:

```march
mod Main do
  needs IO.Console

  fn main(_c : Cap(IO.Console)) do
    println(to_json(42))
  end
end
```

## Why the rule exists

A capability is unforgeable: the only way to get one is to be given it by a
caller that holds it, which is what makes `main`'s grant a bound on the
program. A capability that could be decoded from a file or a network message
could be forged by anyone who can write that file or send that message.

See also: [the language reference](../capabilities.md).
