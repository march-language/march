(** CSV reader, HTTP server, WebSocket framing, and the non-blocking
    connection multiplexer.

    Extracted verbatim from eval.ml:2568-3738 — no behavior change.
    [handle_http_connection] (the blocking implementation) stays ABOVE
    the non-blocking multiplexer that references it, exactly as in the
    original file. *)

open Eval_types
open Eval_prim
open Eval_runtime

(* ------------------------------------------------------------------ *)
(* CSV parser state                                                    *)
(* ------------------------------------------------------------------ *)

(** Opaque CSV reader state stored in a module-level table.
    The table maps integer handles to (in_channel, delimiter, mode, eof_flag). *)
type csv_mode = CsvSimple | CsvRfc4180

type csv_reader = {
  csv_ic      : in_channel;
  csv_delim   : char;
  csv_mode    : csv_mode;
  mutable csv_eof : bool;
}

let csv_table : (int, csv_reader) Hashtbl.t = Hashtbl.create 4
let next_csv_id : int ref = ref 0

(** Scan one complete CSV row from [r].
    Returns [Some fields] or [None] on EOF (before any chars were read). *)
let csv_scan_row (r : csv_reader) : string list option =
  let ic    = r.csv_ic in
  let delim = r.csv_delim in
  if r.csv_eof then None
  else
    let fields      = ref [] in
    let cur         = Buffer.create 64 in
    let row_started = ref false in
    let finished    = ref false in

    (* Emit the current buffer as a field, clear the buffer. *)
    let emit () =
      fields := Buffer.contents cur :: !fields;
      Buffer.clear cur
    in

    let next_char () = try Some (input_char ic) with End_of_file -> None in

    (match r.csv_mode with
     | CsvSimple ->
       (* No quoting: split on delimiter, newline ends the row. *)
       let rec loop () =
         if !finished then ()
         else match next_char () with
           | None ->
             r.csv_eof <- true;
             if !row_started then emit ()
           | Some c ->
             row_started := true;
             if c = delim then (emit (); loop ())
             else if c = '\n' then (emit (); finished := true)
             else if c = '\r' then begin
               (match next_char () with
                | Some '\n' | None -> ()
                | Some c2 -> Buffer.add_char cur c2);
               emit (); finished := true
             end else (Buffer.add_char cur c; loop ())
       in
       loop ()

     | CsvRfc4180 ->
       (* 4-state FSM: FieldStart → Unquoted | Quoted → QuoteInQuoted. *)
       (* State is encoded in two bools: in_quoted and after_close_quote. *)
       let in_quoted       = ref false in
       let after_close_q   = ref false in
       let rec loop () =
         if !finished then ()
         else match next_char () with
           | None ->
             r.csv_eof <- true;
             if !row_started || Buffer.length cur > 0 || !in_quoted then emit ()
           | Some c ->
             row_started := true;
             if !after_close_q then begin
               (* QuoteInQuoted state: previous char was '"' inside/after a quoted field *)
               after_close_q := false;
               if c = '"' then begin
                 (* doubled-quote escape produces a literal quote *)
                 Buffer.add_char cur '"';
                 in_quoted := true;
                 loop ()
               end else if c = delim then begin
                 emit (); loop ()
               end else if c = '\n' then begin
                 emit (); finished := true
               end else if c = '\r' then begin
                 (match next_char () with
                  | Some '\n' | None -> ()
                  | Some c2 -> Buffer.add_char cur c2);
                 emit (); finished := true
               end else begin
                 (* Malformed: char after close-quote; treat literally *)
                 Buffer.add_char cur c; loop ()
               end
             end else if !in_quoted then begin
               if c = '"' then begin
                 (* Might be end-of-field or "" escape; decide on next char *)
                 in_quoted := false;
                 after_close_q := true;
                 loop ()
               end else begin
                 Buffer.add_char cur c; loop ()
               end
             end else begin
               (* FieldStart / Unquoted *)
               if c = '"' && Buffer.length cur = 0 then begin
                 in_quoted := true; loop ()
               end else if c = delim then begin
                 emit (); loop ()
               end else if c = '\n' then begin
                 emit (); finished := true
               end else if c = '\r' then begin
                 (match next_char () with
                  | Some '\n' | None -> ()
                  | Some c2 -> Buffer.add_char cur c2);
                 emit (); finished := true
               end else begin
                 Buffer.add_char cur c; loop ()
               end
             end
       in
       loop ());

    if r.csv_eof && not !row_started && !fields = [] then None
    else Some (List.rev !fields)

(** Dispatch function for the csv_open builtin. *)
let csv_open_impl : value list -> value = function
  | [VString path; VString delim_str; VAtom mode_str] ->
    let delim = if String.length delim_str > 0 then delim_str.[0] else ',' in
    let mode  = if mode_str = "simple" then CsvSimple else CsvRfc4180 in
    (try
       let ic = open_in path in
       let id = !next_csv_id in
       incr next_csv_id;
       Hashtbl.add csv_table id
         { csv_ic = ic; csv_delim = delim; csv_mode = mode; csv_eof = false };
       VCon ("Ok", [VInt id])
     with Sys_error msg ->
       VCon ("Err", [VCon ("FileError", [VString msg])]))
  | _ -> eval_error "csv_open(path, delimiter, mode)"

(** Dispatch function for the csv_next_row builtin. *)
let csv_next_row_impl : value list -> value = function
  | [VInt id] ->
    (match Hashtbl.find_opt csv_table id with
     | None -> eval_error "csv_next_row: invalid handle %d" id
     | Some r ->
       (match csv_scan_row r with
        | None -> VCon ("CsvEof", [])
        | Some fields ->
          let lst = List.fold_right
            (fun f acc -> VCon ("Cons", [VString f; acc]))
            fields (VCon ("Nil", [])) in
          VCon ("Row", [lst])))
  | _ -> eval_error "csv_next_row(handle)"

(** Dispatch function for the csv_close builtin. *)
let csv_close_impl : value list -> value = function
  | [VInt id] ->
    (match Hashtbl.find_opt csv_table id with
     | None -> VAtom "ok"
     | Some r ->
       (try close_in r.csv_ic with _ -> ());
       Hashtbl.remove csv_table id;
       VAtom "ok")
  | _ -> eval_error "csv_close(handle)"

