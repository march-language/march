(** Document analysis pipeline for march-lsp.

    Runs parse → desugar → typecheck on a buffer, then builds lookup
    tables that the hover / definition / completion / inlay-hint handlers
    can query. *)

module Lsp  = Linol_lsp.Lsp
module Ast  = March_ast.Ast
module Tc   = March_typecheck.Typecheck
module Err  = March_errors.Errors
module Pos  = Position   (* our position utilities *)

(* ------------------------------------------------------------------ *)
(* Types                                                               *)
(* ------------------------------------------------------------------ *)

(** A call-site collected from the AST for signature-help queries. *)
type call_site = {
  cs_fn_name  : string option;  (** Name of the callee if it's a plain identifier *)
  cs_span     : Ast.span;       (** Span of the full EApp expression *)
  cs_args     : Ast.expr list;  (** Argument expressions *)
}

(** A non-exhaustive match site extracted from diagnostics. *)
type match_site = {
  ms_span         : Ast.span;  (** Span of the whole match expression *)
  ms_missing_case : string;    (** Pattern example from the warning message *)
}

(** Where a linear/affine value is consumed. *)
type consumption = {
  con_name : string;
  con_def  : Ast.span;
  con_uses : Ast.span list;
}

(** Full analysis result for one document. *)
type t = {
  src         : string;
  filename    : string;
  type_map    : (Ast.span, Tc.ty) Hashtbl.t;
  (** Span → inferred type. *)
  def_map     : (string, Ast.span) Hashtbl.t;
  (** Name → definition span (go-to-definition). *)
  use_map     : (Ast.span, string) Hashtbl.t;
  (** Variable-use span → variable name (go-to-definition from cursor). *)
  vars        : (string * Tc.scheme) list;
  (** In-scope term variables → type scheme (completion). *)
  types       : (string * int) list;
  (** Type constructors → arity (completion). *)
  ctors       : (string * string) list;
  (** Data constructors → parent type name (completion). *)
  interfaces  : (string * Ast.interface_def) list;
  (** Registered interfaces. *)
  impls       : (string * Tc.ty) list;
  (** Interface implementations: iface name → impl type. *)
  actors      : (string * Ast.actor_def) list;
  (** Actor definitions: name → def. *)
  doc_map     : (string, string) Hashtbl.t;
  (** Function name → doc string (from [fn_doc] field). *)
  refs_map    : (string, Ast.span list) Hashtbl.t;
  (** Inverted index: variable name → all use-site spans. *)
  call_sites  : call_site list;
  (** All call sites collected for signature-help queries. *)
  consumption : consumption list;
  (** Linear/affine binding consumption records — used for make-linear actions. *)
  match_sites : match_site list;
  (** Non-exhaustive match warnings, structured for quickfix consumption. *)
  diagnostics : Lsp.Types.Diagnostic.t list;
}

(* ------------------------------------------------------------------ *)
(* Stdlib loading                                                      *)
(* ------------------------------------------------------------------ *)

let find_stdlib_dir () =
  let candidates = [
    "stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../../stdlib";
    Filename.concat (Filename.dirname Sys.executable_name) "../../../stdlib";
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
       let m =
         March_parser.Parser.module_
           March_lexer.Lexer.token lexbuf
       in
       let m = March_desugar.Desugar.desugar_module m in
       let basename = Filename.basename path in
       if basename = "prelude.march" then
         (match m.Ast.mod_decls with
          | [Ast.DMod (_, _, inner, _)] -> inner
          | decls -> decls)
       else
         [Ast.DMod (m.Ast.mod_name, Ast.Public,
                    m.Ast.mod_decls, Ast.dummy_span)]
     with _ -> [])

let load_stdlib () =
  match find_stdlib_dir () with
  | None -> []
  | Some stdlib_dir ->
    let files = [
      "prelude.march"; "option.march"; "result.march"; "list.march";
      "map.march"; "math.march"; "string.march"; "iolist.march";
      "http.march"; "http_transport.march"; "http_client.march";
      "seq.march"; "path.march"; "file.march"; "dir.march";
      "sort.march"; "csv.march"; "websocket.march"; "http_server.march";
    ] in
    List.concat_map
      (fun name -> load_stdlib_file (Filename.concat stdlib_dir name))
      files

(* ------------------------------------------------------------------ *)
(* Diagnostic conversion                                               *)
(* ------------------------------------------------------------------ *)

let severity_to_lsp (sev : Err.severity) =
  match sev with
  | Err.Error   -> Lsp.Types.DiagnosticSeverity.Error
  | Err.Warning -> Lsp.Types.DiagnosticSeverity.Warning
  | Err.Hint    -> Lsp.Types.DiagnosticSeverity.Hint

let diag_to_lsp ~filename (d : Err.diagnostic) =
  let is_user =
    d.span.Ast.file = filename ||
    d.span.Ast.file = "" ||
    d.span.Ast.file = "<unknown>"
  in
  if not is_user then None
  else
    let range = Pos.span_to_lsp_range d.span in
    let message =
      if d.notes = [] then d.message
      else
        d.message ^ "\n" ^
        String.concat "\n" (List.map (fun n -> "note: " ^ n) d.notes)
    in
    Some (Lsp.Types.Diagnostic.create
      ~range
      ~severity:(severity_to_lsp d.severity)
      ~message:(`String message)
      ~source:"march"
      ())

(* ------------------------------------------------------------------ *)
(* AST traversal: build def_map + use_map                             *)
(* ------------------------------------------------------------------ *)

let rec collect_decl ~def_map ~use_map ~doc_map ~calls ~actors_tbl ?(prefix = "") (decl : Ast.decl) =
  let add_def name span =
    Hashtbl.replace def_map name span;
    if prefix <> "" then
      Hashtbl.replace def_map (prefix ^ "." ^ name) span
  in
  match decl with
  | Ast.DFn (fn, _) ->
    add_def fn.fn_name.txt fn.fn_name.span;
    (match fn.fn_doc with
     | Some doc -> Hashtbl.replace doc_map fn.fn_name.txt doc
     | None -> ());
    List.iter (fun (cl : Ast.fn_clause) ->
        collect_expr ~def_map ~use_map ~calls cl.fc_body
      ) fn.fn_clauses

  | Ast.DLet (_, b, _) ->
    collect_pat_defs ~def_map b.bind_pat;
    collect_expr ~def_map ~use_map ~calls b.bind_expr

  | Ast.DType (_, name, _, typedef, _) ->
    add_def name.txt name.span;
    (match typedef with
     | Ast.TDVariant vs ->
       List.iter (fun (v : Ast.variant) ->
           add_def v.var_name.txt v.var_name.span) vs
     | Ast.TDRecord fields ->
       List.iter (fun (f : Ast.field) ->
           add_def f.fld_name.txt f.fld_name.span) fields
     | Ast.TDAlias _ -> ())

  | Ast.DActor (_, name, adef, _) ->
    add_def name.txt name.span;
    Hashtbl.replace actors_tbl name.txt adef;
    collect_expr ~def_map ~use_map ~calls adef.actor_init;
    List.iter (fun (h : Ast.actor_handler) ->
        collect_expr ~def_map ~use_map ~calls h.ah_body
      ) adef.actor_handlers

  | Ast.DMod (name, _, decls, _) ->
    Hashtbl.replace def_map name.txt name.span;
    let mod_prefix =
      if prefix = "" then name.txt else prefix ^ "." ^ name.txt
    in
    List.iter (collect_decl ~def_map ~use_map ~doc_map ~calls ~actors_tbl ~prefix:mod_prefix) decls

  | Ast.DInterface (idef, _) ->
    add_def idef.iface_name.txt idef.iface_name.span;
    List.iter (fun (m : Ast.method_decl) ->
        add_def m.md_name.txt m.md_name.span
      ) idef.iface_methods

  | Ast.DImpl (impl, _) ->
    List.iter (fun ((mname : Ast.name), (fn : Ast.fn_def)) ->
        add_def mname.txt mname.span;
        List.iter (fun (cl : Ast.fn_clause) ->
            collect_expr ~def_map ~use_map ~calls cl.fc_body
          ) fn.fn_clauses
      ) impl.impl_methods

  | Ast.DApp (app, _) ->
    collect_expr ~def_map ~use_map ~calls app.app_body;
    Option.iter (collect_expr ~def_map ~use_map ~calls) app.app_on_start;
    Option.iter (collect_expr ~def_map ~use_map ~calls) app.app_on_stop

  | Ast.DUse _ | Ast.DAlias _ | Ast.DNeeds _
  | Ast.DProtocol _ | Ast.DExtern _ | Ast.DSig _
  | Ast.DDeriving _ -> ()

and collect_expr ~def_map ~use_map ~calls (e : Ast.expr) =
  match e with
  | Ast.EVar name ->
    Hashtbl.replace use_map name.span name.txt

  | Ast.ELet (b, _) ->
    collect_pat_defs ~def_map b.bind_pat;
    collect_expr ~def_map ~use_map ~calls b.bind_expr

  | Ast.ELetFn (name, params, _, body, _) ->
    Hashtbl.replace def_map name.txt name.span;
    List.iter (fun (p : Ast.param) ->
        Hashtbl.replace def_map p.param_name.txt p.param_name.span
      ) params;
    collect_expr ~def_map ~use_map ~calls body

  | Ast.ELam (params, body, _) ->
    List.iter (fun (p : Ast.param) ->
        Hashtbl.replace def_map p.param_name.txt p.param_name.span
      ) params;
    collect_expr ~def_map ~use_map ~calls body

  | Ast.EMatch (subj, branches, _) ->
    collect_expr ~def_map ~use_map ~calls subj;
    List.iter (fun (br : Ast.branch) ->
        collect_pat_defs ~def_map br.branch_pat;
        Option.iter (collect_expr ~def_map ~use_map ~calls) br.branch_guard;
        collect_expr ~def_map ~use_map ~calls br.branch_body
      ) branches

  | Ast.EBlock (exprs, _) ->
    List.iter (collect_expr ~def_map ~use_map ~calls) exprs

  | Ast.EApp (f, args, sp) ->
    let fn_name = match f with
      | Ast.EVar n -> Some n.txt
      | _          -> None
    in
    calls := { cs_fn_name = fn_name; cs_span = sp; cs_args = args } :: !calls;
    collect_expr ~def_map ~use_map ~calls f;
    List.iter (collect_expr ~def_map ~use_map ~calls) args

  | Ast.ECon (_, args, _) ->
    List.iter (collect_expr ~def_map ~use_map ~calls) args

  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) ->
    List.iter (collect_expr ~def_map ~use_map ~calls) es

  | Ast.ERecord (fields, _) ->
    List.iter (fun (_, e) -> collect_expr ~def_map ~use_map ~calls e) fields

  | Ast.ERecordUpdate (e, fields, _) ->
    collect_expr ~def_map ~use_map ~calls e;
    List.iter (fun (_, e2) -> collect_expr ~def_map ~use_map ~calls e2) fields

  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.EDbg (Some e, _)
  | Ast.ESpawn (e, _) ->
    collect_expr ~def_map ~use_map ~calls e

  | Ast.EIf (cond, e1, e2, _) ->
    collect_expr ~def_map ~use_map ~calls cond;
    collect_expr ~def_map ~use_map ~calls e1;
    collect_expr ~def_map ~use_map ~calls e2

  | Ast.EPipe (e1, e2, _) | Ast.ESend (e1, e2, _) ->
    collect_expr ~def_map ~use_map ~calls e1;
    collect_expr ~def_map ~use_map ~calls e2

  | Ast.ELit _ | Ast.EHole _ | Ast.EDbg (None, _)
  | Ast.EResultRef _ -> ()

and collect_pat_defs ~def_map (pat : Ast.pattern) =
  match pat with
  | Ast.PatVar name ->
    Hashtbl.replace def_map name.txt name.span
  | Ast.PatAs (p, name, _) ->
    collect_pat_defs ~def_map p;
    Hashtbl.replace def_map name.txt name.span
  | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) ->
    List.iter (collect_pat_defs ~def_map) ps
  | Ast.PatTuple (ps, _) ->
    List.iter (collect_pat_defs ~def_map) ps
  | Ast.PatRecord (fields, _) ->
    List.iter (fun (_, p) -> collect_pat_defs ~def_map p) fields
  | Ast.PatWild _ | Ast.PatLit _ -> ()

(* ------------------------------------------------------------------ *)
(* Stdlib doc-string collection                                        *)
(* ------------------------------------------------------------------ *)

(** Recursively collect [fn_doc] entries from a list of (possibly desugared)
    declarations into [doc_map].  Used to populate hover docs for stdlib
    functions, which are not part of [user_decls] and therefore not visited
    by [collect_decl]. *)
let rec collect_docs ~doc_map ?(prefix = "") (decls : Ast.decl list) =
  List.iter (fun decl ->
      match decl with
      | Ast.DFn (fn, _) ->
        (match fn.fn_doc with
         | None -> ()
         | Some doc ->
           Hashtbl.replace doc_map fn.fn_name.txt doc;
           if prefix <> "" then
             Hashtbl.replace doc_map (prefix ^ "." ^ fn.fn_name.txt) doc)
      | Ast.DMod (name, _, inner, _) ->
        let sub =
          if prefix = "" then name.txt else prefix ^ "." ^ name.txt
        in
        collect_docs ~doc_map ~prefix:sub inner
      | _ -> ()
    ) decls

(* ------------------------------------------------------------------ *)
(* Linear consumption analysis                                         *)
(* ------------------------------------------------------------------ *)

let rec find_uses name (e : Ast.expr) acc =
  match e with
  | Ast.EVar n when n.txt = name -> n.span :: acc
  | Ast.EApp (f, args, _) ->
    find_uses name f
      (List.fold_left (fun a e -> find_uses name e a) acc args)
  | Ast.ELam (_, body, _) -> find_uses name body acc
  | Ast.EBlock (es, _) ->
    List.fold_left (fun a e -> find_uses name e a) acc es
  | Ast.ELet (b, _) -> find_uses name b.bind_expr acc
  | Ast.ELetFn (_, _, _, body, _) -> find_uses name body acc
  | Ast.EMatch (subj, brs, _) ->
    find_uses name subj
      (List.fold_left
         (fun a (br : Ast.branch) -> find_uses name br.branch_body a)
         acc brs)
  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
    List.fold_left (fun a e -> find_uses name e a) acc es
  | Ast.EIf (c, t, f, _) ->
    find_uses name c (find_uses name t (find_uses name f acc))
  | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) ->
    find_uses name a (find_uses name b acc)
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
  | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) ->
    find_uses name e acc
  | Ast.ERecord (fs, _) ->
    List.fold_left (fun a (_, e) -> find_uses name e a) acc fs
  | Ast.ERecordUpdate (e, fs, _) ->
    find_uses name e
      (List.fold_left (fun a (_, e2) -> find_uses name e2 a) acc fs)
  | _ -> acc

(** Build consumption records for let bindings in a list of decls. *)
let build_consumption_map (_type_map : (Ast.span, Tc.ty) Hashtbl.t)
    (decls : Ast.decl list) : consumption list =
  let result = ref [] in
  let check_binding (b : Ast.binding) let_span body_expr =
    let names = ref [] in
    let rec collect (p : Ast.pattern) =
      match p with
      | Ast.PatVar n -> names := n :: !names
      | Ast.PatAs (p2, n, _) -> collect p2; names := n :: !names
      | Ast.PatTuple (ps, _) -> List.iter collect ps
      | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) ->
        List.iter collect ps
      | Ast.PatRecord (fs, _) -> List.iter (fun (_, p) -> collect p) fs
      | _ -> ()
    in
    collect b.bind_pat;
    List.iter (fun (n : Ast.name) ->
        let uses = find_uses n.txt body_expr [] in
        result := { con_name = n.txt; con_def = let_span; con_uses = uses }
                  :: !result
      ) !names
  in
  let rec scan_expr (e : Ast.expr) =
    match e with
    | Ast.ELet (b, _) -> scan_expr b.bind_expr
    | Ast.EBlock (es, _) ->
      let rec scan_block = function
        | [] -> ()
        | Ast.ELet (b, let_sp) :: rest ->
          let rest_expr = match rest with
            | [e] -> e
            | [] -> Ast.ELit (Ast.LitBool false, Ast.dummy_span)
            | es -> Ast.EBlock (es, Ast.dummy_span)
          in
          check_binding b let_sp rest_expr;
          scan_block rest
        | e :: rest -> scan_expr e; scan_block rest
      in
      scan_block es
    | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) ->
      scan_expr body
    | Ast.EMatch (subj, brs, _) ->
      scan_expr subj;
      List.iter (fun (br : Ast.branch) -> scan_expr br.branch_body) brs
    | Ast.EApp (f, args, _) ->
      scan_expr f; List.iter scan_expr args
    | Ast.EIf (c, t, f, _) ->
      scan_expr c; scan_expr t; scan_expr f
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) ->
      scan_expr a; scan_expr b
    | _ -> ()
  in
  List.iter (function
    | Ast.DFn (fn, _) ->
      List.iter (fun (cl : Ast.fn_clause) -> scan_expr cl.fc_body) fn.fn_clauses
    | Ast.DLet (_, b, _) -> scan_expr b.bind_expr
    | _ -> ()
  ) decls;
  !result

(* ------------------------------------------------------------------ *)
(* Main analysis entry point                                           *)
(* ------------------------------------------------------------------ *)

let analyse ~filename ~src : t =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  let parse_result =
    try
      Ok (March_parser.Parser.module_ March_lexer.Lexer.token lexbuf)
    with
    | Err.ParseError (msg, hint, pos) ->
      Error (`ParseError (msg, hint, pos))
    | March_parser.Parser.Error ->
      Error (`MenhirError (Lexing.lexeme_start_p lexbuf))
    | March_lexer.Lexer.Lexer_error msg ->
      Error (`LexerError (msg, Lexing.lexeme_start_p lexbuf))
  in
  let make_empty_with diag =
    { src;
      filename;
      type_map    = Hashtbl.create 0;
      def_map     = Hashtbl.create 0;
      use_map     = Hashtbl.create 0;
      vars        = [];
      types       = [];
      ctors       = [];
      interfaces  = [];
      impls       = [];
      actors      = [];
      doc_map     = Hashtbl.create 0;
      refs_map    = Hashtbl.create 0;
      call_sites  = [];
      consumption = [];
      match_sites = [];
      diagnostics = [diag] }
  in
  let make_parse_diag pos msg =
    let sp : Ast.span = {
      file = filename;
      start_line = pos.Lexing.pos_lnum;
      start_col  = pos.Lexing.pos_cnum - pos.Lexing.pos_bol;
      end_line   = pos.Lexing.pos_lnum;
      end_col    = pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1;
    } in
    Lsp.Types.Diagnostic.create
      ~range:(Pos.span_to_lsp_range sp)
      ~severity:Lsp.Types.DiagnosticSeverity.Error
      ~message:(`String msg) ~source:"march" ()
  in
  match parse_result with
  | Error (`ParseError (msg, hint, pos)) ->
    let full_msg = match hint with
      | Some h -> msg ^ "\nHint: " ^ h
      | None   -> msg
    in
    make_empty_with (make_parse_diag pos full_msg)

  | Error (`MenhirError pos) ->
    make_empty_with (make_parse_diag pos "Parse error")

  | Error (`LexerError (msg, pos)) ->
    make_empty_with (make_parse_diag pos msg)

  | Ok raw_ast ->
    let desugared = March_desugar.Desugar.desugar_module raw_ast in
    let stdlib_decls = load_stdlib () in
    let desugared =
      { desugared with
        Ast.mod_decls = stdlib_decls @ desugared.Ast.mod_decls }
    in
    let (errors, type_map, final_env) = Tc.check_module_full desugared in
    let def_map        = Hashtbl.create 64 in
    let use_map        = Hashtbl.create 64 in
    let doc_map        = Hashtbl.create 16 in
    let call_sites_acc = ref [] in
    let actors_tbl     = Hashtbl.create 8  in
    let is_user_file (sp : Ast.span) =
      sp.Ast.file = filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"
    in
    let user_decls =
      List.filter (fun d ->
          let sp = match d with
            | Ast.DFn (fn, _)       -> fn.fn_name.span
            | Ast.DType (_, n, _, _, sp) -> ignore n; sp
            | Ast.DMod (n, _, _, _) -> n.Ast.span
            | Ast.DLet (_, _, sp)   -> sp
            | Ast.DActor (_, n, _, _) -> n.Ast.span
            | Ast.DInterface (i, _) -> i.iface_name.Ast.span
            | Ast.DImpl (_, sp)     -> sp
            | Ast.DApp (_, sp)      -> sp
            | _                     -> Ast.dummy_span
          in
          is_user_file sp
        ) raw_ast.Ast.mod_decls
    in
    List.iter (collect_decl ~def_map ~use_map ~doc_map ~calls:call_sites_acc ~actors_tbl) user_decls;
    (* Populate doc_map with stdlib function docs so that hovering over a
       stdlib call site (e.g. [head], [map], [filter]) shows the doc string. *)
    collect_docs ~doc_map stdlib_decls;
    let actors = Hashtbl.fold (fun k v acc -> (k, v) :: acc) actors_tbl [] in
    (* Build refs_map by inverting use_map *)
    let refs_map = Hashtbl.create 64 in
    Hashtbl.iter (fun sp name ->
        let existing =
          match Hashtbl.find_opt refs_map name with
          | Some lst -> lst
          | None     -> []
        in
        Hashtbl.replace refs_map name (sp :: existing)
      ) use_map;
    let call_sites = !call_sites_acc in
    let consumption = build_consumption_map type_map user_decls in
    (* Extract non-exhaustive match warnings as match_sites *)
    let match_sites =
      let prefix = "Non-exhaustive pattern match — missing case: " in
      let plen   = String.length prefix in
      List.filter_map (fun (d : March_errors.Errors.diagnostic) ->
          if d.severity = March_errors.Errors.Warning &&
             String.length d.message >= plen &&
             String.sub d.message 0 plen = prefix
          then
            let ms_missing_case =
              String.sub d.message plen (String.length d.message - plen)
            in
            if d.span.Ast.file = filename || d.span.Ast.file = "" ||
               d.span.Ast.file = "<unknown>"
            then Some { ms_span = d.span; ms_missing_case }
            else None
          else None
        ) (March_errors.Errors.sorted errors)
    in
    let diags = Err.sorted errors |> List.filter_map (diag_to_lsp ~filename) in
    { src; filename; type_map; def_map; use_map;
      vars       = final_env.Tc.vars;
      types      = final_env.Tc.types;
      ctors      = List.map (fun (name, ci) -> (name, ci.Tc.ci_type))
                     final_env.Tc.ctors;
      interfaces = final_env.Tc.interfaces;
      impls      = final_env.Tc.impls;
      actors;
      doc_map;
      refs_map;
      call_sites;
      consumption;
      match_sites;
      diagnostics = diags }

(* ------------------------------------------------------------------ *)
(* Query helpers                                                       *)
(* ------------------------------------------------------------------ *)

let type_at (a : t) ~line ~character : string option =
  let candidates = Hashtbl.fold (fun sp ty acc ->
      if Pos.span_contains sp ~line ~character then (sp, ty) :: acc
      else acc
    ) a.type_map []
  in
  match candidates with
  | [] -> None
  | _ ->
    let (_, ty) =
      List.fold_left (fun (best_sp, best_ty) (sp, ty) ->
          if Pos.span_smaller sp best_sp then (sp, ty)
          else (best_sp, best_ty)
        ) (List.hd candidates) (List.tl candidates)
    in
    Some (Tc.pp_ty ty)

let definition_at (a : t) ~line ~character : Lsp.Types.Location.t option =
  let var_name =
    Hashtbl.fold (fun sp name found ->
        match found with
        | Some _ -> found
        | None ->
          if Pos.span_contains sp ~line ~character then Some name
          else None
      ) a.use_map None
  in
  match var_name with
  | None -> None
  | Some name ->
    (match Hashtbl.find_opt a.def_map name with
     | None -> None
     | Some def_span ->
       let path = def_span.Ast.file in
       let uri =
         if path = "" || path = "<unknown>" then
           Lsp.Types.DocumentUri.of_path "unknown"
         else
           Lsp.Types.DocumentUri.of_path path
       in
       let range = Pos.span_to_lsp_range def_span in
       Some (Lsp.Types.Location.create ~uri ~range))

let keywords = [
  "mod"; "end"; "do"; "fn"; "let"; "match"; "if"; "then"; "else";
  "type"; "interface"; "impl"; "derive"; "use"; "alias"; "needs";
  "extern"; "app"; "actor"; "protocol"; "when"; "as";
  "true"; "false"; "linear"; "affine"; "pub";
]

let completions_at (a : t) ~line:_ ~character:_ =
  let open Lsp.Types in
  let kw_items = List.map (fun kw ->
      CompletionItem.create ~label:kw ~kind:CompletionItemKind.Keyword ()
    ) keywords in
  let var_items = List.filter_map (fun (name, scheme) ->
      if String.length name > 0 && name.[0] = '_' then None
      else
        let detail = match scheme with
          | Tc.Mono ty -> Tc.pp_ty ty
          | Tc.Poly (_, _, ty) -> Tc.pp_ty ty
        in
        Some (CompletionItem.create
          ~label:name ~kind:CompletionItemKind.Function ~detail ())
    ) a.vars in
  let type_items = List.map (fun (name, _) ->
      CompletionItem.create ~label:name ~kind:CompletionItemKind.Class ()
    ) a.types in
  let ctor_items = List.map (fun (name, parent) ->
      CompletionItem.create
        ~label:name ~kind:CompletionItemKind.EnumMember ~detail:parent ()
    ) a.ctors in
  let iface_items = List.map (fun (name, _) ->
      CompletionItem.create ~label:name ~kind:CompletionItemKind.Interface ()
    ) a.interfaces in
  kw_items @ var_items @ type_items @ ctor_items @ iface_items

let inlay_hints_for (a : t) (range : Lsp.Types.Range.t) =
  let open Lsp.Types in
  let is_user_span (sp : Ast.span) =
    sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"
  in
  let in_range (sp : Ast.span) =
    let r = Pos.span_to_lsp_range sp in
    r.Range.end_.line >= range.Range.start.line &&
    r.Range.start.line <= range.Range.end_.line
  in
  let hints = ref [] in
  Hashtbl.iter (fun sp ty ->
      if is_user_span sp && in_range sp &&
         sp.Ast.start_line = sp.Ast.end_line &&
         sp.Ast.end_col - sp.Ast.start_col <= 40
      then begin
        let ty_str = Tc.pp_ty ty in
        let pos = Pos.create
          ~line:(sp.Ast.end_line - 1) ~character:sp.Ast.end_col in
        let hint = InlayHint.create
          ~position:pos
          ~label:(`String (": " ^ ty_str))
          ~kind:InlayHintKind.Type
          ~paddingLeft:true
          () in
        hints := hint :: !hints
      end
    ) a.type_map;
  !hints

let document_symbols (a : t) =
  let open Lsp.Types in
  let syms = Hashtbl.fold (fun name sp acc ->
      let range = Pos.span_to_lsp_range sp in
      let kind =
        if List.mem_assoc name a.types then SymbolKind.Class
        else if List.mem_assoc name a.ctors then SymbolKind.EnumMember
        else if List.mem_assoc name a.interfaces then SymbolKind.Interface
        else SymbolKind.Function
      in
      let sym = DocumentSymbol.create
        ~name ~kind ~range ~selectionRange:range () in
      sym :: acc
    ) a.def_map [] in
  `DocumentSymbol syms

let find_impls_of (a : t) iface_name =
  List.filter_map (fun (iface, ty) ->
      if iface = iface_name then Some (Tc.pp_ty ty)
      else None
    ) a.impls

(* ------------------------------------------------------------------ *)
(* New query helpers: doc strings, references, rename, sig help,      *)
(* code actions                                                        *)
(* ------------------------------------------------------------------ *)

let doc_for (a : t) (name : string) : string option =
  Hashtbl.find_opt a.doc_map name

(** Return the doc string for the function whose name the cursor sits on,
    by resolving the name via [use_map] and then looking up [doc_map]. *)
let doc_name_at (a : t) ~line ~character : string option =
  let name_opt =
    Hashtbl.fold (fun sp name found ->
        match found with
        | Some _ -> found
        | None   ->
          if Pos.span_contains sp ~line ~character then Some name
          else None
      ) a.use_map None
  in
  let name_opt =
    match name_opt with
    | Some _ -> name_opt
    | None ->
      Hashtbl.fold (fun name sp found ->
          match found with
          | Some _ -> found
          | None   ->
            if Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.def_map None
  in
  match name_opt with
  | None -> None
  | Some name -> doc_for a name

let references_at (a : t) ~include_declaration ~line ~character
    : Lsp.Types.Location.t list =
  let name_opt =
    let from_use =
      Hashtbl.fold (fun sp name found ->
          match found with
          | Some _ -> found
          | None   ->
            if Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.use_map None
    in
    match from_use with
    | Some _ -> from_use
    | None ->
      Hashtbl.fold (fun name sp found ->
          match found with
          | Some _ -> found
          | None   ->
            if Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.def_map None
  in
  match name_opt with
  | None -> []
  | Some name ->
    let use_spans =
      match Hashtbl.find_opt a.refs_map name with
      | Some spans -> spans
      | None       -> []
    in
    let all_spans =
      if include_declaration then
        match Hashtbl.find_opt a.def_map name with
        | Some def_sp -> def_sp :: use_spans
        | None        -> use_spans
      else
        use_spans
    in
    List.filter_map (fun (sp : Ast.span) ->
        if sp = Ast.dummy_span then None
        else
          let path =
            if sp.Ast.file = "" || sp.Ast.file = "<unknown>" then a.filename
            else sp.Ast.file
          in
          let uri   = Lsp.Types.DocumentUri.of_path path in
          let range = Pos.span_to_lsp_range sp in
          Some (Lsp.Types.Location.create ~uri ~range)
      ) all_spans

(** Return a flat list of [TextEdit.t] replacing every occurrence of the
    symbol at the cursor with [new_name], including its definition site. *)
let rename_at (a : t) ~line ~character ~new_name
    : Lsp.Types.TextEdit.t list =
  let locs =
    references_at a ~include_declaration:true ~line ~character
  in
  List.map (fun (loc : Lsp.Types.Location.t) ->
      Lsp.Types.TextEdit.create ~range:loc.range ~newText:new_name
    ) locs

(** Walk [TArrow] chain to collect stringified parameter types. *)
let rec unwrap_arrows (ty : Tc.ty) : string list * string =
  match ty with
  | Tc.TArrow (param, rest) ->
    let (more, ret) = unwrap_arrows rest in
    (Tc.pp_ty param :: more, ret)
  | _                       -> ([], Tc.pp_ty ty)

(** Convert 0-indexed (line, character) to a byte offset in [src]. *)
let offset_of_pos src line character =
  let n = String.length src in
  let cur_line = ref 0 in
  let i = ref 0 in
  while !i < n && !cur_line < line do
    if src.[!i] = '\n' then incr cur_line;
    incr i
  done;
  !i + character

(** Count the number of top-level commas in [src] between positions
    [from_ofs] (exclusive) and [to_ofs] (exclusive).
    "Top-level" means not inside nested parens/brackets/braces. *)
let count_commas_between src from_ofs to_ofs =
  let depth = ref 0 in
  let count = ref 0 in
  for i = from_ofs to to_ofs - 1 do
    match src.[i] with
    | '(' | '[' | '{' -> incr depth
    | ')' | ']' | '}' -> if !depth > 0 then decr depth
    | ',' when !depth = 0 -> incr count
    | _ -> ()
  done;
  !count

(** Return [(signature_label, param_labels, active_param_index)] for the
    innermost call expression that contains the cursor, or [None]. *)
let signature_help_at (a : t) ~line ~character
    : (string * string list * int) option =
  let containing =
    List.fold_left (fun best cs ->
        if Pos.span_contains cs.cs_span ~line ~character then
          match best with
          | None      -> Some cs
          | Some prev ->
            if Pos.span_smaller cs.cs_span prev.cs_span
            then Some cs else best
        else best
      ) None a.call_sites
  in
  match containing with
  | None -> None
  | Some cs ->
    let scheme_opt =
      match cs.cs_fn_name with
      | None      -> None
      | Some name -> List.assoc_opt name a.vars
    in
    let ty_opt = match scheme_opt with
      | Some (Tc.Mono ty)         -> Some ty
      | Some (Tc.Poly (_, _, ty)) -> Some ty
      | None                      -> None
    in
    (match ty_opt with
     | None -> None
     | Some ty ->
       let (params, _ret) = unwrap_arrows ty in
       if params = [] then None
       else begin
         let open_paren_ofs =
           offset_of_pos a.src
             (cs.cs_span.Ast.start_line - 1)
             cs.cs_span.Ast.start_col
         in
         let paren_ofs = ref open_paren_ofs in
         let src_len = String.length a.src in
         while !paren_ofs < src_len && a.src.[!paren_ofs] <> '(' do
           incr paren_ofs
         done;
         let cursor_ofs = offset_of_pos a.src line character in
         let active =
           if !paren_ofs >= src_len then 0
           else
             min
               (count_commas_between a.src (!paren_ofs + 1) cursor_ofs)
               (List.length params - 1)
         in
         let label =
           match cs.cs_fn_name with
           | Some n -> Printf.sprintf "%s(%s)" n (String.concat ", " params)
           | None   -> Printf.sprintf "(%s)" (String.concat ", " params)
         in
         Some (label, params, active)
       end)

(** Find the byte offset of name [name] in [src] starting from [hint_ofs]. *)
let find_name_ofs src name hint_ofs =
  let sn  = String.length name in
  let len = String.length src in
  let rec go i =
    if i + sn > len then None
    else if String.sub src i sn = name then Some i
    else go (i + 1)
  in
  go hint_ofs

(** Find the byte offset of the [end] keyword immediately before the end of
    [span] in [src].  Scans backwards to locate it. *)
let find_end_before_span src (span : Ast.span) =
  let end_ofs = offset_of_pos src (span.Ast.end_line - 1) span.Ast.end_col in
  let sn = 3 in
  let rec go i =
    if i < sn then None
    else
      let candidate = String.sub src (i - sn) sn in
      if candidate = "end" then begin
        let before_ok =
          i - sn = 0 ||
          (let c = src.[i - sn - 1] in c = ' ' || c = '\n' || c = '\t')
        in
        let after_ok =
          i >= String.length src ||
          (let c = src.[i] in c = ' ' || c = '\n' || c = '\t' || c = '\r')
        in
        if before_ok && after_ok then Some (i - sn)
        else go (i - 1)
      end else
        go (i - 1)
  in
  go (min end_ofs (String.length src))

(** Generate code actions relevant to the cursor position [line, character].
    Produces:
    - "Make `x` linear" for single-use non-linear let bindings at cursor.
    - "Add missing case: P" quickfix for non-exhaustive matches at cursor. *)
let code_actions_at (a : t) ~line ~character
    : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  (* ---- Make-linear actions ---- *)
  let make_linear_actions =
    List.filter_map (fun (c : consumption) ->
        let span = c.con_def in
        if not (Pos.span_contains span ~line ~character) then None
        else if List.length c.con_uses <> 1 then None
        else begin
          let name = c.con_name in
          let hint_ofs =
            offset_of_pos a.src (span.Ast.start_line - 1) span.Ast.start_col
          in
          match find_name_ofs a.src name hint_ofs with
          | None -> None
          | Some name_ofs ->
            let insert_line = ref 0 and insert_col = ref 0 in
            let cur_line = ref 0 and cur_col = ref 0 in
            String.iteri (fun i _ch ->
                if i = name_ofs then begin
                  insert_line := !cur_line;
                  insert_col  := !cur_col
                end;
                if a.src.[i] = '\n' then begin incr cur_line; cur_col := 0 end
                else incr cur_col
              ) a.src;
            let range =
              Range.create
                ~start:(Position.create ~line:!insert_line ~character:!insert_col)
                ~end_:(Position.create  ~line:!insert_line ~character:!insert_col)
            in
            let edit = TextEdit.create ~range ~newText:"linear " in
            let uri  = DocumentUri.of_path a.filename in
            let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
            let action = CodeAction.create
                           ~title:(Printf.sprintf "Make `%s` linear" name)
                           ~kind:CodeActionKind.RefactorRewrite
                           ~edit:we
                           () in
            Some action
        end
      ) a.consumption
  in
  (* ---- Exhaustion quickfix actions ---- *)
  let exhaustion_actions =
    List.filter_map (fun (ms : match_site) ->
        if not (Pos.span_contains ms.ms_span ~line ~character) then None
        else begin
          match find_end_before_span a.src ms.ms_span with
          | None -> None
          | Some end_ofs ->
            let e_line = ref 0 and e_col = ref 0 in
            let cl = ref 0 and cc = ref 0 in
            String.iteri (fun i _ch ->
                if i = end_ofs then begin
                  e_line := !cl;
                  e_col  := !cc
                end;
                if a.src.[i] = '\n' then begin incr cl; cc := 0 end
                else incr cc
              ) a.src;
            let insert_pos = Position.create ~line:!e_line ~character:!e_col in
            let range      = Range.create ~start:insert_pos ~end_:insert_pos in
            let arm_text   = Printf.sprintf "| %s ->\n    ?\n" ms.ms_missing_case in
            let edit       = TextEdit.create ~range ~newText:arm_text in
            let uri    = DocumentUri.of_path a.filename in
            let we     = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
            let action = CodeAction.create
                           ~title:(Printf.sprintf "Add missing case: %s" ms.ms_missing_case)
                           ~kind:CodeActionKind.QuickFix
                           ~edit:we
                           () in
            Some action
        end
      ) a.match_sites
  in
  make_linear_actions @ exhaustion_actions

let actor_info_at (a : t) ~line ~character : string option =
  let found = List.find_opt (fun (name, _) ->
      match Hashtbl.find_opt a.def_map name with
      | Some sp -> Pos.span_contains sp ~line ~character
      | None -> false
    ) a.actors in
  match found with
  | None -> None
  | Some (name, adef) ->
    let msg_types = List.map (fun (h : Ast.actor_handler) ->
        let params = List.map (fun (p : Ast.param) ->
            p.param_name.txt ^
            (match p.param_ty with
             | Some ty -> " : " ^ Ast.show_ty ty
             | None -> "")
          ) h.ah_params in
        Printf.sprintf "| %s(%s)" h.ah_msg.txt (String.concat ", " params)
      ) adef.actor_handlers in
    let state_fields = List.map (fun (f : Ast.field) ->
        Printf.sprintf "  %s : %s" f.fld_name.txt (Ast.show_ty f.fld_ty)
      ) adef.actor_state in
    let buf = Buffer.create 64 in
    Buffer.add_string buf (Printf.sprintf "**actor %s**\n\n" name);
    if state_fields <> [] then begin
      Buffer.add_string buf "State:\n";
      List.iter (fun s -> Buffer.add_string buf (s ^ "\n")) state_fields;
      Buffer.add_string buf "\n"
    end;
    Buffer.add_string buf "Messages:\n```march\n";
    List.iter (fun s -> Buffer.add_string buf (s ^ "\n")) msg_types;
    Buffer.add_string buf "```";
    Some (Buffer.contents buf)
