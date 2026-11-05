(** UDP datagram builtins for the interpreter: the [udp_*] half of
    runtime/march_udp.c (stdlib/udp.march is the API).

    Same contract, simpler engine: one [recvfrom]/[sendto] per datagram, no
    GSO/GRO, no kernel drop counter ([udp_stats] reports -1 drops).  The
    address encoding is the compiled runtime's, byte for byte, so an address
    String compares equal across backends:
      [4][port hi][port lo][4 bytes]    IPv4
      [6][port hi][port lo][16 bytes]   IPv6
    The empty String means the connected peer. *)

open Eval_types
open Eval_prim

let fd_of (n : int) : Unix.file_descr = Obj.magic n
let int_of_fd (fd : Unix.file_descr) : int = Obj.magic fd

(* [Unix.inet_addr] is the raw 4- or 16-byte address string. *)
let raw_of_inet (a : Unix.inet_addr) : string = Obj.magic a
let inet_of_raw (s : string) : Unix.inet_addr = Obj.magic s

let v4_mapped_prefix = "\000\000\000\000\000\000\000\000\000\000\255\255"

let pack (sa : Unix.sockaddr) : string =
  match sa with
  | Unix.ADDR_INET (a, port) ->
    let raw = raw_of_inet a in
    let port_s = Printf.sprintf "%c%c" (Char.chr ((port lsr 8) land 0xff)) (Char.chr (port land 0xff)) in
    if String.length raw = 4 then "\004" ^ port_s ^ raw
    else if String.length raw = 16 && String.sub raw 0 12 = v4_mapped_prefix then
      "\004" ^ port_s ^ String.sub raw 12 4
    else "\006" ^ port_s ^ raw
  | Unix.ADDR_UNIX _ -> ""

let is_v6 (fd : Unix.file_descr) : bool =
  match Unix.getsockname fd with
  | Unix.ADDR_INET (a, _) -> String.length (raw_of_inet a) = 16
  | _ -> false
  | exception Unix.Unix_error _ -> false

let unpack ~(v6 : bool) (s : string) : Unix.sockaddr option =
  let port () = (Char.code s.[1] lsl 8) lor Char.code s.[2] in
  match String.length s with
  | 7 when s.[0] = '\004' ->
    let raw = String.sub s 3 4 in
    Some (Unix.ADDR_INET (inet_of_raw (if v6 then v4_mapped_prefix ^ raw else raw), port ()))
  | 19 when s.[0] = '\006' && v6 -> Some (Unix.ADDR_INET (inet_of_raw (String.sub s 3 16), port ()))
  | _ -> None

let ok v = VCon ("Ok", [v])
let err s = VCon ("Err", [VString s])
let err_unix what e = err (what ^ ": " ^ Unix.error_message e)

let rec list_of_value = function
  | VCon ("Cons", [h; t]) -> h :: list_of_value t
  | _ -> []

let value_of_list xs = List.fold_right (fun x acc -> VCon ("Cons", [x; acc])) xs (VCon ("Nil", []))

let lookup ~passive host port =
  let opts = Unix.[AI_SOCKTYPE SOCK_DGRAM] @ (if passive then [Unix.AI_PASSIVE] else []) in
  Unix.getaddrinfo host (string_of_int port) opts

let addr_to_string (s : string) : string =
  let port () = (Char.code s.[1] lsl 8) lor Char.code s.[2] in
  match String.length s with
  | 0 -> "<connected peer>"
  | 7 when s.[0] = '\004' ->
    Printf.sprintf "%s:%d" (Unix.string_of_inet_addr (inet_of_raw (String.sub s 3 4))) (port ())
  | 19 when s.[0] = '\006' ->
    Printf.sprintf "[%s]:%d" (Unix.string_of_inet_addr (inet_of_raw (String.sub s 3 16))) (port ())
  | _ -> "<invalid address>"

let set_buf fd opt want =
  if want > 0 then begin
    let rec go v =
      if v >= 65536 then
        (try Unix.setsockopt_int fd opt v with Unix.Unix_error _ -> go (v / 2))
    in
    go (min want (1 lsl 30))
  end

