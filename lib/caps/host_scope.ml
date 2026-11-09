(* Host scopes on IO.NetConnect.  See host_scope.mli. *)

type pattern = { host : string; wildcard : bool; port : int option; path : string list option }
type decl = { patterns : pattern list; no_redirects : bool; methods : string list option }

let http_methods = [ "get"; "head"; "post"; "put"; "patch"; "delete"; "options" ]
type authority = { a_host : string; a_port : int }

let normalize_host (h : string) : string =
  let h = String.lowercase_ascii h in
  let n = String.length h in
  if n > 0 && h.[n - 1] = '.' then String.sub h 0 (n - 1) else h

let contains (s : string) (sub : string) : bool =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  m = 0 || go 0

let is_digit c = c >= '0' && c <= '9'
let is_label_char c = (c >= 'a' && c <= 'z') || is_digit c || c = '-'

let parse_port (s : string) : int option =
  if s = "" || String.length s > 5 || not (String.for_all is_digit s) then None
  else
    let p = int_of_string s in
    if p >= 1 && p <= 65535 then Some p else None

(* Dot-separated DNS-style labels (also covers an IPv4 literal). *)
let valid_name (h : string) : bool =
  h <> ""
  && List.for_all
       (fun l -> l <> "" && String.for_all is_label_char l)
       (String.split_on_char '.' h)

let valid_ipv6_body (b : string) : bool =
  b <> ""
  && String.for_all
       (fun c ->
          is_digit c || (c >= 'a' && c <= 'f') || c = ':' || c = '.')
       b

(* ── Paths ─────────────────────────────────────────────────────────── *)

(* The path part of a request, without query or fragment. *)
let strip_query (p : string) : string =
  let cut c s = match String.index_opt s c with Some i -> String.sub s 0 i | None -> s in
  cut '#' (cut '?' p)

let lower_contains (s : string) (sub : string) = contains (String.lowercase_ascii s) sub

(* Refused, not normalized: a server may resolve these differently from us. *)
let path_ok (p : string) : bool =
  let p = strip_query p in
  (not (String.contains p '\\'))
  && (not (contains p "//"))
  && (not (lower_contains p "%2e"))
  && (not (lower_contains p "%2f"))
  && (not (lower_contains p "%5c"))
  && List.for_all (fun seg -> seg <> "." && seg <> "..") (String.split_on_char '/' p)

let path_segments (p : string) : string list =
  List.filter (fun s -> s <> "") (String.split_on_char '/' (strip_query p))

let path_within ~(prefix : string list) (p : string) : bool =
  let rec go pre segs =
    match (pre, segs) with
    | [], _ -> true
    | _, [] -> false
    | a :: pt, b :: st -> a = b && go pt st
  in
  go prefix (path_segments p)

(* A path scope as written: `/v1/weather/`.  Only unreserved characters, so
   it can never be read two ways (and never collides with the spec string's
   `,` `@` `+` `!` separators). *)
let parse_scope_path (p : string) : (string list, string) result =
  let seg_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || is_digit c
    || c = '-' || c = '_' || c = '.' || c = '~'
  in
  let parts = String.split_on_char '/' p in
  (* p starts with '/', so the first part is ""; a trailing '/' gives a last "". *)
  let inner = match parts with "" :: rest -> rest | l -> l in
  let inner =
    match List.rev inner with "" :: r -> List.rev r | _ -> inner
  in
  match List.find_opt (fun seg -> seg = "" || seg = "." || seg = ".." || not (String.for_all seg_char seg)) inner with
  | Some "" -> Error "a path scope cannot contain `//`"
  | Some seg when seg = "." || seg = ".." ->
    Error (Printf.sprintf "a path scope cannot contain a `%s` segment" seg)
  | Some seg ->
    Error
      (Printf.sprintf
         "the path segment `%s` may contain only letters, digits, `-`, `_`, `.` and \
          `~` (no `%%`, `?`, `#` or `\\`)"
         seg)
  | None -> Ok inner

