`[P1]` HTTP request serializer refuses fields that would smuggle a second request (2026-11-10)

Closes `specs/todos/2026-11-09-http-request-line-injection.md` (found by the path-scopes
review, 2026-11-09, C1).

## The bug

`http_serialize_request` (the interpreter's in `lib/eval/eval_builtins.ml`,
`march_http_serialize_request` in `runtime/march_http.c`) put the method, host, path,
query and headers into the request verbatim. A path such as
`"/x HTTP/1.1\r\nHost: h\r\n\r\nDELETE /admin"` therefore sent a pipelined second
request. Path scopes already refused such paths (`Host_scope.path_ok` /
`Http.scope_path_ok`), but an unscoped program was exposed whenever a path, query or
header came from user input. The method, host, header names and header values had the same
hole in the interpreter. The compiled serializer ignored headers entirely
(`(void)headers_ptr`), so it could not be smuggled through them, but it also never sent
`Connection: close`, `Content-Type` or any user header.

## Reject, not percent-encode

The builtin now returns `Result(String, String)` and gives `Err(reason)` without
building anything. Reasons for rejecting rather than encoding:

- Encoding cannot be right for every field. A CR/LF in a header value or a method has no
  encoded form; it can only be refused. One rule for all fields is simpler to state and test.
- Encoding a path silently sends a different request target than the one the program
  built, and it cannot tell `%` that starts an escape the caller already wrote from a
  literal `%`. Double-encoding `/a%20b` into `/a%2520b` would break every correct caller.
- The client API already has a clean place for the error. `HttpTransport.TransportError`
  and `HttpClient`'s mirror both carry `Refused(String)`, which the path-scope check already
  uses for "this request is not sent". The serializer error maps onto it without adding a
  variant, so no user `match` on `TransportError` stops being exhaustive.

Every `HttpTransport` entry point (`request` over plain HTTP, HTTPS and the browser fetch
path, `request_on`, `stream_request_on`) serializes before it connects or sends, so a
refused request opens no connection and writes nothing. The fetch path builds its own URL
and header block, so it runs the serializer only for its checks.

`Tls.https_get(host, port, path)` built its own `"GET " ++ path ++ …` request string and
had the same hole. It now builds the request with `http_serialize_request` too and turns a
refusal into `TlsWriteError(reason)` before it creates a TLS context or connects.

## What each field accepts

These rules live in `lib/eval/http_request_check.ml`. The C copy (`http_check_*` in
`runtime/march_http.c`) gives the same verdicts and the same message text:

| field | accepts | message on failure |
|---|---|---|
| method, header name | non-empty RFC 9110 token (`tchar`) | `empty method` / `<field> contains byte 0xNN at offset I` |
| host | no control byte, space or DEL | `host contains byte …` |
| path, query | RFC 3986 unreserved, sub-delims, `:@/?`, and well-formed `%HH` | `<field> contains byte …` / `<field> has a malformed %-escape at offset I` |
| header value | VCHAR, obs-text, SP, HTAB | `header value contains byte …` |

Every message starts with `http request rejected: `. The path and query rule is stricter
than "no CR/LF/space": it also rejects `#`, `"`, `<>`, `{}`, `|`, `\`, `^`, a backtick,
`[]`, a bare `%` and non-ASCII bytes, all of which RFC 3986 says must be
percent-encoded. A URL that `Http.get` parsed satisfies it as long as the URL itself was
well formed. `Http.encode_query` / `Http.set_query` do **not** percent-encode, so a query
built from raw values with a space or `#` in them, which used to go out malformed, is now
refused. `Uri.encode_query` and `Uri.encode` percent-encode. The `Http.encode_query` docs
already pointed there, and `Http.set_query`'s now says the request is refused.

## The compiled serializer now matches the interpreter

`march_http_serialize_request` was rewritten to build with lengths rather than `%s`, which
stopped at a NUL. It emits the header list it used to drop, and it sends `Content-Length`
only for a non-empty body, as the interpreter always has. The todo also suspected it
"passes the query `Option` as if it were a string". That was correct as written:
`Option(String)` is a nullable `march_string*` at the C ABI, with `NULL` for `None`. The
parity test exercises `Some(query)` compiled.

## Tests

In `test/test_codegen.ml`, group "http builtins":

- `serialize rejects injection (interp = compiled)` runs one program interpreted and
  compiled. It covers a CRLF-and-space path, a space, a bare `%`, a `#`, a CRLF query, a
  CRLF header value, a CRLF header name and a header name with a space, a method with a
  space, and a host with a CRLF. It also sends an ordinary request
  (`/a%20b/c%2Fd?x=1&y=%2F&z=a+b` with a header) and a POST with a body. It checks each
  verdict and the exact bytes of the request that goes out, and requires the two outputs to
  be byte-identical.
- `transport refuses injected path, sends nothing` calls `HttpTransport.request` with an
  injected path against a local listener, interpreted and compiled. It requires
  `Err(HttpTransport.Refused(…))` and zero bytes, or no connection at all, at the listener.
- The two existing serializer unit tests unwrap `Ok`.

In `test/stdlib/test_http_transport.march`, "request smuggling is refused before
connecting" checks `HttpTransport.request` with a CRLF path and a CRLF header value
(`Refused`) and `Tls.https_get` with a CRLF path (`TlsWriteError`). Each targets
loopback port 1, so a request that wrongly connected would fail with a different error.

## Not changed

`share/march/http_transport.march` is a stale copy of the stdlib from June 2026 that
nothing syncs. It was left alone. The `--target js` runtime (`runtime/march_runtime.mjs`)
has no `http_serialize_request` at all, so `HttpTransport`'s socket path is unusable
there. The in-browser March (js_of_ocaml) goes through the interpreter's builtin and the
fetch path, and refuses the same requests.
