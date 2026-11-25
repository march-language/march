`[P3]` `mock` handlers at the HTTP level (2026-11-24)

A `mock` handler takes over builtin operations (`tcp_connect`, `file_read`, ...), so
`mock IO.NetConnect(...)` cannot answer an `HttpClient.get` without speaking HTTP over a
fake socket. The design's §12 example (`mock IO.NetConnect("api.weather.com/") with
FakeWeather.handler`) wants a handler that answers requests. Phase 7a kept the builtin
level the design specified ("follows today's operation dictionaries"); an HTTP-level
handler shape (method, URL -> response) consulted by the stdlib's HTTP client entry points
is the follow-up.
