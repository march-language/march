(* See cap_ops.mli. *)

type cls =
  | Checked of { entry : string list; gated : bool }
  | Use
  | Internal

let c ?(gated = true) entry = Checked { entry; gated }

let table : (string * cls) list = [
  (* IO.Console *)
  ("print",                  c ["IO.write"]);
  ("println",                c ["IO.puts"; "println"]);
  ("print_line",             c ["IO.puts"; "println"]);
  ("print_stderr",           c ["IO.warn"]);
  ("io_read_line",           c ["IO.read_line"; "IO.gets"]);
  ("io_read_byte",           c ["IO.read_byte"]);
  (* IO.FileRead / IO.FileWrite / IO.FileSystem: path conveniences *)
  ("file_exists",            c ["File.exists"]);
  ("file_read",              c ["File.read"]);
  ("file_stat",              c ["File.stat"]);
  ("dir_exists",             c ["Dir.exists"]);
  ("dir_list",               c ["Dir.list"]);
  ("file_write",             c ["File.write"]);
  ("file_append",            c ["File.append"]);
  ("file_delete",            c ["File.delete"]);
  ("file_rename",            c ["File.rename"]);
  ("file_copy",              c ["File.copy"]);
  ("dir_mkdir",              c ["Dir.mkdir"]);
  ("dir_mkdir_p",            c ["Dir.mkdir_p"]);
  ("dir_rmdir",              c ["Dir.rmdir"]);
  ("dir_rm_rf",              c ["Dir.rm_rf"]);
  (* opens that phase 2 turns into handles, and gates *)
  ("file_open",              c ~gated:false ["File.with_lines"; "File.each_line"]);
  ("csv_open",               c ~gated:false ["Csv.each_row"; "Csv.read_all"]);
  ("file_read_line",         Use);
  ("file_read_chunk",        Use);
  ("csv_next_row",           Use);
  (* IO.NetConnect and descendants *)
  ("tcp_connect",            c ~gated:false ["Socket.connect"]);
  ("tcp_connect_timeout",    c ~gated:false ["Socket.connect_timeout"]);
  ("tcp_send_all",           Use);
  ("tcp_recv_all",           Use);
  ("tcp_recv_exact",         Use);
  ("tcp_recv_http",          Use);
  ("tcp_recv_http_headers",  Use);
  ("tcp_recv_chunk",         Use);
  ("tcp_recv_chunk_timeout", Use);
  ("tcp_set_recv_timeout",   Use);
  ("tcp_recv_chunked_frame", Use);
  ("tcp_recv_timeout",       Use);
  ("dist_monitor_register",  Internal);
  ("dist_monitor_pending",   Internal);
  ("dist_monitor_ack",       Internal);
  ("dist_monitor_forget_node", Internal);
  ("ws_recv",                Use);
  ("ws_send",                Use);
  ("ws_select",              Use);
  ("dns_resolve",            c ["Dns.resolve"]);
  ("udp_open",               c ~gated:false ["Udp.open_with"]);
  ("udp_resolve",            c ~gated:false ["Udp.resolve"]);
  ("udp_connect",            c ~gated:false ["Udp.connect"]);
  ("udp_send_batch",         c ~gated:false ["Udp.send_batch"]);
  ("udp_send_many",          c ~gated:false ["Udp.send_many"]);
  ("udp_close",              Use);
  ("udp_local_addr",         Use);
  ("udp_stats",              Use);
  ("udp_recv_batch",         Use);
  ("tls_client_ctx",         c ~gated:false ["Tls.client_ctx"]);
  ("tls_server_ctx",         c ~gated:false ["Tls.server_ctx"]);
  ("tls_connect",            Use);
  ("tls_accept",             Use);
  ("tls_read",               Use);
  ("tls_read_timeout",       Use);
  ("tls_write",              Use);
  ("tls_negotiated_alpn",    Use);
  ("tls_peer_cn",            Use);
  ("tls_ctx_set_groups",     Use);
  ("tls_negotiated_group",   Use);
  (* IO.NetListen *)
  ("tcp_listen",             c ~gated:false ["HttpServer.listen"]);
  ("tcp_accept",             Use);
  ("tcp_accept_timeout",     Use);
  ("tcp_local_port",         Use);
  ("http_server_listen",     c ~gated:false ["HttpServer.listen"]);
  ("http_server_spawn_n",    c ~gated:false ["HttpServer.spawn_n"]);
  ("http_server_plain_listener", c ~gated:false ["HttpServer.plain_listener"]);
  ("http_server_bind_host",  c ~gated:false ["HttpServer.bind_host"]);
  ("http_server_wait",       Use);
  ("http_server_set_timeouts", Use);
  ("http_server_tls_configure", Use);
  ("http_server_reload_tls", Use);
  (* IO.Process *)
  ("process_env",            c ["Process.env"; "System.env"]);
  ("process_set_env",        c ["Process.set_env"; "System.put_env"]);
  ("process_cwd",            c ["Process.cwd"; "System.cwd"]);
  ("process_argv",           c ["Process.argv"; "System.argv"]);
  ("process_pid",            c ["Process.pid"; "System.pid"]);
  ("process_exit",           c ["Process.exit"; "System.exit"]);
  ("process_spawn_sync",     c ["Process.run"; "System.cmd"]);
  ("process_spawn_lines",    c ["Process.run_stream"]);
  ("process_spawn_async",    c ~gated:false ["Process.spawn_async"]);
  ("process_read_line",      Use);
  ("process_write",          Use);
  ("process_kill_proc",      Use);
  ("process_wait_proc",      Use);
  (* IO.Clock *)
  ("unix_time",              c ["System.unix_time"]);
  ("unix_time_ms",           c ["System.unix_time_ms"]);
  ("uuid_v7",                c ["UUID.v7"]);
  (* IO.Random *)
  ("random_bytes",           c ["Crypto.random_bytes"]);
  ("stdlib_random_bytes",    c ["Crypto.random_bytes"]);
  ("uuid_v4",                c ["UUID.v4"]);
  (* IO.Signal *)
  ("signal_watch",           c ["Signal.watch"]);
  ("signal_unwatch",         Use);
  ("signal_raise_self",      c ["Signal.raise"]);
  (* IO.Spawn *)
  ("task_spawn",             c ["Task.async"]);
  ("task_spawn_link",        c ["Task.async"]);
  ("task_spawn_steal",       c ["Task.async"]);
  ("task_spawn_with_cancel", c ["Task.async"]);
  ("get_work_pool",          Use);
  (* IO.Mut: opening a table by name is checked; using it is not *)
  ("vault_new",              c ["Vault.new"]);
  ("vault_whereis",          c ["Vault.whereis"]);
  ("vault_ns_set",           c ["Vault.ns_set"]);
  ("vault_ns_get",           c ["Vault.ns_get"]);
  ("vault_ns_drop",          c ["Vault.ns_drop"]);
  ("vault_set",              Use);
  ("vault_set_ttl",          Use);
  ("vault_drop",             Use);
  ("vault_update",           Use);
  ("vault_put_new",          Use);
  ("vault_incr",             Use);
  ("vault_push_capped",      Use);
  ("vault_reap",             Use);
  ("vault_close",            Use);
]

let classify name = List.assoc_opt name table

let gated =
  List.filter_map (function
      | (n, Checked { entry; gated = true }) -> Some (n, entry)
      | _ -> None)
    table
