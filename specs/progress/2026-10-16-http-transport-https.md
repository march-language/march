# HTTPS in `HttpTransport.request`

`HttpTransport.request` and `HttpTransport.simple_get` now dispatch
`https://` URLs to March's existing TLS client instead of returning
`SchemeNotSupported`. The transport builds a certificate-verifying TLS context,
connects with the URL host as SNI, writes a `Connection: close` HTTP/1.1
request through the TLS connection, receives the complete response, parses it,
and closes both TLS and TCP resources on every result path.

The fd-oriented APIs (`connect`, `request_on`, and `stream_request_on`) remain
plain HTTP only. A raw TCP descriptor does not provide the TLS context or
session those APIs would need, so they continue to reject HTTPS rather than
allow a request to be sent in plaintext.

Regression coverage in `test/stdlib/test_http_transport.march` verifies that
the convenience request APIs dispatch HTTPS to the TLS path rather than failing
at the scheme guard. The test uses a closed loopback port, so it makes no
external network request.
