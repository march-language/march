(** What [http_serialize_request] accepts in each field of an outgoing
    request, so a CR, LF, space or other control byte cannot end the request
    line or a header early and smuggle a second, pipelined request.

    The C twin is [march_http_check_*] in runtime/march_http.c.  The two must
    accept exactly the same inputs and word every error the same way:
    test_http_serialize_injection_parity (test/test_codegen.ml) runs one
    program through the interpreter and a compiled binary and compares the
    output byte for byte.

    - method, header name: a non-empty RFC 9110 token ([tchar]).
    - host: no control byte, space or DEL.
    - path, query: RFC 3986 characters only (unreserved, sub-delims, [:@/?]),
      and a [%] must start a well-formed escape [%HH].  A byte outside that
      set has to be percent-encoded by the caller.
    - header value: VCHAR, obs-text, space and HTAB (RFC 9110 field-value),
      so no CR, LF, NUL or other control byte. *)

let prefix = "http request rejected: "

let bad_byte field s i =
  Error (Printf.sprintf "%s%s contains byte 0x%02x at offset %d"
           prefix field (Char.code s.[i]) i)

(** First index in [s] whose byte fails [ok], if any. *)
let find_bad ok s =
  let n = String.length s in
  let rec go i = if i >= n then None else if ok s.[i] then go (i + 1) else Some i in
  go 0

let is_tchar c =
  match c with
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_'
  | '`' | '|' | '~' -> true
  | _ -> false

let check_token field s =
  if s = "" then Error (Printf.sprintf "%sempty %s" prefix field)
  else match find_bad is_tchar s with
    | Some i -> bad_byte field s i
    | None -> Ok ()

let check_method s = check_token "method" s
let check_header_name s = check_token "header name" s

let check_host s =
  match find_bad (fun c -> c > ' ' && c <> '\x7f') s with
  | Some i -> bad_byte "host" s i
  | None -> Ok ()

let check_header_value s =
  match find_bad (fun c -> c = '\t' || (c >= ' ' && c <> '\x7f')) s with
  | Some i -> bad_byte "header value" s i
  | None -> Ok ()

let is_hex c =
  match c with '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false

let is_target_char c =
  match c with
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
  | '-' | '.' | '_' | '~' -> true                                   (* unreserved *)
  | '!' | '$' | '&' | '\'' | '(' | ')' | '*' | '+' | ',' | ';' | '=' -> true
  | ':' | '@' | '/' | '?' -> true
  | _ -> false

(** [field] is ["path"] or ["query"]; the same character set serves both. *)
let check_target field s =
  let n = String.length s in
  let rec go i =
    if i >= n then Ok ()
    else if s.[i] = '%' then
      if i + 2 < n && is_hex s.[i + 1] && is_hex s.[i + 2] then go (i + 3)
      else Error (Printf.sprintf "%s%s has a malformed %%-escape at offset %d"
                    prefix field i)
    else if is_target_char s.[i] then go (i + 1)
    else bad_byte field s i
  in
  go 0
