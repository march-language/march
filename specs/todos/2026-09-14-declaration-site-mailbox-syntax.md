# `[P3]` Declaration-site `mailbox N policy` on an actor

Filed 2026-09-14, split out of [[2026-09-14-distributed-plane-known-gaps]]
(item C there; item 4 of [[2026-08-11-actor-hardening-distributed-plane]]).

Today a bounded mailbox is set after the fact, per spawn site:
`Actor.set_queue_limit(pid, n, policy)` (`stdlib/actor.march`, over the
`actor_set_mailbox_limit` builtin). The runtime primitive exists on both
backends (the interpreter refuses `block_sender`, see the known-gaps file).

## What is missing

A declaration on the actor itself:

```march
actor Worker do
  mailbox 1000 drop_old
  state { ... }
  ...
end
```

so the bound is a property of the actor type, not something every spawn site
must remember. A parser + desugar slice: the clause lowers to an
`actor_set_mailbox_limit(pid, N, policy)` call after each `spawn(Worker)`
(the desugar knows the actor name at the spawn site). The policy names are
the three `Actor.set_queue_limit` accepts (`drop_new`, `drop_old`,
`block_sender`).

Not blocking anything; do it when a fixture wants it.
