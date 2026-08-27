(** The interpreter's networking, encoding and file-format runtime: the HTTP
    server loop, WebSockets, base64, compression stubs, PBKDF2, and the CSV
    reader.

    [Eval_builtins] dispatches builtins straight to these and [Eval]
    [include]s the module. Roughly half of what it used to export is
    scaffolding for the two loops at the bottom of the file: the wire-level
    read helpers ([http_recv_line], [http_recv_exactly], [ws_recv_exact]), the
    request parsers ([parse_header_line], [http_find_header_end],
    [http_parse_request_head], [http_try_parse_request]), the connection state
    machine ([http_conn_state], [http_conn_new]), the value constructors
    ([march_string_list], [http_method_of_string], [split_path_info],
    [build_conn_value], [extract_conn_response], [march_headers_to_string],
    [http_reason_phrase]), the CSV reader's own table and scanner, the base64
    alphabet and [ws_accept_key]. None of those had a caller outside this
    file; all are now private, as is the [Ws_block] effect, which is performed
    and handled entirely within [run_http_event_loop]'s fiber. *)

open Eval_types

(** {1 HTTP server}

    [run_http_event_loop listen_fd handler] is the entry point: it accepts on
    [listen_fd] and drives every connection through non-blocking parse,
    [http_run_pipeline_and_respond], and (for an upgrade) the WebSocket fiber.
    [handle_http_connection] is the older blocking one-connection-at-a-time
    path. *)

val run_http_event_loop : Unix.file_descr -> value -> unit
val handle_http_connection : Unix.file_descr -> value -> unit

type http_outcome =
  | HttpRespond of string
  | HttpWsUpgrade of value
  | HttpDrop

(** [http_run_pipeline_and_respond sock handler meth path headers body] runs
    the March-side handler pipeline for one already-parsed request. *)
val http_run_pipeline_and_respond :
  Unix.file_descr ->
  value ->
  string ->
  string ->
  (string * string) list ->
  string ->
  http_outcome

(** {1 WebSockets}

    Frames are read and written on the raw fd. [ws_wait_ready] parks the
    calling fiber until the fd is ready in [dir] — it must be called from
    inside [run_http_event_loop]'s handler, which is what resumes it. *)

type ws_wait_dir = Ws_wait_read | Ws_wait_write

val ws_wait_ready : Unix.file_descr -> ws_wait_dir -> unit
val ws_recv_frame : Unix.file_descr -> value
val ws_send_frame : Unix.file_descr -> value -> unit

(** {1 Sockets} *)

(** [tcp_send_all fd s] loops until every byte of [s] is written. *)
val tcp_send_all : Unix.file_descr -> string -> unit

(** {1 Bytes and values} *)

val march_bytes_of_string : string -> value
val march_val_to_raw : value -> (string, string) result

(** {1 Encodings} *)

val base64_encode : string -> string
val base64_decode : string -> (string, string) result

val pbkdf2_hmac_sha256 :
  password:string -> salt:string -> iterations:int -> dklen:int -> string

(** {1 Compression stubs}

    Implemented in [compress_stubs.c]; each raises on a malformed or
    unsupported input, which the builtin wrapper turns into an [Err]. *)

external caml_march_gzip_encode : string -> int -> string
  = "caml_march_gzip_encode"

external caml_march_gzip_decode : string -> string = "caml_march_gzip_decode"

external caml_march_deflate_encode : string -> string
  = "caml_march_deflate_encode"

external caml_march_deflate_decode : string -> string
  = "caml_march_deflate_decode"

external caml_march_zstd_encode : string -> int -> string
  = "caml_march_zstd_encode"

external caml_march_zstd_decode : string -> string = "caml_march_zstd_decode"

external caml_march_brotli_encode : string -> int -> int -> string
  = "caml_march_brotli_encode"

external caml_march_brotli_decode : string -> string
  = "caml_march_brotli_decode"

(** {1 File errors}

    Both turn a host error into the March [FileError] value, tagged with the
    operation name passed as the first argument. *)

val file_error_of_unix : string -> Unix.error -> value
val file_error_of_sys : string -> string -> value

(** {1 CSV reader}

    Handle-based: [csv_open_impl] returns an integer handle into a table
    private to this module, and the other two take it back. *)

val csv_open_impl : value list -> value
val csv_next_row_impl : value list -> value
val csv_close_impl : value list -> value
