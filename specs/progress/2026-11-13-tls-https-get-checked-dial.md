# `Tls.https_get` dials through the checked `Socket.connect` (2026-11-13)

Ocap phase 2b final whole-branch review, finding I2
(`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-review.md`).

`Tls.https_get` (`https_get_raw`, stdlib/tls.march) dialled with the raw `tcp_connect` and
adopted the fd, so the only check was `Tls.client_ctx`'s `Authority.check("IO.NetConnect.TLS", "")`,
which names no host. Every other dial goes through `Socket.connect`, which checks
`IO.NetConnect` on `host:port`. It now dials through `Socket.connect` too, as
`HttpTransport.dial` does; a refusal is folded into the single Result it still returns
(`TlsHandshakeFailed("connect: <Authority.describe>")`, nothing dialled), and a failed
connect keeps its old text (`TlsHandshakeFailed("tcp_connect: <msg>")`).

Test: `test/cap_conformance/tls_https_get_refused` (`-- REFUSE: IO.NetConnect`). Before:
"TLS handshake failed: tcp_connect: Connection refused" (it dialled); after:
"TLS handshake failed: connect: IO.NetConnect("127.0.0.1:1") refused by the launch grant
(IO.NetConnect)". `test/test_cap_check_coverage.ml` drops the `Tls.https_get_raw`/`tcp_connect`
allowlist row, and the deferred-open rows now say phase 4.

The re-typing (`Result(Result(_, TlsError), CapError)`) stays open in
specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md, now targeted at ocap phase 4.
