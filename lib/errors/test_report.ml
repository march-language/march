(** Test-failure reports: a failing `assert`, a failing `Check.all` property
    and a test body that panics, rendered in the house diagnostic style
    (a `-- TEST FAILURE --` header, one sentence, the source line with a
    caret) through {!Errors.render_diagnostic}.

    A report is built in two halves, because the compiled backend only knows
    the values at run time:

    - the {b header} (header bar, sentence, source line and caret) is
      rendered here, in OCaml, from the assertion's span: by the interpreter
      when the assertion fails, and by lowering ([Lower_expr]'s [EAssert]
      arm) at compile time, where it becomes a string constant;
    - the {b value diff} below it is computed from the two operands' printed
      forms (`to_string`, a `String` operand quoted by {!quote}).  The
      interpreter calls {!compare_report}; a compiled program calls
      `march_assert_fail` in `runtime/march_runtime.c`, a line-for-line port
      of the parser, differ and renderer below.  The two must print byte for
      byte the same: `test/errors_tests/` runs each case both ways and pins
      one golden (see test/run_test_reports.ml).

    Nothing here changes whether a test passes; only what a failure prints.

    The differ works on printed forms, not values, so it needs no type
    information and the compiled runtime can run it: {!parse} reads a printed
    value back into a tree (lists, tuples, records, constructor applications,
    strings, leaves), and anything it cannot read is one opaque leaf, so a
    custom `Show` impl degrades to "the whole value differs", never to an
    error. *)

open March_ast.Ast

(* ── Header ───────────────────────────────────────────────────────────── *)

let source_cache : (string, string option) Hashtbl.t = Hashtbl.create 8

(** The text of [file], read once; [None] when it cannot be read. *)
let source_of (file : string) : string option =
  match Hashtbl.find_opt source_cache file with
  | Some s -> s
  | None ->
    let s =
      try
        let ic = open_in_bin file in
        Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
          Some (really_input_string ic (in_channel_length ic)))
      with _ -> None
    in
    Hashtbl.replace source_cache file s;
    s

(** [render_diagnostic] without colour and without trailing blank lines,
    whatever the process's colour setting: the compiled header is a string
    constant in a binary that may print to a pipe, and the interpreter's
    copy must match it. *)
let header ~code ~(span : span) (message : string) : string =
  let src = match source_of span.file with Some s -> s | None -> "" in
  let d = Errors.make ~code ~span message in
  let saved = !Errors.use_color in
  Errors.use_color := false;
  let r = Fun.protect ~finally:(fun () -> Errors.use_color := saved)
      (fun () -> Errors.render_diagnostic ~src ~filename:span.file d) in
  let n = ref (String.length r) in
  while !n > 0 && (r.[!n - 1] = '\n' || r.[!n - 1] = ' ') do decr n done;
  String.sub r 0 !n

(** The source text of [span] on one line: whitespace runs collapsed, cut to
    40 characters with an ellipsis.  [None] when the file cannot be read. *)
let source_text (span : span) : string option =
  match source_of span.file with
  | None -> None
  | Some src ->
    let lines = String.split_on_char '\n' src in
    let line n = try List.nth lines (n - 1) with _ -> "" in
    let buf = Buffer.create 32 in
    for l = span.start_line to span.end_line do
      let t = line l in
      let a = if l = span.start_line then span.start_col else 0 in
      let b = if l = span.end_line then span.end_col else String.length t in
      let a = max 0 (min a (String.length t)) and b = max 0 (min b (String.length t)) in
      if b > a then begin
        if Buffer.length buf > 0 then Buffer.add_char buf ' ';
        Buffer.add_string buf (String.sub t a (b - a))
      end
    done;
    let s = Buffer.contents buf in
    (* collapse whitespace runs *)
    let out = Buffer.create (String.length s) in
    let prev_space = ref false in
    String.iter (fun c ->
      if c = ' ' || c = '\t' || c = '\r' then begin
        if not !prev_space then Buffer.add_char out ' ';
        prev_space := true
      end else begin Buffer.add_char out c; prev_space := false end) s;
    let s = String.trim (Buffer.contents out) in
    if s = "" then None
    else if String.length s > 40 then begin
      (* Cut at a character boundary, never inside a UTF-8 sequence. *)
      let n = ref 39 in
      while !n > 0 && Char.code s.[!n] land 0xc0 = 0x80 do decr n done;
      Some (String.sub s 0 !n ^ "\xe2\x80\xa6")
    end
    else Some s

