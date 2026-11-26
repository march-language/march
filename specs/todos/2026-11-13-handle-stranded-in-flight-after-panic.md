`[P3]` A panic inside a handle use strands its in-flight count; close then never releases (2026-11-13)

Found by the ocap phase 2b final review (M6,
`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-review.md`). The stdlib's
`with_raw`/`with_listener`/`with_live` helpers call `handle_enter`, run the operation,
then `handle_leave`. A panic in between (in a callback, e.g. an `accept` path) never
leaves, so the box's in-flight count stays above zero. `close` then sets CLOSED but the
release waits for a leave that never comes; only the destructor (`march_handle_dtor`,
runtime/march_handle.c) releases. A long-lived `Listener` keeps its port bound after
`close_listener` until the box is dropped. The borrowed-box drain
(`march_handle_close_drain`, used when an HTTP or ws:// connection ends) times out on
such a box instead of waiting forever, and the server then closes the fd.

Expected: the `with_*` helpers leave in a `try_finally` (or the runtime leaves on
unwind), or the behaviour is documented next to the box's close semantics in
specs/lang/capabilities.md.

**The drain's timeout path** (re-review m1, `final-rereview.md`). When
`march_handle_close_drain` times out on a stranded use:
- (a) it keeps the sticky fd-wait cancel, which protects the stranded use, but the server
  then closes the fd. The next connection to get that number has every green-thread
  fd-wait on it fail with ECANCELED until its own drain forgets the cancel, so one
  connection breaks a later, unrelated one. Forgetting the cancel when the next accept
  takes the number would fix it.
- (b) on the event loop the drain runs on the loop's OS thread
  (runtime/march_http_evloop.c), so a use that never leaves (a panic, or a task killed
  while parked in `recv`, probably the commoner case) stalls every connection on that
  loop for 2 s per close.
- A use that saw READY and was preempted for more than 2 s before its `recv` still
  reaches a recycled number: a narrow window, accepted.

## 2026-11-25: the stranded count itself is fixed; the drain's timeout path is what is left

The runtime now leaves the uses a caught panic jumped out of, and the ones a dead green
thread was inside (`specs/progress/2026-11-25-handle-use-left-on-caught-panic.md`). That
removes the usual cause of a drain timing out. Still open, both in
`march_handle_close_drain`'s timeout branch: (a) the sticky fd-wait cancel that outlives the
descriptor, and (b) the 2 s stall of the event-loop thread. A use that is merely slow (not
abandoned) can still reach both.

## 2026-11-26: (a) fixed; (b) left, now hard to reach

(a) Every `accept()` result now goes through `march_handle_fd_accepted`
(runtime/march_handle.c), which forgets a sticky fd-wait cancel on the number: the blocking
accept in `tcp_accept_raw_until` (runtime/march_http.c, behind `Socket.accept` and the
blocking HTTP server) and the event loop's `accept_connections`
(runtime/march_http_evloop.c). The timed-out drain still keeps the cancel until then, so a
use still in flight stays protected while the number is unused. Test:
`test/test_handle.c`, `test_drain_timeout_cancel_forgotten_on_accept` (a wait on the reused
number fails with the stale cancel before the hook, and times out normally after it).
Progress note: `progress/2026-11-26-handle-drain-cancel-forgotten-on-accept.md`.

(b) is not fixed. Since 2026-11-25 a use a panic or a dead task abandoned is left by the
runtime, and a parked use is woken by the drain (shutdown plus the fd-wait cancel) and
leaves at once. So the drain on the event-loop thread now times out only when a woken use
is not scheduled for 2 s. A fix that does not sleep the loop thread would defer the close:
delete the connection's kqueue/epoll registration explicitly (kqueue keeps filters while
the fd stays open, and their udata would point at a freed `conn_state_t`), park the fd and
box on a list, and close once the box's in-flight count reaches zero or a deadline passes.
Not done: it touches the event loop's ownership of descriptors for a case no test can
produce today.
