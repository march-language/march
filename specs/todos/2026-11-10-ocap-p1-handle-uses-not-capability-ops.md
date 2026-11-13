# Handover to ocap phase 1: handle uses are not capability operations (2026-11-10)

Left by ocap phase 2b, Task 10 (`specs/plans/2026-11-10-ocap-p2-handles-plan.md`, "Landing
order"; done in `specs/progress/2026-11-10-ocap-p2b-gate-raw-builtins.md`). Since that task
these builtins act only on a handle the caller already holds (opened by a checked operation),
so they are no longer in `builtin_cap_table` and are not capability operations: anything that
converts capability operations to `Result(_, CapError)` must not wrap them, or the stdlib
functions over them (`File.read_line`, `Socket.write`, `Process.wait_proc`, ...).

Removed from `builtin_cap_table` (and `Cap_symbols`, `Cap_infer`, `Cap_ops`):

- files: `file_read_line`, `file_read_chunk`, `csv_next_row`;
- TCP: `tcp_send_all`, `tcp_recv_all`, `tcp_recv_exact`, `tcp_recv_http`,
  `tcp_recv_http_headers`, `tcp_recv_chunk`, `tcp_recv_chunk_timeout`, `tcp_set_recv_timeout`,
  `tcp_recv_chunked_frame`, `tcp_recv_timeout`, `tcp_accept`, `tcp_accept_timeout`,
  `tcp_local_port`;
- UDP: `udp_connect`, `udp_close`, `udp_local_addr`, `udp_stats`, `udp_send_batch`,
  `udp_send_many`, `udp_recv_batch`;
- TLS: `tls_read`, `tls_read_timeout`, `tls_write`, `tls_negotiated_alpn`, `tls_peer_cn`,
  `tls_negotiated_group`, `tls_accept`, `tls_connect`, `tls_ctx_set_groups`;
- WebSocket: `ws_recv`, `ws_send`, `ws_select`;
- process: `process_read_line`, `process_write`, `process_kill_proc`, `process_wait_proc`.

What remains for phase 1 (or whoever lands second): nothing to convert for these; when phase
1's own tables are rebased, drop any row it still carries for one of them. Close this file
once phase 1 has confirmed its tables agree.
