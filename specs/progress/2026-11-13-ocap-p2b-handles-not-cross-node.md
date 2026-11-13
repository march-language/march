# Handles do not cross nodes (2026-11-13)

Ocap phase 2b, Task 13 of `specs/plans/2026-11-10-ocap-p2-handles-plan.md` (logged as a
todo 2026-11-10, deferred from phase 2a, PR march-language/march#1244). Within a node a
message shares the handle box, as before; across nodes a handle is refused at compile time.

- **One list** of handle types, `Cap_surface_ty.handle_type_spellings`
  (`lib/caps/cap_surface_ty.ml`): the builtin boxes `File.Handle`, `File.Dir`, `Socket`,
  `Listener`, `Process` (exact spelling only; a bare `Handle` is the typestate type) and
  the opaque `Socket` wrappers `UdpSocket`, `TlsConn`, `TlsCtx`, `WsSocket` (bare or
  module-qualified, shown bare, so the message names what the program wrote rather than
  the `Socket` inside). Found by grepping the stdlib for `handle_new(`: every kind 1-9
  box is made under one of these types (the HTTP server's borrowed connection, kind 4, is a
  `Socket`; it declares no handle type of its own). `test_compiler`'s
  `handle_name_tables_agree` pins that every lowered handle box name is in the list.
- **`derive Json`** (`lib/desugar/desugar_derive.ml`, arm after the `Pid` refusal) refuses
  a type whose declaration names a handle, with a label on the handle and the holder
  (field or constructor) named. A type the module declares itself under a handle's name
  (a user's own `type Process`) is exempt (`local_types`). Before this the derive was
  ACCEPTED: the generated encoder fell through to a generic `to_json` on the box.
- **The typed send** (`check_node_send_sites` / `handle_in_message` in
  `lib/typecheck/typecheck_caps.ml`): before the codec check, the message's solved type is
  walked, then every declaration it names (record fields, constructor arguments, the way
  `schema_hash` expands them), so a handle at any depth (inside an un-derived variant, an
  `Option`, a tuple) is found. A user's own `Process` has a qualified identity as a solved
  `TCon`, and in a declaration's surface types `Typecheck_nominal.refers_to_user_decl`
  tells the two apart. `Node.send` / `Node.enqueue` report at the call; an `@[remote]`
  handler reports once, at the handler's annotation. Code `handle_not_sendable` (ACTOR).
- **Message:** "`File.Handle` cannot be sent to another node: a handle names a resource on
  this node." then the site detail, and a note to send a path, an address or a
  `GlobalPid.Pid` of an owning actor instead.
- **Untyped remote path: none exists.** Every cross-node send carries bytes or a
  `JsonValue`: `Node.send_tagged`/`send_tagged_schema` run `Json.to_string(json)` (so the
  payload is a `JsonValue`), `NodeSend.cast*`, `NodeQueue.cast*`, `ClusterNode.send_msg`
  and `NodeCall.call` take `List(Int)`, and the `__rpc_stub` functions
  `march_remote_register` enrolls are user-written `List(Int) -> List(Int)` msgpack stubs.
  `to_json` has no generic implementation (compiled: impl dispatch or a compile error in
  `llvm_calls.ml`; interpreter: `to_json: no Json derive for type ...`), and a local `send`
  to a `Pid` never leaves the node. So there is no serialiser that could meet a
  `MARCH_HANDLE_TAG` cell and no run-time refusal to add.
- Tests: golden `test/errors/handle_not_sendable_1.march`; `test_compiler` "handle types"
  cases `handle_send_direct`, `handle_send_at_depth`, `handle_derive_refused`,
  `handle_remote_actor`, `handle_user_types_send`. Docs: `specs/lang/clustering.md`
  (Sending), `specs/lang/capabilities.md` (Handles need no capability).
