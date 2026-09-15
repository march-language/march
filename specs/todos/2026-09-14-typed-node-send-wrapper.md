# `[P3]` `@[endpoints]` over `Node.send`: the generated network transport

**Steps 1–3 shipped 2026-09-15** — `Node.send(peer, to, msg)` exists, with
the codec checked at the call site, the tag minted, and `Pid` refused by the
derive: [[2026-09-15-typed-node-send]]. What remains is step 4 below (the
generator) and the receiver-side dispatch table it needs.

Filed 2026-09-14 as the last open part of
[[2026-09-14-remote-send-to-a-global-pid]] (now a progress record). Every
layer below it exists: `NodeSend.cast` / `cast_from` (bytes on the wire,
the sender recorded for `DELIVERY_FAILED`), `PeerReader` (one reader per
connection), the control/data split, and `GlobalPid`. What a user writes
today is

```march
NodeSend.cast_from(fd, seq, self, target, "App.Ping", Json.encode(ping_to_json(p)))
```

with the type tag a string they must keep in step with the receiver's
dispatch, and the codec a function they must remember exists.

## Surface

```march
Node.send(peer : PeerRegistry.Peer, to : GlobalPid.Pid, msg : m) : Result(Int, NodeSend.SendError)
```

where `m` must have `derive Json` (the codec `@[endpoints]` already uses
over `Bytes`; a `derive Msgpack` would be the later, smaller wire). The
compiler enforces the derive **at the call site**: a missing instance is a
typecheck error naming the type and the site, not the runtime panic
`to_json: cannot determine type` that a generic `to_json` gives today
(the failure [[2026-09-13-generated-code-diagnostics-dropped-at-the-cli]]
recorded).

The type tag is the message type's fully-qualified name, minted by the
compiler (the same name `derive Json for T` registers), so sender and
receiver agree by construction. The receiver side is
`Node.dispatch(peer, frame, table)` where `table` maps type names to
`(pid, decode + constructor)` entries the actor's module builds with a
generated helper — the "a library cannot name an actor's constructors"
rule holds; the generator can.

## What the compiler has to do

1. A typecheck rule for `Node.send`'s third argument: resolve the type,
   require a `Json` instance (the derive registry the typechecker already
   consults for `@[endpoints]` payloads), and record the instance's
   fully-qualified type name on the call for lowering.
2. Lowering: `Node.send(peer, to, msg)` →
   `NodeSend.enqueue(queue_of(peer), next_seq(), to, "<fqn>", Bytes.to_list(Json.encode(T_to_json(msg))))`
   — once [[2026-09-14-credit-based-flow-control]] provides the queue;
   until then `cast_from` on `peer.data_fd`.
3. A `Pid(_)` anywhere in `m` is rejected by the derive (a local pid is
   meaningless on another node); the message carries `GlobalPid.Pid`.
4. `@[endpoints]`'s generator gains a `Node`-transport `Session.Ops`
   builder so the `stream` two-node scenario's hand-written transport
   becomes one generated line.

## Tests

- Reject: `Node.send` of a type without a codec (typecheck error text
  pinned in `@types-check`); a payload with a `Pid(_)` field.
- Accept, both backends: the `stream` scenario's Prod/Cons over
  `Node.send`, trace identical to today's.
- Interpreter unit: the minted type tag equals the derive's registered
  name for a nested-module type.
