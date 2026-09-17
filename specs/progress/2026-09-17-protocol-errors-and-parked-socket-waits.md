# Protocol errors as `RunError`, and the last blocking socket waits parked

Shipped 2026-09-17. Two follow-ups of [[2026-09-16-role-runner]] /
[[2026-09-17-actor-hosted-runner]] and of [[2026-09-16-park-socket-waits]].

## 1. A message the protocol cannot receive is the transport's to report

The generated receive handler (`<P>_<Role>.recv_*` / `offer_*`, run by the transport's
`suspend` handler) used to `panic` on a message it could not decode or one its state does
not receive. That panic ran in whatever turn the delivery ran in -- `SessionNode`'s
endpoint actor -- where there is no caller to return to, so `run` could never report it.

Now `Session.Ops` has a fifth op, **`fail : Int -> String -> ()`**, and `Session.fail(s, ep,
why)` hands the transport the message it cannot take. What that means is the transport's:

- the same-thread transports (`test/session/*.march`, the endpoints unit harness) `panic`,
  exactly as the handler itself did -- a message that cannot be received is a bug in the
  program that sent it, and nothing changes for them beyond the extra record field;
- `SessionNode` ends the session the way a dead host's ends: no Bye, every reader ended,
  and `run` / `run_hosted` return **`Err(Protocol(from, why))`** naming the sender (recorded
  per delivery by `resume_with`) and the generated message (`"Bad, role A: message is not
  JSON: …"`, `"…: unexpected message"`).

The generator emits **`<P>_Msg.try_decode : Bytes -> Result(Msg, String)`** beside the
panicking `decode` and uses it in every handler; the unexpected-message arm calls `fail`
too. The event API's `resume` keeps its panics: it runs in the *user's* actor, where a
supervisor is the right tool.

Witness: `test/two_node/protocol` -- node-b, written against the raw `Session` API so it
can, answers node-a's typed message with `"this is not a Bad_Msg"`; node-a's `run_A`
returns `Err(Protocol(2, "Bad, role A: message is not JSON: …"))` and exits 0. The seven
in-process session goldens are unmoved.

## 2. `tcp_connect`, `send`, WebSocket and OpenSSL park the green thread

[[2026-09-16-park-socket-waits]] converted the reads on the path that hung and listed the
rest. All of it is now on `march_sched_wait_fd`, with the same two rules (the wait runs
unmasked; readiness is a hint, so the syscall after it never blocks):

- **`tcp_connect`**: the socket is non-blocking for the `connect()`; `EINPROGRESS`/`EINTR`
  park on writability, a zero-timeout `poll` confirms, `SO_ERROR` is the outcome; the
  flags are restored before the fd is handed out. `getaddrinfo` still blocks (there is no
  async resolver) -- the one wait left on this path.
- **`tcp_send_all`** and the WebSocket frame writes go through `send_all_parked`
  (`MSG_DONTWAIT`, park on writability when the buffer is full).
- **WebSocket** `recv_exact` parks per chunk; `ws_select` waits on the socket *and* the
  actor-notification pipe with the new **`march_sched_wait_fds`** (up to four fds, one
  park; C test case 6), then confirms which one has data.
- **OpenSSL**: one driver, `tls_drive`, runs `SSL_connect`/`SSL_accept`/`SSL_read`/
  `SSL_write` on a non-blocking fd and parks on `WANT_READ`/`WANT_WRITE` for the direction
  OpenSSL asked for -- which is also the only correct way to wait on TLS (readable bytes are
  not application data; a record can need several reads; renegotiation needs a write).
  The fd's `SO_RCVTIMEO` still bounds the handshake and untimed reads, reported with the
  same expired-deadline sentinel as before; `tls_read_timeout` keeps its absolute deadline
  and `Ok(None)`. The preempt mask covers each SSL call, never a park.

Not exercised locally beyond compilation: a real TLS peer (the TLS and WebSocket stdlib
tests run under the interpreter). CI's HTTP client tests are the first real run.

## Also

- `SessionNode.run`'s address parameter is typed `List(Addr)` outright: the `Addrs` alias
  did not unify with a hand-built `Cons(addr, Nil)` from another module (the `protocol`
  node-b builds its table by hand), so the alias is documentation only.
- Seen once while running every scenario: `restart`'s node-b (creation 2) exited 137 with
  a complete, correct trace; 3/3 on rerun. Recorded here, not root-caused.
