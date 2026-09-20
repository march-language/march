# `[P2]` Audit: runtime code that reads `errno` after a green-thread park

Filed 2026-09-19 from [[2026-09-19-tcp-connect-errno-after-park]]. A green
thread that parks (`march_sched_wait_fd`, `march_sched_wait_fds`, any
park/yield) can resume on another scheduler thread. On glibc
`__errno_location()` is `const`, so in the same function activation clang may
reuse the errno address computed before the park: a later `errno` read or
write goes to the OLD thread's errno. This made a refused `tcp_connect`
report "Interrupted system call" (fixed with `march_errno_now()`).

The same pattern remains wherever a function parks and then checks the errno
of a syscall it made afterwards. As of this filing:

- `runtime/march_http.c`: the accept loop after `march_sched_wait_fd` (the
  `poll`/`accept` EINTR/EAGAIN checks, ~l.228-235); the send loop
  (`send_errno`, ~l.477); the recv loops (`recv_errno` after the wait,
  ~l.639, 678, 722, 806); the chunked read (~l.2647).
- `runtime/march_tls.c`: `*saved_errno = errno` after the wait (~l.323), and
  the `errno = 0; ... *saved_errno = errno` around `SSL_*` on later
  iterations of the same loop.

Failure modes if a stale errno is read: a real recv/accept error taken for
EAGAIN/EINTR (a busy retry), or a stale-hint EAGAIN taken for a hard error (a
spurious "connection closed"). Only Linux (glibc) is affected, and only when
the park migrated.

**What to do.** Read errno through `march_errno_now()` (or capture it via a
`noinline` helper) at every site above. Then extend
`test/native/tcp_connect_refused_after_park.march`'s approach, with many
concurrent tasks so parks migrate, to a recv-side fixture that forces EAGAIN
after a stale readiness hint. It fails only on Linux, so check it in the
container (`scripts/two-node-docker.sh`'s image) before trusting a green.
