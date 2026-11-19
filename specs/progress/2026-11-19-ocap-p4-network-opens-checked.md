# `HttpServer` opens and `Udp.resolve` are checked capability operations (2026-11-19)

Ocap phase 4, Task 9 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, PR B). Closes the
`HttpServer`/`Udp.resolve` part of
specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md; the `HttpTransport`/
`HttpClient`/`Tls.https_get` re-typing stays open there.

What changed (stdlib/http_server.march, stdlib/udp.march):

- `HttpServer.listen(server) : Result((), CapError)` and
  `HttpServer.spawn_n(server, n) : Result(Int, CapError)` call
  `Authority.check("IO.NetListen", port)` first, then (in `configure_runtime`, which
  now returns `Result((), CapError)`) the same check on a `plain_listener` port, before
  any TLS, timeout or plain-listener setting reaches the runtime and before anything is
  bound or forked.
- `HttpServer.bind_host(host) : Result((), CapError)` checks `IO.NetListen` on
  `host ++ ":0"` before setting the bind address.
- `Udp.resolve(host, port) : Result(Result(UdpAddr, UdpError), CapError)` checks
  `IO.NetConnect` on `host ++ ":" ++ int_to_string(port)` before the lookup, the target
  `Udp.open_with` and `Socket.connect` check, so a port-scoped grant
  (`IO.NetConnect("dns.example.com:53")`) that admits opening the socket also admits
  resolving its address (fix round 1; the first version checked `host:0`, which such a
  grant refused).
- `plain_listener` stays a builder (`Server -> Server`): it opens nothing, and its port
  is checked where it is bound.
- The raw `http_server_listen` and `http_server_bind_host` builtins join the
  hand-written stdlib-only list (lib/typecheck/typecheck_env.ml), so user code reaches
  them only through the checked wrappers, like `http_server_spawn_n` and
  `http_server_plain_listener` already were.

The return types follow the strict rule of the ocap p1 plan (Task 10 there): an
operation whose old type was not a `Result` gets `Result(T, CapError)`; one already
returning `Result(T, E)` nests.

Targets: `IO.NetListen` is not scopable, so its target appears only in a refusal's text.
`listen`/`spawn_n` name the port, as `Socket.listen` does: the bind address is the
process-wide setting `bind_host` writes, not something the call knows
(specs/todos/2026-11-13-listen-address-parameter.md).

Call sites migrated (each to `Authority.must(...)`, so a refusal panics with its reason
instead of a server silently exiting): examples (6), bench (5), test/native (3),
test/bind_host (2), embedded programs in test/test_https_native.ml (4),
test/test_http_native.ml (1), test/test_stdlib_suite.ml (2), test/test_link_deps.ml (1),
forge/tasks/notebook_server.march (1), demo_app (1), docs (docs/examples.md,
docs/cookbook/http.md, docs/stdlib.md, the march-lang SKILL).

Tests: `test/test_cap_check_coverage.ml` loses the five deferred rows
(`HttpServer.configure_runtime`/`http_server_plain_listener`, `HttpServer.listen`,
`HttpServer.spawn_n`, `HttpServer.bind_host`, `Udp.resolve`); the new conformance fixture
`test/cap_conformance/listen_refused` (`-- GRANT: IO.Console`) shows every one refused by
the launch grant with nothing bound (its `plain_listener` line is refused on the main
port, checked first: `IO.NetListen` takes no scope, so the plain port's check cannot
refuse on its own); `test/cap_conformance/resolve_port_scoped`
(`-- GRANT: IO.Console, IO.NetConnect("localhost:53")`) shows a port-scoped grant allows
`Udp.resolve("localhost", 53)` and refuses port 54; `test/test_stdlib_only.ml` pins the
two new stdlib-only rows.
