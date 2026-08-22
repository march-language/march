# tcp_recv_timeout and tls_read_timeout

A companion to the deadline work in #325 and #327, not a replacement for it.
Those made socket and TLS deadlines real; these add a second reporting shape
and a second TLS mechanism, for callers the first two do not fit.

## Ok(None) alongside Err(RecvTimeout)

`tcp_recv_timeout` is `tcp_recv_chunk_timeout` with one difference: an expired
deadline is `Ok(None)` rather than `Err(MARCH_RECV_TIMEOUT_MSG)`. It shares the
same preempt masking, the same `march_wait_readable`, and the same errno
capture, so the two cannot drift on what "expired" means.

`Err(RecvTimeout(ms))` says a timeout is a kind of failure. `Ok(None)` says it
is the absence of an event. A reader polling a peer that is usually quiet, and
a reader for which silence is an error, should not have to share a spelling —
and a caller that branches on `Ok(None)` cannot be broken by a future rewording
of a sentinel string. `Socket.recv_deadline` is the wrapper.

## A TLS deadline that leaves nothing on the fd

`tls_read_timeout` bounds one TLS read without `SO_RCVTIMEO`. That matters
where a deadline is per-call rather than per-connection — a client with a
generous first-byte budget and a tight one between frames sets no lasting
property and cannot leave a stale deadline on a descriptor it later hands
somewhere else.

**Polling the fd and then calling a blocking `SSL_read` does not work, and the
first version of this did exactly that.** Right after a TLS 1.3 handshake the
server sends session tickets, so the socket is readable while holding no
application data. `poll` returned ready, `SSL_read` consumed the tickets and
then blocked for the full sixty seconds until the peer hung up — reproducing
the hang it was written to end. Readable bytes are not application data, and
one record can need several socket reads.

So the read gives up: the fd goes non-blocking for the duration, `SSL_read`
drives, and `WANT_READ`/`WANT_WRITE` sends it to `poll` with whatever remains
of the deadline. That also covers renegotiation, where progress needs a WRITE.
Preemption is masked for the wait, for the reason #327 documents — under
`SA_RESTART` a ~1ms SIGUSR1 tick restarts an interrupted wait, and a deadline
that restarts with it never expires. The fd flags are restored on every exit
path, because `march_tls_write` assumes blocking semantics.

## What was measured, and what a test cannot reach

The session-ticket bug was found by a probe against a real server: handshake,
send nothing, read with a 700ms deadline. Before the rewrite it returned EOF at
sixty seconds; after, `Ok(None)` at 700ms. A second probe confirms a real
response still arrives (863 bytes) and that a following `Tls.write` succeeds,
proving the fd was left blocking.

No stub connection sends a session ticket, so no in-suite test can catch this
class of bug — the interpreter has no TLS at all and `tls_read_timeout` is a
stub there, as `tls_read` already was. The suite covers the plain-TCP path:
listen, connect, read from a peer that never speaks, assert `Ok(None)`.
