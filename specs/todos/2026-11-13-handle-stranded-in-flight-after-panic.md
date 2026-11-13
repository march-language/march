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
