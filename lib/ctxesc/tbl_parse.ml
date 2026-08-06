(** Parser for [specs/security/html-contexts.tbl].

    That file is the source of truth for ~H's contextual escaping; see
    [specs/security/README.md] for the format. No external dependencies — the
    format is deliberately small enough to parse by hand, which is also why
    there is no regex engine in the pattern vocabulary.

    DESIGN RULE: every unrecognised token is a hard [Error] carrying the line
    number. A security table that silently drops a row it could not understand
    is the worst possible failure mode — a typo'd state name would quietly
    disable an escaping rule. *)

module C = Context

type pattern =
  | PLit of string        (** [lit:"<"] — literal match *)
  | PILit of string       (** [ilit:"</script"] — case-insensitive; stored lowercased *)
  | PClass of char list   (** [cls:[a-z]] — exactly one char from the set *)
  | PClassPlus of char list (** [cls+:[a-z]] — one or more, greedy *)
  | PName                 (** an attribute name, classified via [attrs] *)
  | PTag                  (** an element name, classified via [tags] *)
  | PUntil of string      (** consume through this literal *)
  | PAny                  (** exactly one character; the catch-all *)
  | PInterp               (** a hole, not source text *)

(** A source-context pattern. [None] is `*` — matches any value. *)
type from_pat = {
  f_state : C.state option;
  f_element : C.element option;
  f_attr : C.attr option;
  f_delim : C.delim option;
}

(** A successor context. [None] is `=` — unchanged from the matched source. *)
type succ_pat = {
  s_state : C.state option;
  s_element : C.element option;
  s_attr : C.attr option;
  s_delim : C.delim option;
}

type row = {
  from_pat : from_pat;
  pat : pattern;
  subst : string option;
  succ : succ_pat;
  diag : string option;  (** if set, this transition is a compile error *)
  line : int;
}

type name_rule = { np : string; (* literal, or prefix for a `foo*` glob *)
                   glob : bool;
                   cls : string }

type t = {
  tags : name_rule list;
  attrs : name_rule list;
  transitions : row list;
}

exception Bad of string * int

let bad line fmt = Printf.ksprintf (fun s -> raise (Bad (s, line))) fmt

let trim = String.trim

let split_on_bar s =
  (* Split on `|`, but not inside a "..." literal — patterns and substitutions
     can legitimately contain a bar. *)
  let out = ref [] and buf = Buffer.create 32 and in_str = ref false in
  String.iteri
    (fun i ch ->
       let escaped = i > 0 && s.[i - 1] = '\\' in
       match ch with
       | '"' when not escaped -> in_str := not !in_str; Buffer.add_char buf ch
       | '|' when not !in_str ->
         out := Buffer.contents buf :: !out; Buffer.clear buf
       | _ -> Buffer.add_char buf ch)
    s;
  out := Buffer.contents buf :: !out;
  (* [out] is built by prepending, so it is already reversed; [rev_map] puts it
     back in source order. Do NOT add a further [List.rev] — that shifts every
     field by one and silently misreads the whole table. *)
  List.rev_map trim !out

let unquote line s =
  let n = String.length s in
  if n < 2 || s.[0] <> '"' || s.[n - 1] <> '"' then
    bad line "expected a quoted string, got `%s`" s;
  let b = Buffer.create (n - 2) in
  let i = ref 1 in
  while !i < n - 1 do
    (if s.[!i] = '\\' && !i + 1 < n - 1 then begin
       incr i;
       Buffer.add_char b
         (match s.[!i] with
          | 'n' -> '\n' | 't' -> '\t' | 'r' -> '\r'
          | c -> c)
     end
     else Buffer.add_char b s.[!i]);
    incr i
  done;
  Buffer.contents b

(* [a-z0-9-_] style sets. Ranges, literal members, and \] \\ \t \n \r escapes.
   NOT regex: no negation, no metacharacters — see README "no regex engine". *)
let parse_class line s =
  let n = String.length s in
  if n < 2 || s.[0] <> '[' || s.[n - 1] <> ']' then
    bad line "expected a [character class], got `%s`" s;
  let chars = ref [] and i = ref 1 in
  let next () =
    if s.[!i] = '\\' && !i + 1 < n - 1 then begin
      incr i;
      let c = match s.[!i] with
        | 'n' -> '\n' | 't' -> '\t' | 'r' -> '\r' | c -> c in
      incr i; c
    end else begin let c = s.[!i] in incr i; c end
  in
  while !i < n - 1 do
    let c = next () in
    if !i < n - 1 && s.[!i] = '-' && !i + 1 < n - 1 then begin
      incr i;
      let hi = next () in
      if Char.code hi < Char.code c then
        bad line "reversed range `%c-%c` in class" c hi;
      for k = Char.code c to Char.code hi do
        chars := Char.chr k :: !chars
      done
    end
    else chars := c :: !chars
  done;
  List.rev !chars

let parse_pattern line s =
  let starts p = String.length s > String.length p
                 && String.sub s 0 (String.length p) = p in
  let arg p = String.sub s (String.length p) (String.length s - String.length p) in
  match s with
  | "interp" -> PInterp
  | "any" -> PAny
  | "name" -> PName
  | "tag" -> PTag
  | _ when starts "lit:" -> PLit (unquote line (arg "lit:"))
  | _ when starts "ilit:" -> PILit (String.lowercase_ascii (unquote line (arg "ilit:")))
  | _ when starts "until:" -> PUntil (unquote line (arg "until:"))
  | _ when starts "cls+:" -> PClassPlus (parse_class line (arg "cls+:"))
  | _ when starts "cls:" -> PClass (parse_class line (arg "cls:"))
  | _ ->
    bad line
      "unknown pattern `%s`. Valid forms: lit:\"..\" ilit:\"..\" until:\"..\" \
       cls:[..] cls+:[..] name tag any interp. There is deliberately no regex \
       form — see specs/security/README.md."
      s

