# `Node.send(peer, to, msg)`: the typed remote send, shipped

Shipped 2026-09-15. Closes steps 1–3 of
[[2026-09-14-typed-node-send-wrapper]] (the todo is trimmed to its step 4,
the `@[endpoints]` generator's `Node` transport). Design record:
[[2026-09-14-remote-send-to-a-global-pid]].

## What a user writes

```march
mod Msgs do
  type Ping = { n : Int, who : String }
  derive Json for Ping
end
...
Node.send(peer, target, ping)      -- Result(Int, NodeSend.SendError); Ok(seq)
```

No type tag, no codec. The compiler supplies both:

- **Codec, checked at the call site.** `msg`'s type must `derive Json`.
  A missing codec is a typecheck error naming the type and the site
  (`reject/t239`), not the run-time `to_json: cannot determine type`.
- **Type tag, minted.** The wire `type_tag` is the message type's name as
  the typechecker resolves it, module-qualified where the declaration is
  (`Msgs.Ping` for a type in nested `mod Msgs` of the entry file; an
  imported library's type is `Lib.Msgs.Ping`). Two nodes compiled against
  the same declaration mint the same string by construction. For
  cross-program agreement, declare message types in a shared library module
  — the entry module's own name is unwrapped, so a type declared in one
  program's entry file and imported by the other would differ.
- **`Pid` refused by the derive.** `derive Json` for a type with a local
  `Pid` anywhere in it is an error at the declaration (`reject/t240`),
  alongside the existing `Cap` refusal; carry a `GlobalPid.Pid`.

Receiving is the caller's (`NodeSend.serve_one` / `PeerReader`): compare
`d.type_tag`, decode with `Node.payload(d)` and a `from_json` pinned to the
hosted type — dispatch the typechecker already does.

## Mechanism

- `stdlib/node.march`: `send` (a real stdlib fn whose body panics
  "not resolved by the compiler" — never reached), `send_tagged(peer, to,
  tag, json)` (one seq space per process; the peer's data connection when it
  has one, else its control connection), `payload(d)`.
- `Typecheck`: the `Node.send` three-argument application is inferred as
  written, demoted to monomorphic, and recorded in `env.node_send_sites`.
  `Typecheck_caps.check_node_send_sites` (end of module, fails CLOSED)
  resolves the message type (`json_dispatch_head`, split out of
  `json_dispatch_target`), requires a `JsonTo` impl for it via the new
  shared `env.json_codecs` list (a nested module's `impls` are not exported
  to its parent, but a derived codec is a module-wide fact for both
  backends), and records the qualified name in `March_ast.Json_dispatch`
  under the call's span — the same side channel `from_json` uses.
- Both backends rewrite off that entry, through one helper
  (`Json_dispatch.node_send_rewrite`): `Lower_expr` lowers the rewritten
  `Node.send_tagged(peer, to, "<tag>", JsonTo$T.to_json(msg))`; `Eval`
  takes the encoder straight out of `impl_tbl ("JsonTo", T)`. The
  interpreter also runs UNCHECKED programs (the stdlib March test harness
  never typechecks), where the table is empty: there it names the type from
  the value, as the generic `to_json` builtin does, and the tag is the
  runtime (short) name. Only a value neither can name reaches `send`'s
  panicking body.
- Parser: `fn_decl_name ::= lower_name | "send"` at every `fn`/`pfn`
  production, so a module can declare `fn send`; the bare call stays the
  actor primitive; menhir conflict count unchanged (11). `parse/p37`.

## Two holes this exposed and closed

- **`derive` inside a nested module was a silent no-op.** `Desugar` only
  expanded `DDeriving` at the top level; a nested one reached the
  typechecker's "should not reach here" arm and returned the env, so
  `derive Json for T` in `mod Inner` generated nothing and the first
  `from_json` to `T` failed at run time. `expand_level` now recurses, with
  the nested level's declarations resolved first.
- **`send` could not be declared.** See the parser note above.

## Tests

- `test/native/node_send_typed_loopback.march` (compiled, dune rule): three
  typed sends of nested-module types over a loopback TCP pair; the receiver
  prints the minted tag and the decoded value. Compiled only: the interpreter
  parks on the loopback accept, as every socket fixture here does.
- `test/stdlib/test_node.march` (interpreter): a typed send on a dead
  connection is `Err(NoConnection)` — reaching it at all proves the
  rewrite ran, since `send`'s own body panics; plus `payload` round-trip.
- `reject/t239`, `reject/t240` (`@types-check`), `parse/p37`
  (`@grammar-check`).

## Left open

Step 4 of the todo: the `@[endpoints]` generator emitting a `Node`-transport
`Session.Ops` so the `stream` scenario's hand-written transport becomes one
generated line. And the receiver-side `Node.dispatch(peer, frame, table)`
sketched in the design, which needs the generator too (a library cannot name
an actor's constructors).