let udp_open host port opts rcvbuf sndbuf =
  if port < 0 || port > 65535 then err "udp_open: port out of range"
  else
    match lookup ~passive:true (if host = "" then "0.0.0.0" else host) port with
    | [] -> err "udp_open: host not found"
    | ai :: _ ->
      (try
         let fd = Unix.socket ai.Unix.ai_family Unix.SOCK_DGRAM 0 in
         (try
            if ai.Unix.ai_family = Unix.PF_INET6 then Unix.setsockopt fd Unix.IPV6_ONLY false;
            if opts land 1 <> 0 then Unix.setsockopt fd Unix.SO_REUSEADDR true;
            if opts land 2 <> 0 then Unix.setsockopt fd Unix.SO_REUSEPORT true;
            if opts land 4 <> 0 then Unix.setsockopt fd Unix.SO_BROADCAST true;
            set_buf fd Unix.SO_RCVBUF rcvbuf;
            set_buf fd Unix.SO_SNDBUF sndbuf;
            Unix.bind fd ai.Unix.ai_addr;
            Unix.set_nonblock fd;
            ok (VInt (int_of_fd fd))
          with Unix.Unix_error (e, f, _) ->
            Unix.close fd;
            err_unix ("udp_open: " ^ f) e)
       with Unix.Unix_error (e, _, _) -> err_unix "udp_open: socket" e)

let udp_resolve host port =
  if host = "" then err "udp_resolve: empty host"
  else if port < 0 || port > 65535 then err "udp_resolve: port out of range"
  else
    match lookup ~passive:false host port with
    | [] -> err "udp_resolve: host not found"
    | ais ->
      let pick =
        match List.find_opt (fun ai -> ai.Unix.ai_family = Unix.PF_INET) ais with
        | Some ai -> ai
        | None -> List.hd ais
      in
      ok (VString (pack pick.Unix.ai_addr))

(* Wait for [fd] to become ready; deadline [None] = for ever. *)
let wait fd ~write deadline =
  let rec go () =
    let t = match deadline with
      | None -> -1.0
      | Some d -> max 0.0 (d -. Unix.gettimeofday ()) in
    match (if write then Unix.select [] [fd] [] t else Unix.select [fd] [] [] t) with
    | [], [], _ -> `Timeout
    | _ -> `Ready
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> go ()
  in
  go ()

(* Send each (dst, payload) in order, waiting out a full buffer. *)
let send_all fd (outs : (Unix.sockaddr option * string) list) =
  let total = List.length outs in
  let rec go sent = function
    | [] -> ok (VInt sent)
    | (dst, p) :: rest as all ->
      let b = Bytes.unsafe_of_string p in
      (match
         (match dst with
          | Some sa -> Unix.sendto fd b 0 (Bytes.length b) [] sa
          | None -> Unix.send fd b 0 (Bytes.length b) [])
       with
       | _ -> go (sent + 1) rest
       | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.ENOBUFS), _, _) ->
         ignore (wait fd ~write:true (Some (Unix.gettimeofday () +. 0.001)));
         go sent all
       | exception Unix.Unix_error (Unix.EINTR, _, _) -> go sent all
       | exception Unix.Unix_error (e, _, _) ->
         err (Printf.sprintf "send failed after %d of %d datagrams: %s"
                sent total (Unix.error_message e)))
  in
  go 0 outs

let udp_send_batch fd addr payloads =
  let fd = fd_of fd in
  let dst =
    if addr = "" then Ok None
    else match unpack ~v6:(is_v6 fd) addr with
      | Some sa -> Ok (Some sa)
      | None -> Error ()
  in
  match dst with
  | Error () -> err "udp_send: invalid address"
  | Ok dst ->
    send_all fd (List.map (function
        | VString p -> (dst, p)
        | _ -> eval_error "udp_send_batch: payload must be a String") payloads)

let udp_send_many fd pairs =
  let fd = fd_of fd in
  let v6 = is_v6 fd in
  let exception Bad in
  try
    send_all fd (List.map (function
        | VTuple [VString "" ; VString p] -> (None, p)
        | VTuple [VString a; VString p] ->
          (match unpack ~v6 a with Some sa -> (Some sa, p) | None -> raise Bad)
        | _ -> eval_error "udp_send_many: expected (addr, payload) pairs") pairs)
  with Bad -> err "udp_send: invalid address"

