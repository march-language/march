(** Minimal TOML parser for forge.toml.
    Supports: quoted strings, booleans, bare values, inline tables, arrays
    (which may span lines), sections, [[array-of-tables]], comments.

    Every line is either parsed or rejected: a malformed line raises
    [Parse_error] naming its line number, rather than being dropped. The
    located view ([document.located], the [_at] accessors) carries the line of
    every section header and key, so a consumer can say
    [forge.toml:12: unknown key 'replica']. *)

type value =
  | Str of string
    (** A quoted string, or any bare value that is not a boolean (bare
        values such as versions have always read as strings). *)
  | Bool of bool
    (** The bare words [true] / [false] exactly (TOML booleans are
        lowercase). A quoted ["true"] stays a [Str]. *)
  | InlineTable of (string * value) list
  | Array of value list

(** A section with the line of its header (0 for the implicit top-level
    section) and the line of each key. *)
type located_section = {
  sec_name  : string;
  sec_line  : int;
  sec_pairs : (string * value * int) list;  (** key, value, line of the key *)
}

type document = {
  sections : (string * (string * value) list) list;
  (** Every section in file order, lines dropped. Sections with the same name
      (array-of-tables) appear once each. *)
  located : located_section list;
  (** The same sections, in the same order, with line numbers. *)
}

(** A malformed document. From [parse], the message starts with
    ["line N: "]; [parse_located] returns the line separately. *)
exception Parse_error of string

let fail msg = raise (Parse_error msg)

let skip_ws s i =
  let n = String.length s in
  let i = ref i in
  while !i < n && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
  !i

let parse_quoted_string s i =
  let n = String.length s in
  if i >= n || s.[i] <> '"' then fail "expected '\"'";
  let buf = Buffer.create 16 in
  let pos = ref (i + 1) in
  while !pos < n && s.[!pos] <> '"' do
    (match s.[!pos] with
     | '\\' ->
       incr pos;
       if !pos >= n then fail "unterminated escape sequence";
       (match s.[!pos] with
        | '"'  -> Buffer.add_char buf '"'
        | '\\' -> Buffer.add_char buf '\\'
        | 'n'  -> Buffer.add_char buf '\n'
        | 't'  -> Buffer.add_char buf '\t'
        | 'r'  -> Buffer.add_char buf '\r'
        | c    -> Buffer.add_char buf '\\'; Buffer.add_char buf c);
       incr pos
     | c ->
       Buffer.add_char buf c;
       incr pos)
  done;
  if !pos >= n then fail "unterminated string";
  (Buffer.contents buf, !pos + 1)

