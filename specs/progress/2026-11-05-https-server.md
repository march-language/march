`[P2]` HTTPS for the stdlib HTTP server

Filed 2026-11-05. Not started. Design: `specs/2026-11-05-https-server-design.md`.

## What

`HttpServer` cannot serve `https://`. The runtime binds OpenSSL and has server-side builtins
(`tls_server_ctx`, `tls_accept`), but neither server mode (event loop, thread pool) nor the
WebSocket handoff uses them; all read and write the raw socket.

Scope agreed for the first version: HTTPS on both server modes, `wss://` with no change to
`WebSocket`'s API, certificate rotation without a restart (file polling plus
`HttpServer.reload_tls`, files or PEM text), handshake and idle timeouts that apply (today
`idle_timeout` is discarded), an extra plain-HTTP listener started by the same `listen`, and
`redirect_to_https` / ACME-challenge plugs.

Done when the HTTPS end-to-end tests pass on both server modes (and under ASAN), and a staging
deploy of an example app serves itself on 443 with a certbot certificate, `wss://` works, and a
forced renewal takes effect without a restart. forgepm keeps its Cloudflare Tunnel and is not
the acceptance test.

Unblocks HTTP/3 (`specs/plans/http2-http3-udp-plan.md`, Part 3).
