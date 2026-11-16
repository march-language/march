`[P2]` Host scopes, phase 2: bound dependencies' own code, and the phase-1 cuts.

Phase 1 shipped (`specs/progress/2026-11-09-host-scoped-network-capabilities.md`). Open:

- **Scoped `main` grant.** `fn main(c : Cap(IO.NetConnect("api.example.com", methods(get))))`
  bounds the whole program, dependencies included. Without it a dependency's own code
  (an actor it starts, a function nothing of yours calls) is bounded only by its own
  self-declared `needs`.
- **Audit.** Hosts and methods in `forge.caps.lock`, `forge audit`, `forge cap inspect`
  and the embedded capability manifest; a widened host list counts as a widening.
- **Scoped per-function bounds** (`fn f() needs IO.NetConnect("x")`): needs `fn_needs`
  to carry scopes in the AST.
- **Redirect guard through another module.** A scoped module calling another module's
  `HttpClient`-calling helper is refused today (`cap_host_unproven`); the twin rewrite
  would have to clone the helper chain per scope.
- **Opaque connection handles.** Integer fds were forgeable, so handle-taking calls and the
  stdlib server APIs are refused in scoped modules. Unblocked since ocap phase 2b Task 10
  (2026-11-12): the raw descriptor builtins are stdlib-only, so a `Socket` / `Tls.TlsConn` a
  module holds came from a checked open. Until this is done, `Socket.write` (or `Tls.connect`)
  on a socket a scoped module was handed is a `cap_host_unproven` false positive
  (`lib/caps/net_dest.ml` still maps handle operations to `Handle`).
- **Per-role grants** for protocol roles.
- **Call-site spans.** Violations point at the module (post-lowering TIR has no spans).
- **Actor messages to a handed-in pid.** A scoped module sending a message to an actor
  in an unscoped module (pid supplied by `main`) is not checked against the sender's
  scope (review 2026-11-09, I1): a confused-deputy route, documented as a limit.
- **Host-less `@[net_dest]` on a host parameter** is rejected; a host+port judge would
  make TCP wrappers annotatable (review I4).
