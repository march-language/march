# Network opens not yet returning Result(T, CapError): deferred to ocap phase 2

Logged 2026-11-10 by ocap phase 1 (specs/plans/2026-11-10-ocap-p1-result-plan.md,
Task 10). Phase 1 made `Socket.connect`, `Socket.connect_timeout`,
`Socket.with_connection` and `Dns.resolve`/`resolve_one` check their target and
return `Result(Result(_, E), CapError)`. These still do neither:

- ~~`Udp.open_with` (and `open`, `open_sharded`)~~ (done at the phase 2b merge,
  2026-11-11: specs/progress/2026-11-11-ocap-p2b-merge-p1-wrapping.md), `Udp.resolve`, `Udp.connect`,
  `Udp.send_batch`, `Udp.send_batch_connected`, `Udp.send_many`;
- ~~`Tls.client_ctx`, `Tls.server_ctx`~~ (done at the phase 2b merge), `Tls.https_get`;
- `HttpTransport.connect`, `request`, `simple_get` (they now dial through the checked
  `Socket.connect`; a refusal is folded into `Refused(reason)` until they are re-typed) (and the private
  `request_plain`, `request_https_with_context` that dial), so `HttpClient.*`;
- `HttpServer.listen`, `spawn_n`, `bind_host`, `plain_listener`.

Why deferred: every one of them opens a handle (a UDP socket, a TLS context, an
HTTP connection, a listener) that ocap phase 2 re-types as an opaque handle, and
the HTTP stack sits on those. Re-typing them here and again in phase 2 doubles
the churn for users of `HttpClient` (about 200 call sites).

What remains: in phase 2, each of these checks its target with
`Authority.check` (IO.NetConnect / IO.NetListen / IO.NetConnect.TLS) and
returns `Result(Result(Handle, E), CapError)` by the owner's strict rule
(2026-11-10); `HttpError` loses `OutOfScope`, `MethodRefused` and
`PathRefused`, which move to the outer `CapError` (`ByModNeeds`).
test/test_cap_check_coverage.ml lists them with this file as the reason; its
allowlist rows go when they are done.
