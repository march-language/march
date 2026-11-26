# A timed-out drain's fd-wait cancel no longer breaks the next connection (2026-11-26)

Item (a) of `todos/2026-11-13-handle-stranded-in-flight-after-panic.md` (plan unit U5,
step 1, the drain's timeout branch).

When `march_handle_close_drain` timed out on a borrowed box, it kept the sticky fd-wait
cancel (to protect the use still in flight) and the server closed the descriptor. The
cancel is keyed by the number, so the next connection that `accept()` gave that number had
every green-thread wait on it fail with ECANCELED until its own drain forgot the cancel.

Fix: `march_handle_fd_accepted(fd)` (runtime/march_handle.c) forgets the cancel, and both
accept sites call it on every descriptor accept returns: `tcp_accept_raw_until`
(runtime/march_http.c; `Socket.accept`, `accept_timeout`, the blocking HTTP server) and
`accept_connections` (runtime/march_http_evloop.c). Until the number is reused the cancel
stays, so the stranded use is protected as before.

Test: `test/test_handle.c`, `test_drain_timeout_cancel_forgotten_on_accept`: a drain times
out on a stranded use, the descriptor is closed and its number reused; a wait on the new
descriptor fails with ECANCELED before the hook and times out normally after it.

Not covered: no end-to-end test. Since 2026-11-25 a stranded use is rare (the runtime leaves
abandoned uses), so a drain timeout cannot be produced from a March program. Item (b), the
2 s stall of the event-loop thread, is still open in the todo.
