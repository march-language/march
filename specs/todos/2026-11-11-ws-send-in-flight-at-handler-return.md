# Plain ws:// send still in flight when the handler returns can hit a reused fd (2026-11-11)

Ocap phase 2b, Task 5 review. After a WebSocket handler returns, the server closes
the `WsSocket`'s borrowed handle box (`march_ws_sock_done`, runtime/march_http.c) and
then closes the connection's fd. Closing the box refuses every NEW `recv` /
`send_frame` / `select`, but a task that is already inside `ws_send` / `ws_recv` at
that moment (it entered the box before the close) keeps using the descriptor number
after the server's `close(fd)`; if the OS has handed that number to another
connection, the frame goes to the wrong peer. wss:// is not affected: its value
names the TLS session, and the session registry refuses a closed session
(`march_ws_tls_teardown` waits for touching operations to finish).

Before Task 5 every late send hit this window; now only one already in flight does.

Fix: after `march_handle_close(box)`, the server waits for the box's in-flight count
to reach zero before closing the fd, waking a parked sender first (shutdown of the
plain fd, plus `march_sched_fdwait_cancel`). The wait must not block the scheduler
thread a parked green thread needs (park, or bound it). Test: a handler that spawns
a task looping `send_frame` and returns at once, with a second connection opened
right after; the second peer must never receive the first one's frames.