let udp_recv_batch fd max_msgs max_size timeout_ms =
  let fd = fd_of fd in
  let max_msgs = max 1 (min max_msgs 1024) in
  let max_size = max 1 (min max_size 65535) in
  let buf = Bytes.create max_size in
  let deadline =
    if timeout_ms > 0 then Some (Unix.gettimeofday () +. float_of_int timeout_ms /. 1000.) else None in
  let rec drain acc n =
    if n >= max_msgs then Ok (List.rev acc)
    else
      match Unix.recvfrom fd buf 0 max_size [] with
      | (len, from) ->
        drain (VTuple [VString (pack from); VString (Bytes.sub_string buf 0 len)] :: acc) (n + 1)
      | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> Ok (List.rev acc)
      | exception Unix.Unix_error (e, _, _) ->
        if acc = [] then Error e else Ok (List.rev acc)
  in
  let rec loop () =
    match drain [] 0 with
    | Error e -> err_unix "udp_recv" e
    | Ok (_ :: _ as got) -> ok (value_of_list got)
    | Ok [] when timeout_ms = 0 -> ok (value_of_list [])
    | Ok [] ->
      (match wait fd ~write:false deadline with
       | `Timeout -> ok (value_of_list [])
       | `Ready -> loop ())
  in
  loop ()

let builtins : (string * value) list = [
  ("udp_open", VBuiltin ("udp_open", function
       | [VString h; VInt p; VInt o; VInt rb; VInt sb] -> udp_open h p o rb sb
       | _ -> eval_error "udp_open(host, port, opts, rcvbuf, sndbuf)"));
  ("udp_resolve", VBuiltin ("udp_resolve", function
       | [VString h; VInt p] -> udp_resolve h p
       | _ -> eval_error "udp_resolve(host, port)"));
  ("udp_addr_to_string", VBuiltin ("udp_addr_to_string", function
       | [VString a] -> VString (addr_to_string a)
       | _ -> eval_error "udp_addr_to_string(addr)"));
  ("udp_connect", VBuiltin ("udp_connect", function
       | [VInt fd; VString a] ->
         let fd = fd_of fd in
         (match unpack ~v6:(is_v6 fd) a with
          | None -> err "udp_connect: invalid address"
          | Some sa ->
            (try Unix.connect fd sa; ok VUnit
             with Unix.Unix_error (e, _, _) -> err_unix "udp_connect" e))
       | _ -> eval_error "udp_connect(fd, addr)"));
  ("udp_close", VBuiltin ("udp_close", function
       | [VInt fd] -> (try Unix.close (fd_of fd) with Unix.Unix_error _ -> ()); VUnit
       | _ -> eval_error "udp_close(fd)"));
  ("udp_local_addr", VBuiltin ("udp_local_addr", function
       | [VInt fd] ->
         (match Unix.getsockname (fd_of fd) with
          | Unix.ADDR_INET _ as sa -> ok (VString (pack sa))
          | Unix.ADDR_UNIX _ -> err "udp_local_addr: not an INET socket"
          | exception Unix.Unix_error (e, _, _) -> err_unix "udp_local_addr" e)
       | _ -> eval_error "udp_local_addr(fd)"));
  ("udp_stats", VBuiltin ("udp_stats", function
       | [VInt _] -> VTuple [VInt (-1); VInt 0]
       | _ -> eval_error "udp_stats(fd)"));
  ("udp_send_batch", VBuiltin ("udp_send_batch", function
       | [VInt fd; VString a; ps] -> udp_send_batch fd a (list_of_value ps)
       | _ -> eval_error "udp_send_batch(fd, addr, payloads)"));
  ("udp_send_many", VBuiltin ("udp_send_many", function
       | [VInt fd; ps] -> udp_send_many fd (list_of_value ps)
       | _ -> eval_error "udp_send_many(fd, pairs)"));
  ("udp_recv_batch", VBuiltin ("udp_recv_batch", function
       | [VInt fd; VInt m; VInt s; VInt t] -> udp_recv_batch fd m s t
       | _ -> eval_error "udp_recv_batch(fd, max_msgs, max_size, timeout_ms)"));
]