let parse_bare_key s i =
  let n = String.length s in
  let start = i in
  let i = ref i in
  while !i < n &&
        (let c = s.[!i] in
         (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c = '-' || c = '_') do
    incr i
  done;
  if !i = start then
    fail (Printf.sprintf "expected bare key at position %d" start);
  (String.sub s start (!i - start), !i)

let parse_key s i =
  let i = skip_ws s i in
  let n = String.length s in
  if i >= n then fail "expected key, got end of input";
  if s.[i] = '"' then parse_quoted_string s i
  else parse_bare_key s i

let rec parse_value s i =
  let i = skip_ws s i in
  let n = String.length s in
  if i >= n then fail "expected value, got end of input";
  match s.[i] with
  | '"' ->
    let (v, i') = parse_quoted_string s i in
    (Str v, i')
  | '{' ->
    let (tbl, i') = parse_inline_table s (i + 1) in
    (InlineTable tbl, i')
  | '[' ->
    let (arr, i') = parse_array s (i + 1) in
    (Array arr, i')
  | _ ->
    let start = i in
    let i = ref i in
    while !i < n && s.[!i] <> ',' && s.[!i] <> '}' && s.[!i] <> ']' && s.[!i] <> '#' do
      incr i
    done;
    let v = String.trim (String.sub s start (!i - start)) in
    let v = match v with
      | "true"  -> Bool true
      | "false" -> Bool false
      | v       -> Str v
    in
    (v, !i)

and parse_array s i =
  let n = String.length s in
  let i = ref (skip_ws s i) in
  let items = ref [] in
  if !i < n && s.[!i] = ']' then ([], !i + 1)
  else begin
    let stop = ref false in
    while not !stop do
      let (v, i2) = parse_value s !i in
      items := v :: !items;
      i := skip_ws s i2;
      if !i >= n then fail "unterminated array";
      (match s.[!i] with
       | ']' -> stop := true; incr i
       | ',' ->
         i := skip_ws s (!i + 1);
         (* TOML allows a trailing comma before the closing bracket. *)
         if !i < n && s.[!i] = ']' then (stop := true; incr i)
       | c   -> fail (Printf.sprintf "expected ',' or ']', got '%c'" c))
    done;
    (List.rev !items, !i)
  end

and parse_inline_table s i =
  let n = String.length s in
  let i = ref (skip_ws s i) in
  let pairs = ref [] in
  if !i < n && s.[!i] = '}' then ([], !i + 1)
  else begin
    let stop = ref false in
    while not !stop do
      let (k, i2) = parse_key s !i in
      let i3 = skip_ws s i2 in
      if i3 >= n || s.[i3] <> '=' then
        fail (Printf.sprintf "expected '=' after key '%s'" k);
      let i4 = skip_ws s (i3 + 1) in
      let (v, i5) = parse_value s i4 in
      pairs := (k, v) :: !pairs;
      i := skip_ws s i5;
      if !i >= n then fail "unterminated inline table";
      (match s.[!i] with
       | '}' -> stop := true; incr i
       | ',' -> incr i
       | c   -> fail (Printf.sprintf "expected ',' or '}', got '%c'" c))
    done;
    (List.rev !pairs, !i)
  end

(* Position of a [#] comment start outside a quoted string, if any. *)
let comment_start s =
  let n = String.length s in
  let rec go i in_str =
    if i >= n then None
    else match s.[i] with
      | '\\' when in_str -> go (i + 2) true
      | '"' -> go (i + 1) (not in_str)
      | '#' when not in_str -> Some i
      | _ -> go (i + 1) in_str
  in
  go 0 false

let strip_comment s =
  match comment_start s with
  | Some i -> String.sub s 0 i
  | None -> s

(* Does [s] (comment already stripped) leave a '[' or '{' open outside a
   string? Used to join an array that spans lines. *)
let opens_unclosed s =
  let n = String.length s in
  let depth = ref 0 and in_str = ref false and i = ref 0 in
  while !i < n do
    (match s.[!i] with
     | '\\' when !in_str -> incr i
     | '"' -> in_str := not !in_str
     | ('[' | '{') when not !in_str -> incr depth
     | (']' | '}') when not !in_str -> decr depth
     | _ -> ());
    incr i
  done;
  !depth > 0

exception Located_error of int * string

(** Parse a TOML document, reporting the first malformed line separately:
    [Error (line, message)]. *)
let parse_located text : (document, int * string) result =
  let lines = Array.of_list (String.split_on_char '\n' text) in
  let nlines = Array.length lines in
  let located = ref [] in
  let cur_name = ref "" and cur_line = ref 0 in
  let cur_pairs : (string * value * int) list ref = ref [] in
  let finish () =
    located := { sec_name = !cur_name; sec_line = !cur_line;
                 sec_pairs = List.rev !cur_pairs } :: !located;
    cur_pairs := []
  in
  let err lineno msg = raise (Located_error (lineno, msg)) in
  let header lineno line =
    let is_aot = String.length line >= 2 && line.[1] = '[' in
    let opener = if is_aot then 2 else 1 in
    let closer = if is_aot then "]]" else "]" in
    let body = String.sub line opener (String.length line - opener) in
    let cl = String.length closer in
    let rec find i =
      if i + cl > String.length body then None
      else if String.sub body i cl = closer then Some i
      else find (i + 1)
    in
    match find 0 with
    | None ->
      err lineno (Printf.sprintf "unterminated section header (missing '%s')" closer)
    | Some close ->
      let name = String.trim (String.sub body 0 close) in
      let rest = String.trim (String.sub body (close + cl)
                                (String.length body - close - cl)) in
      if name = "" then err lineno "empty section name";
      if rest <> "" then
        err lineno (Printf.sprintf "unexpected text after section header: %s" rest);
      finish ();
      cur_name := name;
      cur_line := lineno
  in
  let i = ref 0 in
  (try
     while !i < nlines do
       let lineno = !i + 1 in
       let line = String.trim (strip_comment lines.(!i)) in
       incr i;
       if line = "" then ()
       else if line.[0] = '[' then header lineno line
       else
         match String.index_opt line '=' with
         | None -> err lineno (Printf.sprintf "expected 'key = value', got: %s" line)
         | Some eq ->
           let key = String.trim (String.sub line 0 eq) in
           if key = "" then err lineno "missing key before '='";
           let key =
             if String.length key >= 2 && key.[0] = '"' then
               (try fst (parse_quoted_string key 0)
                with Parse_error m -> err lineno m)
             else key
           in
           let rest = ref (String.trim (String.sub line (eq + 1)
                                          (String.length line - eq - 1))) in
           (* An array may continue on the following lines. *)
           while opens_unclosed !rest && !i < nlines do
             rest := !rest ^ " " ^ String.trim (strip_comment lines.(!i));
             incr i
           done;
           let (v, stop) =
             try parse_value !rest 0 with Parse_error m -> err lineno m
           in
           let stop = skip_ws !rest stop in
           if stop < String.length !rest then
             err lineno (Printf.sprintf "unexpected text after the value of '%s': %s"
                           key (String.sub !rest stop (String.length !rest - stop)));
           cur_pairs := (key, v, lineno) :: !cur_pairs
     done;
     finish ();
     let located = List.rev !located in
     let sections =
       List.map (fun ls ->
           (ls.sec_name, List.map (fun (k, v, _) -> (k, v)) ls.sec_pairs))
         located
     in
     Ok { sections; located }
   with Located_error (l, m) -> Error (l, m))

(** Parse a TOML document. Returns a list of (section_name, key/value pairs).
    The empty string "" holds top-level (pre-section) pairs. Raises
    [Parse_error "line N: ..."] on the first malformed line. *)
let parse text =
  match parse_located text with
  | Ok doc -> doc
  | Error (line, msg) -> raise (Parse_error (Printf.sprintf "line %d: %s" line msg))

let get_section doc name =
  match List.assoc_opt name doc.sections with
  | None -> []
  | Some pairs -> pairs

(** Return ALL sections with the given name (for [[array-of-tables]]). *)
let get_all_sections doc name =
  List.filter_map
    (fun (n, pairs) -> if n = name then Some pairs else None)
    doc.sections

let get_string pairs key =
  match List.assoc_opt key pairs with
  | Some (Str s) -> Some s
  | _ -> None

let get_bool pairs key =
  match List.assoc_opt key pairs with
  | Some (Bool b) -> Some b
  | _ -> None

let get_table pairs key =
  match List.assoc_opt key pairs with
  | Some (InlineTable t) -> Some t
  | _ -> None

let get_string_list pairs key =
  match List.assoc_opt key pairs with
  | Some (Array items) ->
    List.filter_map (function Str s -> Some s | _ -> None) items
  | _ -> []

(* ── Located accessors ───────────────────────────────────────────────── *)

(** The first section named [name] with its lines, if present. *)
let get_section_at doc name =
  List.find_opt (fun ls -> ls.sec_name = name) doc.located

(** Every section named [name] with its lines (for [[array-of-tables]]). *)
let get_all_sections_at doc name =
  List.filter (fun ls -> ls.sec_name = name) doc.located

let find_at (ls : located_section) key =
  List.find_map (fun (k, v, l) -> if k = key then Some (v, l) else None) ls.sec_pairs

let get_string_at ls key =
  match find_at ls key with
  | Some (Str s, l) -> Some (s, l)
  | _ -> None

let get_table_at ls key =
  match find_at ls key with
  | Some (InlineTable t, l) -> Some (t, l)
  | _ -> None

let get_string_list_at ls key =
  match find_at ls key with
  | Some (Array items, l) ->
    Some (List.filter_map (function Str s -> Some s | _ -> None) items, l)
  | _ -> None

(** [(key, line)] for every key, in every section named [section], that is
    not in [known]. *)
let check_keys ~section ~known doc =
  List.concat_map (fun ls ->
      List.filter_map (fun (k, _, l) ->
          if List.mem k known then None else Some (k, l))
        ls.sec_pairs)
    (get_all_sections_at doc section)
