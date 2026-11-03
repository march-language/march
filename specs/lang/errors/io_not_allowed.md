---
layout: docs
title: "io_not_allowed"
permalink: /docs/errors/io_not_allowed/
---

# `io_not_allowed`: a `migrate_state` function performs IO

An actor module's `<actor>_migrate_state` function turns the state of a
running actor into the state the new code expects, during a hot code upgrade.
It must be IO-free: no capability-needing calls, directly or through the
functions it calls.

## A program that triggers it

```march
mod Counter do
  needs IO.Console

  actor CounterActor do
    state { count : Int }
    init { count: 0 }
    on Inc(x : Int) do { count: state.count + x } end
  end

  fn counter_migrate_state(old : Int) : Int do
    println("upgrading")
    old + 1
  end
end
```

## The fix

Compute the new state only; log from a handler once the actor runs the new
code:

```march
mod Counter do
  needs IO.Console

  actor CounterActor do
    state { count : Int }
    init { count: 0 }
    on Inc(x : Int) do { count: state.count + x } end
  end

  fn counter_migrate_state(old : Int) : Int do
    old + 1
  end
end
```

## Why the rule exists

Migration runs inside the upgrade window, after the old code stops and before
the actor takes messages again. IO there can block or fail halfway, leaving the
actor neither on the old state nor the new one, and it would run again on every
retry of the upgrade.

See also: [the language reference](../actors.md).
