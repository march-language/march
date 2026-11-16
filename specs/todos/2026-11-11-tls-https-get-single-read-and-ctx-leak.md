`[P2]` `Tls.https_get` reads the response once and never frees its TLS context (2026-11-11)

Two faults in `https_get_raw`.
1. It calls `read(conn, 1048576)` once. One read returns at most one TLS record's worth of data, so a response that spans several records comes back truncated, with `Ok`. The doc string notes this.
2. It builds a context with `client_ctx` and never calls `ctx_free` on any path. `tls_client_ctx` returns the raw `SSL_CTX*` as an Int (runtime/march_tls.c, `march_tls_client_ctx`, `make_ok_int`), not a self-releasing handle, so every call leaks one `SSL_CTX`.

Repro: none that runs standalone; classified from the current source (see the pointer below).

Expected: the whole response is returned and the context is freed.

Actual (interpreted / compiled): by source reading only (needs a TLS server): stdlib/tls.march `https_get_raw` has one `read` and no `ctx_free`.

Source: `https_get_raw`, stdlib/tls.march. `HttpTransport.request` already loops (`tls_recv_all`); the fix is to do the same here and free the context.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
