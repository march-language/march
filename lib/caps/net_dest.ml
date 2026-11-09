(* Where a network operation's destination comes from.  See net_dest.mli. *)

type dest =
  | Url of int
  | Host of int * int option
  | Handle
  | Inbound
  | Neutral
  | Unknown

let builtin_dest (name : string) : dest option =
  match name with
  (* Connections made from a host name and port. *)
  | "tcp_connect" | "tcp_connect_timeout" -> Some (Host (0, Some 1))
  (* Operations on an already-open fd.  tls_connect is one of them: its third
     argument is the SNI / certificate name, NOT where the fd is connected. *)
  | "tcp_send_all" | "tcp_recv_all" | "tcp_recv_exact" | "tcp_recv_http"
  | "tcp_recv_http_headers" | "tcp_recv_chunk" | "tcp_recv_chunk_timeout"
  | "tcp_set_recv_timeout" | "tcp_recv_chunked_frame" | "tcp_recv_timeout"
  | "tls_connect" | "tls_read" | "tls_read_timeout" | "tls_write"
  | "tls_negotiated_alpn" | "tls_peer_cn" | "tls_negotiated_group"
  | "ws_recv" | "ws_send" | "ws_select"
  | "udp_close" | "udp_local_addr" | "udp_stats" | "udp_recv_batch" ->
    Some Handle
  (* Server side. *)
  | "tls_server_ctx" | "tls_accept" -> Some Inbound
  (* Contact no remote host. *)
  | "tls_client_ctx" | "tls_ctx_set_groups" | "udp_open" | "udp_resolve" ->
    Some Neutral
  (* Addresses the compiler does not read: a resolved UDP address string, a
     cluster node. *)
  | "udp_connect" | "udp_send_batch" | "udp_send_many"
  | "dist_monitor_register" | "dist_monitor_pending" | "dist_monitor_ack"
  | "dist_monitor_forget_node" ->
    Some Unknown
  | _ -> None

let is_network_cap (cap : string) : bool =
  cap = "IO.NetConnect"
  || (String.length cap > 14 && String.sub cap 0 14 = "IO.NetConnect.")
  || cap = "IO.WebSocket" || cap = "IO.Database"

let redirect_capable (name : string) : bool =
  match name with
  | "HttpClient.get" | "HttpClient.post" | "HttpClient.put_request"
  | "HttpClient.delete" | "HttpClient.stream_get" | "HttpClient.with_connection" ->
    true
  | _ -> false

let net_dest_attr (attrs : string list) : string option =
  let pre = "net_dest:" in
  let n = String.length pre in
  List.find_map
    (fun a ->
       if String.length a > n && String.sub a 0 n = pre then
         Some (String.sub a n (String.length a - n))
       else None)
    attrs
