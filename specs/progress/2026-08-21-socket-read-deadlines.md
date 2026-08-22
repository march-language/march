# Socket read deadlines: `recv_timeout` honours its argument, and TLS reads can be bounded

Landed 2026-08-21. Found in a March application (Envoy) driving streamed HTTPS
to a model provider: the provider accepted the connection and then sent
nothing, and the session stopped dead — no error, no recovery, no way to time
out. Two runs, same model, same silent wedge.

## What was wrong

Three separate defects, stacked.

### 1. `Socket.recv_timeout` ignored its own timeout

`stdlib/socket.march` shipped:

```march
fn recv_timeout(fd : Int, max_bytes : Int, _timeout_ms : Int) : Result(String, SocketError) do
  match tcp_recv_chunk(fd, max_bytes) do
  ...
```

The parameter was `_timeout_ms` — unused — and the body was byte-for-byte the
untimed `recv/2` above it. A function that documents a timeout and silently
ignores it is worse than one that does not exist: the caller believes they are
protected and is not. `march_tcp_recv_all` carried the identical lie three
lines away (`(void)timeout_ms; /* TODO: implement timeout */`).

### 2. No timeout-capable read existed on any TLS path

`Tls.read` → `march_tls_read` was a bare `SSL_read`, and March exposed no way
to set socket options on an fd, so an application could not bound it from
outside either.

### 3. The one that actually mattered: `SO_RCVTIMEO` is defeated by preemption

This is the part worth remembering, because it makes the obvious fix silently
useless. The scheduler preempts green threads with `SIGUSR1` roughly every
millisecond, and installs that handler with **`SA_RESTART`**
(`runtime/march_scheduler.c:2926`). A restarted `recv()` **restarts its
`SO_RCVTIMEO` timer from zero**. With preemption at ~1ms and a deadline in the
hundreds of ms, the timer can never accumulate.

The failure mode is maximally deceptive: `setsockopt` succeeds, `getsockopt`
reads the value back correctly, and the read still blocks forever. Verified
directly — a standalone C program against the same silent peer returned
`EAGAIN` after 502ms, while the identical sequence inside a compiled March
program hung indefinitely, with `sample` showing the process parked in
`march_tcp_recv_chunk → __recvfrom` with `_sigtramp` frames throughout.

`march_tcp_send_all` and `march_tcp_recv_exact` already masked `SIGUSR1`;
`march_tcp_recv_chunk`, `march_tcp_recv_all` and every TLS entry point never
did.

## The fix

Two mechanisms, deliberately not interchangeable:

| builtin | mechanism | scope |
|---|---|---|
| `tcp_recv_chunk_timeout(fd, max, ms)` | `poll(POLLIN, ms)` then one `recv` | this call only; mutates no fd state |
| `tcp_set_recv_timeout(fd, ms)` | `SO_RCVTIMEO` | persistent fd property; the only one that reaches `SSL_read` |

`poll`-then-`recv` cannot bound a TLS read (OpenSSL may need several socket
reads per record and may hold buffered plaintext `poll` cannot see), so the
fd-level option is what a TLS client needs; and the fd-level option is inert
without the signal mask, so both were required to fix the reported outage.

- `runtime/march_preempt.h` — new. The `SIGUSR1` mask helpers, previously
  private to `march_http.c`, moved to a shared header so `march_tls.c` can use
  them. Its comment documents the `SA_RESTART`/`SO_RCVTIMEO` interaction, which
  is not discoverable from the call sites.
- `march_tcp_recv_chunk`, `march_tcp_recv_all` — now masked. `recv_all`'s
  timeout is a **total** deadline across the loop (a peer dribbling one byte per
  interval must not be able to reset a per-call timer forever).
- `march_tls_read`, `march_tls_connect`, `march_tls_accept`, `march_tls_write`
  — now masked, so an `SO_RCVTIMEO` set before the handshake bounds both the
  handshake and every later read.
- `errno` is captured **before** unmasking at every site: `pthread_sigmask` may
  set `errno` even when it succeeds, which loses the `recv` result.

### Error classification

`SocketError` gains `RecvTimeout(Int)` and `SocketOptionFailed(String)`.
"The peer went quiet" and "the read failed" are different facts and only one is
worth retrying. The runtime emits one sentinel string (`"recv: timed out"`,
`MARCH_RECV_TIMEOUT_MSG`), the interpreter emits the same string
(`recv_timeout_msg` in `eval.ml`), and `stdlib/socket.march` matches it. All
three must agree; `test/test_socket_timeout.ml` asserts the exact variant so
drift cannot silently degrade every timeout back into `RecvFailed`.

`EAGAIN`/`EWOULDBLOCK` from a still-blocking socket is classified as the same
fact, so `Socket.recv` on an fd carrying a deadline reports `RecvTimeout(0)` —
the `0` recording that the bound came from the descriptor, not from that call.

## Verification

`test/test_socket_timeout.ml`, compiled at `--opt 2`, riding `run_stdlib.exe`.

The silent peer is a listening socket that **never calls `accept()`**: the
kernel completes the handshake into the backlog, so the client connects and
then nothing can arrive. No thread, no subprocess, no timing race.

- **A** — `recv_timeout` returns `RecvTimeout(500)`.
- **B** — `set_recv_timeout` then the **untimed** `Socket.recv` (the path
  `SSL_read` rides) returns `RecvTimeout` instead of hanging.
- **C** — a TLS handshake against a silent peer fails within the fd deadline.
  Skipped, loudly, only when the compiler finds no OpenSSL.
- **D** — non-vacuity control: a peer that answers within the deadline still
  returns its data. Without it, a `recv_timeout` regressed into "always time
  out" would pass everything else.

Timing is proved by reachability rather than by a clock: because the peer never
sends, an ignored deadline blocks forever, so reaching a later probe at all is
evidence the earlier one expired. The harness additionally bounds the whole
process.

All four probes were observed **failing** before the corresponding fix — B and
C each hung to the 30s bound — so none of them is vacuous.

## Notes for whoever touches this next

- `unix_time_ms` typechecks but has **no codegen backing**: it fails to link in
  a compiled program (`Undefined symbols: _unix_time_ms`). Filed separately in
  `specs/todos/`. That is why the test measures elapsed time in the harness.
- `within` is a reserved word in March. `fn within(...)` fails to parse with
  "I got stuck here" pointing at the declaration.
- `run_stdlib` had no `source_tree` deps on `runtime/`/`stdlib/` despite hosting
  tests that shell out to the real compiler; added, because a stale staged tree
  makes an edit simply absent from what the test exercises.
