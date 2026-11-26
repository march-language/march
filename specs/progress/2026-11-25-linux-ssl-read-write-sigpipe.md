# SSL_read / SSL_write can raise SIGPIPE on Linux (2026-11-11)

Ocap phase 2b, Task 5 review. OpenSSL's socket BIO writes with `write()`, so a TLS
write to a peer that has reset the connection raises SIGPIPE, whose default action
kills the process (exit 141). Task 5 made the close path quiet everywhere
(`tls_shutdown_quiet` in runtime/march_tls.c: on macOS/BSD the fd gets `SO_NOSIGPIPE`
at `march_tls_connect` / `march_tls_accept`, which covers every later write too; on
Linux SIGPIPE is blocked and consumed around `SSL_shutdown` only). On Linux,
`SSL_write` (`Tls.write`) and `SSL_read` (which can write: TLS 1.3 session tickets,
alerts, key updates) are still unprotected, as before Task 5. The HTTP server only
avoids it because it ignores SIGPIPE process-wide (`signal(SIGPIPE, SIG_IGN)`).

Fix options: a custom BIO (or `BIO_meth` wrapper) that sends with `MSG_NOSIGNAL`;
or the same block-and-consume bracket around every `tls_drive` call. Test (Linux):
TLS client writes after the server reset the connection; the process must get
`Err(TlsWriteError(_))`, not die.

## Fixed (2026-11-25)

The BIO option. On Linux (no `SO_NOSIGPIPE`, `MSG_NOSIGNAL` present) `march_tls_connect`
and `march_tls_accept` bind the session with `tls_set_fd` (runtime/march_tls.c): the
socket BIO's method with its write replaced by `send(fd, ..., MSG_NOSIGNAL)`. Every write
OpenSSL makes on the connection then fails with EPIPE without signalling, whichever call
made it (`SSL_write`, `SSL_read`, `SSL_shutdown`), and nothing is masked, so there is no
bracket that could span a scheduler wait. The BIO keeps `BIO_TYPE_SOCKET`, so `SSL_get_fd`
still works. macOS/BSD are unchanged (`SO_NOSIGPIPE` at the handshake).

Test: `test/test_tls_sigpipe.ml` (suite `stdlib`, group `tls_sigpipe`). One compiled
program plays both roles: the server completes a handshake and exits at once, the client
writes until a write fails, then reads and closes. In a local Linux container the client
exited 141 before the fix (3 of 3 runs) and 0 with "C write error" after it (3 of 3). On
macOS the test passes before and after.

Not covered: the HTTP server's TLS sessions (runtime/march_tls_session.c) use memory BIOs
and their own socket writes, and that server ignores SIGPIPE process-wide; unchanged.
