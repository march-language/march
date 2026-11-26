`[P3]` `scoped` only covers a handle parameter, not a function a callback is handed (2026-11-25)

Phase 8b marks the callback parameter of `File.with_open`, `File.with_open_write` and
`Socket.with_connection` as `scoped`. `HttpClient.with_connection(client, url, callback)` is the
same shape of API, but it hands the callback a *function* (`do_request`) that holds the socket,
and closes the socket when the callback returns. The design's `scoped` (§4.4) marks a handle, so
a callback that returns or stores `do_request` is not rejected, and calling it later fails at
run time.

What it needs: let `scoped` mark a function-typed parameter too. The capture pass already
carries a tracked name in any set (`Capture_set.name`), so the name would start on the handed
function's own set instead of on a handle's; `mark_scoped` in `lib/typecheck/capture.ml` seeds
`T.held` of the parameter type, which already includes an arrow's set. The open questions are
the surface (`scoped (Request -> Response) -> r`, which the parser's `scoped ty_atom` already
accepts with parentheses) and whether a name on a function set should print.
