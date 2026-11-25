# Udp.recv_batch drops received datagrams when the socket is closed concurrently (2026-11-11)

Ocap phase 2b, Task 5 review. `Udp.recv_batch` (stdlib/udp.march) checks
`handle_is_closed(b)` after the raw `udp_recv_batch` returns and, if another task
closed the socket meanwhile, answers `Err(Closed)` even when the raw call returned
`Ok(datagrams)`; those datagrams are lost. `Socket.recv` (stdlib/socket.march,
`closed_read`) keeps a non-empty read and only maps an empty read or an error to
`Err(Closed)`.

Fix: match `Socket.recv`: return `Ok(dgrams)` when the batch is non-empty and only
turn `Ok([])` (a wait the close cancelled) or an `Err` into `Err(Closed)`. Mind the
module's `cap verified` contracts (the result type is unrefined here, so no proof is
affected). Test: hard to make deterministic (the close must land after the kernel
handed the batch over); at least a unit check of the mapping.

## Fixed (2026-11-25)

Two losses, and the fixture needs both fixes:

1. `Udp.recv_batch` (stdlib/udp.march) keeps a non-empty batch when the socket was
   closed during the call; only `Ok([])` or an `Err` on a closed socket becomes
   `Err(Closed)`.
2. The commoner loss was in the runtime. `march_udp_recv_batch` (runtime/march_udp.c)
   parks in `march_sched_wait_fd`; `Udp.close` cancels that wait, which returns
   `ECANCELED`, and the function returned the error without reading a datagram that had
   been queued in the meantime. The socket was then closed with the datagram in it. It
   now reads once more on a cancelled wait and returns what it finds.

Test: `test/native/udp_close_after_datagram.march` (Linux only, one scheduler thread):
a reader parks in `Udp.recv`, main sends one datagram and closes at once, 20 rounds.
On Linux, 20 of 20 with both fixes, 0 of 20 on main, and 0 of 20 with either fix alone.
It does not run on macOS: loopback delivery is asynchronous there, so a close right after
the send can precede the datagram (5 of 20 delivered with the fix), and any wait long
enough to be safe lets the reader take the datagram the ordinary way.

Checked and not needed: after `shutdown()` a non-blocking `recvmmsg` on an empty UDP
queue answers `EAGAIN` on Linux (connected or not), so a closed socket does not produce
empty datagrams that the kept batch could pass on.

Not covered by a test: the first loss on its own (the close landing between the raw
receive's return and the closed check), which has no deterministic schedule.
