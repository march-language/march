`[P2]` `Tls.https_get` reads the response once, so a long response is truncated (2026-11-11)

`https_get_raw` calls `read(conn, 1048576)` once. One read returns at most one TLS record's worth of data, so a response that spans several records comes back truncated, with `Ok`. The doc string notes this.

Repro: none that runs standalone; classified from the current source (see the pointer below).

Expected: the whole response is returned.

Actual (interpreted / compiled): by source reading only (needs a TLS server): stdlib/tls.march `https_get_raw` has one `read`.

Source: `https_get_raw`, stdlib/tls.march. `HttpTransport.request` already loops (`tls_recv_all`); the fix is to do the same here.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

Update 2026-11-22 (`40f901bab`): the second fault this file listed, a TLS context that was never freed, is fixed: `https_get_raw` calls `ctx_free(ctx)` on every path that built one (`789165b78`, ocap phase 2b). The single read is unchanged.
