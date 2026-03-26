(** March LSP — Language Server Protocol server.

    Speaks JSON-RPC 2.0 over stdio.

    Implements:
      - textDocument/didOpen, didChange  (full document sync)
      - textDocument/publishDiagnostics  (parse + type errors → LSP diagnostics)
      - textDocument/hover               (type of expression at cursor)
      - textDocument/definition          (go-to-definition for local bindings)

    No external JSON library required — minimal encoder/decoder is inlined.
*)

module Ast    = March_ast.Ast
module Err    = March_errors.Errors
module TC     = March_typecheck.Typecheck

(* ================================================================== *)
(* §1  Minimal JSON value type + encoder                              *)
(* ================================================================== *)

type json =
  | Null
  | Bool   of bool
  | Int    of int
  | Float  of float
  | Str    of string
  | Arr    of json list
  | Obj    of (string * json) list

let rec encode = function
  | Null    -> "null"
  | Bool b  -> if b then "true" else "false"
  | Int n   -> string_of_int n
  | Float f -> Printf.sprintf "%.17g" f
  | Str s   ->
    let buf = Buffer.create (String.length s + 2) in
    Buffer.add_char buf '"';
    String.iter (fun c ->
      match c with
      | '"'  -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | '\t' -> Buffer.add_string buf "\\t"
      | c when Char.code c < 0x20 ->
        Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char buf c
    ) s;
    Buffer.add_char buf '"';
    Buffer.contents buf
  | Arr items ->
    "[" ^ String.concat "," (List.map encode items) ^ "]"
  | Obj pairs ->
    let pair (k, v) = encode (Str k) ^ ":" ^ encode v in
    "{" ^ String.concat "," (List.map pair pairs) ^ "}"

(* ================================================================== *)
(* §2  Minimal JSON parser                                            *)
(* ================================================================== *)

exception Json_error of string

type pstate = { src : string; mutable i : int }

