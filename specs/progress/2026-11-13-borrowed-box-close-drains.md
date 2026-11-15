# A borrowed socket box drains its in-flight uses before the server closes the fd (2026-11-13)

Ocap phase 2b final whole-branch review, finding I1
(`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-review.md`).

**The bug.** An HTTP `Conn`'s socket and a plain ws:// `WsSocket` are `TCP_BORROWED` handle
boxes: the server owns the fd and the box's release is a no-op (ruling R12). When the
connection ended, `march_http_conn_sock_done` / `march_ws_sock_done` called
`march_handle_close` (which, for a borrowed box, neither shuts down nor cancels waits) and
the server then closed the fd at once. A use already in flight (a task that kept the
`Conn` and parked in `Socket.recv`) went on holding the descriptor NUMBER; the next
`accept` could reuse it, the scheduler's fd-wait table is keyed by number, and the stale
waiter could read the next client's bytes.

**The fix.** `march_handle_close_drain(box, timeout_ms)` (runtime/march_handle.c): close the
box (no new use can enter), and when a use is in flight wake it as close does
(`shutdown(SHUT_RDWR)` + `march_sched_fdwait_cancel`), then wait, parking a green thread
or sleeping an OS thread a millisecond at a time, until no use is in flight; for a borrowed
box the sticky fd-wait cancel is then forgotten, so the reused number does not inherit it.
Bounded (2 s, `MARCH_BORROWED_DRAIN_MS`): a use stranded by a panic between enter and leave
(specs/todos/2026-11-13-handle-stranded-in-flight-after-panic.md) times the drain out
rather than hanging the server. `march_http_conn_sock_done` and `march_ws_sock_done` drain;
the event loop's WebSocket hand-off, whose fd lives on in the WebSocket thread, uses the new
`march_http_conn_sock_handoff` (the old close: no drain, no shutdown). The normal path (no
use in flight) is unchanged: no shutdown, no wait.

**Test.** `test/test_handle.c` `test_close_drain_waits_for_in_flight`: a reader enters a
borrowed box over a socketpair and parks in `recv`; `close_drain` wakes it, returns only
after its leave, refuses a later enter, and leaves the borrowed fd open; an idle box drains
at once; a stranded use times the drain out at its bound. With `march_handle_close` in
place of the drain the case fails ("the parked recv was woken", "returned only after the
use left") and the runner then hangs on the never-woken reader.

A deterministic end-to-end reproduction (two clients, fd reuse, a stale waiter reading
the second client's bytes) was not written: it needs a handler task parked on a kept `Conn`
at the instant the server closes and a new accept reusing the number before the stale waiter
runs, which the scheduler does not let a test order.
