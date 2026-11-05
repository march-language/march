---
layout: docs
title: "supervise_field_missing"
permalink: /docs/errors/supervise_field_missing/
---

# `supervise_field_missing`: a supervised child's field is not in the state

Each child line of a `supervise` block, `Worker worker`, names the child actor
and the supervisor's state field that holds the child's current pid. The
supervisor writes the pid there when it starts the child and again after each
restart, so the field must be one its `state { … }` declares.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  actor Worker do
    state { n : Int }
    init { n: 0 }
    on Tick() do { state with n: state.n + 1 } end
  end

  actor Pool do
    state { worker : Int }
    init { worker: 0 }
    supervise do
      strategy one_for_one
      max_restarts 5 within 30
      Worker wroker
    end
  end

  fn main(_c : Cap(IO.Console)) do
    let _ = spawn(Pool)
  end
end
```

## The fix

Name a field the state declares, or add the field:

```march
mod Main do
  needs IO.Console

  actor Worker do
    state { n : Int }
    init { n: 0 }
    on Tick() do { state with n: state.n + 1 } end
  end

  actor Pool do
    state { worker : Int }
    init { worker: 0 }
    supervise do
      strategy one_for_one
      max_restarts 5 within 30
      Worker worker
    end
  end

  fn main(_c : Cap(IO.Console)) do
    let _ = spawn(Pool)
  end
end
```

## Why the rule exists

A restart gives the child a new pid. Keeping it in a named state field is how
the supervisor's own handlers reach the current instance; a field that does
not exist has nowhere to keep it.

See also: [Supervision](../supervision.md).