let json_parse str =
  let p = { src = str; i = 0 } in
  let len = String.length str in
  let peek () = if p.i < len then Some str.[p.i] else None in
  let bump () = p.i <- p.i + 1 in
  let next () = let c = str.[p.i] in bump (); c in
  let skip_ws () =
    while p.i < len &&
          (str.[p.i] = ' ' || str.[p.i] = '\t' ||
           str.[p.i] = '\n' || str.[p.i] = '\r') do
      bump ()
    done
  in
  let expect c =
    skip_ws ();
    if p.i >= len || str.[p.i] <> c then
      raise (Json_error (Printf.sprintf "expected '%c' at pos %d" c p.i));
    bump ()
  in
  let parse_str () =
    expect '"';
    let buf = Buffer.create 16 in
    let rec loop () =
      if p.i >= len then raise (Json_error "unterminated string");
      let c = next () in
      (match c with
       | '"' -> ()
       | '\\' ->
         if p.i >= len then raise (Json_error "bad escape");
         (match next () with
          | '"'  -> Buffer.add_char buf '"'
          | '\\' -> Buffer.add_char buf '\\'
          | '/'  -> Buffer.add_char buf '/'
          | 'n'  -> Buffer.add_char buf '\n'
          | 'r'  -> Buffer.add_char buf '\r'
          | 't'  -> Buffer.add_char buf '\t'
          | 'b'  -> Buffer.add_char buf '\b'
          | 'f'  -> Buffer.add_char buf '\012'
          | 'u'  ->
            if p.i + 4 > len then raise (Json_error "bad \\u escape");
            let hex = String.sub str p.i 4 in
            p.i <- p.i + 4;
            let code = int_of_string ("0x" ^ hex) in
            (* encode as UTF-8 *)
            if code < 0x80 then
              Buffer.add_char buf (Char.chr code)
            else if code < 0x800 then begin
              Buffer.add_char buf (Char.chr (0xC0 lor (code lsr 6)));
              Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F)))
            end else begin
              Buffer.add_char buf (Char.chr (0xE0 lor (code lsr 12)));
              Buffer.add_char buf (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
              Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F)))
            end
          | c -> Buffer.add_char buf c);
         loop ()
       | c -> Buffer.add_char buf c; loop ())
    in
    loop ();
    Buffer.contents buf
  in
  let rec parse_val () =
    skip_ws ();
    match peek () with
    | None -> raise (Json_error "unexpected end of input")
    | Some '"' -> Str (parse_str ())
    | Some '{' -> parse_obj ()
    | Some '[' -> parse_arr ()
    | Some 't' ->
      if p.i + 4 > len || String.sub str p.i 4 <> "true" then
        raise (Json_error "bad value");
      p.i <- p.i + 4; Bool true
    | Some 'f' ->
      if p.i + 5 > len || String.sub str p.i 5 <> "false" then
        raise (Json_error "bad value");
      p.i <- p.i + 5; Bool false
    | Some 'n' ->
      if p.i + 4 > len || String.sub str p.i 4 <> "null" then
        raise (Json_error "bad value");
      p.i <- p.i + 4; Null
    | Some c when c = '-' || (c >= '0' && c <= '9') -> parse_num ()
    | Some c -> raise (Json_error (Printf.sprintf "unexpected '%c'" c))

  and parse_num () =
    let start = p.i in
    if p.i < len && str.[p.i] = '-' then bump ();
    while p.i < len && str.[p.i] >= '0' && str.[p.i] <= '9' do bump () done;
    let is_float = ref false in
    if p.i < len && str.[p.i] = '.' then begin
      is_float := true; bump ();
      while p.i < len && str.[p.i] >= '0' && str.[p.i] <= '9' do bump () done
    end;
    if p.i < len && (str.[p.i] = 'e' || str.[p.i] = 'E') then begin
      is_float := true; bump ();
      if p.i < len && (str.[p.i] = '+' || str.[p.i] = '-') then bump ();
      while p.i < len && str.[p.i] >= '0' && str.[p.i] <= '9' do bump () done
    end;
    let s = String.sub str start (p.i - start) in
    if !is_float then Float (float_of_string s) else Int (int_of_string s)

  and parse_obj () =
    expect '{';
    skip_ws ();
    if peek () = Some '}' then (bump (); Obj [])
    else begin
      let pairs = ref [] in
      let go = ref true in
      while !go do
        skip_ws ();
        let key = parse_str () in
        expect ':';
        let v = parse_val () in
        pairs := (key, v) :: !pairs;
        skip_ws ();
        match peek () with
        | Some ',' -> bump ()
        | _ -> go := false
      done;
      expect '}';
      Obj (List.rev !pairs)
    end

  and parse_arr () =
    expect '[';
    skip_ws ();
    if peek () = Some ']' then (bump (); Arr [])
    else begin
      let items = ref [] in
      let go = ref true in
      while !go do
        items := parse_val () :: !items;
        skip_ws ();
        match peek () with
        | Some ',' -> bump ()
        | _ -> go := false
      done;
      expect ']';
      Arr (List.rev !items)
    end
  in
  parse_val ()

(* ================================================================== *)
(* §3  JSON-RPC 2.0 framing over stdio                               *)
(* ================================================================== *)

(** Read one JSON-RPC message from stdin. Returns the raw JSON string. *)
let read_message () =
  let content_length = ref 0 in
  (* Read HTTP-style headers until blank line *)
  let rec read_headers () =
    let line = input_line stdin in
    let line =
      let n = String.length line in
      if n > 0 && line.[n-1] = '\r' then String.sub line 0 (n-1) else line
    in
    if line = "" then ()
    else begin
      let prefix = "Content-Length: " in
      let plen = String.length prefix in
      if String.length line > plen &&
         String.sub line 0 plen = prefix then
        content_length := int_of_string (String.sub line plen (String.length line - plen));
      read_headers ()
    end
  in
  read_headers ();
  let n = !content_length in
  let buf = Bytes.create n in
  really_input stdin buf 0 n;
  Bytes.to_string buf

