---
layout: docs
title: "undeclared_transition"
permalink: /docs/errors/undeclared_transition/
---

# `undeclared_transition`: a function changes a typestate handle's state but is not listed in `transitions`

This is a warning. A module has a `transitions` block for a handle type,
and also a function that takes the handle in one state and returns it in
another, but the block does not list that function. The warning suggests the
entry to add.

## A program that triggers it

```march
mod Main do
  always_linear type Door(s) = Door(Int)
  tag DoorTag
  tag Shut
  tag Ajar

  fn open_door(d : Door(Shut)) : Door(Ajar) do
    match d do Door(n) -> Door(n) end
  end

  fn shut_door(d : Door(Ajar)) : Door(Shut) do
    match d do Door(n) -> Door(n) end
  end

  transitions Door do
    DoorTag: Shut -> Ajar via open_door
  end

  fn main() do
    let d = shut_door(open_door(Door(1)))
    match d do Door(_) -> () end
  end
end
```

`shut_door` moves a `Door` from `Ajar` to `Shut`, but the `transitions`
block lists only `open_door`.

## The fix

Add an entry for the function:

```march
mod Main do
  always_linear type Door(s) = Door(Int)
  tag DoorTag
  tag Shut
  tag Ajar

  fn open_door(d : Door(Shut)) : Door(Ajar) do
    match d do Door(n) -> Door(n) end
  end

  fn shut_door(d : Door(Ajar)) : Door(Shut) do
    match d do Door(n) -> Door(n) end
  end

  transitions Door do
    DoorTag: Shut -> Ajar via open_door
    DoorTag: Ajar -> Shut via shut_door
  end

  fn main() do
    let d = shut_door(open_door(Door(1)))
    match d do Door(_) -> () end
  end
end
```

## Why the rule exists

The `transitions` block is meant to be the full list of how a handle's
state can change. A function that changes it without being listed makes the
list incomplete, so a reader cannot trust it.

See also: [declaring transitions](../capabilities.md#declaring-transitions).
