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
