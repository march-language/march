# `SessionNode`: the `Session.Ops` network transport, as a library

Shipped 2026-09-15 as the transport half of step 4 in
[[2026-09-14-typed-node-send-wrapper]]. That todo stays open for `Node.dispatch`, the
generated receiver-side table for typed sends to user actors.

## Decision: a stdlib module, not generated code

The todo planned a generator change: `@[endpoints]` would emit a `Node`-transport
`Session.Ops` builder per protocol. Reading the generator
(`lib/desugar/desugar_endpoints.ml`) and the hand-written transport in
`test/two_node/stream` showed that is unnecessary:
- `Session.Ops` is `register`/`emit`/`suspend`/`close` over endpoint ids (`Int`) and
  encoded messages (`Bytes`, the generated `<P>_Msg.encode`), so a transport never
  names a protocol's constructors.
- The endpoint actor that runs continuations can be library-owned, the way `NodeQueue`
  owns its writer.

The rule "a library cannot name an actor's constructors" applies to routing a typed
`Node.send` to a user actor's handlers. That is `Node.dispatch`, and it still needs the
generator. The graph decision node records the two options.

## Surface (`stdlib/session_node.march`)

```march
let link = SessionNode.open(conn, "node-a", accepted, fn ep -> ...)   -- conn from connect_split / accept_split
let s = Session.attach(io, SessionNode.ops(link))
let _ = drive_role(s, Stream_Prod.register(s, 0))                     -- to its first suspension
SessionNode.serve(link)     -- deliveries until the peer's endpoint closes
SessionNode.finish(link)    -- close data, Bye on control, await the control reader, close control
```

`open` does four things:
1. Spawns the node's `Endpoint` actor.
2. Exchanges endpoint `GlobalPid`s on the control connection. The accepting side
   announces first, and frames are read with `recv_frame_exact`, never over-reading
   into the next frame.
3. Starts the data connection's `NodeQueue`.
4. Spawns the control reader, which handles CREDIT, Bye, and DELIVERY_FAILED (an
   error).

`ops(link)` builds the record:
- `emit` becomes `NodeQueue.cast(..., "SessionNode.Deliver", [to, from, msg])` under
  `DropNew`.
- `suspend` stores the continuation.
- `close` runs `on_close(ep)`, marks the link closed, and queues a Bye.

`serve` reads the data connection and hands each Deliver to the endpoint actor's
mailbox. That counts as consumed, so it sends CREDIT. It stops at the peer's Bye, and a
peer close after a local endpoint has closed is a clean end.

Wire tags: `SessionNode.Hello`, `SessionNode.Deliver`, `SessionNode.Bye`. The inner
delivery is msgpack `[to, from, bin msg]`, since `msg` is already the protocol's JSON
bytes.

## Witness

The two-node `stream` scenario now uses it with unchanged goldens: each node's trace is
still its projection of the in-process `stream_endpoints.expected`. node-a went from 267
to 73 lines and node-b from 250 to 59; what remains is the connection setup and the
role's code. The scenario passed 3/3 locally, and CI runs it through
`scripts/two-node.sh --list`.

There is no interpreter unit test. The transport is sockets and a scheduler end to end,
which the eval-based stdlib harness does not run (the same convention as `NodeQueue`'s
socket paths).
