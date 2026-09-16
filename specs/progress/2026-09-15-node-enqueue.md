# `Node.enqueue`: the typed remote send through a NodeQueue

Shipped 2026-09-15. This is step 2's queued half of
[[2026-09-15-remote-actor-dispatch]] ("once
[[2026-09-15-credit-based-flow-control]] provides the queue"), which stays open
for step 4, the `@[endpoints]` Node transport.

## Surface

```march
Node.enqueue(q, to : GlobalPid.Pid, msg : m, policy : NodeQueue.Policy)
  : Result(Int, NodeQueue.EnqueueError)
```

The contract is exactly `Node.send`'s. `m` must `derive Json`, and a missing codec is a
typecheck error at the call site naming `Node.enqueue` and the type
(`specs/lang/types/reject/t241_node_enqueue_no_codec`). The wire tag is the declaration's
qualified name. The result is `Ok(seq)` when the queue admits the frame; a later
`DELIVERY_FAILED` echoes that seq. The errors are the queue's, `Backpressure` and
`NoConnection`, under the chosen `DropNew` / `DropOld` / `BlockSender(ms)` policy.

## Mechanism: one table, two callees

`Node.send` and `Node.enqueue` share every compiler site, keyed on (callee, arity), and
the message is the third argument of both:

- `typecheck.ml` records `("Node.send", 3)` and `("Node.enqueue", 4)` sites;
  `env.node_send_sites` now carries the callee name, so the diagnostics name the call
  the user wrote.
- `Typecheck_caps.check_node_send_sites`: unchanged logic.
- `Json_dispatch.tagged_callee` / `node_send_rewrite`: `Node.enqueue(q, to, msg, p)`
  becomes `Node.enqueue_tagged(q, to, "<tag>", JsonTo$T.to_json(msg), p)`. Trailing
  arguments are kept, so `Node.send`'s rewrite is byte-identical to before.
- `Lower_expr` and the interpreter's `EApp` arm match both names and call the same
  rewrite / `tagged_callee`.

`Node.enqueue_tagged` (stdlib) is `NodeQueue.cast` with the next node seq. The body of
`Node.enqueue` panics if an entry point skipped the table, as `Node.send`'s does.

## Witnesses

- Compiled: `test/native/node_send_typed_loopback` sends a fourth message with
  `Node.enqueue` through a queue on the same connection. The receiver gets seq 4 tagged
  `Msgs.Report` (the table-minted qualified tag) and decodes `Hot(7)`.
- Interpreter (`test/stdlib/test_node.march`): a frame that fits is admitted (`Ok`,
  which the unresolved body cannot produce); one past a 10-byte budget under `DropNew`
  is `Err(Backpressure)`.
- Reject: `t241` (the type corpus is 360/360).