(** The operators whose two sides a failed assertion shows. *)
let comparison_ops = [ "=="; "!="; "<"; ">"; "<="; ">=" ]

(** The source text an operand is labelled with ([span] is its span), or
    [""] for a literal (`[1, 2]`, `"abc"`, `Some(1)`), which its printed
    value already shows. *)
let operand_source ~(span : span) (e : expr) : string =
  let rec literal = function
    | ELit _ -> true
    | ECon (_, args, _) | ETuple (args, _) -> List.for_all literal args
    | ERecord (fields, _) -> List.for_all (fun (_, v) -> literal v) fields
    | _ -> false
  in
  if literal e then "" else Option.value (source_text span) ~default:""

(** The sentence for a failed assertion over [op] ([""] for a plain
    `assert cond`). *)
let assert_sentence (op : string) : string =
  match op with
  | "==" -> "The two sides of this `==` are not equal."
  | "!=" -> "The two sides of this `!=` are equal."
  | "" -> "This assertion is false."
  | op -> Printf.sprintf "This `%s` comparison is false." op

(** The header of a failed assertion: [span] is the asserted expression's
    (the caret goes under it), [op] its comparison operator or [""]. *)
let assert_header ~(span : span) ~(op : string) : string =
  header ~code:Code.assert_failed ~span (assert_sentence op)

(** The marker a panic report carries where its message goes.  The test
    runners render the header once, with this in the sentence, and put the
    panic message in its place ({!fill_panic}).  Rendering with the real
    message would put the `[slug]` after its first line instead. *)
let panic_hole = "\x01"

(** The header of a test whose body panicked: the caret goes under the
    `test "…"` line ([span] is the test declaration's; only its first line
    is underlined). *)
let panic_header ~(span : span) : string =
  let span = { span with end_line = span.start_line; end_col = 0 } in
  header ~code:Code.test_panicked ~span ("This test panicked: " ^ panic_hole)

let fill_panic (header : string) (msg : string) : string =
  match String.index_opt header '\x01' with
  | None -> header
  | Some i ->
    String.sub header 0 i ^ msg
    ^ String.sub header (i + 1) (String.length header - i - 1)

(** Whether [msg] is already a rendered report (an assertion or property
    failure), which a runner prints as it is. *)
let is_report (msg : string) : bool =
  String.starts_with ~prefix:"-- TEST FAILURE " msg

(* ── Printed values ─────────────────────────────────────────────────── *)

(** A String operand as the report shows it: in double quotes, with a
    backslash, a double quote and control characters escaped (the same
    escapes `march_assert_fail` makes). *)
