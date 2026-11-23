# ocap: `HttpTransport` / `HttpClient` / `Tls.https_get` still fold a refusal into their own error type

Logged 2026-11-10 by ocap phase 1 and again 2026-11-17 by ocap phase 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, decision 7).

`HttpTransport.connect` / `request` / `simple_get` and the `HttpClient` functions over them
already dial through the checked `Socket.connect`, so the run-time authority refuses an
out-of-scope host. But they return their pre-phase-1 types, and a refusal arrives as
`HttpTransport.Refused(reason)` (`stdlib/http_transport.march`), not as
`Err(CapError(...))`: a caller cannot tell a refusal from a network failure by type, and
`Authority.describe` cannot render it.

What to do: re-type them to `Result(Result(T, E), CapError)` like the other capability
operations, with the `cap_result_unhandled` fix migrating callers (about 200 call sites).
`Tls.https_get` is in the same state: it dials through the checked `Socket.connect`
(`specs/progress/2026-11-13-tls-https-get-checked-dial.md`), returns its single Result and folds
a refusal into `TlsHandshakeFailed`. Re-type it with the others.

With the re-typing, `HttpError` loses `OutOfScope`, `MethodRefused` and `PathRefused`, which
move to the outer `CapError` (`ByModNeeds`), by the owner's strict rule of 2026-11-10.

Functions to re-type: `HttpTransport.connect`, `request`, `simple_get` (and the private
`request_plain` and `request_https_with_context`, which dial), every `HttpClient` function over
them, and `Tls.https_get`.

This file was trimmed on 2026-11-22 to what is still open, and absorbed
`2026-11-17-ocap-http-transport-retype.md` (the same item, logged again by phase 4). The file
name is historical: `stdlib/http_transport.march` and `stdlib/tls.march` cite it. Every other
open it once listed is done (`Udp.*` and the `Tls` contexts at the phase 2b merge,
`HttpServer.*` and `Udp.resolve` in phase 4,
`specs/progress/2026-11-19-ocap-p4-network-opens-checked.md`); the history is in git.
