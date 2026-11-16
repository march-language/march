# Interpreter: the WsSocket box is not closed after the handler returns (2026-11-11)

Ocap phase 2b, Task 5 review. Compiled servers close a WebSocket handler's
`WsSocket` box when the handler returns (`march_ws_sock_done`, runtime/march_http.c,
march_http_evloop.c), so a task that kept the socket gets `Close(1001, "going
away")` from `recv` and a no-op from `send_frame`. The interpreter's server
(lib/eval/eval_net.ml, both the blocking path and the effect-based fiber path,
`start_ws_fiber`) builds the same borrowed box but never closes it, so a late send
there still reaches the descriptor, which may be reused.

Fix: close the box (`Eval_handle` `handle_close` semantics: set `h_closed`) once the
handler is finished. On the fiber path that is when the fiber completes, not when
`match_with` returns after a suspension. Test: the interpreted half of a
`wslate`-style test (test/test_https_native.ml) asserting a late send is dropped.