let quote (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\t' -> Buffer.add_string b "\\t"
    | '\r' -> Buffer.add_string b "\\r"
    | c when Char.code c < 0x20 || Char.code c = 0x7f ->
      Buffer.add_string b (Printf.sprintf "\\x%02x" (Char.code c))
    | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

type node =
  | Leaf of string                    (** a number, a nullary constructor, … *)
  | Str of string                     (** a quoted string, quotes included *)
  | List of node list
  | Tuple of node list
  | Record of string * string * (string * node) list
      (** [(name, sep, fields)]: `{ k: v }` is [("", ": ", …)], a derived
          `Show`'s `User { k = v }` is [("User", " = ", …)] *)
  | Ctor of string * node list        (** [Name(args)] *)

exception Unreadable

let is_delim c =
  match c with ',' | '(' | ')' | '[' | ']' | '{' | '}' | '"' -> true | _ -> false

let is_ident s =
  s <> ""
  && (match s.[0] with 'A' .. 'Z' | 'a' .. 'z' | '_' -> true | _ -> false)
  && String.for_all (fun c ->
       match c with 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '.' -> true
                  | _ -> false) s

(** Read a printed value back into a tree; an unreadable one is a [Leaf]. *)
let parse (s : string) : node =
  let n = String.length s in
  let pos = ref 0 in
  let skip () = while !pos < n && s.[!pos] = ' ' do incr pos done in
  let peek () = if !pos < n then Some s.[!pos] else None in
  let rec value () =
    skip ();
    match peek () with
    | None -> raise Unreadable
    | Some '"' -> str ()
    | Some '[' -> incr pos; List (seq ']')
    | Some '(' ->
      incr pos;
      (match seq ')' with [] -> Leaf "()" | xs -> Tuple xs)
    | Some '{' -> incr pos; let (sep, fs) = fields () in Record ("", sep, fs)
    | Some c when is_delim c -> raise Unreadable
    | Some _ -> atom ()
  and str () =
    let start = !pos in
    incr pos;
    while !pos < n && s.[!pos] <> '"' do
      if s.[!pos] = '\\' then incr pos;
      incr pos
    done;
    if !pos >= n then raise Unreadable;
    incr pos;
    Str (String.sub s start (!pos - start))
  and atom () =
    let start = !pos in
    while !pos < n && not (is_delim s.[!pos]) do incr pos done;
    let text = String.trim (String.sub s start (!pos - start)) in
    if text = "" then raise Unreadable;
    if !pos < n && s.[!pos] = '(' && is_ident text then begin
      incr pos;
      Ctor (text, seq ')')
    end else if !pos < n && s.[!pos] = '{' && is_ident text then begin
      incr pos;
      let (sep, fs) = fields () in
      Record (text, sep, fs)
    end else Leaf text
  and seq close =
    skip ();
    if peek () = Some close then (incr pos; [])
    else
      let rec loop acc =
        let v = value () in
        skip ();
        match peek () with
        | Some ',' -> incr pos; loop (v :: acc)
        | Some c when c = close -> incr pos; List.rev (v :: acc)
        | _ -> raise Unreadable
      in
      loop []
  and fields () =
    (* `k: v` (a record) or `k = v` (a derived Show); the first field
       decides, and every field must use the same one. *)
    let sep = ref "" in
    skip ();
    if peek () = Some '}' then (incr pos; (": ", []))
    else
      let rec loop acc =
        skip ();
        let start = !pos in
        while !pos < n && s.[!pos] <> ':' && s.[!pos] <> '='
              && not (is_delim s.[!pos]) do incr pos done;
        let this = match peek () with
          | Some ':' -> ": " | Some '=' -> " = " | _ -> raise Unreadable in
        if !sep = "" then sep := this else if !sep <> this then raise Unreadable;
        let key = String.trim (String.sub s start (!pos - start)) in
        if not (is_ident key) then raise Unreadable;
        incr pos;
        let v = value () in
        skip ();
        match peek () with
        | Some ',' -> incr pos; loop ((key, v) :: acc)
        | Some '}' -> incr pos; (!sep, List.rev ((key, v) :: acc))
        | _ -> raise Unreadable
      in
      loop []
  in
  try
    let v = value () in
    skip ();
    if !pos <> n then Leaf s else v
  with Unreadable -> Leaf s

(** Display width: UTF-8 continuation bytes take no column. *)
let width (s : string) : int =
  let w = ref 0 in
  String.iter (fun c -> if Char.code c land 0xc0 <> 0x80 then incr w) s;
  !w

let ellipsis = "\xe2\x80\xa6"

(** [s] cut to at most [max] columns, the last one an ellipsis. *)
let clip (s : string) (max : int) : string =
  if width s <= max then s
  else begin
    let b = Buffer.create max in
    let w = ref 0 in
    let i = ref 0 in
    let n = String.length s in
    while !i < n && (!w < max - 1 || Char.code s.[!i] land 0xc0 = 0x80) do
      if Char.code s.[!i] land 0xc0 <> 0x80 then incr w;
      Buffer.add_char b s.[!i];
      incr i
    done;
    Buffer.add_string b ellipsis;
    Buffer.contents b
  end

let rec print (v : node) : string =
  match v with
  | Leaf s | Str s -> s
  | List xs -> "[" ^ String.concat ", " (List.map print xs) ^ "]"
  | Tuple xs -> "(" ^ String.concat ", " (List.map print xs) ^ ")"
  | Record (name, sep, fs) ->
    (if name = "" then "" else name ^ " ")
    ^ "{ " ^ String.concat ", " (List.map (fun (k, v) -> k ^ sep ^ print v) fs) ^ " }"
  | Ctor (c, xs) -> c ^ "(" ^ String.concat ", " (List.map print xs) ^ ")"

(* ── The first difference ───────────────────────────────────────────── *)

type step = Idx of int | Field of string | Arg of int

type kind =
  | Whole                (** the parts at the path differ outright *)
  | Chars of int         (** two strings; byte offset of the first difference *)
  | Length of int * int  (** two lists equal up to the shorter's length *)

let rec first_diff (a : node) (b : node) (path : step list) : (step list * kind) option =
  if a = b then None
  else
    let rec items i xs ys mk =
      match xs, ys with
      | x :: xs', y :: ys' ->
        if x = y then items (i + 1) xs' ys' mk
        else first_diff x y (mk i :: path)
      | _ -> None
    in
    match a, b with
    | List xs, List ys ->
      (match items 0 xs ys (fun i -> Idx i) with
       | Some d -> Some d
       | None -> Some (List.rev path, Length (List.length xs, List.length ys)))
    | Tuple xs, Tuple ys when List.length xs = List.length ys ->
      items 0 xs ys (fun i -> Arg i)
    | Ctor (c, xs), Ctor (d, ys) when c = d && List.length xs = List.length ys ->
      items 0 xs ys (fun i -> Arg i)
    | Record (m, _, fs), Record (m', _, gs) when m = m' && List.map fst fs = List.map fst gs ->
      let rec go fs gs =
        match fs, gs with
        | (k, x) :: fs', (_, y) :: gs' ->
          if x = y then go fs' gs' else first_diff x y (Field k :: path)
        | _ -> Some (List.rev path, Whole)   (* only the separators differ *)
      in
      go fs gs
    | Str s, Str t ->
      let n = min (String.length s) (String.length t) in
      let i = ref 0 in
      while !i < n && s.[!i] = t.[!i] do incr i done;
      (* Back up to the start of a UTF-8 character. *)
      while !i > 0 && Char.code s.[!i] land 0xc0 = 0x80 do decr i done;
      Some (List.rev path, Chars !i)
    | _ -> Some (List.rev path, Whole)

(** The path as a March-like accessor: `.field` and `[i]` steps, up to the
    first constructor or tuple argument (the carets show the rest). *)
let path_text (path : step list) : string =
  let b = Buffer.create 16 in
  let rec go = function
    | Idx i :: rest -> Buffer.add_string b (Printf.sprintf "[%d]" i); go rest
    | Field f :: rest -> Buffer.add_string b ("." ^ f); go rest
    | Arg _ :: _ | [] -> ()
  in
  go path;
  Buffer.contents b

(* ── Rendering one side with its caret ──────────────────────────────── *)

(** Values wider than this are shown elided: only the path to the
    difference, the rest as `…`. *)
let elide_over = 60

(** [render ~elide v path kind ~longer] prints [v] with the part at [path]
    marked, returning the text and the marked part's column and width.
    [longer] says, for a [Length] difference, whether this is the longer
    list (its extra elements are marked) or the shorter (its `]` is). *)
let render ~elide (v : node) (path : step list) (kind : kind) ~(longer : bool)
  : string * int * int =
  let b = Buffer.create 64 in
  let col = ref 0 in
  let mark = ref (0, 1) in
  let add s = Buffer.add_string b s; col := !col + width s in
  let marked s =
    let c = !col in add s; mark := (c, max 1 (width s)) in
  let full v = if elide then clip (print v) elide_over else print v in
  let rec go v path =
    match path, v with
    | [], _ -> target v
    | step :: rest, List xs ->
      let i = (match step with Idx i -> i | _ -> -1) in
      on_path xs i rest ~open_:"[" ~close:"]"
    | step :: rest, Tuple xs ->
      let i = (match step with Arg i -> i | _ -> -1) in
      on_path xs i rest ~open_:"(" ~close:")"
    | step :: rest, Ctor (c, xs) ->
      let i = (match step with Arg i -> i | _ -> -1) in
      on_path xs i rest ~open_:(c ^ "(") ~close:")"
    | Field f :: rest, Record (name, sep, fs) ->
      let idx = ref (-1) in
      List.iteri (fun j (k, _) -> if k = f then idx := j) fs;
      let n = List.length fs in
      if name <> "" then add (name ^ " ");
      add "{ ";
      if elide then begin
        if !idx > 0 then add (ellipsis ^ ", ");
        add (f ^ sep);
        go (List.assoc f fs) rest;
        if !idx < n - 1 then add (", " ^ ellipsis)
      end else
        List.iteri (fun j (k, x) ->
          if j > 0 then add ", ";
          add (k ^ sep);
          if j = !idx then go x rest else add (print x)) fs;
      add " }"
    | _ -> target v   (* a path that does not fit: mark what is here *)
  and on_path xs i rest ~open_ ~close =
    let n = List.length xs in
    add open_;
    if elide then begin
      if i > 0 then add (ellipsis ^ ", ");
      go (List.nth xs i) rest;
      if i < n - 1 then add (", " ^ ellipsis)
    end else
      List.iteri (fun j x ->
        if j > 0 then add ", ";
        if j = i then go x rest else add (print x)) xs;
    add close
  and target v =
    match kind, v with
    | Chars i, Str s -> str_marked s i
    | Length (nl, nr), List xs ->
      let common = min nl nr in
      if not longer then begin
        add "[";
        if elide && xs <> [] then add ellipsis
        else List.iteri (fun j x -> if j > 0 then add ", "; add (print x)) xs;
        marked "]"
      end else begin
        add "[";
        if common > 0 then
          (if elide then add (ellipsis ^ ", ")
           else List.iteri (fun j x -> if j < common then (add (print x); add ", ")) xs);
        let extra = List.filteri (fun j _ -> j >= common) xs in
        let extra_text =
          if elide then
            (match extra with
             | [x] -> clip (print x) elide_over
             | x :: _ -> clip (print x) elide_over ^ ", " ^ ellipsis
             | [] -> "")
          else String.concat ", " (List.map print extra)
        in
        marked extra_text;
        add "]"
      end
    | _ -> marked (full v)
  and str_marked s i =
    (* [s] includes its quotes; [i] is the byte offset of the difference. *)
    let n = String.length s in
    if not elide || width s <= elide_over then begin
      add (String.sub s 0 i);
      let j = ref (i + 1) in
      while !j < n && Char.code s.[!j] land 0xc0 = 0x80 do incr j done;
      marked (String.sub s i (!j - i));
      add (String.sub s !j (n - !j))
    end else begin
      (* A window: up to 20 characters before the difference, up to 30 after. *)
      let back = ref i and cols = ref 0 in
      while !back > 1 && !cols < 20 do
        decr back;
        if Char.code s.[!back] land 0xc0 <> 0x80 then incr cols
      done;
      let fwd = ref i and fcols = ref 0 in
      while !fwd < n - 1 && !fcols < 30 do
        incr fwd;
        if !fwd < n && Char.code s.[!fwd] land 0xc0 <> 0x80 then incr fcols
      done;
      while !fwd < n && Char.code s.[!fwd] land 0xc0 = 0x80 do incr fwd done;
      (* Only the closing quote left: show it rather than an ellipsis. *)
      if !fwd >= n - 1 then fwd := n;
      add (if !back > 1 then "\"" ^ ellipsis else "\"");
      add (String.sub s !back (i - !back));
      let j = ref (i + 1) in
      while !j < n && Char.code s.[!j] land 0xc0 = 0x80 do incr j done;
      let j = min !j n in
      marked (String.sub s i (j - i));
      let stop = max j !fwd in
      add (String.sub s j (stop - j));
      if stop < n then add (ellipsis ^ "\"")
    end
  in
  go v path;
  let (c, w) = !mark in
  (Buffer.contents b, c, w)

(* ── The body under the header ──────────────────────────────────────── *)

(** The label of one side: `left` or `right`, and its source expression in
    backticks when that says something the printed value does not. *)
let label side (src : string) (printed : string) : string =
  let squash s = String.concat "" (String.split_on_char ' ' s) in
  if src = "" || squash src = squash printed then side
  else Printf.sprintf "%s `%s`" side src

let indent = "    "
let value_indent = "        "

(** The body of a failed comparison [op]: both sides by their source
    expressions [lsrc]/[rsrc], printed [l]/[r] (a String already quoted),
    and for `==` the first difference marked. *)
let compare_body ~(op : string) ~(lsrc : string) ~(rsrc : string)
    (l : string) (r : string) : string =
  let b = Buffer.create 256 in
  let line s = Buffer.add_string b s; Buffer.add_char b '\n' in
  let shown v = clip v 200 in
  if op = "!=" then begin
    line (indent ^ "Both sides are:");
    line (value_indent ^ shown l)
  end else if op = "==" && l <> r then begin
    let lt = parse l and rt = parse r in
    match first_diff lt rt [] with
    | None ->
      (* Different text, same tree (spacing): show both as they are. *)
      line (indent ^ label "left" lsrc l);
      line (value_indent ^ shown l);
      line (indent ^ label "right" rsrc r);
      line (value_indent ^ shown r)
    | Some (path, kind) ->
      let elide = width l > elide_over || width r > elide_over in
      let nl, nr = match kind with Length (a, c) -> a, c | _ -> 0, 0 in
      let side name src printed tree ~longer =
        let (text, c, w) = render ~elide tree path kind ~longer in
        line (indent ^ label name src printed);
        line (value_indent ^ text);
        line (value_indent ^ String.make c ' ' ^ String.make w '^')
      in
      side "left" lsrc l lt ~longer:(nl > nr);
      side "right" rsrc r rt ~longer:(nr > nl);
      let where = path_text path in
      (match kind with
       | Length (a, c) ->
         let what = if where = "" then "The left list" else Printf.sprintf "`%s` on the left" where in
         line "";
         line (Printf.sprintf "%s%s has %d element%s; on the right it has %d." indent what
                 a (if a = 1 then "" else "s") c)
       | _ ->
         if where <> "" then begin
           line "";
           line (Printf.sprintf "%sThey first differ at `%s`." indent where)
         end)
  end else begin
    line (indent ^ label "left" lsrc l);
    line (value_indent ^ shown l);
    line (indent ^ label "right" rsrc r);
    line (value_indent ^ shown r);
    if op = "==" then begin
      line "";
      line (indent ^ "They print the same, so they differ in something printing");
      line (indent ^ "does not show: a custom `Eq` impl, or a Float NaN.")
    end
  end;
  let s = Buffer.contents b in
  String.sub s 0 (max 0 (String.length s - 1))

(** A whole failed-comparison report: the header, a blank line, the body. *)
let compare_report ~header ~op ~lsrc ~rsrc l r : string =
  header ^ "\n\n" ^ compare_body ~op ~lsrc ~rsrc l r
