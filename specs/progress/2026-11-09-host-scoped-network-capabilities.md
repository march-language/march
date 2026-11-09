`[P2]` Host-scoped network capabilities: `needs IO.NetConnect("example.com")` — phase 1 DONE (2026-11-09).

Design: `specs/2026-11-09-host-scoped-network-capabilities-design.md`.
Plan: `specs/plans/2026-11-09-host-scoped-network-capabilities-plan.md`.

## What shipped

- Host scopes on `IO.NetConnect` (host, host:port, `*.suffix`, IP literal), with
  `methods(get, head, post, put, patch, delete, options)` and `no_redirects` options;
  parser, tree-sitter and formatter support (options stored in the scope string as
  `"<host>;<option>;..."`).
- `lib/caps/host_scope.ml` (algebra), `lib/caps/net_dest.ml` (where each network
  builtin's destination comes from; `@[net_dest(param)]` for functions).
- `lib/tir/net_scope.ml`: the compile-time check on post-lowering TIR (fail-closed;
  follows calls into other modules; checks `@[net_dest]` honesty) and the rewrite of a
  scoped module's redirect-capable `HttpClient` calls to private `*_scoped` twins.
- `HttpClient` run-time guard: request host and method after request steps, redirect
  targets, `no_redirects` (`OutOfScope`, `MethodRefused`, `RedirectRefused`).
- Tests: `test/test_host_scope.ml` (algebra, declarations, OCaml-vs-March matcher and URL
  parser differential), `test/test_cap_net_scope.ml` (end to end through `--compile`),
  `test/stdlib/test_http_client.march`.

Follow-ups: `specs/todos/2026-11-09-host-scope-phase-2.md`.