let field line kind of_string wildcard s =
  if s = wildcard then None
  else
    match of_string s with
    | Some v -> Some v
    | None -> bad line "unknown %s `%s`" kind s

let parse_from line s =
  match String.split_on_char ',' s |> List.map trim with
  | [ st; el; at; dl ] ->
    { f_state = field line "state" C.state_of_string "*" st;
      f_element = field line "element" C.element_of_string "*" el;
      f_attr = field line "attr class" C.attr_of_string "*" at;
      f_delim = field line "delimiter" C.delim_of_string "*" dl }
  | _ ->
    bad line "a source context needs 4 comma-separated fields \
              (state,element,attr,delim), got `%s`" s

let parse_succ line s =
  match String.split_on_char ',' s |> List.map trim with
  | [ st; el; at; dl ] ->
    { s_state = field line "state" C.state_of_string "=" st;
      s_element = field line "element" C.element_of_string "=" el;
      s_attr = field line "attr class" C.attr_of_string "=" at;
      s_delim = field line "delimiter" C.delim_of_string "=" dl }
  | _ ->
    bad line "a successor context needs 4 comma-separated fields \
              (state,element,attr,delim), got `%s`" s

let parse_name_rule line kind valid s =
  match split_on_bar s with
  | [ pat; cls ] ->
    if not (List.mem cls valid) then
      bad line "unknown %s class `%s` (valid: %s)" kind cls
        (String.concat " " valid);
    let glob = String.length pat > 0 && pat.[String.length pat - 1] = '*' in
    let np = if glob then String.sub pat 0 (String.length pat - 1) else pat in
    { np = String.lowercase_ascii np; glob; cls }
  | _ -> bad line "a [%ss] row needs 2 fields (pattern | class), got `%s`" kind s

let parse_transition line s =
  match split_on_bar s with
  | [ from_s; pat_s; subst_s; succ_s; diag_s ] ->
    { from_pat = parse_from line from_s;
      pat = parse_pattern line pat_s;
      (* A substitution is ALWAYS a quoted string. It must be: an unquoted
         bare quote character would open a literal that [split_on_bar] never
         closes, silently swallowing the rest of the row's separators. *)
      subst = (if subst_s = "" then None else Some (unquote line subst_s));
      succ = parse_succ line succ_s;
      diag = (if diag_s = "" then None else Some diag_s);
      line }
  | fields ->
    bad line
      "a [transitions] row needs 5 fields separated by `|` \
       (from | pattern | substitution | successor | diagnostic), got %d"
      (List.length fields)

let parse_file path =
  try
    let ic = open_in path in
    let tags = ref [] and attrs = ref [] and trans = ref [] in
    let section = ref `None in
    let lineno = ref 0 in
    (try
       while true do
         let raw = input_line ic in
         incr lineno;
         let line = !lineno in
         (* strip comments, but not a `#` inside a quoted literal *)
         let s =
           let b = Buffer.create (String.length raw) in
           (try
              let in_str = ref false in
              String.iteri
                (fun i ch ->
                   let escaped = i > 0 && raw.[i - 1] = '\\' in
                   if ch = '"' && not escaped then in_str := not !in_str;
                   if ch = '#' && not !in_str then raise Exit;
                   Buffer.add_char b ch)
                raw
            with Exit -> ());
           trim (Buffer.contents b)
         in
         if s <> "" then
           match s with
           | "[tags]" -> section := `Tags
           | "[attrs]" -> section := `Attrs
           | "[transitions]" -> section := `Transitions
           | _ when String.length s > 1 && s.[0] = '[' ->
             bad line "unknown section `%s` (expected [tags], [attrs] or [transitions])" s
           | _ ->
             (match !section with
              | `None ->
                bad line
                  "row appears before any section header — every row must \
                   follow [tags], [attrs] or [transitions]"
              | `Tags ->
                tags := parse_name_rule line "tag"
                          (List.map C.element_name C.all_elements) s :: !tags
              | `Attrs ->
                attrs := parse_name_rule line "attr"
                           (List.map C.attr_name C.all_attrs) s :: !attrs
              | `Transitions -> trans := parse_transition line s :: !trans)
       done
     with End_of_file -> ());
    close_in ic;
    Ok { tags = List.rev !tags;
         attrs = List.rev !attrs;
         transitions = List.rev !trans }
  with
  | Bad (msg, line) -> Error (Printf.sprintf "%s: line %d: %s" path line msg)
  | Sys_error e -> Error e

(** Classify a tag or attribute name against a [name_rule] list. First match
    wins, so ordering in the file is significant (e.g. `on*` above `*`). *)
let classify rules name =
  let name = String.lowercase_ascii name in
  let matches r =
    if r.glob then
      String.length name >= String.length r.np
      && String.sub name 0 (String.length r.np) = r.np
    else r.np = name
  in
  match List.find_opt matches rules with
  | Some r -> Some r.cls
  | None -> None
