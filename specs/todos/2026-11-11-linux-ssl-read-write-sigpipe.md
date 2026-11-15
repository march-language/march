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