(** Write one JSON-RPC message to stdout. *)
let send_message body =
  let n = String.length body in
  Printf.printf "Content-Length: %d\r\n\r\n%s%!" n body

(* ================================================================== *)
(* §4  JSON access helpers                                            *)
(* ================================================================== *)

let get_field key = function
  | Obj pairs -> List.assoc_opt key pairs
  | _ -> None

let get_str key j =
  match get_field key j with Some (Str s) -> Some s | _ -> None

let get_int key j =
  match get_field key j with Some (Int n) -> Some n | _ -> None

let get_obj key j =
  match get_field key j with Some (Obj _ as o) -> Some o | _ -> None

let get_arr key j =
  match get_field key j with Some (Arr a) -> Some a | _ -> None

(* ================================================================== *)
(* §5  LSP message builders                                           *)
(* ================================================================== *)

let lsp_range sl sc el ec =
  Obj [
    "start", Obj ["line", Int sl; "character", Int sc];
    "end",   Obj ["line", Int el; "character", Int ec];
  ]

let respond id result =
  send_message @@ encode @@ Obj [
    "jsonrpc", Str "2.0";
    "id",      id;
    "result",  result;
  ]

let respond_null id = respond id Null

let notify method_ params =
  send_message @@ encode @@ Obj [
    "jsonrpc", Str "2.0";
    "method",  Str method_;
    "params",  params;
  ]

(* ================================================================== *)
(* §6  Position utilities                                             *)
(* ================================================================== *)

(** LSP uses 0-based line + 0-based character.
    March AST spans use 1-based line + 0-based column. *)

let span_contains (sp : Ast.span) lsp_line lsp_char =
  (* Convert LSP 0-based line to March 1-based *)
  if sp.start_line <= 0 then false        (* dummy / invalid span *)
  else
    let sl = sp.start_line - 1 in   (* inclusive, 0-based *)
    let el = sp.end_line   - 1 in   (* inclusive, 0-based *)
    let sc = sp.start_col in
    let ec = sp.end_col in
    if lsp_line < sl || lsp_line > el then false
    else if sl = el then
      (* single-line span *)
      lsp_char >= sc && lsp_char < ec
    else if lsp_line = sl then lsp_char >= sc
    else if lsp_line = el then lsp_char < ec
    else true

(** Span "size" in characters — used to prefer narrower spans. *)
let span_size (sp : Ast.span) =
  let lines = sp.end_line - sp.start_line in
  lines * 100_000 + sp.end_col - sp.start_col

(* ================================================================== *)
(* §7  Stdlib loading (mirrors bin/main.ml)                          *)
(* ================================================================== *)

let find_stdlib_dir () =
  let candidates = [
    "stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../../stdlib";
  ] in
  List.find_opt Sys.file_exists candidates

let load_stdlib_file path =
  let src =
    try
      let ic = open_in path in
      let n  = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    with Sys_error _ -> ""
  in
  if src = "" then []
  else
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    (try
       let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
       let m = March_desugar.Desugar.desugar_module m in
       let basename = Filename.basename path in
       if basename = "prelude.march" then
         (match m.Ast.mod_decls with
          | [Ast.DMod (_, _, inner, _)] -> inner
          | decls -> decls)
       else
         [Ast.DMod (m.Ast.mod_name, Ast.Public, m.Ast.mod_decls, Ast.dummy_span)]
     with _ -> [])

let stdlib_cache : Ast.decl list option ref = ref None

let load_stdlib () =
  match !stdlib_cache with
  | Some d -> d
  | None ->
    let d =
      match find_stdlib_dir () with
      | None -> []
      | Some dir ->
        (* Load only the stable core stdlib; skip WIP modules *)
        let files = [
          "prelude.march"; "option.march"; "result.march"; "list.march";
          "math.march"; "string.march"; "iolist.march"; "sigil.march"; "sort.march";
        ] in
        List.concat_map
          (fun name -> load_stdlib_file (Filename.concat dir name))
          files
    in
    stdlib_cache := Some d;
    d