let parse_pattern (raw : string) : (pattern, string) result =
  if raw = "" then Error "a host scope cannot be empty"
  else if contains raw "://" then
    Error "a host scope names a host, not a URL: drop the scheme (`https://`)"
  else
  (* The path starts at the first '/'; it keeps its case (paths are
     case-sensitive), the host part is lowercased. *)
  let host_raw, path_r =
    match String.index_opt raw '/' with
    | None -> (raw, Ok None)
    | Some i ->
      ( String.sub raw 0 i,
        Result.map (fun x -> Some x) (parse_scope_path (String.sub raw i (String.length raw - i))) )
  in
  match path_r with
  | Error e -> Error e
  | Ok path ->
  let s = String.lowercase_ascii host_raw in
  if s = "" then Error "a host scope needs a host before its path"
  else if String.contains s '@' then
    Error "a host scope cannot carry userinfo (`user@`)"
  else if String.exists (fun c -> Char.code c >= 0x80) s then
    Error "a host scope must be ASCII: write an international name in its \
           punycode (`xn--`) form"
  else
    (* Split off the port: after the closing bracket for IPv6, else at the
       last ':'. *)
    let host_part, port_part =
      if s.[0] = '[' then
        match String.index_opt s ']' with
        | None -> (s, None)
        | Some i ->
          let rest = String.sub s (i + 1) (String.length s - i - 1) in
          let h = String.sub s 0 (i + 1) in
          if rest = "" then (h, None)
          else if rest.[0] = ':' then
            (h, Some (String.sub rest 1 (String.length rest - 1)))
          else (s, None)
      else
        match String.rindex_opt s ':' with
        | None -> (s, None)
        | Some i ->
          (String.sub s 0 i, Some (String.sub s (i + 1) (String.length s - i - 1)))
    in
    let port_r =
      match port_part with
      | None -> Ok None
      | Some p -> (
          match parse_port p with
          | Some n -> Ok (Some n)
          | None -> Error (Printf.sprintf "`%s` is not a port (1-65535)" p))
    in
    match port_r with
    | Error e -> Error e
    | Ok port ->
      if host_part <> "" && host_part.[0] = '[' then
        let n = String.length host_part in
        if n >= 2 && host_part.[n - 1] = ']'
           && valid_ipv6_body (String.sub host_part 1 (n - 2))
        then Ok { host = host_part; wildcard = false; port; path }
        else Error (Printf.sprintf "`%s` is not an IPv6 literal" host_part)
      else
        let wildcard, name =
          if String.length host_part >= 2 && String.sub host_part 0 2 = "*."
          then (true, String.sub host_part 2 (String.length host_part - 2))
          else (false, host_part)
        in
        let name = normalize_host name in
        if String.contains name '*' || host_part = "*" then
          Error "a wildcard must be the whole leftmost label (`*.example.com`)"
        else if not (valid_name name) then
          Error
            (Printf.sprintf
               "`%s` is not a host name: labels are letters, digits and `-`, \
                separated by single dots"
               host_part)
        else Ok { host = name; wildcard; port; path }

let pattern_to_string (p : pattern) : string =
  (if p.wildcard then "*." else "")
  ^ p.host
  ^ (match p.port with None -> "" | Some n -> ":" ^ string_of_int n)
  ^ match p.path with
    | None -> ""
    | Some [] -> "/"
    | Some segs -> "/" ^ String.concat "/" segs ^ "/"

let is_option_text (o : string) : bool =
  let word w = w <> "" && String.for_all (fun c -> (c >= 'a' && c <= 'z') || c = '_') w in
  match String.index_opt o '=' with
  | None -> word o
  | Some i ->
    word (String.sub o 0 i)
    && List.for_all word (String.split_on_char ',' (String.sub o (i + 1) (String.length o - i - 1)))

let split_options (s : string) : string * string list =
  match String.split_on_char ';' s with
  | scope :: (_ :: _ as opts) when List.for_all is_option_text opts -> (scope, opts)
  | _ -> (s, [])

let parse_methods (v : string) : (string list, string) result =
  let ms = String.split_on_char ',' v in
  if v = "" then Error "`methods(...)` needs at least one method"
  else
    match List.find_opt (fun m -> not (List.mem m http_methods)) ms with
    | Some m ->
      Error
        (Printf.sprintf "`%s` is not an HTTP method a scope can name; use %s" m
           (String.concat ", " (List.map (fun m -> "`" ^ m ^ "`") http_methods)))
    | None -> Ok (List.sort_uniq compare ms)

let parse_decl (scope : string option) : (decl, string) result =
  match scope with
  | None -> Ok { patterns = []; no_redirects = false; methods = None }
  | Some s -> (
      match String.split_on_char ';' s with
      | [] -> Error "a host scope cannot be empty"
      | p :: opts ->
        if p = "" && opts = [] then Error "a host scope cannot be empty"
        else
          let pats =
            if p = "" then Ok [] else Result.map (fun x -> [ x ]) (parse_pattern p)
          in
          let rec go d = function
            | [] -> Ok d
            | "no_redirects" :: rest ->
              if d.no_redirects then Error "`no_redirects` is given twice"
              else go { d with no_redirects = true } rest
            | o :: rest
              when String.length o >= 8 && String.sub o 0 8 = "methods=" -> (
                if d.methods <> None then Error "`methods(...)` is given twice"
                else
                  match parse_methods (String.sub o 8 (String.length o - 8)) with
                  | Ok ms -> go { d with methods = Some ms } rest
                  | Error e -> Error e)
            | o :: _ ->
              Error
                (Printf.sprintf
                   "unknown option `%s`: the options are `no_redirects` and \
                    `methods(...)`"
                   o)
          in
          match pats with
          | Error e -> Error e
          | Ok patterns -> go { patterns; no_redirects = false; methods = None } opts)

let matches (p : pattern) ~(host : string) ~(port : int) : bool =
  let h = normalize_host host in
  let port_ok = match p.port with None -> true | Some n -> n = port in
  port_ok
  &&
  if p.wildcard then
    let suffix = "." ^ p.host in
    let n = String.length h and m = String.length suffix in
    n > m && String.sub h (n - m) m = suffix
  else h = p.host

