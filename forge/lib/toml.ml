(** Minimal TOML parser for forge.toml.
    Supports: quoted strings, bare values, inline tables, sections, comments. *)

type value =
  | Str of string
  | InlineTable of (string * value) list

type document = {
  sections : (string * (string * value) list) list;
}

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
  | _ ->
    let start = i in
    let i = ref i in
    while !i < n && s.[!i] <> ',' && s.[!i] <> '}' && s.[!i] <> '#' do
      incr i
    done;
    let v = String.trim (String.sub s start (!i - start)) in
    (Str v, !i)

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

(** Parse a TOML document. Returns a list of (section_name, key/value pairs).
    The empty string "" holds top-level (pre-section) pairs. *)
let parse text =
  let lines = String.split_on_char '\n' text in
  let sections : (string * (string * value) list) list ref = ref [] in
  let cur_section = ref "" in
  let cur_pairs : (string * value) list ref = ref [] in
  let finish () =
    sections := (!cur_section, List.rev !cur_pairs) :: !sections;
    cur_pairs := []
  in
  List.iter (fun raw ->
    let line = String.trim raw in
    if line = "" || (String.length line > 0 && line.[0] = '#') then
      ()
    else if String.length line >= 3 && line.[0] = '[' then begin
      (match String.index_opt line ']' with
       | None -> ()
       | Some close ->
         finish ();
         let name = String.trim (String.sub line 1 (close - 1)) in
         cur_section := name)
    end else begin
      match String.index_opt line '=' with
      | None -> ()
      | Some eq ->
        let key = String.trim (String.sub line 0 eq) in
        let rest = String.trim (String.sub line (eq + 1) (String.length line - eq - 1)) in
        (try
           let (v, _) = parse_value rest 0 in
           cur_pairs := (key, v) :: !cur_pairs
         with Parse_error _ -> ())
    end
  ) lines;
  finish ();
  { sections = List.rev !sections }

let get_section doc name =
  match List.assoc_opt name doc.sections with
  | None -> []
  | Some pairs -> pairs

let get_string pairs key =
  match List.assoc_opt key pairs with
  | Some (Str s) -> Some s
  | _ -> None

let get_table pairs key =
  match List.assoc_opt key pairs with
  | Some (InlineTable t) -> Some t
  | _ -> None
