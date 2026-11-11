# HTTP client and server on handles (2026-11-11)

Ocap phase 2b, Task 6 (plan: `specs/plans/2026-11-10-ocap-p2-handles-plan.md`). Closes
`specs/todos/2026-11-10-ocap-p2b-http-on-handles.md`.

- `stdlib/http_transport.march`: `connect(req)` returns `Ok(Socket)` (errors unchanged:
  `ConnectionRefused(msg)` carries the connect message). `request_on`, `stream_request_on`,
  `stream_chunked_body` and `stream_fixed_body` take a `Socket`; each raw call is bracketed
  by `handle_enter` / `handle_leave` in its own private helper (`send_all_on`,
  `recv_http_on`, ...), so a use after close is `Err(Closed)` and the descriptor is never
  released under a call in flight. The helpers take no closure: the capability ceiling
  charges a lambda lifted out of a stdlib function to the entry module, which made
  `march check` and the REPL reject `HttpTransport.simple_get` for `IO.NetConnect`
  (`test/test_cap_mode_parity.ml`). Filed as
  `specs/todos/2026-11-11-cap-attrib-stdlib-lambdas.md`; the same bug, through `Tls`'s
  closures (Task 5), still rejects it for `IO.NetConnect.TLS`. The
  connect-per-request paths (`request` over plain HTTP and HTTPS) also open a `Socket`
  instead of calling `tcp_connect` / `tcp_close` directly.
- `stdlib/http_client.march`: `transport_keepalive` takes a `Socket` (it closes it with
  `Socket.close` on failure); `run_on_fd` is renamed `run_on` with no alias (no caller
  outside the stdlib); `with_connection` and `stream_get` close the socket.
- `stdlib/http_server.march`: `Conn`'s first field is a `Socket`. `HttpServer.fd` is
  `@[stdlib_internal]` (`Socket.raw_fd`, -1 when closed); `peer_addr` goes through
  `Socket.peer_addr` (`""` on a closed socket); new
  `test_conn(method, path, headers, body)` builds a request conn over a closed borrowed
  socket (`?` splits off the query string; `path_info` as the runtime builds it).
- Runtime (`runtime/march_http.c`, `march_http_evloop.c`, `march_http_internal.h`,
  `march_http_io.h`): `march_http_conn_sock(fd)` makes one TCP_BORROWED box per
  connection, and `march_conn_from_parsed` stores it (one reference per `Conn`) in field 0.
  `march_http_conn_sock_done` closes the box and drops the server's reference when the
  connection ends, before `close(fd)` (thread pool: end of `connection_thread`; event
  loop: `close_conn`, and `detach_conn` on a WebSocket hand-off), so a `Conn` kept past its
  connection reaches no descriptor. `march_process_one_request` takes the box too.
- Interpreter (`lib/eval/eval_net.ml`): both servers build the `Conn` over a per-request
  borrowed box (`conn_socket`) and close it when the pipeline returns
  (`Eval_handle.close`, new).
- Call sites: `test/stdlib/test_http_server.march` (its local mirror of `Conn` replaced by
  `HttpServer.test_conn`; new test `handler unit test with test_conn`; also declares
  `needs IO.NetListen`, which `march test` has required since phase 3),
  `test/test_https_native.ml`, `examples/bastion_tests/*.march`, and
  `forge/tasks/forge_registry.march` (plain-HTTP path on `Socket.connect` / `write` /
  `recv`).

Benchmark (`bench/tfb/tfb_server.march` /plaintext, `--compile --opt 2`, macOS/arm64,
`wrk -t4 -d8s`, base = this branch's parent, interleaved, load average 4.3 to 6.9):
event loop (`-c256`) base 26.42 / 26.50 / 25.99 CPU-us/request vs new 25.79 / 26.15 / 26.36;
thread pool (`-c64`) base 26.56 / 26.93 / 27.19 vs new 26.72 / 26.90 / 26.78. Within noise;
req/s pinned near macOS loopback's ~30k either way.
