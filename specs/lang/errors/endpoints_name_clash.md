---
layout: docs
title: "endpoints_name_clash"
permalink: /docs/errors/endpoints_name_clash/
---

# `endpoints_name_clash`: two steps of one role get the same generated name

`@[endpoints]` names each role's functions after the steps it takes: a step
labelled `line` gives the sender `send_Line` and the receiver `recv_Line`. Two
steps may share a label only when no single role takes both of them. When one
role would take two steps with the same name, its module would define the same
function twice, and that is this error. It names the protocol, the role, and
the function that would be defined twice.

## A program that triggers it

```march
mod Main do
  needs IO
  needs Session.Live

  @[endpoints]
  protocol Chat do
    line: Client -> Server : String
    reply: Server -> Client : String
    line: Client -> Server : String
  end

  fn main(c : Cap(IO)) do () end
end
```

`Client` sends `line` twice, so `Chat_Client` would get two `send_Line`
functions, and `Chat_Server` two `recv_Line` functions.

## The fix

Give the second step a label of its own:

```march
mod Main do
  needs IO
  needs Session.Live

  @[endpoints]
  protocol Chat do
    line: Client -> Server : String
    reply: Server -> Client : String
    follow_up: Client -> Server : String
  end

  fn main(c : Cap(IO)) do () end
end
```

## Why the rule exists

A role's code takes each step by calling the function named after it, and the
function's state argument says where in the conversation the role is. Two
steps sharing a function would need that one function to accept two different
states and lead to two different next steps, which a single typed function
cannot do. Renaming one step keeps each function tied to one point in the
protocol.

See also: [the language reference](../choreography.md#generated-names).
