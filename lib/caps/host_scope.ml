(* Host scopes on IO.NetConnect.  See host_scope.mli. *)

type pattern = { host : string; wildcard : bool; port : int option }
type decl = { patterns : pattern list; no_redirects : bool }
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

let parse_pattern (raw : string) : (pattern, string) result =
  let s = String.lowercase_ascii raw in
  if s = "" then Error "a host scope cannot be empty"
  else if contains s "://" then
    Error "a host scope names a host, not a URL: drop the scheme (`https://`)"
  else if String.contains s '/' then
    Error "a host scope names a host, not a URL: drop the path"
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
        then Ok { host = host_part; wildcard = false; port }
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
        else Ok { host = name; wildcard; port }

let pattern_to_string (p : pattern) : string =
  (if p.wildcard then "*." else "")
  ^ p.host
  ^ match p.port with None -> "" | Some n -> ":" ^ string_of_int n

let parse_decl (scope : string option) : (decl, string) result =
  match scope with
  | None -> Ok { patterns = []; no_redirects = false }
  | Some s -> (
      let pattern_of p =
        if p = "" then Ok [] else Result.map (fun x -> [ x ]) (parse_pattern p)
      in
      match String.split_on_char ';' s with
      | [ p ] ->
        if p = "" then Error "a host scope cannot be empty"
        else Result.map (fun ps -> { patterns = ps; no_redirects = false }) (pattern_of p)
      | [ p; "no_redirects" ] ->
        Result.map (fun ps -> { patterns = ps; no_redirects = true }) (pattern_of p)
      | [ _; opt ] ->
        Error (Printf.sprintf "unknown option `%s`: the only option is `no_redirects`" opt)
      | _ -> Error "a host scope takes at most one option, `no_redirects`")

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

let encode_spec (ds : decl list) : string =
  String.concat ","
    (List.map
       (fun d ->
          (if d.no_redirects then "!" else "")
          ^ match d.patterns with [] -> "" | p :: _ -> pattern_to_string p)
       ds)

let decode_spec (s : string) : decl list =
  if s = "" then []
  else
    List.map
      (fun e ->
         let no_redirects = e <> "" && e.[0] = '!' in
         let body = if no_redirects then String.sub e 1 (String.length e - 1) else e in
         if body = "" then { patterns = []; no_redirects }
         else
           match parse_pattern body with
           | Ok p -> { patterns = [ p ]; no_redirects }
           | Error msg -> invalid_arg ("Host_scope.decode_spec: " ^ msg))
      (String.split_on_char ',' s)
