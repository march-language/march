`[P3]` Udp: an io_uring receive/send backend on Linux

`stdlib/udp.march` batches through `recvmmsg`/`sendmmsg` + GSO/GRO
(specs/progress/2026-11-04-udp-stdlib-high-throughput.md). The next step that
needs no privileges is io_uring: multishot `IORING_OP_RECVMSG` with a provided
buffer ring removes the per-batch syscall and the readiness park, and
registered buffers remove a copy. The API is already batch-shaped, so this is a
runtime change behind `udp_recv_batch` / `udp_send_batch`. Gate it on kernel
support at `udp_open` (fall back to mmsg), and measure it against
`bench/udp_flood.march` and the mmsg numbers in the progress file.
