# The role runner's setup has a deadline

Shipped 2026-09-18. Finding 2 of the choreography deadlock review (the first,
dropped session frames, is [[2026-09-18-session-frames-never-dropped]]).

## The bug

The role runner (`SessionNode.run`) dials every lower role, then accepts every higher
one. Dialing retried for 20 s and gave up; accepting had no deadline at all
(`ClusterConn.accept_split` over `tcp_accept`), and neither did the handshake or the
hello once a connection was open.

- A listening role whose peer never started waited for ever: role A alone was still in
  `accept` after 30 s.
- With three or more roles it held a whole cluster. In `Tri` (A = 1, B = 2, C = 3; C
  dials A and B), a C that reached A but not B returned `Err(Connect)`, but B waited
  for C for ever, and C kept its connection to A open, so A (waiting on C) heard
  nothing until the heartbeat declared C dead.
- A peer that connected and then said nothing held the listener in the handshake read,
  also for ever.

## The fix

Runtime (`runtime/march_http.c`):
- New builtin `tcp_accept_timeout(listen_fd, timeout_ms)`: `tcp_accept` with a
  deadline on the parked readiness wait; `Err("tcp_accept: timed out")`. Wired through
  typecheck (type and capability), `cap_infer`, `cap_symbols`, the interpreter,
  `llvm_builtins` (entry and `PDeclare`), `defun`'s builtin names and the codegen
  preamble golden.
- `tcp_recv_exact` honours a socket receive timeout (`tcp_set_recv_timeout`), as
  `tcp_recv` already did: the parked wait never sees the kernel's timer, so the timeout
  is read back and turned into a deadline for the whole read. The interpreter reports
  the kernel's `EAGAIN` in the same words.

`stdlib/cluster_conn.march`: `accept_split_within` / `connect_split_within` bound the
accept and each handshake (receive timeout set for the handshake, cleared after), and
close the socket on a failed handshake. The old names wait for ever, as before.

`stdlib/session_node.march`:
- One setup bound, `MARCH_SESSION_CONNECT_MS` (default 20000; <= 0 for ever), for the
  dial retries, each accept, each handshake and each hello. Each accept waits that
  long, so a cluster whose roles keep arriving is never cut off; one where no expected
  role connects for that long gives up with
  `Accept("no connection from role(s) … within … ms")`.
- The runner joins through `join_accepted` / `join_dialed`, which return an `Err` for
  a quiet or garbled hello instead of panicking. The public `accept_from`,
  `connect_to` and `open` keep their panics.
- A failed setup tears down every connection made so far (`abort_links`: close the
  queue, shut down both sockets, await the control reader, close), and closes the
  listener, so the roles already reached learn of it at once.

## Tests

- `test/two_node/setup_timeout` (three nodes, `Tri`, C given a dead address for B and
  kept alive after its failure): C reports the failed connect, B gives up waiting for
  C, A is cancelled with "connection lost". On main's `session_node` and
  `cluster_conn`, B never exits (and A says "no heartbeat"); with `abort_links` made a
  no-op, A says "no heartbeat". The scenario compiles all three nodes before starting
  any, so no deadline counts a compile; `compile` is now a documented harness helper.
- `test/native/tcp_accept_timeout`: a listener nobody dials times out; one that is
  dialed accepts.
- `test/native/cluster_accept_silent_peer`: a client that connects and says nothing is
  refused after the timeout (`tcp_recv_exact: timed out`); nobody else, `tcp_accept:
  timed out`.

## Not covered

- A peer that stalls AFTER setup is the heartbeat's job, as before.
- Heartbeats still start only once a role reaches its first send or receive, so a role
  that computes past the heartbeat timeout before then is taken for dead (finding 3 of
  the review; separate).
