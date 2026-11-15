# The raw builtins become stdlib-only, and handle uses charge nothing (2026-11-10, done 2026-11-12)

Ocap phase 2b, Task 10 (`specs/plans/2026-11-10-ocap-p2-handles-plan.md`). Filed when phase 2a
(PR march-language/march#1244) shipped the handle box, the handle types, `@[stdlib_internal]` and
`File.Handle`; closed on branch `claude/ocap-p2b-handles`.

## What changed

- **Gate.** Every raw Int-descriptor builtin behind a handle type is in
  `Typecheck_env.stdlib_only`, each with a hint naming its wrapper: the file and directory
  builtins (`file_open`, `file_read_line`, `file_read_chunk`, `file_close`, plus Task 4/7's
  `file_open_write`, `file_write_handle`, `file_seek`, `dir_open`, `dir_open_write`,
  `file_open_at`, `dir_list_at`), `csv_open`/`csv_next_row`/`csv_close`, every `tcp_*`, `udp_*`
  and `tls_*`, `ws_recv`/`ws_send`/`ws_select`, `http_server_spawn_n`, `http_server_wait`,
  `http_server_plain_listener`, `http_conn_is_tls`, and the five `process_*` handle builtins.
  A user reference is `[stdlib_internal]`.
- **Uses charge nothing.** The use builtins left `builtin_cap_table` (and with it
  `lib/caps/cap_symbols.ml`, `lib/refinecheck/cap_infer.ml` and `lib/caps/cap_ops.ml`); the
  list is in `specs/todos/2026-11-10-ocap-p1-handle-uses-not-capability-ops.md`. Opens stay:
  `file_open`, `file_open_write`, `dir_open`, `dir_open_write` (ruling R14, IO.FileWrite only),
  `csv_open`, `tcp_connect`, `tcp_connect_timeout`, `tcp_listen`, `udp_open`, `udp_resolve`,
  `tls_client_ctx`, `tls_server_ctx`, `process_spawn_async`, every `http_server_*` and the
  dist-monitor rows. `tls_connect`/`tls_accept` are uses (they run over a held `Socket`).
  A function bounded by `needs ()` may now read a `File.Handle`/`File.Dir`, write a `Socket`,
  accept on a `Listener` and read/wait on a `Process` it was handed, under both `--check` and
  the compiled ceiling. `lib/caps/net_dest.ml` keeps handle operations as `Handle` (a
  host-scoped module still cannot prove where a held socket goes).
- **`Socket.recv_exact(s, n)`** (new): the handle form of `tcp_recv_exact`, which the control
  wiring needed.
- **Migrated off raw descriptors:** `lib/desugar/control_wiring.march` (to `Socket`/`Listener`;
  only the cluster handshake and its sealed frames see `Socket.raw_fd`, since `<control>` is
  exempt from the `@[stdlib_internal]` function gate but not from the builtin gate);
  `test/native/{getaddrinfo_green_thread,tcp_accept_timeout,tcp_connect_refused_after_park}`;
  `test/two_node/{partition,skew,stall}/node_{a,b}` and `frame_tampered/node_c`; the embedded
  programs in `test_cap_net_scope`, `test_cap_package`, `test_cap_sandbox_profile`,
  `test_cap_sandbox_runtime`, `test_cap_strip` and `test_codegen` (cross TLS probe).
- **Kept on the raw builtins, with an explicit opt-in and a comment:**
  `test/native/close_returns_ok_atom` and `file_handle_leak_probe` (they pin the raw
  `file_close`/`csv_close` results and the raw handle table: `--stdlib-source` in `test/dune`);
  `test_stdlib_suite`'s compiled `file_open` FileError-cell guard (`--stdlib-source`); the
  `-- compile-flags: --stdlib-source` two-node nodes and the `--stdlib-source` test/native
  cluster loopbacks, which drive the raw-fd wire layer itself (Task 9). The typecheck unit
  tests that pin how the capability body scan treats a raw builtin lift the gate for exactly
  the names they call (`with_raw_builtins` in `test_compiler.ml`).
- **Tests:** `test_stdlib_only` `raw_handle_builtins_gated`; `test_compiler`
  `handle_use_charges_nothing` (Socket.write and Socket.accept under `needs ()` pass `--check`
  and `--compile`, Socket.connect is refused); the deferred "needs no capability" modules in
  `test/stdlib/test_file_handle.march` (Task 4) and `test_file_dir.march` (Task 7) are live,
  and `test_process.march` gained one for Task 8 (`ProcReader`).
