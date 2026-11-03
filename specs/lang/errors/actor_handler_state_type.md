---
layout: docs
title: "actor_handler_state_type"
permalink: /docs/errors/actor_handler_state_type/
---

# `actor_handler_state_type`: a handler does not return the actor's state

Every `on Msg(..) do … end` handler returns the actor's next state, a value of
the record type its `state` declaration gives. A handler that returns anything
else (one field's new value, `()`, a record with other fields) is rejected.
`{ state with field: value }` builds the new state from the old one, keeping
the fields you don't change.

## A program that triggers it

```march
mod Main do
  needs IO.Console

  actor Total do
    state { sum : Int, count : Int }
    init { sum: 0, count: 0 }
    on Deposit(k : Int) do state.sum + k end
  end

  fn main(_c : Cap(IO.Console)) do
    let t = spawn(Total)
    send(t, Deposit(5))
  end
end
```

## The fix

Return the whole state, with the changed field updated:

```march
mod Main do
  needs IO.Console

  actor Total do
    state { sum : Int, count : Int }
    init { sum: 0, count: 0 }
    on Deposit(k : Int) do { state with sum: state.sum + k } end
  end

  fn main(_c : Cap(IO.Console)) do
    let t = spawn(Total)
    send(t, Deposit(5))
  end
end
```

## Why the rule exists

An actor's state is replaced by its handler's result after each message. If a
handler could return a different type, the next handler would run on a value
that is not the state it was written against.

See also: [the language reference](../actors.md).
