# Declaration-site `mailbox N policy` on an actor

Shipped 2026-09-14. `mailbox N policy` after `init` (before any `supervise`
block). `mailbox` is CONTEXTUAL, not a reserved word: the first cut reserved
it and broke every fixture with `fn mailbox(...)` (the session transport
constructor in `stream_actor.march`); it is now recognised only in that
position, where no other lower-case identifier can start anything, and any
other identifier there gets a parse error naming the three continuations.
The policy by name (`drop_new` 1, `drop_old` 2, `block_sender` 3),
an unknown name a parse error naming the three. AST `actor_mailbox`;
interpreter applies it at spawn (`block_sender` refused there, the call's
message); the lowering fills `Lower_state._actor_mailboxes` in a pre-pass
and wraps each `spawn(Name)` in `actor_set_mailbox_limit(pid, N, policy)`.
Tests: two interpreter cases in `test_stdlib_suite.ml`; native golden
`test/native/mailbox_decl` (the `mailbox_bounded` shape, limit declared).
Docs in both trees and `surface-syntax.md`. The original note follows.


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
