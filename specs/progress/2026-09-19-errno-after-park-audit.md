# DONE 2026-09-19 — every runtime `errno` read after a park goes through `march_errno_now()`

Closes the `[P2]` audit filed from [[2026-09-19-tcp-connect-errno-after-park]].
That fix made one site — `tcp_connect_impl`'s SO_ERROR path — stop carrying its
outcome through `errno`, and left the rest of the pattern open.

**The hazard.** A green thread that parks (`march_sched_wait_fd`,
`march_sched_wait_fds`) can resume on another scheduler thread. glibc declares
`__errno_location()` `const`, so within one function activation clang may
compute the errno address once and reuse it across the park: a later `errno`
read, or a later `errno = ...` write, lands on the OLD OS thread's errno. The
read side turns a real recv/accept error into a spurious EAGAIN (a busy retry
on a dead fd) or a stale-hint EAGAIN into a hard error (an invented "recv
failed"); the write side both loses the value the caller meant to set and
corrupts a scheduler thread that is running something else.

**Changed.**
- `runtime/march_scheduler.{c,h}`: added `march_errno_set(int)`, the `noinline`
  write-side companion to `march_errno_now()`.
- `runtime/march_http.c`, every errno read that a park in the same activation
  dominates now goes through `march_errno_now()`:
  `tcp_accept_raw_until` (the zero-timeout `poll` and the `accept` EINTR/EAGAIN
  checks), `send_all_parked`, `march_tcp_recv_all`, `march_tcp_recv_chunk`,
  `march_tcp_recv_chunk_timeout`, `march_tcp_recv_timeout`,
  `march_tcp_recv_exact`, `recv_exact` (the WebSocket frame reader), and two
  sites the audit had not listed: `march_ws_select`'s `poll` after
  `march_sched_wait_fds`, and the HTTP accept loop's `select`, whose next
  iteration follows `tcp_accept_raw`'s park.
- `send_all_parked` now returns its errno in an out-param rather than through
  `errno`: it wrote `errno = EIO` / `errno = send_errno` after a park, and its
  one caller that cares, `march_tcp_send_all`, read `errno` back in a different
  activation — on the thread that never received the write.
- `runtime/march_tls.c` `tls_drive`: the `errno = 0` before each `SSL_*` call
  and the `*saved_errno = errno` after it are on the loop's later iterations,
  which follow the `march_sched_wait_fd` at its bottom. They are now
  `march_errno_set(0)` / `march_errno_now()`, as is the wait's own error path.

Sites deliberately left alone: `writev_all`, `march_http_send_file`'s three
`sendfile`/read-write loops and `march_tcp_set_recv_timeout` read errno with no
park anywhere in the activation, and every errno use inside
`march_sched_wait_fd`/`march_sched_wait_fds` themselves precedes their park.

**Regression.** `test/native/tcp_recv_eagain_after_park.march`: eight green
threads read single bytes off ONE socket while the peer dribbles 60 of them,
one every 2 ms. Every byte wakes all eight, seven find nothing and get a
post-park EAGAIN that must stay a retry; instrumenting the pre-fix runtime
counted 284 of them per run. All 60 bytes must arrive and no read may fail.

**What this fixture does and does not prove.** It is GREEN on the pre-fix
runtime, because clang 18 on aarch64 does not currently hoist the errno address
out of any of these loops — `objdump` puts every `__errno_location` call after
its own `recv`, inside the loop. `tcp_connect_impl` was hit because it read
`errno` BEFORE its park, giving clang an address to CSE with; the loops have no
such earlier read. So these sites were latently, not actively, wrong.

The fixture was proved to be a real detector by hand-writing the hoist into the
pre-fix `march_tcp_recv_timeout` (`int *ep = &errno;` above the loop, `*ep`
inside it) and rebuilding: **22–35 of the reads failed per run, in 3/3 runs**,
where the unperturbed pre-fix and the fixed runtime both report 0. The stale
values read back were EEXIST (17) — another scheduler thread's `fdwait_arm`
epoll registration — which is exactly the signature of reading a foreign
thread's errno.

**Verified.** Linux container (`march-two-node`, glibc 2.39, aarch64, clang 18,
built with `dune build --root . --build-dir /lbuild bin/main.exe
@bin/warm-cache`): the new fixture 15/15 green and
`tcp_connect_refused_after_park` 15/15 green on the fixed runtime; the two-node
sweep passes. macOS: the fixture is green and the full suite passes.

No `CHANGELOG.md` entry: with clang not hoisting at any of these sites, nothing
a user can observe changed. The one entry this class of bug earned is the
`tcp_connect` one, already under `[Unreleased]`.
