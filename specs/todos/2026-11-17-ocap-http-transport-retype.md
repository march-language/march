# ocap: `HttpTransport` / `HttpClient` still fold a refusal into their own error type

Logged 2026-11-17 by ocap phase 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, decision 7).

`HttpTransport.connect` / `request` / `simple_get` and the `HttpClient` functions over them
already dial through the checked `Socket.connect`, so the run-time authority refuses an
out-of-scope host. But they return their pre-phase-1 types, and a refusal arrives as
`HttpTransport.Refused(reason)` (`stdlib/http_transport.march`), not as
`Err(CapError(...))`: a caller cannot tell a refusal from a network failure by type, and
`Authority.describe` cannot render it.

What to do: re-type them to `Result(Result(T, E), CapError)` like the other capability
operations, with the `cap_result_unhandled` fix migrating callers (about 200 call sites).
The call-site inventory is in `specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md`.
