`[P3]` # `HttpClient.with_connection` stops keep-alive after one failure (2026-11-11)

Found in review of ocap phase 2b, Task 6 (ruling R13: file, don't fix).

`with_connection(client, url, callback)` opens one `Socket` and hands `callback` a
`do_request` that runs `run_on_scoped(s, ...)` on it. When a request on `s` fails,
`transport_keepalive` closes `s` and retries on a fresh connection from
`reconnect_and_retry`, but that new socket is returned only inside
`transport_keepalive`'s `Ok((socket, resp))` and dropped by `run_on_scoped`. Every later
`do_request` in the same callback still uses the closed `s`: `HttpTransport.request_on` gives
`Err(Closed)` at once, and the request is sent on yet another new connection, which is dropped
too. So after the first failure each request costs a connect, and keep-alive is gone for the
rest of the callback.

Before Task 6 the same path reused the closed descriptor NUMBER, which could by then name
another connection; now it fails safely, but still without keep-alive.

Fix: keep the current socket in mutable state shared by `do_request` (or thread it through
the callback), replacing it with the socket `transport_keepalive` returns.