let decl_covers (d : decl) ~host ~port =
  d.patterns = [] || List.exists (fun p -> matches p ~host ~port) d.patterns

let permits (ds : decl list) ~(host : string) ~(port : int) : bool =
  ds = [] || List.exists (fun d -> decl_covers d ~host ~port) ds

let permits_method (ds : decl list) ~(host : string) ~(port : int) ~(meth : string) :
    bool =
  ds = []
  || List.exists
       (fun d ->
          decl_covers d ~host ~port
          && match d.methods with None -> true | Some ms -> List.mem meth ms)
       ds

let method_ok d meth =
  match (meth, d.methods) with
  | None, _ | _, None -> true
  | Some m, Some ms -> List.mem m ms

let path_admits (p : pattern) (path : string option) =
  match (p.path, path) with
  | None, _ -> true
  | Some _, None -> false
  | Some segs, Some pth -> path_ok pth && path_within ~prefix:segs pth

let permits_request (ds : decl list) ~(host : string) ~(port : int) ~(meth : string option)
    ~(path : string option) : bool =
  ds = []
  || List.exists
       (fun d ->
          method_ok d meth
          && (d.patterns = []
              || List.exists (fun p -> matches p ~host ~port && path_admits p path) d.patterns))
       ds

let permits_host_ignoring_path (ds : decl list) ~(host : string) ~(port : int)
    ~(meth : string option) : bool =
  ds = [] || List.exists (fun d -> method_ok d meth && decl_covers d ~host ~port) ds

let permits_raw (ds : decl list) ~(host : string) ~(port : int) : bool =
  ds = []
  || List.exists
       (fun d ->
          d.methods = None
          && (d.patterns = []
              || List.exists (fun p -> p.path = None && matches p ~host ~port) d.patterns))
       ds

let forbids_redirects (ds : decl list) ~(host : string) ~(port : int) : bool =
  List.exists (fun d -> d.no_redirects && decl_covers d ~host ~port) ds

let authority_of_url ~(prefix : bool) (s : string) : authority option =
  let strip pre =
    let n = String.length pre in
    if String.length s >= n && String.sub s 0 n = pre then
      Some (String.sub s n (String.length s - n))
    else None
  in
  let scheme =
    match strip "https://" with
    | Some rest -> Some (rest, 443)
    | None -> Option.map (fun rest -> (rest, 80)) (strip "http://")
  in
  match scheme with
  | None -> None
  | Some (rest, default_port) -> (
      let auth =
        match String.index_opt rest '/' with
        | Some i -> Some (String.sub rest 0 i)
        | None -> if prefix then None else Some rest
      in
      match auth with
      | None -> None
      | Some a ->
        let ok_char c =
          (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || is_digit c
          || c = '-' || c = '.' || c = ':'
        in
        if a = "" || not (String.for_all ok_char a) then None
        else
          let host, port =
            match String.split_on_char ':' a with
            | [ h ] -> (h, Some default_port)
            | [ h; p ] -> (h, parse_port p)
            | _ -> ("", None)
          in
          let host = normalize_host host in
          match port with
          | Some port when valid_name host -> Some { a_host = host; a_port = port }
          | _ -> None)

let url_path_of_literal ~(prefix : bool) (s : string) : string option =
  let strip pre =
    let n = String.length pre in
    if String.length s >= n && String.sub s 0 n = pre then
      Some (String.sub s n (String.length s - n))
    else None
  in
  let rest =
    match strip "https://" with Some r -> Some r | None -> strip "http://"
  in
  match rest with
  | None -> None
  | Some rest -> (
      match String.index_opt rest '/' with
      | None -> if prefix then None else Some "/"
      | Some i ->
        let p = strip_query (String.sub rest i (String.length rest - i)) in
        if prefix then
          match String.rindex_opt p '/' with
          | Some j -> Some (String.sub p 0 (j + 1))
          | None -> None
        else Some p)

let encode_spec (ds : decl list) : string =
  String.concat ","
    (List.map
       (fun d ->
          (if d.no_redirects then "!" else "")
          ^ (match d.patterns with [] -> "" | p :: _ -> pattern_to_string p)
          ^ match d.methods with None -> "" | Some ms -> "@" ^ String.concat "+" ms)
       ds)

let decode_spec (s : string) : decl list =
  if s = "" then []
  else
    List.map
      (fun e ->
         let no_redirects = e <> "" && e.[0] = '!' in
         let body = if no_redirects then String.sub e 1 (String.length e - 1) else e in
         let body, methods =
           match String.index_opt body '@' with
           | None -> (body, None)
           | Some i ->
             ( String.sub body 0 i,
               Some (String.split_on_char '+' (String.sub body (i + 1) (String.length body - i - 1))) )
         in
         if body = "" then { patterns = []; no_redirects; methods }
         else
           match parse_pattern body with
           | Ok p -> { patterns = [ p ]; no_redirects; methods }
           | Error msg -> invalid_arg ("Host_scope.decode_spec: " ^ msg))
      (String.split_on_char ',' s)
