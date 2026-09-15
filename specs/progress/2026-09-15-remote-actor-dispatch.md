# Typed remote sends to user actors: `Node.send`, `Node.enqueue`, `SessionNode`, `@[remote]` (closed)

**Steps 1–3 shipped 2026-09-15** — `Node.send(peer, to, msg)` exists, with
the codec checked at the call site, the tag minted, and `Pid` refused by the
derive: [[2026-09-15-typed-node-send]]. Step 2's queued half shipped the same
day as `Node.enqueue(q, to, msg, policy)`: [[2026-09-15-node-enqueue]]. Step 4's
transport half shipped as the stdlib `SessionNode` rather than generated code:
[[2026-09-15-session-node-transport]]. `Session.Ops` speaks in endpoint ids and
bytes, so the transport names no protocol constructor. What remains is the one piece
that does need the generator: the receiver-side dispatch table below
(`Node.dispatch`), which routes a typed `Node.send` to a USER actor's
constructors.

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
   — once [[2026-09-15-credit-based-flow-control]] provides the queue;
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

---

## Closed 2026-09-15: `@[remote]`, the generated receiver-side dispatch (the last piece)

`Node.dispatch` as sketched above (a table argument) became an actor attribute.
Researching the options settled the shape:
- **A `Node.dispatch(pid, d)` resolved from the pid** cannot be built: `Pid[state]` names
  the state record, not the actor, and two actors with the same state look alike.
- **`derive Remote for Counter`** misuses derive, which looks up types and produces
  interface impls.
- **An attribute on the actor**, generating code next to it, is the natural home: the
  generator can name the actor's constructors, and a library cannot.

### Surface

```march
@[remote]
actor Counter do
  state { total : Int }
  init  { total: 0 }
  on Bump(h : Msgs.Hit) do ... end    -- routable: one parameter, a declared type
  on Reset() do ... end               -- not routable: still an ordinary local message
end

Counter_Remote.dispatch(pid, d) : Result(Bool, String)
```

It returns `Ok(true)` when the delivery was decoded and sent to `pid`'s mailbox, `Ok(false)`
when no handler takes its type, and `Err` when the payload is not JSON or does not decode
as the type its tag names.

### Mechanism

- **Parser** (`parser.mly`, the actor attrs arm): `@[remote]` sets `actor_def.actor_remote`.
- **`Desugar_remote.expand`** (after the endpoints expansion, recursing into nested
  modules) inserts `mod <Actor>_Remote` right AFTER the actor. A nested module sees an
  actor's constructors only once the actor is declared. For each routable handler,
  `dispatch` has one arm: `if Node.accepts(d, fn (_w : T) -> ())`, then `from_json`
  pinned by a `Result(T, Json.DecodeError)` annotation, then `send(pid, Ctor(x))`. The
  generated module is respanned: `from_json` and the tag test resolve per call span.
- **Routable** means exactly one parameter, annotated with a named type that has no
  arguments and is not a builtin (`Int`, `String`, `Bool`, `Float`, `Bytes`, `Unit`,
  `Atom`, `Pid`, `Cap`). An `@[remote]` actor with none is a desugar error
  (`reject/t243`).
- **`Node.accepts(d, witness)`** is the tag test. Desugar cannot know the tag, because the
  qualified name is resolved at typecheck. So it is a third callee in the typed-send table:
  - the typechecker records the site;
  - `check_node_send_sites` takes the message type from the witness's parameter, requires
    a codec (`reject/t242`, whose diagnostic names `@[remote] dispatch`), and records the
    tag;
  - both backends rewrite the call to `Node.tag_is(d, "<tag>")`
    (`Json_dispatch.node_send_rewrite`).

  The sender's tag and the receiver's test therefore come from one resolution.

### A tag bug found on the way

A type declared at the entry module's top level got the tag `RemoteDispatch.Note`, while a
nested one got `Msgs.Hit`. `qualified_name` picks the longest registered key ending in the
short name, and the entry module prebinds its top-level declarations under its own name.
So a top-level type's tag depended on what each program's entry module is called, and two
nodes built from different entry files could never agree on it.

Fix: the sweep takes the entry module's name (`~entry`) and strips its prefix, as the
nested case already did.

### Witnesses

- **`test/native/remote_actor_dispatch`**, run on both backends (`native_` and `interp_`
  rules, identical goldens): deliveries built with `NodeSend`'s own codec for a
  nested-module type (`Msgs.Hit`), a top-level type (`Note`, which the tag fix makes
  deliverable), a type no handler takes (`Ok(false)`), a payload that does not decode,
  and one that is not JSON, plus a non-routable local message.
- **`test/native/node_send_typed_loopback`** now also routes every delivery sent over the
  real socket into a `@[remote]` actor. All four arrive, and it passed 5/5 runs.
- **Reject fixtures** `t242` and `t243` (types corpus 362/362).

Found in passing and filed as a separate task: under the interpreter only, a user function
named `show` hijacks the prelude `println`'s internal `show` call. The test helper was
renamed to avoid it.