(* ================================================================== *)
(* §8  Document store + compile pipeline                             *)
(* ================================================================== *)

(** Per-document state: source text, type map, and parsed AST. *)
type doc = {
  uri      : string;
  source   : string;
  path        : string;   (** filesystem path decoded from URI *)
  type_map    : (Ast.span, TC.ty) Hashtbl.t;
  ast         : Ast.module_ option;
  line_offset : int;
  (** 0 for normal [mod Name do ... end] files.
      1 for bare scripts wrapped in a synthetic [mod Script do\n...\nend].
      All span line numbers from the typechecker are shifted by this amount
      relative to what the editor sees, so position lookups must add it. *)
}

let docs : (string, doc) Hashtbl.t = Hashtbl.create 16

(** Decode a file:// URI to a filesystem path. *)
let uri_to_path uri =
  (* Percent-decode: replace %XX with the corresponding byte *)
  let decode s =
    let n = String.length s in
    let buf = Buffer.create n in
    let i = ref 0 in
    while !i < n do
      if s.[!i] = '%' && !i + 2 < n then begin
        let hex = String.sub s (!i + 1) 2 in
        (try Buffer.add_char buf (Char.chr (int_of_string ("0x" ^ hex)))
         with _ -> Buffer.add_char buf s.[!i]);
        i := !i + 3
      end else begin
        Buffer.add_char buf s.[!i];
        i := !i + 1
      end
    done;
    Buffer.contents buf
  in
  (* Strip file:// prefix; on Unix, file:///path → /path *)
  if String.length uri >= 7 && String.sub uri 0 7 = "file://" then
    decode (String.sub uri 7 (String.length uri - 7))
  else uri

(** Publish LSP diagnostics for [uri]. *)
let publish_diagnostics uri (diags : Err.diagnostic list) path =
  let lsp_diags = List.filter_map (fun (d : Err.diagnostic) ->
      (* Only show diagnostics from the user's file *)
      if d.span.Ast.file <> path &&
         d.span.Ast.file <> "" &&
         d.span.Ast.file <> "<unknown>" &&
         d.span.Ast.file <> "<none>" then
        None
      else begin
        let sl = max 0 (d.span.start_line - 1) in
        let sc = d.span.start_col in
        let el = max sl (d.span.end_line - 1) in
        let ec = if d.span.end_col > 0 then d.span.end_col else sc + 1 in
        let severity = match d.severity with
          | Err.Error   -> Int 1
          | Err.Warning -> Int 2
          | Err.Hint    -> Int 3
        in
        let extra = if d.notes = [] then []
          else ["relatedInformation",
                Arr (List.map (fun n ->
                    Obj ["message", Str n;
                         "location", Obj [
                           "uri", Str uri;
                           "range", lsp_range sl sc el ec]]) d.notes)] in
        Some (Obj ([
          "range",    lsp_range sl sc el ec;
          "severity", severity;
          "source",   Str "march";
          "message",  Str d.message;
        ] @ extra))
      end
  ) diags in
  notify "textDocument/publishDiagnostics" (Obj [
    "uri",         Str uri;
    "diagnostics", Arr lsp_diags;
  ])

(** Try to parse [src] as a March module.  Returns [Some m] on success.
    On failure, records the error into [errors] and returns [None].

    If the file does not start with [mod], it is wrapped in a synthetic
    [mod Script do ... end] so bare-declaration files (e.g. REPL-style
    scripts) also get diagnostics and hover.  The wrapping adds 1 line,
    so spans reported by the typechecker are adjusted before storage. *)
let try_parse_module path src errors =
  let make_lexbuf text =
    let lb = Lexing.from_string text in
    lb.Lexing.lex_curr_p <-
      { lb.Lexing.lex_curr_p with Lexing.pos_fname = path };
    lb
  in
  let do_parse lexbuf text =
    try
      let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
      Some (m, text, false (* not wrapped *))
    with
    | Err.ParseError _ | March_parser.Parser.Error ->
      None
  in
  (* First attempt: parse as-is *)
  let direct = do_parse (make_lexbuf src) src in
  match direct with
  | Some (m, _, _) -> Some (m, false)
  | None ->
    (* Second attempt: wrap in synthetic module so bare files work.
       If the file starts with 'mod', the first parse already failed for
       a real syntax error — don't mask it with a wrapper. *)
    let trimmed = String.trim src in
    let starts_with_mod =
      String.length trimmed >= 3 &&
      String.sub trimmed 0 3 = "mod"
    in
    if starts_with_mod then begin
      (* Real parse error in a proper module file — report it *)
      let lexbuf = make_lexbuf src in
      (try ignore (March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
       with
       | Err.ParseError (msg, _hint, pos) ->
         let line = pos.Lexing.pos_lnum in
         let col  = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
         Err.report errors {
           Err.severity = Err.Error;
           span = { Ast.file = path;
                    start_line = line; start_col = col;
                    end_line   = line; end_col   = col + 1 };
           message = msg; labels = []; notes = [];
         }
       | March_parser.Parser.Error ->
         let pos  = Lexing.lexeme_start_p lexbuf in
         let line = pos.Lexing.pos_lnum in
         let col  = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in
         Err.report errors {
           Err.severity = Err.Error;
           span = { Ast.file = path;
                    start_line = line; start_col = col;
                    end_line   = line; end_col   = col + 1 };
           message = "parse error"; labels = []; notes = [];
         }
       | _ -> ());
      None
    end else begin
      (* Bare file (e.g. a script or REPL-style buffer without `mod`).
         Wrap it so the parser sees a valid module. *)
      let wrapped = "mod Script do\n" ^ src ^ "\nend\n" in
      match do_parse (make_lexbuf wrapped) wrapped with
      | None ->
        (* Still fails — report error relative to original src *)
        let lexbuf = make_lexbuf src in
        (try ignore (March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
         with
         | March_parser.Parser.Error ->
           let pos  = Lexing.lexeme_start_p lexbuf in
           Err.report errors {
             Err.severity = Err.Error;
             span = { Ast.file = path;
                      start_line = pos.Lexing.pos_lnum;
                      start_col  = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
                      end_line   = pos.Lexing.pos_lnum;
                      end_col    = pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1 };
             message = "parse error"; labels = []; notes = [];
           }
         | _ -> ());
        None
      | Some (m, _, _) -> Some (m, true (* wrapped — spans are offset by 1 line *))
    end

(** Run parse → desugar → typecheck on [src] and store the result.

    Works for both proper [mod Name do ... end] files and bare scripts
    (which are wrapped in a synthetic module for analysis). *)
let compile_doc uri src =
  let path = uri_to_path uri in
  let errors      = Err.create () in
  let type_map    = Hashtbl.create 128 in
  let ast_ref     = ref None in
  let line_offset = ref 0 in

  (match try_parse_module path src errors with
   | None -> ()
   | Some (m, wrapped) ->
     if wrapped then line_offset := 1;
     (try
        let m = March_desugar.Desugar.desugar_module m in
        ast_ref := Some m;
        let stdlib_decls = load_stdlib () in
        let m_full =
          { m with Ast.mod_decls = stdlib_decls @ m.Ast.mod_decls }
        in
        let (_, tm) = TC.check_module ~errors m_full in
        Hashtbl.iter (Hashtbl.replace type_map) tm
      with exn ->
        Err.report errors {
          Err.severity = Err.Error;
          span = { Ast.file = path;
                   start_line = 1; start_col = 0;
                   end_line   = 1; end_col   = 1 };
          message = Printf.sprintf "internal error: %s" (Printexc.to_string exn);
          labels = []; notes = [];
        }));

  let doc = { uri; source = src; path; type_map; ast = !ast_ref;
              line_offset = !line_offset } in
  Hashtbl.replace docs uri doc;
  publish_diagnostics uri (Err.sorted errors) path;
  doc

(* ================================================================== *)
(* §9  Hover — type at cursor position                               *)
(* ================================================================== *)

let handle_hover id params =
  let td_uri =
    match get_obj "textDocument" params with
    | None -> None
    | Some td -> get_str "uri" td
  in
  let pos_args =
    match get_obj "position" params with
    | None -> None
    | Some pos ->
      match get_int "line" pos, get_int "character" pos with
      | Some l, Some c -> Some (l, c)
      | _ -> None
  in
  match td_uri, pos_args with
  | None, _ | _, None -> respond_null id
  | Some uri, Some (line, ch) ->
    match Hashtbl.find_opt docs uri with
    | None -> respond_null id
    | Some doc ->
      (* Find the narrowest span in type_map containing (line, ch)
         that belongs to the user's file.
         [doc.line_offset] corrects for the synthetic module wrapper added
         to bare (non-mod) files: spans are 1 line ahead in the type_map. *)
      let span_line = line + doc.line_offset in
      let best : (int * TC.ty) option ref = ref None in
      Hashtbl.iter (fun (sp : Ast.span) ty ->
        if (sp.Ast.file = doc.path || sp.Ast.file = "") &&
           span_contains sp span_line ch then begin
          let sz = span_size sp in
          match !best with
          | None -> best := Some (sz, ty)
          | Some (bsz, _) when sz < bsz -> best := Some (sz, ty)
          | _ -> ()
        end
      ) doc.type_map;
      match !best with
      | None -> respond_null id
      | Some (_, ty) ->
        let type_str = TC.pp_ty ty in
        respond id @@ Obj [
          "contents", Obj [
            "kind",  Str "markdown";
            "value", Str (Printf.sprintf "```\n%s\n```" type_str);
          ]
        ]

(* ================================================================== *)
(* §10  Definition — go-to-definition for local bindings             *)
(* ================================================================== *)

(** Walk the AST and collect:
    - [defs]: name → definition span
    - [uses]: (use_span, name) pairs

    Uses a simple first-occurrence approach (last-write wins on collisions,
    giving the innermost/last definition, which is usually correct). *)
let collect_names (m : Ast.module_) =
  let defs : (string, Ast.span) Hashtbl.t = Hashtbl.create 64 in
  let uses : (Ast.span * string) list ref  = ref [] in

  let def (name : Ast.name) =
    if name.span.Ast.start_line > 0 then
      Hashtbl.replace defs name.txt name.span
  in
  let use (name : Ast.name) =
    if name.span.Ast.start_line > 0 then
      uses := (name.span, name.txt) :: !uses
  in

  let rec visit_expr e =
    match e with
    | Ast.EVar n                       -> use n
    | Ast.EApp  (f, args, _)           -> visit_expr f; List.iter visit_expr args
    | Ast.ECon  (_, args, _)           -> List.iter visit_expr args
    | Ast.ELam  (params, body, _)      ->
      List.iter (fun p -> def p.Ast.param_name) params;
      visit_expr body
    | Ast.EBlock (es, _)               -> List.iter visit_expr es
    | Ast.ELet   (b, _)               -> visit_pat b.Ast.bind_pat; visit_expr b.Ast.bind_expr
    | Ast.EMatch (e, arms, _)          ->
      visit_expr e;
      List.iter (fun (arm : Ast.branch) ->
        visit_pat arm.branch_pat;
        Option.iter visit_expr arm.branch_guard;
        visit_expr arm.branch_body
      ) arms
    | Ast.ETuple         (es,  _)      -> List.iter visit_expr es
    | Ast.ERecord        (flds, _)     -> List.iter (fun (_, e) -> visit_expr e) flds
    | Ast.ERecordUpdate  (e, flds, _)  ->
      visit_expr e; List.iter (fun (_, e) -> visit_expr e) flds
    | Ast.EField         (e, _, _)     -> visit_expr e
    | Ast.EIf            (c, t, f, _)  -> visit_expr c; visit_expr t; visit_expr f
    | Ast.EPipe          (a, b, _)     -> visit_expr a; visit_expr b
    | Ast.EAnnot         (e, _, _)     -> visit_expr e
    | Ast.ESend          (a, b, _)     -> visit_expr a; visit_expr b
    | Ast.ESpawn         (e, _)        -> visit_expr e
    | Ast.EDbg           (oe, _)       -> Option.iter visit_expr oe
    | Ast.ELetFn         (n, ps, _, body, _) ->
      def n;
      List.iter (fun p -> def p.Ast.param_name) ps;
      visit_expr body
    | Ast.EAtom          (_, es, _)    -> List.iter visit_expr es
    | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ -> ()

  and visit_pat p =
    match p with
    | Ast.PatVar  n               -> def n
    | Ast.PatCon  (_, pats)       -> List.iter visit_pat pats
    | Ast.PatAtom (_, pats, _)    -> List.iter visit_pat pats
    | Ast.PatTuple (pats, _)      -> List.iter visit_pat pats
    | Ast.PatAs   (pat, n, _)     -> visit_pat pat; def n
    | Ast.PatRecord (flds, _)     ->
      List.iter (fun (n, pat) -> def n; visit_pat pat) flds
    | Ast.PatWild _ | Ast.PatLit _ -> ()

  and visit_decl d =
    match d with
    | Ast.DFn (fd, _) ->
      def fd.fn_name;
      List.iter (fun (cl : Ast.fn_clause) ->
        List.iter (fun fp ->
          match fp with
          | Ast.FPPat pat   -> visit_pat pat
          | Ast.FPNamed p   -> def p.Ast.param_name
        ) cl.fc_params;
        Option.iter visit_expr cl.fc_guard;
        visit_expr cl.fc_body
      ) fd.fn_clauses
    | Ast.DLet (_, b, _)         -> visit_pat b.Ast.bind_pat; visit_expr b.Ast.bind_expr
    | Ast.DMod (_, _, decls, _)  -> List.iter visit_decl decls
    | _ -> ()
  in

  List.iter visit_decl m.mod_decls;
  (defs, List.rev !uses)

let handle_definition id params =
  let td_uri =
    match get_obj "textDocument" params with
    | None -> None
    | Some td -> get_str "uri" td
  in
  let pos_args =
    match get_obj "position" params with
    | None -> None
    | Some pos ->
      match get_int "line" pos, get_int "character" pos with
      | Some l, Some c -> Some (l, c)
      | _ -> None
  in
  match td_uri, pos_args with
  | None, _ | _, None -> respond_null id
  | Some uri, Some (line, ch) ->
    match Hashtbl.find_opt docs uri with
    | None -> respond_null id
    | Some doc ->
      match doc.ast with
      | None -> respond_null id
      | Some ast ->
        let (defs, uses) = collect_names ast in
        (* Adjust for the synthetic module wrapper used with bare files.
           Spans in the AST are line_offset lines ahead of what the editor sees. *)
        let span_line = line + doc.line_offset in
        (* Find the narrowest use-span containing (span_line, ch).
           We cannot just take the first match because infix operators like `+`
           get the span of the whole expression in the parser's $loc. *)
        let found =
          List.fold_left (fun best (sp, name) ->
            if span_contains sp span_line ch then
              let sz = span_size sp in
              match best with
              | None -> Some (sz, sp, name)
              | Some (bsz, _, _) when sz < bsz -> Some (sz, sp, name)
              | b -> b
            else best
          ) None uses
          |> Option.map (fun (_, _, name) -> name)
        in
        (match found with
         | None -> respond_null id
         | Some name ->
           match Hashtbl.find_opt defs name with
           | None -> respond_null id
           | Some def_sp ->
             (* Adjust def span back to editor coordinates *)
             let sl = def_sp.start_line - 1 - doc.line_offset in
             let el = def_sp.end_line   - 1 - doc.line_offset in
             let loc = Obj [
               "uri",   Str ("file://" ^ doc.path);
               "range", lsp_range sl def_sp.start_col el def_sp.end_col;
             ] in
             respond id (Arr [loc]))

(* ================================================================== *)
(* §11  Request dispatcher                                            *)
(* ================================================================== *)

let handle_initialize id _params =
  respond id @@ Obj [
    "capabilities", Obj [
      (* Full document sync: client sends the entire file on each change *)
      "textDocumentSync", Obj [
        "openClose", Bool true;
        "change",    Int 1;   (* TextDocumentSyncKind.Full *)
      ];
      "hoverProvider",      Bool true;
      "definitionProvider", Bool true;
    ];
    "serverInfo", Obj [
      "name",    Str "march-lsp";
      "version", Str "0.1.0";
    ];
  ]

let handle_did_open params =
  match get_obj "textDocument" params with
  | None -> ()
  | Some td ->
    let uri  = match get_str "uri"  td with Some s -> s | None -> "" in
    let text = match get_str "text" td with Some s -> s | None -> "" in
    if uri <> "" then ignore (compile_doc uri text)

let handle_did_change params =
  match get_obj "textDocument" params with
  | None -> ()
  | Some td ->
    let uri = match get_str "uri" td with Some s -> s | None -> "" in
    if uri = "" then ()
    else
      let text =
        match get_arr "contentChanges" params with
        | Some (first :: _) ->
          (match get_str "text" first with Some s -> s | None -> "")
        | _ -> ""
      in
      ignore (compile_doc uri text)

let handle_did_close params =
  match get_obj "textDocument" params with
  | None -> ()
  | Some td ->
    match get_str "uri" td with
    | None -> ()
    | Some uri ->
      Hashtbl.remove docs uri;
      (* Clear diagnostics for the closed file *)
      notify "textDocument/publishDiagnostics" @@ Obj [
        "uri",         Str uri;
        "diagnostics", Arr [];
      ]

let dispatch (msg : json) =
  let method_ = match get_str "method" msg with Some s -> s | None -> "" in
  let id      = match get_field "id" msg with Some v -> v | None -> Null in
  let params  = match get_field "params" msg with Some v -> v | None -> Obj [] in
  (match method_ with
   | "initialize"             -> handle_initialize id params
   | "initialized"            -> ()   (* notification, no reply needed *)
   | "shutdown"               -> respond_null id
   | "exit"                   -> exit 0
   | "textDocument/didOpen"   -> handle_did_open params
   | "textDocument/didChange" -> handle_did_change params
   | "textDocument/didClose"  -> handle_did_close params
   | "textDocument/hover"     -> handle_hover id params
   | "textDocument/definition"-> handle_definition id params
   | _ -> ())   (* unknown method: ignore silently *)

(* ================================================================== *)
(* §12  Main loop                                                     *)
(* ================================================================== *)

let () =
  (* Binary mode: stdin/stdout must not translate \r\n *)
  set_binary_mode_in  stdin  true;
  set_binary_mode_out stdout true;
  let alive = ref true in
  while !alive do
    (try
       let raw = read_message () in
       (try
          let msg = json_parse raw in
          dispatch msg
        with
        | Json_error e ->
          Printf.eprintf "[march-lsp] JSON parse error: %s\n%!" e
        | exn ->
          Printf.eprintf "[march-lsp] dispatch error: %s\n%!" (Printexc.to_string exn))
     with
     | End_of_file -> alive := false
     | Sys_error _ -> alive := false
     | exn ->
       Printf.eprintf "[march-lsp] read error: %s\n%!" (Printexc.to_string exn);
       alive := false)
  done