(* ------------------------------------------------------------------ *)
(* HTTP server helpers (interpreter mode)                             *)
(* ------------------------------------------------------------------ *)

(** Convert an OCaml string list to a March List(String) value. *)
let march_string_list xs =
  List.fold_right
    (fun s acc -> VCon ("Cons", [VString s; acc]))
    xs (VCon ("Nil", []))

(** Parse an HTTP method string to the March Method variant. *)
let http_method_of_string s =
  match String.lowercase_ascii s with
  | "get"     -> VAtom "get"
  | "post"    -> VAtom "post"
  | "put"     -> VAtom "put"
  | "patch"   -> VAtom "patch"
  | "delete"  -> VAtom "delete"
  | "head"    -> VAtom "head"
  | "options" -> VAtom "options"
  | "trace"   -> VAtom "trace"
  | "connect" -> VAtom "connect"
  | _         -> VAtom (String.lowercase_ascii s)

(** Split a URI path on "/" into non-empty segments → March List(String). *)
let split_path_info path =
  path
  |> String.split_on_char '/'
  |> List.filter (fun s -> s <> "")
  |> march_string_list

(** Read exactly one HTTP header line (up to CRLF) from a Unix socket.
    Returns the line without the trailing CR/LF. Raises End_of_file on close. *)
let http_recv_line sock =
  let buf = Buffer.create 128 in
  let one = Bytes.create 1 in
  let stop = ref false in
  while not !stop do
    let n = Unix.recv sock one 0 1 [] in
    if n = 0 then (stop := true)
    else begin
      let c = Bytes.get one 0 in
      if c = '\n' then stop := true
      else Buffer.add_char buf c
    end
  done;
  let s = Buffer.contents buf in
  (* Strip trailing CR if present *)
  if String.length s > 0 && s.[String.length s - 1] = '\r'
  then String.sub s 0 (String.length s - 1)
  else s

(** Read exactly [n] bytes from a socket into a string. *)
let http_recv_exactly sock n =
  let buf = Bytes.create n in
  let remaining = ref n in
  let off = ref 0 in
  while !remaining > 0 do
    let got = Unix.recv sock buf !off !remaining [] in
    if got = 0 then remaining := 0
    else begin off := !off + got; remaining := !remaining - got end
  done;
  Bytes.sub_string buf 0 !off

(** Parse "Name: Value" header lines into an OCaml association list. *)
let parse_header_line line =
  match String.index_opt line ':' with
  | None -> None
  | Some i ->
    let name  = String.sub line 0 i in
    let value = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
    Some (name, value)

(** Build a March Conn value from parsed request data.
    The [headers_raw] list contains (name, value) pairs.
    [fd] is the client socket fd so builtins like tcp_peer_addr can
    query the connection (0 when no live socket backs the conn). *)
let build_conn_value ?(fd = 0) ~method_str ~full_path ~headers_raw ~body () =
  let path, query_string =
    match String.index_opt full_path '?' with
    | Some i ->
      ( String.sub full_path 0 i,
        String.sub full_path (i + 1) (String.length full_path - i - 1) )
    | None -> (full_path, "")
  in
  let method_val  = http_method_of_string method_str in
  let path_info   = split_path_info path in
  let header_list =
    List.fold_right
      (fun (n, v) acc ->
         VCon ("Cons", [VCon ("Header", [VString n; VString v]); acc]))
      headers_raw (VCon ("Nil", []))
  in
  VCon ("Conn", [
    VInt fd;                 (* client socket fd (0 = no live socket) *)
    method_val;
    VString path;
    path_info;
    VString query_string;
    header_list;
    VString body;
    VInt 0;                  (* response status = 0 (not yet set) *)
    VCon ("Nil", []);        (* response headers = [] *)
    VString "";              (* response body = "" *)
    VBool false;             (* halted = false *)
    VCon ("Nil", []);        (* assigns = [] *)
    VCon ("NoUpgrade", []);  (* upgrade = NoUpgrade *)
  ])

(** Extract (status, resp_headers_value, resp_body) from a March Conn. *)
let extract_conn_response conn =
  match conn with
  | VCon ("Conn", [_fd; _meth; _path; _pi; _qs;
                   _rh; _rb;
                   VInt status; resp_headers; VString resp_body;
                   _halted; _assigns; _upgrade]) ->
    (status, resp_headers, resp_body)
  | _ -> (500, VCon ("Nil", []), "Internal Server Error")

(** Standard HTTP reason phrases. *)
let http_reason_phrase = function
  | 200 -> "OK"        | 201 -> "Created"
  | 204 -> "No Content"
  | 301 -> "Moved Permanently" | 302 -> "Found"
  | 304 -> "Not Modified"
  | 400 -> "Bad Request"       | 401 -> "Unauthorized"
  | 403 -> "Forbidden"         | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 500 -> "Internal Server Error"
  | n   -> string_of_int n

(** Serialize a March List(Header) value to HTTP header lines. *)
let rec march_headers_to_string = function
  | VCon ("Nil", []) -> ""
  | VCon ("Cons", [VCon ("Header", [VString n; VString v]); rest]) ->
    n ^ ": " ^ v ^ "\r\n" ^ march_headers_to_string rest
  | _ -> ""

(* ── Cooperative blocking for WebSocket-owned sockets ───────────────── *)
(* A WebSocket connection's March handler (e.g. a `ws_loop` that calls
   WebSocket.recv in a loop) is written in ordinary blocking style: recv
   must not return until a frame arrives. Running that inline on the
   single-threaded HTTP event loop would stall EVERY other connection for
   the WS connection's entire lifetime — one idle browser tab holding a
   socket open would block all further page loads.

   So a WS-owned socket stays non-blocking, and every recv/send that would
   block performs [Ws_block] instead. [run_http_event_loop] installs an
   effect handler that captures the continuation, parks it against the fd,
   and resumes it once select reports that fd ready. That's the same
   cooperative discipline the HTTP request/response phases already use —
   but here the suspension point is deep inside the *interpreted* handler,
   which is precisely what an effect continuation can capture and a
   hand-rolled state machine cannot (we do not control the shape of the
   user's ws_loop).

   Callers with no handler installed — the blocking spawn_n accept loop,
   or any genuinely blocking socket — get [Effect.Unhandled] and fall back
   to a blocking select, preserving the previous behavior exactly. *)
