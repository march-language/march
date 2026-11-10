`[P1]` HTTP request serializer writes the path (and query) verbatim: CR/LF/space smuggle a second request.

Found by the path-scopes review (2026-11-09, C1). `http_serialize_request`
(`runtime/march_http.c`, and the interpreter's copy in `lib/eval/eval_builtins.ml`) puts
the request path into the request line unchanged, so a path containing
`" HTTP/1.1\r\nHost: h\r\n\r\nDELETE /admin"` sends a pipelined second request. Path
scopes now refuse such paths (`Host_scope.path_ok` / `Http.scope_path_ok` are an
allowlist), but an unscoped program is still exposed, e.g. when a path or query comes
from user input.

Done when: the serializer refuses CR, LF, NUL and space (and other bytes outside RFC 3986
for the path and query) in every runtime (C, interpreter, JS), returning a transport
error rather than sending; a test sends such a request to a local listener and sees
nothing written. Also noted by the review: the compiled serializer ignores headers
(`(void)headers_ptr`) and passes the query `Option` as if it were a string; check both.
