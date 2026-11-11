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