type ws_wait_dir = Ws_wait_read | Ws_wait_write

type _ Effect.t +=
  Ws_block : (Unix.file_descr * ws_wait_dir) -> unit Effect.t

let ws_wait_ready (sock : Unix.file_descr) (dir : ws_wait_dir) : unit =
  try Effect.perform (Ws_block (sock, dir))
  with Effect.Unhandled _ ->
    (* No event loop driving us: wait synchronously, as before. *)
    (try
       match dir with
       | Ws_wait_read  -> ignore (Unix.select [sock] [] [] (-1.0))
       | Ws_wait_write -> ignore (Unix.select [] [sock] [] (-1.0))
     with _ -> ())

(** Send all bytes in [data] to [sock], ignoring short writes.
    On a non-blocking socket an EAGAIN is a "not yet", never an error:
    yield until writable and resume, or the response would be silently
    truncated (the pre-existing [with Unix_error _ -> ()] below would
    otherwise swallow it). *)
let tcp_send_all sock data =
  let buf   = Bytes.of_string data in
  let total = Bytes.length buf in
  let off   = ref 0 in
  (try
     while !off < total do
       match
         (try `Sent (Unix.send sock buf !off (total - !off) [])
          with Unix.Unix_error
                 ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> `Again)
       with
       | `Again  -> ws_wait_ready sock Ws_wait_write
       | `Sent 0 -> off := total
       | `Sent n -> off := !off + n
     done
   with Unix.Unix_error _ -> ())

(* ------------------------------------------------------------------ *)
(* WebSocket helpers                                                   *)
(* ------------------------------------------------------------------ *)

(** Base64 encoding table. *)
let b64_table =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

(** Encode a raw byte string to base64. *)
let base64_encode s =
  let n = String.length s in
  let out = Buffer.create ((n / 3 + 1) * 4) in
  let i = ref 0 in
  while !i + 2 < n do
    let a = Char.code s.[!i] in
    let b = Char.code s.[!i + 1] in
    let c = Char.code s.[!i + 2] in
    Buffer.add_char out b64_table.[a lsr 2];
    Buffer.add_char out b64_table.[((a land 3) lsl 4) lor (b lsr 4)];
    Buffer.add_char out b64_table.[((b land 0xF) lsl 2) lor (c lsr 6)];
    Buffer.add_char out b64_table.[c land 0x3F];
    i := !i + 3
  done;
  (match n - !i with
   | 1 ->
     let a = Char.code s.[!i] in
     Buffer.add_char out b64_table.[a lsr 2];
     Buffer.add_char out b64_table.[(a land 3) lsl 4];
     Buffer.add_string out "=="
   | 2 ->
     let a = Char.code s.[!i] in
     let b = Char.code s.[!i + 1] in
     Buffer.add_char out b64_table.[a lsr 2];
     Buffer.add_char out b64_table.[((a land 3) lsl 4) lor (b lsr 4)];
     Buffer.add_char out b64_table.[(b land 0xF) lsl 2];
     Buffer.add_char out '='
   | _ -> ());
  Buffer.contents out

(** Decode a base64 string to raw bytes. Strict per RFC 4648:
    - input length MUST be a non-negative multiple of 4 (zero is OK)
    - padding is exactly 0, 1, or 2 trailing `=` characters
    - all non-padding characters MUST be in the base64 alphabet
    Returns [Error msg] on bad input. *)
let base64_decode (s : string) : (string, string) result =
  let dec = Array.make 256 (-1) in
  String.iteri (fun i c ->
    dec.(Char.code c) <- i
  ) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let n = String.length s in
  if n mod 4 <> 0 then
    Error (Printf.sprintf "base64_decode: input length %d is not a multiple of 4" n)
  else if n = 0 then
    Ok ""
  else
    (* Count trailing '=' padding (0, 1, or 2 only). *)
    let pad =
      if s.[n-1] <> '=' then 0
      else if n >= 2 && s.[n-2] = '=' then
        (if n >= 3 && s.[n-3] = '=' then 3 else 2)
      else 1
    in
    if pad > 2 then
      Error "base64_decode: too much padding (more than 2 '=' characters)"
    else
      let out_len = (n / 4 * 3) - pad in
      let out = Bytes.create out_len in
      let o = ref 0 in
      let bad = ref None in
      let i = ref 0 in
      while !bad = None && !i < n - pad do
        let lookup k =
          if k >= n - pad then 0  (* impossible given the loop bound *)
          else
            let v = dec.(Char.code s.[k]) in
            if v < 0 then begin
              bad := Some (Printf.sprintf
                "base64_decode: invalid character '%c' at offset %d"
                s.[k] k);
              0
            end else v
        in
        let a = lookup !i in
        let b = lookup (!i+1) in
        let c = if !i+2 < n - pad then lookup (!i+2) else 0 in
        let d = if !i+3 < n - pad then lookup (!i+3) else 0 in
        if !bad = None then begin
          if !o < out_len then begin Bytes.set out !o (Char.chr (((a lsl 2) lor (b lsr 4)) land 0xFF)); incr o end;
          if !o < out_len then begin Bytes.set out !o (Char.chr ((((b land 0xF) lsl 4) lor (c lsr 2)) land 0xFF)); incr o end;
          if !o < out_len then begin Bytes.set out !o (Char.chr ((((c land 3) lsl 6) lor d) land 0xFF)); incr o end
        end;
        i := !i + 4
      done;
      match !bad with
      | Some msg -> Error msg
      | None -> Ok (Bytes.to_string out)

(* ── Compression C stubs (compress_stubs.c) ─────────────────────────────── *
 * Each stub returns a string on success or raises Failure(msg) on error.
 * eval.ml wraps results into Ok(Bytes) | Err(String) March values.
 * ──────────────────────────────────────────────────────────────────────── *)
external caml_march_gzip_encode    : string -> int -> string = "caml_march_gzip_encode"
external caml_march_gzip_decode    : string -> string        = "caml_march_gzip_decode"
external caml_march_deflate_encode : string -> string        = "caml_march_deflate_encode"
external caml_march_deflate_decode : string -> string        = "caml_march_deflate_decode"
external caml_march_zstd_encode    : string -> int -> string = "caml_march_zstd_encode"
external caml_march_zstd_decode    : string -> string        = "caml_march_zstd_decode"
external caml_march_brotli_encode  : string -> int -> int -> string = "caml_march_brotli_encode"
external caml_march_brotli_decode  : string -> string        = "caml_march_brotli_decode"

(** Convert an OCaml raw string to a March Bytes value.

    [type Bytes = Bytes(String)] — the payload is the raw byte buffer itself,
    so this is a wrap rather than the per-byte cons spine it used to build.
    See specs/plans/2026-08-10-array-backed-bytes-design.md. *)
let march_bytes_of_string (s : string) : value =
  VCon ("Bytes", [VString s])

(** Extract raw bytes from a March value (String or Bytes). *)
let march_val_to_raw (v : value) : (string, string) result =
  match v with
  | VString s -> Ok s
  | VCon ("Bytes", [VString s]) -> Ok s
  (* Tolerate the legacy cons-spine payload: an FFI shim or a serialized value
     produced before the representation change can still reach here. *)
  | VCon ("Bytes", [lst]) ->
    let buf = Buffer.create 16 in
    let rec go = function
      | VCon ("Nil", []) -> Ok ()
      | VCon ("Cons", [VInt b; rest]) ->
        Buffer.add_char buf (Char.chr (b land 0xFF)); go rest
      | _ -> Error "Bytes: expected String payload"
    in
    (match go lst with Ok () -> Ok (Buffer.contents buf) | Error e -> Error e)
  | _ -> Error (Printf.sprintf "expected String or Bytes, got %s" (value_to_string v))

(** Build a `File.FileError` March value from a `Unix.error`. Maps the
    common POSIX error codes onto the named variants (NotFound /
    Permission / IsDirectory / NotEmpty) and falls back to IoError for
    anything else.  Preserves the path in the payload so callers can
    report which file failed. *)
let file_error_of_unix (path : string) (e : Unix.error) : value =
  match e with
  | Unix.ENOENT      -> VCon ("NotFound",   [VString path])
  | Unix.EACCES
  | Unix.EPERM       -> VCon ("Permission", [VString path])
  | Unix.EISDIR      -> VCon ("IsDirectory",[VString path])
  | Unix.ENOTEMPTY   -> VCon ("NotEmpty",   [VString path])
  | _ ->
    VCon ("IoError",
          [VString (Printf.sprintf "%s: %s" path (Unix.error_message e))])

(** Map a Sys_error message to a FileError variant using best-effort
    substring matching.  OCaml's Sys module raises [Sys_error] with a
    textual "path: reason" format that's not machine-parseable, but the
    common cases are consistent enough to classify.  This is a fallback
    for operations that still use the Sys API (Sys.remove, etc.); the
    Unix_error catch above should fire first when the underlying call
    is a Unix primitive. *)
let file_error_of_sys (path : string) (msg : string) : value =
  let contains s sub =
    let ls = String.length s and lb = String.length sub in
    if lb > ls then false
    else
      let rec loop i =
        if i + lb > ls then false
        else if String.sub s i lb = sub then true
        else loop (i + 1)
      in
      loop 0
  in
  if contains msg "No such file" || contains msg "No such" then
    VCon ("NotFound", [VString path])
  else if contains msg "Permission denied" then
    VCon ("Permission", [VString path])
  else if contains msg "Is a directory" then
    VCon ("IsDirectory", [VString path])
  else if contains msg "Directory not empty" then
    VCon ("NotEmpty", [VString path])
  else
    VCon ("IoError", [VString msg])

(** PBKDF2-HMAC-SHA256: derive [dklen] bytes from [password] and [salt]
    using [iters] iterations of HMAC-SHA256. *)
let pbkdf2_hmac_sha256 ~password ~salt ~iterations ~dklen : string =
  let hash_len = 32 in (* SHA-256 output bytes *)
  let blocks = (dklen + hash_len - 1) / hash_len in
  let buf = Buffer.create dklen in
  for block_idx = 1 to blocks do
    (* U1 = HMAC(password, salt || INT(block_idx)) *)
    let block_num = Bytes.create 4 in
    Bytes.set block_num 0 (Char.chr ((block_idx lsr 24) land 0xFF));
    Bytes.set block_num 1 (Char.chr ((block_idx lsr 16) land 0xFF));
    Bytes.set block_num 2 (Char.chr ((block_idx lsr  8) land 0xFF));
    Bytes.set block_num 3 (Char.chr ( block_idx         land 0xFF));
    let u1 =
      Digestif.SHA256.(to_raw_string
        (hmac_string ~key:password (salt ^ Bytes.to_string block_num)))
    in
    let xor_block = Bytes.of_string u1 in
    let prev = ref u1 in
    for _ = 2 to iterations do
      let ui = Digestif.SHA256.(to_raw_string (hmac_string ~key:password !prev)) in
      let uib = Bytes.of_string ui in
      Bytes.iteri (fun i c ->
        Bytes.set xor_block i (Char.chr (Char.code c lxor Char.code (Bytes.get uib i)))
      ) xor_block;
      prev := ui
    done;
    Buffer.add_string buf (Bytes.to_string xor_block)
  done;
  String.sub (Buffer.contents buf) 0 dklen

(** Compute the WebSocket accept key: SHA1(key + magic) |> base64. *)
let ws_accept_key (client_key : string) : string =
  let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" in
  let input = client_key ^ magic in
  let digest = Digestif.SHA1.(to_raw_string (digest_string input)) in
  base64_encode digest

(** Read exactly [n] bytes from a socket into a Bytes buffer at [off].
    Returns true on success, false if the connection closed early. *)
let ws_recv_exact sock (buf : bytes) off n =
  let got = ref 0 in
  let ok  = ref true in
  while !ok && !got < n do
    (* EAGAIN on a WS-owned (non-blocking) socket means "no bytes yet", not
       end-of-stream: yield to the event loop and resume mid-frame. [got]
       is captured by the continuation, so a frame split across several
       readiness events reassembles correctly. Without this the caller's
       catch-all would misread EAGAIN as the peer hanging up. *)
    match
      (try `Got (Unix.recv sock buf (off + !got) (n - !got) [])
       with Unix.Unix_error
              ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> `Again)
    with
    | `Again -> ws_wait_ready sock Ws_wait_read
    | `Got 0 -> ok := false
    | `Got r -> got := !got + r
  done;
  !ok

(** Read and parse one WebSocket frame from [sock].
    Returns a March WsFrame variant value. *)
let ws_recv_frame (sock : Unix.file_descr) : value =
  let close_gone = VCon ("Close", [VInt 1001; VString "going away"]) in
  try
    let hdr = Bytes.create 2 in
    if not (ws_recv_exact sock hdr 0 2) then close_gone
    else begin
      let b0 = Char.code (Bytes.get hdr 0) in
      let b1 = Char.code (Bytes.get hdr 1) in
      let opcode  = b0 land 0x0F in
      let masked  = (b1 lsr 7) land 1 = 1 in
      let len7    = b1 land 0x7F in
      let payload_len =
        if len7 < 126 then len7
        else if len7 = 126 then begin
          let ext = Bytes.create 2 in
          if not (ws_recv_exact sock ext 0 2) then raise Exit;
          (Char.code (Bytes.get ext 0) lsl 8) lor (Char.code (Bytes.get ext 1))
        end else begin
          let ext = Bytes.create 8 in
          if not (ws_recv_exact sock ext 0 8) then raise Exit;
          let v = ref 0 in
          for i = 0 to 7 do
            v := (!v lsl 8) lor (Char.code (Bytes.get ext i))
          done;
          !v
        end
      in
      let mask_key = Bytes.create 4 in
      if masked then
        (if not (ws_recv_exact sock mask_key 0 4) then raise Exit);
      let payload = Bytes.create payload_len in
      if payload_len > 0 then
        (if not (ws_recv_exact sock payload 0 payload_len) then raise Exit);
      if masked then
        for i = 0 to payload_len - 1 do
          let m = Char.code (Bytes.get mask_key (i mod 4)) in
          Bytes.set payload i (Char.chr ((Char.code (Bytes.get payload i)) lxor m))
        done;
      let text = Bytes.to_string payload in
      match opcode with
      | 0x1 -> VCon ("TextFrame",   [VString text])
      | 0x2 -> VCon ("BinaryFrame", [VString text])
      | 0x8 ->
        let code   = if payload_len >= 2
          then (Char.code (Bytes.get payload 0) lsl 8) lor (Char.code (Bytes.get payload 1))
          else 1000 in
        let reason = if payload_len > 2
          then String.sub (Bytes.to_string payload) 2 (payload_len - 2)
          else "" in
        VCon ("Close", [VInt code; VString reason])
      | 0x9 -> VCon ("Ping", [])
      | 0xA -> VCon ("Pong", [])
      | _   -> VCon ("Close", [VInt 1002; VString "unknown opcode"])
    end
  with _ -> close_gone

(** Write one WebSocket frame to [sock] (server→client, unmasked). *)
let ws_send_frame (sock : Unix.file_descr) (frame : value) : unit =
  try
    let (opcode, payload) = match frame with
      | VCon ("TextFrame",   [VString s]) -> (0x81, s)
      | VCon ("BinaryFrame", [VString s]) -> (0x82, s)
      | VCon ("Ping", _)                  -> (0x89, "")
      | VCon ("Pong", _)                  -> (0x8A, "")
      | VCon ("Close", [VInt code; VString reason]) ->
        let buf = Bytes.create (2 + String.length reason) in
        Bytes.set buf 0 (Char.chr ((code lsr 8) land 0xFF));
        Bytes.set buf 1 (Char.chr (code land 0xFF));
        Bytes.blit_string reason 0 buf 2 (String.length reason);
        (0x88, Bytes.to_string buf)
      | _ -> (0x88, "")
    in
    let plen = String.length payload in
    let hdr =
      if plen < 126 then begin
        let b = Bytes.create 2 in
        Bytes.set b 0 (Char.chr opcode);
        Bytes.set b 1 (Char.chr plen);
        b
      end else if plen < 65536 then begin
        let b = Bytes.create 4 in
        Bytes.set b 0 (Char.chr opcode);
        Bytes.set b 1 (Char.chr 126);
        Bytes.set b 2 (Char.chr ((plen lsr 8) land 0xFF));
        Bytes.set b 3 (Char.chr (plen land 0xFF));
        b
      end else begin
        let b = Bytes.create 10 in
        Bytes.set b 0 (Char.chr opcode);
        Bytes.set b 1 (Char.chr 127);
        for i = 0 to 7 do
          Bytes.set b (2 + i) (Char.chr ((plen lsr (56 - 8*i)) land 0xFF))
        done;
        b
      end
    in
    tcp_send_all sock (Bytes.to_string hdr);
    if plen > 0 then tcp_send_all sock payload
  with _ -> ()

(** Handle a single HTTP connection: read request → call pipeline → write response.
    [pipeline_fn] is a March value (VClosure or VBuiltin) of type Conn → Conn. *)
let handle_http_connection (sock : Unix.file_descr) (pipeline_fn : value) : unit =
  try
    (* 1. Read the request line *)
    let req_line = http_recv_line sock in
    if req_line = "" then ()
    else begin
      let (meth, full_path) =
        match String.split_on_char ' ' req_line with
        | m :: fp :: _ -> (m, fp)
        | _ -> ("GET", "/")
      in
      (* 2. Read header lines until a blank line *)
      let headers_raw = ref [] in
      let stop = ref false in
      while not !stop do
        let line = http_recv_line sock in
        if line = "" then stop := true
        else
          (match parse_header_line line with
           | Some pair -> headers_raw := pair :: !headers_raw
           | None -> ())
      done;
      let headers_raw = List.rev !headers_raw in
      (* 3. Read body if Content-Length present (case-insensitive) *)
      let content_length =
        match List.find_opt
                (fun (n, _) -> String.lowercase_ascii n = "content-length")
                headers_raw
        with
        | Some (_, s) -> int_of_string_opt (String.trim s)
        | None        -> None
      in
      let body = match content_length with
        | Some n when n > 0 -> http_recv_exactly sock n
        | _ -> ""
      in
      (* 4. Build the Conn value *)
      let conn_val = build_conn_value
          ~fd:(Obj.magic sock : int)
          ~method_str:meth ~full_path ~headers_raw ~body () in
      (* 5. Call the pipeline closure *)
      let result_conn = !apply_hook pipeline_fn [conn_val] in
      (* 6. Check for WebSocket upgrade *)
      (match result_conn with
       | VCon ("Conn", [_fd; _meth; _path; _pi; _qs;
                        _rh; _rb; _status; _rhs; _rbody;
                        _halted; _assigns;
                        VCon ("WebSocketUpgrade", [handler_fn])]) ->
         (* Find Sec-WebSocket-Key in request headers *)
         let ws_key_opt =
           List.find_opt
             (fun (n, _) -> String.lowercase_ascii n = "sec-websocket-key")
             headers_raw
         in
         (match ws_key_opt with
          | None ->
            tcp_send_all sock "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
          | Some (_, key) ->
            let accept = ws_accept_key (String.trim key) in
            let handshake =
              "HTTP/1.1 101 Switching Protocols\r\n" ^
              "Upgrade: websocket\r\n" ^
              "Connection: Upgrade\r\n" ^
              "Sec-WebSocket-Accept: " ^ accept ^ "\r\n\r\n"
            in
            tcp_send_all sock handshake;
            (* Store fd as int in WsSocket value *)
            let fd_int = (Obj.magic sock : int) in
            let ws_sock = VCon ("WsSocket", [VInt fd_int]) in
            (try ignore (!apply_hook handler_fn [ws_sock])
             with _ -> ()))
       | _ ->
         (* Normal HTTP response *)
         let (status, resp_headers, resp_body) = extract_conn_response result_conn in
         let effective_status = if status = 0 then 200 else status in
         let reason     = http_reason_phrase effective_status in
         let header_str = march_headers_to_string resp_headers in
         let response   =
           Printf.sprintf "HTTP/1.1 %d %s\r\n%sContent-Length: %d\r\n\r\n%s"
             effective_status reason
             header_str
             (String.length resp_body)
             resp_body
         in
         tcp_send_all sock response)
    end
  with
  | Eval_error msg ->
    (* Application-level runtime error — log it so it's visible in the server output. *)
    Printf.eprintf "[http handler error] %s\n%!" msg
  | Unix.Unix_error _ -> ()  (* swallow TCP/socket errors (client disconnected, etc.) *)
  | _ -> ()                  (* swallow other connection errors *)

(* ------------------------------------------------------------------ *)
(* Non-blocking, single-threaded, multiplexed HTTP connection handling *)
(* ------------------------------------------------------------------ *)
(* [handle_http_connection] above is fully blocking: it assumes every recv/
   send completes immediately. That's fine for the fork-per-accept-loop
   variant (http_server_spawn_n) where each forked child only ever serves
   one client at a time by design, but it is fatal for [http_server_listen]'s
   main accept loop — a single slow/idle client (e.g. a WebSocket client that
   opens the TCP connection and then pauses before sending the upgrade
   request) blocks that one OS thread inside a blocking recv(), and since
   there is only one thread, NO other client can be accepted or served until
   that recv() returns.

   The fix follows the same cooperative, single-threaded pattern the
   interpreter already uses for actor mailboxes (see [BlockedOnReceive] /
   [run_scheduler] above): instead of blocking, each connection is a small
   state machine that is driven forward only when [Unix.select] reports its
   socket ready. No connection can ever stall another. *)

(** What a connection is currently waiting to do. *)
type http_conn_phase =
  | HCReadingRequest    (* accumulating bytes until headers (+ body) complete *)
  | HCWriting           (* response bytes queued; draining via non-blocking send *)

type http_conn_state = {
  hc_sock            : Unix.file_descr;
  mutable hc_phase    : http_conn_phase;
  hc_in_buf           : Buffer.t;   (* raw bytes read so far (request line+headers+body) *)
  mutable hc_out_buf  : string;     (* full response bytes still to be written *)
  mutable hc_out_off  : int;        (* bytes of hc_out_buf already written *)
}

let http_conn_new sock =
  { hc_sock = sock;
    hc_phase = HCReadingRequest;
    hc_in_buf = Buffer.create 512;
    hc_out_buf = "";
    hc_out_off = 0;
  }

(** Look for "\r\n\r\n" (or bare "\n\n") marking the end of the header block
    in the bytes accumulated so far. Returns the byte offset just past the
    blank line, or None if not yet seen. *)
let http_find_header_end (raw : string) : int option =
  let n = String.length raw in
  let rec go i =
    if i + 3 >= n then None
    else if raw.[i] = '\r' && raw.[i+1] = '\n' && raw.[i+2] = '\r' && raw.[i+3] = '\n'
    then Some (i + 4)
    else go (i + 1)
  in
  (* Also allow a bare "\n\n" for leniency, matching how http_recv_line
     tolerates missing CR. *)
  let rec go_lf i =
    if i + 1 >= n then None
    else if raw.[i] = '\n' && raw.[i+1] = '\n' then Some (i + 2)
    else go_lf (i + 1)
  in
  match go 0 with
  | Some _ as r -> r
  | None -> go_lf 0

(** Parse the accumulated header block (everything up to but not including
    the blank-line terminator) into (method, full_path, headers_raw). *)
let http_parse_request_head (head_block : string) : string * string * (string * string) list =
  let lines = String.split_on_char '\n' head_block in
  let lines = List.map (fun l ->
      if String.length l > 0 && l.[String.length l - 1] = '\r'
      then String.sub l 0 (String.length l - 1) else l)
      lines
  in
  match lines with
  | [] -> ("GET", "/", [])
  | req_line :: header_lines ->
    let (meth, full_path) =
      match String.split_on_char ' ' req_line with
      | m :: fp :: _ -> (m, fp)
      | _ -> ("GET", "/")
    in
    let headers_raw = List.filter_map parse_header_line header_lines in
    (meth, full_path, headers_raw)

(** Given the bytes read so far, determine whether a complete HTTP request
    (headers + body, per Content-Length) is present. Returns
    Some (meth, full_path, headers_raw, body) once complete. *)
let http_try_parse_request (raw : string) :
  (string * string * (string * string) list * string) option =
  match http_find_header_end raw with
  | None -> None
  | Some header_end ->
    let head_block = String.sub raw 0 header_end in
    let (meth, full_path, headers_raw) = http_parse_request_head head_block in
    let content_length =
      match List.find_opt
              (fun (n, _) -> String.lowercase_ascii n = "content-length")
              headers_raw
      with
      | Some (_, s) -> (match int_of_string_opt (String.trim s) with
          | Some n when n >= 0 -> n
          | _ -> 0)
      | None -> 0
    in
    let available_body = String.length raw - header_end in
    if available_body < content_length then None  (* body not fully arrived yet *)
    else Some (meth, full_path, headers_raw, String.sub raw header_end content_length)

(** What the event loop should do with a connection once its request has
    been run through the pipeline. *)
type http_outcome =
  | HttpRespond of string  (* queue these response bytes for writing *)
  | HttpWsUpgrade of value (* 101 sent; [value] is the WS handler closure *)
  | HttpDrop               (* nothing to send — close the connection *)

(** Run the pipeline for a fully-received request and decide the outcome.
    This is pure in-memory computation (no blocking I/O) apart from the WS
    handshake write.

    On a WebSocket upgrade the socket is NOT taken over here. The 101 is
    written and the handler closure is handed back to the event loop, which
    runs it as a cooperative fiber ([Ws_block] / [ws_wait_ready]) so the WS
    connection cannot stall the other connections. It also deliberately
    leaves the socket in non-blocking mode: the fiber depends on recv/send
    reporting EAGAIN in order to yield. *)
let http_run_pipeline_and_respond
    (sock : Unix.file_descr) (pipeline_fn : value)
    (meth : string) (full_path : string)
    (headers_raw : (string * string) list) (body : string) : http_outcome =
  let conn_val = build_conn_value
      ~fd:(Obj.magic sock : int)
      ~method_str:meth ~full_path ~headers_raw ~body () in
  let result_conn = !apply_hook pipeline_fn [conn_val] in
  match result_conn with
  | VCon ("Conn", [_fd; _meth; _path; _pi; _qs;
                   _rh; _rb; _status; _rhs; _rbody;
                   _halted; _assigns;
                   VCon ("WebSocketUpgrade", [handler_fn])]) ->
    let ws_key_opt =
      List.find_opt
        (fun (n, _) -> String.lowercase_ascii n = "sec-websocket-key")
        headers_raw
    in
    (match ws_key_opt with
     | None ->
       HttpRespond "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
     | Some (_, key) ->
       let accept = ws_accept_key (String.trim key) in
       let handshake =
         "HTTP/1.1 101 Switching Protocols\r\n" ^
         "Upgrade: websocket\r\n" ^
         "Connection: Upgrade\r\n" ^
         "Sec-WebSocket-Accept: " ^ accept ^ "\r\n\r\n"
       in
       (* Socket stays non-blocking (the accept loop set that): the WS fiber
          needs EAGAIN to know when to yield. *)
       tcp_send_all sock handshake;
       HttpWsUpgrade handler_fn)
  | _ ->
    let (status, resp_headers, resp_body) = extract_conn_response result_conn in
    let effective_status = if status = 0 then 200 else status in
    let reason     = http_reason_phrase effective_status in
    let header_str = march_headers_to_string resp_headers in
    let response   =
      Printf.sprintf "HTTP/1.1 %d %s\r\n%sContent-Length: %d\r\n\r\n%s"
        effective_status reason
        header_str
        (String.length resp_body)
        resp_body
    in
    HttpRespond response

(** Non-blocking multiplexed HTTP accept/serve loop.
    Tracks every open connection (not just the listening socket) and
    [Unix.select]s across all of them each iteration, so a connection that
    is idle/slow/partially-written never blocks progress on any other
    connection. Each connection is driven forward only when [select]
    reports it ready for the operation it is currently waiting on.

    Upgraded WebSocket connections are multiplexed the same way: each runs
    as an effect-handler fiber that parks on [Ws_block] whenever its recv/
    send would block, so a long-lived (usually idle) WS connection costs one
    parked continuation rather than the whole loop. See [ws_wait_ready]. *)
let run_http_event_loop (server_sock : Unix.file_descr) (pipeline_fn : value) : unit =
  let open Unix in
  set_nonblock server_sock;
  (* fd -> connection state, for all currently-open client connections. *)
  let conns : (Unix.file_descr, http_conn_state) Hashtbl.t = Hashtbl.create 64 in
  let close_conn (c : http_conn_state) =
    Hashtbl.remove conns c.hc_sock;
    (try close c.hc_sock with _ -> ())
  in
  (* Upgraded WS connections, parked mid-handler waiting on readiness.
     A fiber is present here only while suspended; while it runs it owns
     the (single) thread of control, exactly like an HTTP phase callback. *)
  let ws_parked :
    (Unix.file_descr,
     (unit, unit) Effect.Deep.continuation * ws_wait_dir) Hashtbl.t =
    Hashtbl.create 8
  in
  let close_ws (fd : Unix.file_descr) =
    Hashtbl.remove ws_parked fd;
    (try close fd with _ -> ())
  in
  (* Deep handler: persists across every [continue], so the fiber can park
     and resume any number of times over the connection's lifetime. *)
  let ws_fiber_handler fd : (unit, unit) Effect.Deep.handler =
    { Effect.Deep.retc = (fun () -> close_ws fd)
    ; Effect.Deep.exnc = (fun _ -> close_ws fd)
    ; Effect.Deep.effc =
        (fun (type a) (eff : a Effect.t) ->
           match eff with
           | Ws_block (bfd, dir) ->
             Some (fun (k : (a, unit) Effect.Deep.continuation) ->
                 Hashtbl.replace ws_parked bfd (k, dir))
           | _ -> None)
    }
  in
  let start_ws_fiber fd handler_fn =
    let ws_sock = VCon ("WsSocket", [VInt (Obj.magic fd : int)]) in
    Effect.Deep.match_with
      (fun () -> ignore (!apply_hook handler_fn [ws_sock]))
      ()
      (ws_fiber_handler fd)
  in
  let resume_ws fd =
    match Hashtbl.find_opt ws_parked fd with
    | None -> ()
    | Some (k, _dir) ->
      (* Remove before resuming: the fiber will re-park itself (fresh
         continuation) if it blocks again. *)
      Hashtbl.remove ws_parked fd;
      Effect.Deep.continue k ()
  in
  (* Try to make forward progress reading a request on [c]. Called only
     after select reports the socket readable. *)
  let advance_read (c : http_conn_state) =
    let chunk = Bytes.create 65536 in
    match (try `Read (Unix.read c.hc_sock chunk 0 (Bytes.length chunk))
           with
           | Unix_error ((EAGAIN | EWOULDBLOCK), _, _) -> `WouldBlock
           | Unix_error (EINTR, _, _) -> `WouldBlock
           | Unix_error _ -> `Closed
           | _ -> `Closed)
    with
    | `WouldBlock -> ()
    | `Closed -> close_conn c
    | `Read 0 -> close_conn c   (* peer closed before completing a request *)
    | `Read n ->
      Buffer.add_subbytes c.hc_in_buf chunk 0 n;
      (match http_try_parse_request (Buffer.contents c.hc_in_buf) with
       | None -> ()  (* need more bytes; keep waiting on this socket *)
       | Some (meth, full_path, headers_raw, body) ->
         (* Run the (in-memory, non-blocking) pipeline now. A WebSocket
            upgrade hands the socket to a cooperative fiber instead of
            queueing a response. *)
         (match
            (try http_run_pipeline_and_respond c.hc_sock pipeline_fn
                   meth full_path headers_raw body
             with
             | Eval_error msg ->
               Printf.eprintf "[http handler error] %s\n%!" msg;
               HttpRespond
                 "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n"
             | Unix.Unix_error _ -> HttpDrop
             | _ -> HttpDrop)
          with
          | HttpDrop -> close_conn c
          | HttpRespond response ->
            c.hc_out_buf <- response;
            c.hc_out_off <- 0;
            c.hc_phase <- HCWriting
          | HttpWsUpgrade handler_fn ->
            (* No longer an HTTP connection: the fiber owns the fd (and
               closes it via the handler's retc/exnc). Drop it from [conns]
               WITHOUT closing, then run until it first parks. *)
            Hashtbl.remove conns c.hc_sock;
            start_ws_fiber c.hc_sock handler_fn))
  in
  (* Try to make forward progress writing the queued response on [c].
     Called only after select reports the socket writable. *)
  let advance_write (c : http_conn_state) =
    let remaining = String.length c.hc_out_buf - c.hc_out_off in
    if remaining <= 0 then close_conn c
    else
      match
        (try `Wrote (Unix.write_substring c.hc_sock c.hc_out_buf c.hc_out_off remaining)
         with
         | Unix_error ((EAGAIN | EWOULDBLOCK), _, _) -> `WouldBlock
         | Unix_error (EINTR, _, _) -> `WouldBlock
         | Unix_error _ -> `Closed
         | _ -> `Closed)
      with
      | `WouldBlock -> ()
      | `Closed -> close_conn c
      | `Wrote n ->
        c.hc_out_off <- c.hc_out_off + n;
        if c.hc_out_off >= String.length c.hc_out_buf then close_conn c
  in
  (try
     while not !shutdown_requested do
       let read_fds =
         server_sock ::
         Hashtbl.fold (fun fd (_, dir) acc ->
             if dir = Ws_wait_read then fd :: acc else acc)
           ws_parked
           (Hashtbl.fold (fun _ c acc ->
                if c.hc_phase = HCReadingRequest then c.hc_sock :: acc else acc)
              conns [])
       in
       let write_fds =
         Hashtbl.fold (fun fd (_, dir) acc ->
             if dir = Ws_wait_write then fd :: acc else acc)
           ws_parked
           (Hashtbl.fold (fun _ c acc ->
                if c.hc_phase = HCWriting then c.hc_sock :: acc else acc)
              conns [])
       in
       let (readable, writable, _) =
         try select read_fds write_fds [] 1.0
         with Unix_error (EINTR, _, _) -> ([], [], [])
            | _ -> ([], [], [])
       in
       if not !shutdown_requested then begin
         (* New connections first. *)
         if List.mem server_sock readable then begin
           (* Drain every pending connection in the backlog, not just one —
              under load, select only guarantees at least one is ready. *)
           let continue_accepting = ref true in
           while !continue_accepting do
             match
               (try `Accepted (accept server_sock)
                with
                | Unix_error ((EAGAIN | EWOULDBLOCK), _, _) -> `WouldBlock
                | Unix_error (EINTR, _, _) -> `WouldBlock
                | Unix_error _ -> `WouldBlock
                | _ -> `WouldBlock)
             with
             | `WouldBlock -> continue_accepting := false
             | `Accepted (client_sock, _addr) ->
               (try set_nonblock client_sock with _ -> ());
               Hashtbl.replace conns client_sock (http_conn_new client_sock)
           done
         end;
         (* Drive every connection ready for its current phase. Snapshot
            first since advance_read/advance_write may remove entries.
            A parked WS fiber and an HTTP conn can never share an fd, so
            the [conns] lookup failing means "try the WS table". *)
         List.iter (fun fd ->
             match Hashtbl.find_opt conns fd with
             | Some c when c.hc_phase = HCReadingRequest -> advance_read c
             | Some _ -> ()
             | None -> resume_ws fd)
           readable;
         List.iter (fun fd ->
             match Hashtbl.find_opt conns fd with
             | Some c when c.hc_phase = HCWriting -> advance_write c
             | Some _ -> ()
             | None -> resume_ws fd)
           writable
       end
     done;
     Printf.eprintf "march: Shutting down...\n%!"
   with exn ->
     Hashtbl.iter (fun _ c -> try close c.hc_sock with _ -> ()) conns;
     Hashtbl.iter (fun fd _ -> try close fd with _ -> ()) ws_parked;
     raise exn);
  Hashtbl.iter (fun _ c -> try close c.hc_sock with _ -> ()) conns;
  Hashtbl.iter (fun fd _ -> try close fd with _ -> ()) ws_parked

