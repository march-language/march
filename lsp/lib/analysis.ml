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
  ms_span          : Ast.span;         (** Span of the whole match expression *)
  ms_missing_cases : string list;      (** All missing patterns for this match *)
  ms_matched_type  : string option;    (** Inferred type name being matched, if known *)
  ms_ctor_sigs     : (string * Ast.ty list) list;
  (** Constructor name → field arg types (surface AST types), for typed stub generation. *)
}

(** What kind of annotation site this is. *)
type annotation_kind =
  | AnnLet       (** let x = e  →  let x: T = e *)
  | AnnFnReturn  (** fn foo(x) do e end  →  fn foo(x) -> T do e end *)
  | AnnFnParam   (** fn foo(x) do e end  →  fn foo(x: T) do e end *)

(** A site where a type annotation can be inserted. *)
type annotation_site = {
  as_name_span : Ast.span;         (** Span of the unannotated name (cursor detection) *)
  as_rhs_span  : Ast.span;         (** Span used for type lookup in type_map *)
  as_kind      : annotation_kind;  (** What kind of annotation to insert *)
}

(** Where a linear/affine value is consumed. *)
type consumption = {
  con_name : string;
  con_def  : Ast.span;
  con_uses : Ast.span list;
}

(** A naming convention violation.
    Functions should be snake_case; types should be PascalCase. *)
type naming_violation = {
  nv_name      : string;
  nv_suggested : string;
  nv_span      : Ast.span;
  nv_kind      : [`Function | `Type];
}

(** A De Morgan rewrite opportunity. *)
type demorgan_site = {
  dm_span       : Ast.span;  (** Span of the whole expression *)
  dm_form       : [`NegatedBinop of string | `PairOfNegs of string];
  (** [`NegatedBinop op] = !(a op b); offer !a op' !b  (op' = dual of op)
      [`PairOfNegs  op] = !a op !b;  offer !(a op' b) *)
  dm_left_span  : Ast.span;  (** Span of the left operand a *)
  dm_right_span : Ast.span;  (** Span of the right operand b *)
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
  ctor_arities : (string * int) list;
  (** Data constructor name → argument count (used for snippet completions). *)
  fold_ranges : (int * int * string) list;
  (** Fold ranges: (start_line_0indexed, end_line_0indexed, kind). *)
  annotation_sites : annotation_site list;
  (** Unannotated let bindings eligible for "Add type annotation" code action. *)
  unused_fns : string list;
  (** Private function names that are never reachable from any public root. *)
  type_matches : (string * match_site list) list;
  (** All match sites grouped by matched type name (for bulk file-scope fixes). *)
  naming_violations : naming_violation list;
  (** Functions/types that violate the naming convention (camelCase fn, snake_case type). *)
  demorgan_sites   : demorgan_site list;
  (** Sites eligible for De Morgan rewriting: !(a&&b), !(a||b), !a&&!b, !a||!b. *)
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
    (* Load prelude first (special treatment: its top-level mod wrapper is
       stripped so its decls land in the global scope).  Then load every
       other *.march file in the stdlib directory so the full standard
       library — including Array, Test, Bigint, Json, etc. — is available
       to the type-checker when the LSP analyses any file. *)
    let all_files =
      try
        Sys.readdir stdlib_dir
        |> Array.to_list
        |> List.filter (fun f -> Filename.check_suffix f ".march")
        |> List.sort String.compare
      with Sys_error _ -> []
    in
    let prelude = "prelude.march" in
    let rest = List.filter (fun f -> f <> prelude) all_files in
    let ordered = if List.mem prelude all_files then prelude :: rest else rest in
    List.concat_map
      (fun name -> load_stdlib_file (Filename.concat stdlib_dir name))
      ordered

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
    let code = Option.map (fun s -> `String s) d.code in
    Some (Lsp.Types.Diagnostic.create
      ~range
      ~severity:(severity_to_lsp d.severity)
      ~message:(`String message)
      ~source:"march"
      ?code
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
    collect_pat_defs ~def_map ~use_map b.bind_pat;
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

  | Ast.DTest (tdef, _) ->
    collect_expr ~def_map ~use_map ~calls tdef.test_body

  | Ast.DSetup (body, _) | Ast.DSetupAll (body, _) ->
    collect_expr ~def_map ~use_map ~calls body

  | Ast.DUse _ | Ast.DAlias _ | Ast.DNeeds _
  | Ast.DProtocol _ | Ast.DExtern _ | Ast.DSig _
  | Ast.DDeriving _ | Ast.DDescribe _ -> ()

and collect_expr ~def_map ~use_map ~calls (e : Ast.expr) =
  match e with
  | Ast.EVar name ->
    Hashtbl.replace use_map name.span name.txt

  | Ast.ELet (b, _) ->
    collect_pat_defs ~def_map ~use_map b.bind_pat;
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
        collect_pat_defs ~def_map ~use_map br.branch_pat;
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

  | Ast.ECon (name, args, _) ->
    Hashtbl.replace use_map name.span name.txt;
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

  | Ast.ECond (arms, _) ->
    List.iter (fun (ce, be) ->
      collect_expr ~def_map ~use_map ~calls ce;
      collect_expr ~def_map ~use_map ~calls be
    ) arms

  | Ast.EPipe (e1, e2, _) | Ast.ESend (e1, e2, _) ->
    collect_expr ~def_map ~use_map ~calls e1;
    collect_expr ~def_map ~use_map ~calls e2

  | Ast.EAssert (e, _) ->
    collect_expr ~def_map ~use_map ~calls e

  | Ast.ELit _ | Ast.EHole _ | Ast.EDbg (None, _)
  | Ast.EResultRef _ -> ()

and collect_pat_defs ~def_map ~use_map (pat : Ast.pattern) =
  match pat with
  | Ast.PatVar name ->
    Hashtbl.replace def_map name.txt name.span
  | Ast.PatAs (p, name, _) ->
    collect_pat_defs ~def_map ~use_map p;
    Hashtbl.replace def_map name.txt name.span
  | Ast.PatCon (name, ps) ->
    Hashtbl.replace use_map name.span name.txt;
    List.iter (collect_pat_defs ~def_map ~use_map) ps
  | Ast.PatAtom (_, ps, _) ->
    List.iter (collect_pat_defs ~def_map ~use_map) ps
  | Ast.PatTuple (ps, _) ->
    List.iter (collect_pat_defs ~def_map ~use_map) ps
  | Ast.PatRecord (fields, _) ->
    List.iter (fun (_, p) -> collect_pat_defs ~def_map ~use_map p) fields
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
(* Fold-range and annotation-site collection                          *)
(* ------------------------------------------------------------------ *)

(** Extract the source span from any expression node. *)
let span_of_expr = function
  | Ast.ELit (_, sp) | Ast.EApp (_, _, sp) | Ast.ECon (_, _, sp)
  | Ast.ELam (_, _, sp) | Ast.EBlock (_, sp) | Ast.ELet (_, sp)
  | Ast.EMatch (_, _, sp) | Ast.ETuple (_, sp) | Ast.ERecord (_, sp)
  | Ast.ERecordUpdate (_, _, sp) | Ast.EField (_, _, sp)
  | Ast.EIf (_, _, _, sp) | Ast.ECond (_, sp) | Ast.EPipe (_, _, sp) | Ast.EAnnot (_, _, sp)
  | Ast.EHole (_, sp) | Ast.EAtom (_, _, sp) | Ast.ESend (_, _, sp)
  | Ast.ESpawn (_, sp) | Ast.EDbg (_, sp) | Ast.ELetFn (_, _, _, _, sp)
  | Ast.EAssert (_, sp) -> sp
  | Ast.EVar name -> name.Ast.span
  | Ast.EResultRef _ -> Ast.dummy_span

(** Walk an AST module collecting folding ranges.
    Returns (start_line_0idx, end_line_0idx, kind) triples. *)
let collect_fold_ranges (m : Ast.module_) : (int * int * string) list =
  let ranges = ref [] in
  let add (sp : Ast.span) kind =
    let sl = sp.Ast.start_line - 1 in
    let el = sp.Ast.end_line   - 1 in
    if el > sl then ranges := (sl, el, kind) :: !ranges
  in
  let rec go_decls decls = List.iter go_decl decls
  and go_decl decl =
    match decl with
    | Ast.DFn (fn, sp) ->
      add sp "region";
      List.iter (fun (cl : Ast.fn_clause) -> go_expr cl.fc_body) fn.fn_clauses
    | Ast.DMod (_, _, decls, sp) ->
      add sp "region";
      go_decls decls
    | Ast.DActor (_, _, adef, sp) ->
      add sp "region";
      go_expr adef.actor_init;
      List.iter (fun (h : Ast.actor_handler) -> go_expr h.ah_body)
        adef.actor_handlers
    | Ast.DDescribe (_, decls, sp) ->
      add sp "region";
      go_decls decls
    | Ast.DLet (_, b, _) -> go_expr b.bind_expr
    | _ -> ()
  and go_expr e =
    match e with
    | Ast.EMatch (subj, branches, sp) ->
      add sp "region";
      go_expr subj;
      List.iter (fun (br : Ast.branch) ->
          let bsp = span_of_expr br.branch_body in
          add bsp "region";
          go_expr br.branch_body
        ) branches
    | Ast.EBlock (es, _) -> List.iter go_expr es
    | Ast.ELet (b, _)    -> go_expr b.bind_expr
    | Ast.ELetFn (_, _, _, body, sp) -> add sp "region"; go_expr body
    | Ast.ELam (_, body, _) -> go_expr body
    | Ast.EIf (c, t, f, _) -> go_expr c; go_expr t; go_expr f
    | Ast.EApp (f, args, _) -> go_expr f; List.iter go_expr args
    | _ -> ()
  in
  go_decls m.Ast.mod_decls;
  !ranges

(** Walk an AST module collecting unannotated let bindings, function return types,
    and function parameters. *)
let collect_annotation_sites (m : Ast.module_) : annotation_site list =
  let sites = ref [] in
  let collect_fn_sites (fn : Ast.fn_def) =
    (* Return-type annotation site: only if fn has no declared return type *)
    if fn.fn_ret_ty = None then
      sites := { as_name_span = fn.fn_name.span;
                 as_rhs_span  = fn.fn_name.span;
                 as_kind      = AnnFnReturn } :: !sites;
    (* Parameter annotation sites: one per unannotated param in first clause.
       March parses bare `x` as FPPat(PatVar x) and `x: T` as FPNamed.
       Only collect sites for FPPat(PatVar) — those lack type annotations. *)
    (match fn.fn_clauses with
     | cl :: _ ->
       List.iter (fun fp ->
           match fp with
           | Ast.FPPat (Ast.PatVar name) when name.span <> Ast.dummy_span ->
             sites := { as_name_span = name.span;
                        as_rhs_span  = name.span;
                        as_kind      = AnnFnParam } :: !sites
           | _ -> ()
         ) cl.fc_params
     | [] -> ())
  in
  let rec go_decls decls = List.iter go_decl decls
  and go_decl decl =
    match decl with
    | Ast.DLet (_, b, _) ->
      (match b.bind_pat, b.bind_ty with
       | Ast.PatVar name, None ->
         let rhs_sp = span_of_expr b.bind_expr in
         if rhs_sp <> Ast.dummy_span then
           sites := { as_name_span = name.Ast.span;
                      as_rhs_span  = rhs_sp;
                      as_kind      = AnnLet } :: !sites
       | _ -> ());
      go_expr b.bind_expr
    | Ast.DFn (fn, _) ->
      collect_fn_sites fn;
      List.iter (fun (cl : Ast.fn_clause) -> go_expr cl.fc_body) fn.fn_clauses
    | Ast.DMod (_, _, decls, _) -> go_decls decls
    | Ast.DDescribe (_, decls, _) -> go_decls decls
    | _ -> ()
  and go_expr e =
    match e with
    | Ast.ELet (b, _) ->
      (match b.bind_pat, b.bind_ty with
       | Ast.PatVar name, None ->
         let rhs_sp = span_of_expr b.bind_expr in
         if rhs_sp <> Ast.dummy_span then
           sites := { as_name_span = name.Ast.span;
                      as_rhs_span  = rhs_sp;
                      as_kind      = AnnLet } :: !sites
       | _ -> ());
      go_expr b.bind_expr
    | Ast.EBlock (es, _)         -> List.iter go_expr es
    | Ast.ELam (_, body, _)      -> go_expr body
    | Ast.ELetFn (_, _, _, body, _) -> go_expr body
    | Ast.EMatch (subj, brs, _) ->
      go_expr subj;
      List.iter (fun br -> go_expr br.Ast.branch_body) brs
    | Ast.EIf (c, t, f, _)      -> go_expr c; go_expr t; go_expr f
    | Ast.EApp (f, args, _)      -> go_expr f; List.iter go_expr args
    | _ -> ()
  in
  go_decls m.Ast.mod_decls;
  !sites

(* ------------------------------------------------------------------ *)
(* Naming convention helpers (P2.8)                                   *)
(* ------------------------------------------------------------------ *)

(** True if [name] has a lowercase letter immediately followed by uppercase — camelCase. *)
let is_camel_case name =
  let n = String.length name in
  let rec check i =
    if i + 1 >= n then false
    else
      let lo = Char.code name.[i] and hi = Char.code name.[i + 1] in
      if lo >= Char.code 'a' && lo <= Char.code 'z'
         && hi >= Char.code 'A' && hi <= Char.code 'Z'
      then true
      else check (i + 1)
  in
  check 0

(** Convert camelCase to snake_case. *)
let camel_to_snake name =
  let buf = Buffer.create (String.length name + 4) in
  String.iteri (fun i c ->
    if i > 0
       && Char.code c >= Char.code 'A' && Char.code c <= Char.code 'Z'
    then begin
      Buffer.add_char buf '_';
      Buffer.add_char buf (Char.lowercase_ascii c)
    end else
      Buffer.add_char buf (Char.lowercase_ascii c)
  ) name;
  Buffer.contents buf

(** True if [name] starts with a lowercase letter — not PascalCase (for type names). *)
let is_non_pascal name =
  String.length name > 0 &&
  Char.code name.[0] >= Char.code 'a' && Char.code name.[0] <= Char.code 'z'

(** Convert snake_case (or lowercase) to PascalCase. *)
let to_pascal name =
  let parts = String.split_on_char '_' name in
  String.concat "" (List.map (fun p ->
    if String.length p = 0 then ""
    else String.make 1 (Char.uppercase_ascii p.[0])
         ^ String.sub p 1 (String.length p - 1)
  ) parts)

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
      type_map         = Hashtbl.create 0;
      def_map          = Hashtbl.create 0;
      use_map          = Hashtbl.create 0;
      vars             = [];
      types            = [];
      ctors            = [];
      interfaces       = [];
      impls            = [];
      actors           = [];
      doc_map          = Hashtbl.create 0;
      refs_map         = Hashtbl.create 0;
      call_sites       = [];
      consumption      = [];
      match_sites      = [];
      diagnostics      = [diag];
      ctor_arities     = [];
      fold_ranges      = [];
      annotation_sites = [];
      unused_fns        = [];
      type_matches      = [];
      naming_violations = [];
      demorgan_sites    = [] }
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
    (* Populate doc_map with stdlib function docs first so that user-defined
       functions with the same name take precedence (user docs overwrite). *)
    collect_docs ~doc_map stdlib_decls;
    List.iter (collect_decl ~def_map ~use_map ~doc_map ~calls:call_sites_acc ~actors_tbl) user_decls;
    (* Collect stdlib definitions into def_map for cross-stdlib go-to-definition.
       Use throw-away tables for use_map/doc_map/calls/actors so we don't pollute
       the user-file maps with stdlib-internal references. *)
    let _slib_use    = Hashtbl.create 0 in
    let _slib_doc    = Hashtbl.create 0 in
    let _slib_calls  = ref [] in
    let _slib_actors = Hashtbl.create 0 in
    List.iter
      (collect_decl ~def_map ~use_map:_slib_use ~doc_map:_slib_doc
         ~calls:_slib_calls ~actors_tbl:_slib_actors)
      stdlib_decls;
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
    (* Extract non-exhaustive match warnings as match_sites.
       Phase 1: collect spans from typecheck warnings (one per match expression).
       Phase 2: augment with ALL missing cases by AST analysis. *)
    let match_site_spans =
      let prefix = "Non-exhaustive pattern match" in
      let plen   = String.length prefix in
      List.filter_map (fun (d : March_errors.Errors.diagnostic) ->
          if d.severity = March_errors.Errors.Warning &&
             String.length d.message >= plen &&
             String.sub d.message 0 plen = prefix &&
             (d.span.Ast.file = filename || d.span.Ast.file = "" ||
              d.span.Ast.file = "<unknown>")
          then Some d.span
          else None
        ) (March_errors.Errors.sorted errors)
      |> List.sort_uniq compare
    in
    (* Build ctor → parent-type map from final env *)
    let ctor_parent_map =
      List.map (fun (name, ci) -> (name, ci.Tc.ci_type)) final_env.Tc.ctors
    in
    (* Build ctor → surface arg types map (for typed stub generation — P1.1) *)
    let ctor_sigs_map : (string, Ast.ty list) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (name, (ci : Tc.ctor_info)) ->
        if not (String.contains name '.') then
          Hashtbl.replace ctor_sigs_map name ci.Tc.ci_arg_tys
      ) final_env.Tc.ctors;
    (* Build parent-type → all ctors map (bare names only — skip "Type.Ctor" keys) *)
    let type_ctors_map : (string, string list) Hashtbl.t = Hashtbl.create 8 in
    List.iter (fun (ctor, parent) ->
        (* Skip qualified constructor names like "Bit.Zero" *)
        if not (String.contains ctor '.') then begin
          let existing = match Hashtbl.find_opt type_ctors_map parent with
            | Some xs -> xs | None -> []
          in
          if not (List.mem ctor existing) then
            Hashtbl.replace type_ctors_map parent (existing @ [ctor])
        end
      ) ctor_parent_map;
    (* Top-level ctor name from a pattern (None if wildcard/other) *)
    let rec pat_ctor_name (pat : Ast.pattern) =
      match pat with
      | Ast.PatCon (name, _) -> Some name.txt
      | Ast.PatAs (p, _, _) -> pat_ctor_name p
      | _ -> None
    in
    (* Does the pattern list have a wildcard/catch-all that would make it exhaustive? *)
    let has_wildcard_pat branches =
      List.exists (fun (br : Ast.branch) ->
          match br.branch_pat with
          | Ast.PatWild _ | Ast.PatVar _ -> true
          | _ -> false
        ) branches
    in
    (* For a match expression, compute all missing variant constructors *)
    let missing_cases_for_match scrut branches =
      if has_wildcard_pat branches then []  (* already exhaustive *)
      else begin
        (* Look up scrutinee type *)
        let scrut_sp = span_of_expr scrut in
        let scrut_line = scrut_sp.Ast.start_line - 1 in
        let scrut_char = scrut_sp.Ast.start_col in
        let candidates = Hashtbl.fold (fun sp ty acc ->
            if Pos.span_contains sp ~line:scrut_line ~character:scrut_char
            then (sp, ty) :: acc else acc
          ) type_map []
        in
        let ty_opt = match candidates with
          | [] -> None
          | _ ->
            Some (snd (List.fold_left (fun (bs, bt) (sp, ty) ->
                if Pos.span_smaller sp bs then (sp, ty) else (bs, bt)
              ) (List.hd candidates) (List.tl candidates)))
        in
        match ty_opt with
        | None -> []
        | Some ty ->
          let type_name = Tc.pp_ty ty in
          (match Hashtbl.find_opt type_ctors_map type_name with
           | None -> []
           | Some all_ctors ->
             let covered = List.filter_map (fun (br : Ast.branch) ->
                 pat_ctor_name br.branch_pat
               ) branches
             in
             List.filter (fun c -> not (List.mem c covered)) all_ctors)
      end
    in
    (* Walk the desugared AST to find EMatch nodes at known non-exhaustive spans *)
    let match_span_tbl : (Ast.span, string list * string option * (string * Ast.ty list) list) Hashtbl.t =
      Hashtbl.create 4
    in
    let is_nonexhaustive_span sp =
      List.mem sp match_site_spans
    in
    let rec augment_decl (d : Ast.decl) =
      match d with
      | Ast.DFn (fn, _) ->
        List.iter (fun (cl : Ast.fn_clause) -> augment_expr cl.fc_body) fn.fn_clauses
      | Ast.DLet (_, b, _) -> augment_expr b.bind_expr
      | Ast.DMod (_, _, decls, _) -> List.iter augment_decl decls
      | _ -> ()
    and augment_expr (e : Ast.expr) =
      match e with
      | Ast.EMatch (scrut, branches, sp) when is_nonexhaustive_span sp ->
        let missing = missing_cases_for_match scrut branches in
        (* Infer matched type from ctor_parent_map using first missing case *)
        let ms_matched_type = match missing with
          | [] -> None
          | c :: _ -> List.assoc_opt c ctor_parent_map
        in
        (* Fall back: use cases from ctor_parent_map for any covered ctor *)
        let ms_matched_type = match ms_matched_type with
          | Some _ as t -> t
          | None ->
            List.find_map (fun (br : Ast.branch) ->
                match br.branch_pat with
                | Ast.PatCon (n, _) -> List.assoc_opt n.txt ctor_parent_map
                | _ -> None
              ) branches
        in
        (* Build ctor sigs for missing cases (typed stub generation) *)
        let ms_ctor_sigs = List.filter_map (fun case ->
            match Hashtbl.find_opt ctor_sigs_map case with
            | Some arg_tys -> Some (case, arg_tys)
            | None -> None
          ) missing in
        Hashtbl.replace match_span_tbl sp (missing, ms_matched_type, ms_ctor_sigs);
        augment_expr scrut;
        List.iter (fun (br : Ast.branch) -> augment_expr br.branch_body) branches
      | Ast.EMatch (scrut, branches, _) ->
        augment_expr scrut;
        List.iter (fun (br : Ast.branch) -> augment_expr br.branch_body) branches
      | Ast.EBlock (es, _) -> List.iter augment_expr es
      | Ast.ELet (b, _)    -> augment_expr b.bind_expr
      | Ast.ELetFn (_, _, _, body, _) | Ast.ELam (_, body, _) -> augment_expr body
      | Ast.EIf (c, t, f, _) ->
        augment_expr c; augment_expr t; augment_expr f
      | Ast.EApp (f, args, _) ->
        augment_expr f; List.iter augment_expr args
      | _ -> ()
    in
    List.iter augment_decl user_decls;
    (* Build match_sites: use augmented data if available, else fall back to
       the span-only data from typecheck warnings *)
    let match_sites =
      List.map (fun sp ->
          match Hashtbl.find_opt match_span_tbl sp with
          | Some (missing, ms_matched_type, ms_ctor_sigs) ->
            { ms_span = sp; ms_missing_cases = missing; ms_matched_type; ms_ctor_sigs }
          | None ->
            (* Fallback: no AST info found — use the single case from typecheck *)
            let prefix = "Non-exhaustive pattern match — missing case: " in
            let plen = String.length prefix in
            let fallback_case =
              List.find_map (fun (d : March_errors.Errors.diagnostic) ->
                  if d.span = sp &&
                     String.length d.message >= plen &&
                     String.sub d.message 0 plen = prefix
                  then
                    Some (String.sub d.message plen (String.length d.message - plen))
                  else None
                ) (March_errors.Errors.sorted errors)
            in
            { ms_span = sp;
              ms_missing_cases = (match fallback_case with Some c -> [c] | None -> []);
              ms_matched_type = None;
              ms_ctor_sigs = [] }
        ) match_site_spans
    in
    (* Group match_sites by matched type for file-scope fix actions *)
    let type_matches =
      let tbl : (string, match_site list) Hashtbl.t = Hashtbl.create 4 in
      List.iter (fun (ms : match_site) ->
          match ms.ms_matched_type with
          | None -> ()
          | Some tname ->
            let existing = match Hashtbl.find_opt tbl tname with
              | Some xs -> xs | None -> []
            in
            Hashtbl.replace tbl tname (ms :: existing)
        ) match_sites;
      Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl []
    in
    (* Dead code analysis: unused private functions *)
    (* Collect all top-level function names and their visibility *)
    let fn_visibility : (string * Ast.visibility) list =
      List.filter_map (function
        | Ast.DFn (fn, _) -> Some (fn.fn_name.txt, fn.fn_vis)
        | _ -> None
      ) user_decls
    in
    (* Collect all function call names in an expression *)
    let rec collect_calls_expr (e : Ast.expr) acc =
      match e with
      | Ast.EApp (Ast.EVar n, args, _) ->
        let acc = n.txt :: acc in
        List.fold_left (fun a arg -> collect_calls_expr arg a) acc args
      | Ast.EApp (f, args, _) ->
        let acc = collect_calls_expr f acc in
        List.fold_left (fun a arg -> collect_calls_expr arg a) acc args
      | Ast.EVar n -> n.txt :: acc
      | Ast.ELam (_, body, _) -> collect_calls_expr body acc
      | Ast.ELetFn (_, _, _, body, _) -> collect_calls_expr body acc
      | Ast.EBlock (es, _) ->
        List.fold_left (fun a e -> collect_calls_expr e a) acc es
      | Ast.ELet (b, _) -> collect_calls_expr b.bind_expr acc
      | Ast.EMatch (subj, brs, _) ->
        let acc = collect_calls_expr subj acc in
        List.fold_left (fun a (br : Ast.branch) ->
            collect_calls_expr br.branch_body a) acc brs
      | Ast.EIf (c, t, f, _) ->
        collect_calls_expr c (collect_calls_expr t (collect_calls_expr f acc))
      | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) ->
        collect_calls_expr a (collect_calls_expr b acc)
      | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
        List.fold_left (fun a e -> collect_calls_expr e a) acc es
      | Ast.ERecord (fs, _) ->
        List.fold_left (fun a (_, e) -> collect_calls_expr e a) acc fs
      | Ast.ERecordUpdate (e, fs, _) ->
        List.fold_left (fun a (_, e2) -> collect_calls_expr e2 a)
          (collect_calls_expr e acc) fs
      | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
      | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) | Ast.EAssert (e, _) ->
        collect_calls_expr e acc
      | _ -> acc
    in
    (* Build set of all names called by each function *)
    let fn_calls_tbl : (string, string list) Hashtbl.t = Hashtbl.create 8 in
    List.iter (function
      | Ast.DFn (fn, _) ->
        let calls = List.fold_left (fun acc (cl : Ast.fn_clause) ->
            collect_calls_expr cl.fc_body acc
          ) [] fn.fn_clauses
        in
        Hashtbl.replace fn_calls_tbl fn.fn_name.txt calls
      | _ -> ()
    ) user_decls;
    (* Reachability from public roots (BFS) *)
    let private_names =
      List.filter_map (fun (name, vis) ->
          if vis = Ast.Private then Some name else None
        ) fn_visibility
    in
    let reachable = Hashtbl.create 8 in
    let queue = Queue.create () in
    (* Seed with public functions and "main" *)
    List.iter (fun (name, vis) ->
        if vis = Ast.Public || name = "main" then begin
          Hashtbl.replace reachable name ();
          Queue.push name queue
        end
      ) fn_visibility;
    while not (Queue.is_empty queue) do
      let name = Queue.pop queue in
      let callees = match Hashtbl.find_opt fn_calls_tbl name with
        | Some cs -> cs | None -> []
      in
      List.iter (fun callee ->
          if not (Hashtbl.mem reachable callee) then begin
            Hashtbl.replace reachable callee ();
            Queue.push callee queue
          end
        ) callees
    done;
    let unused_fns =
      List.filter (fun name ->
          not (Hashtbl.mem reachable name)
        ) private_names
    in
    (* Unreachable code after panic/unreachable_ in blocks.
       Collect spans of expressions following a diverging call. *)
    let rec diverges (e : Ast.expr) =
      match e with
      | Ast.EApp (Ast.EVar n, _, _)
        when n.txt = "panic" || n.txt = "panic_" || n.txt = "unreachable_" -> true
      | Ast.ELet (b, _) -> diverges b.bind_expr
      | Ast.EAnnot (e2, _, _) -> diverges e2
      | _ -> false
    in
    let dead_code_diags = ref [] in
    let rec scan_for_dead_code (e : Ast.expr) =
      match e with
      | Ast.EBlock (es, _) ->
        let rec scan_block = function
          | [] | [_] -> ()
          | hd :: ((_ :: _) as rest) ->
            if diverges hd then begin
              (* Everything after hd is unreachable *)
              List.iter (fun dead ->
                  let sp = span_of_expr dead in
                  if sp <> Ast.dummy_span &&
                     (sp.Ast.file = filename || sp.Ast.file = "" ||
                      sp.Ast.file = "<unknown>") then begin
                    let range = Pos.span_to_lsp_range sp in
                    let diag = Lsp.Types.Diagnostic.create
                      ~range
                      ~severity:Lsp.Types.DiagnosticSeverity.Warning
                      ~message:(`String "Unreachable code after diverging call")
                      ~source:"march"
                      ~code:(`String "unreachable_code")
                      ()
                    in
                    dead_code_diags := diag :: !dead_code_diags
                  end
                ) rest
            end else begin
              scan_for_dead_code hd;
              scan_block rest
            end
        in
        scan_block es
      | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) ->
        scan_for_dead_code body
      | Ast.ELet (b, _) -> scan_for_dead_code b.bind_expr
      | Ast.EMatch (subj, brs, _) ->
        scan_for_dead_code subj;
        List.iter (fun (br : Ast.branch) -> scan_for_dead_code br.branch_body) brs
      | Ast.EIf (c, t, f, _) ->
        scan_for_dead_code c; scan_for_dead_code t; scan_for_dead_code f
      | Ast.EApp (f, args, _) ->
        scan_for_dead_code f; List.iter scan_for_dead_code args
      | _ -> ()
    in
    List.iter (function
      | Ast.DFn (fn, _) ->
        List.iter (fun (cl : Ast.fn_clause) ->
            scan_for_dead_code cl.fc_body) fn.fn_clauses
      | Ast.DLet (_, b, _) -> scan_for_dead_code b.bind_expr
      | _ -> ()
    ) user_decls;
    (* Unused private function diagnostics *)
    let unused_fn_diags =
      List.filter_map (fun name ->
          match Hashtbl.find_opt def_map name with
          | None -> None
          | Some sp ->
            if sp.Ast.file <> filename && sp.Ast.file <> "" &&
               sp.Ast.file <> "<unknown>" then None
            else
              let range = Pos.span_to_lsp_range sp in
              Some (Lsp.Types.Diagnostic.create
                ~range
                ~severity:Lsp.Types.DiagnosticSeverity.Warning
                ~message:(`String (Printf.sprintf
                    "Private function `%s` is never used" name))
                ~source:"march"
                ~code:(`String "unused_private_fn")
                ())
        ) unused_fns
    in
    (* ---- Naming convention violations (P2.8) ---- *)
    let naming_acc = ref [] in
    let rec collect_naming_decl (d : Ast.decl) =
      match d with
      | Ast.DFn (fn, _) ->
        let name = fn.fn_name.txt in
        if is_camel_case name then
          naming_acc := { nv_name      = name;
                          nv_suggested = camel_to_snake name;
                          nv_span      = fn.fn_name.span;
                          nv_kind      = `Function } :: !naming_acc
      | Ast.DType (_, _n, _, _, _) -> ()
        (* Type names must start with uppercase (UPPER_IDENT) per the parser,
           so non-PascalCase type names cannot appear in valid March source. *)
      | Ast.DMod (_, _, decls, _) -> List.iter collect_naming_decl decls
      | _ -> ()
    in
    List.iter collect_naming_decl user_decls;
    let naming_violations = !naming_acc in
    (* ---- De Morgan rewrite sites (P3.10) ---- *)
    let demorgan_acc = ref [] in
    let rec collect_dm_expr (e : Ast.expr) =
      match e with
      (* !(a && b) or !(a || b) *)
      | Ast.EApp (Ast.EVar not_n,
                  [Ast.EApp (Ast.EVar op_n, [left; right], _)],
                  outer_sp)
        when not_n.txt = "not" && (op_n.txt = "&&" || op_n.txt = "||") ->
        demorgan_acc := {
          dm_span       = outer_sp;
          dm_form       = `NegatedBinop op_n.txt;
          dm_left_span  = span_of_expr left;
          dm_right_span = span_of_expr right;
        } :: !demorgan_acc;
        collect_dm_expr left;
        collect_dm_expr right
      (* !a && !b or !a || !b *)
      | Ast.EApp (Ast.EVar op_n,
                  [Ast.EApp (Ast.EVar not1, [left],  _);
                   Ast.EApp (Ast.EVar not2, [right], _)],
                  outer_sp)
        when (op_n.txt = "&&" || op_n.txt = "||")
             && not1.txt = "not" && not2.txt = "not" ->
        demorgan_acc := {
          dm_span       = outer_sp;
          dm_form       = `PairOfNegs op_n.txt;
          dm_left_span  = span_of_expr left;
          dm_right_span = span_of_expr right;
        } :: !demorgan_acc;
        collect_dm_expr left;
        collect_dm_expr right
      (* recurse into sub-expressions *)
      | Ast.EApp (f, args, _) ->
        collect_dm_expr f; List.iter collect_dm_expr args
      | Ast.EBlock (es, _) -> List.iter collect_dm_expr es
      | Ast.ELet (b, _) -> collect_dm_expr b.bind_expr
      | Ast.ELetFn (_, _, _, body, _) | Ast.ELam (_, body, _) ->
        collect_dm_expr body
      | Ast.EIf (c, t, f, _) ->
        collect_dm_expr c; collect_dm_expr t; collect_dm_expr f
      | Ast.EMatch (subj, brs, _) ->
        collect_dm_expr subj;
        List.iter (fun (br : Ast.branch) -> collect_dm_expr br.branch_body) brs
      | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) ->
        collect_dm_expr a; collect_dm_expr b
      | Ast.ETuple (es, _) | Ast.ECon (_, es, _) | Ast.EAtom (_, es, _) ->
        List.iter collect_dm_expr es
      | Ast.ERecord (fs, _) ->
        List.iter (fun (_, e2) -> collect_dm_expr e2) fs
      | Ast.ERecordUpdate (e2, fs, _) ->
        collect_dm_expr e2; List.iter (fun (_, e3) -> collect_dm_expr e3) fs
      | Ast.EField (e2, _, _) | Ast.EAnnot (e2, _, _)
      | Ast.EDbg (Some e2, _) | Ast.ESpawn (e2, _) | Ast.EAssert (e2, _) ->
        collect_dm_expr e2
      | _ -> ()
    in
    let rec collect_dm_decl (d : Ast.decl) =
      match d with
      | Ast.DFn (fn, _) ->
        List.iter (fun (cl : Ast.fn_clause) ->
            collect_dm_expr cl.fc_body) fn.fn_clauses
      | Ast.DLet (_, b, _) -> collect_dm_expr b.bind_expr
      | Ast.DMod (_, _, decls, _) -> List.iter collect_dm_decl decls
      | _ -> ()
    in
    List.iter collect_dm_decl user_decls;
    let demorgan_sites = !demorgan_acc in
    let diags =
      (Err.sorted errors |> List.filter_map (diag_to_lsp ~filename))
      @ !dead_code_diags
      @ unused_fn_diags
    in
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
      diagnostics      = diags;
      ctor_arities     = List.map (fun (name, ci) ->
                           (name, List.length ci.Tc.ci_arg_tys)) final_env.Tc.ctors;
      fold_ranges      = collect_fold_ranges raw_ast;
      annotation_sites = collect_annotation_sites raw_ast;
      unused_fns;
      type_matches;
      naming_violations;
      demorgan_sites }

(* ------------------------------------------------------------------ *)
(* Query helpers                                                       *)
(* ------------------------------------------------------------------ *)

(** Walk [TArrow] chain to collect stringified parameter types. *)
let rec unwrap_arrows (ty : Tc.ty) : string list * string =
  match ty with
  | Tc.TArrow (param, rest) ->
    let (more, ret) = unwrap_arrows rest in
    (Tc.pp_ty param :: more, ret)
  | _                       -> ([], Tc.pp_ty ty)

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
  (* Fallback: cursor may be sitting on a definition site itself (e.g. the
     function name in "fn foo()").  Check def_map by span. *)
  let var_name = match var_name with
    | Some _ -> var_name
    | None ->
      Hashtbl.fold (fun name sp found ->
          match found with
          | Some _ -> found
          | None ->
            if Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.def_map None
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
        let ty = match scheme with
          | Tc.Mono ty -> ty
          | Tc.Poly (_, _, ty) -> ty
        in
        let detail = Tc.pp_ty ty in
        let (params, _) = unwrap_arrows ty in
        if params = [] then
          Some (CompletionItem.create
            ~label:name ~kind:CompletionItemKind.Function ~detail ())
        else begin
          let parts = List.mapi
            (fun i p -> Printf.sprintf "${%d:%s}" (i + 1) p)
            params
          in
          let insert_text =
            Printf.sprintf "%s(%s)" name (String.concat ", " parts)
          in
          Some (CompletionItem.create
            ~label:name ~kind:CompletionItemKind.Function ~detail
            ~insertText:insert_text
            ~insertTextFormat:InsertTextFormat.Snippet ())
        end
    ) a.vars in
  let type_items = List.map (fun (name, _) ->
      CompletionItem.create ~label:name ~kind:CompletionItemKind.Class ()
    ) a.types in
  let ctor_items = List.map (fun (name, parent) ->
      let arity = Option.value ~default:0 (List.assoc_opt name a.ctor_arities) in
      if arity = 0 then
        CompletionItem.create
          ~label:name ~kind:CompletionItemKind.EnumMember ~detail:parent ()
      else begin
        let parts = List.init arity
          (fun i -> Printf.sprintf "${%d:arg%d}" (i + 1) (i + 1))
        in
        let insert_text =
          Printf.sprintf "%s(%s)" name (String.concat ", " parts)
        in
        CompletionItem.create
          ~label:name ~kind:CompletionItemKind.EnumMember ~detail:parent
          ~insertText:insert_text
          ~insertTextFormat:InsertTextFormat.Snippet ()
      end
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

(* ------------------------------------------------------------------ *)
(* Diagnostics-driven quickfix framework                              *)
(* ------------------------------------------------------------------ *)

(** A fix generator takes the analysis result and a diagnostic and returns
    zero or more code actions that would fix that diagnostic. *)
type fix_gen = t -> Lsp.Types.Diagnostic.t -> Lsp.Types.CodeAction.t list

(** Registry mapping diagnostic code strings to their fix generators.
    Register new fixes with [register_fix]. *)
let fix_registry : (string, fix_gen) Hashtbl.t = Hashtbl.create 8

let register_fix code gen =
  Hashtbl.replace fix_registry code gen

(** Run all registered fix generators for every diagnostic in [diags] and
    return the collected code actions. *)
let apply_fix_registry (a : t) (diags : Lsp.Types.Diagnostic.t list)
    : Lsp.Types.CodeAction.t list =
  List.concat_map (fun (diag : Lsp.Types.Diagnostic.t) ->
      let code = match diag.code with
        | Some (`String s) -> Some s
        | _ -> None
      in
      match code with
      | None -> []
      | Some c ->
        (match Hashtbl.find_opt fix_registry c with
         | None -> []
         | Some gen -> gen a diag)
    ) diags

(* The following diagnostic codes have registered fix generators.
   Inline code_actions_at handlers provide cursor-position accuracy for most;
   the registry entries serve as the extension point for tooling that queries
   fixes by code without a cursor position.  They return [] by default to
   avoid duplicating the inline logic — override via register_fix at any time. *)
let () =
  register_fix "non_exhaustive_match"  (fun _a _diag -> []);
  register_fix "unused_binding"        (fun _a _diag -> []);
  register_fix "unused_private_fn"     (fun _a _diag -> []);
  register_fix "unreachable_code"      (fun _a _diag -> []);
  register_fix "unused_import"         (fun _a _diag -> [])

(** Generate code actions relevant to the cursor position [line, character].
    Produces:
    - "Make `x` linear" for single-use non-linear let bindings at cursor.
    - "Add missing case: P" quickfix for non-exhaustive matches at cursor.
    - "Add all N missing cases" when multiple cases missing for one match.
    - "Fix all incomplete T matches in file" when multiple match sites.
    - "Add type annotation" for unannotated let bindings at cursor.
    - "Prefix with underscore / Remove unused binding" for unused variables.
    - Registry-driven fixes for any diagnostic with a registered code. *)
let code_actions_at (a : t) ~line ~character
    ?(diagnostics : Lsp.Types.Diagnostic.t list = [])
    ()
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
  (* Helper: derive a variable name from an AST surface type (for typed stubs). *)
  let name_from_ast_ty (ty : Ast.ty) =
    match ty with
    | Ast.TyCon (n, args) ->
      (match n.Ast.txt, args with
       | "Int",    []  -> "n"
       | "String", []  -> "s"
       | "Float",  []  -> "f"
       | "Bool",   []  -> "b"
       | "List",   _   -> "items"
       | "Option", _   -> "opt"
       | name, _ ->
         let lower = String.lowercase_ascii name in
         if lower = "" then "x" else String.sub lower 0 1)
    | Ast.TyVar v -> v.Ast.txt
    | _ -> "x"
  in
  (* Helper: deduplicate a list of names by appending numeric suffixes. *)
  let dedup_names names =
    let counts : (string, int) Hashtbl.t = Hashtbl.create 4 in
    List.iter (fun n ->
        Hashtbl.replace counts n
          (1 + (match Hashtbl.find_opt counts n with Some c -> c | None -> 0))
      ) names;
    let seen : (string, int) Hashtbl.t = Hashtbl.create 4 in
    List.map (fun n ->
        let total = match Hashtbl.find_opt counts n with Some c -> c | None -> 1 in
        if total = 1 then n
        else begin
          let idx = 1 + (match Hashtbl.find_opt seen n with Some c -> c | None -> 0) in
          Hashtbl.replace seen n idx;
          Printf.sprintf "%s%d" n idx
        end
      ) names
  in
  (* Helper: generate arm text for one missing case using typed stubs. *)
  let arm_text_for_case (ms : match_site) case =
    match List.assoc_opt case ms.ms_ctor_sigs with
    | None | Some [] ->
      Printf.sprintf "| %s ->\n    ?\n" case
    | Some arg_tys ->
      let base_names = List.map name_from_ast_ty arg_tys in
      let names = dedup_names base_names in
      Printf.sprintf "| %s(%s) ->\n    ?\n" case (String.concat ", " names)
  in
  (* Helper: given a match_site, compute the insert position just before 'end' *)
  let insert_pos_for_match_site (ms : match_site) =
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
      Some (Position.create ~line:!e_line ~character:!e_col)
  in
  let exhaustion_actions =
    List.concat_map (fun (ms : match_site) ->
        if not (Pos.span_contains ms.ms_span ~line ~character) then []
        else begin
          match insert_pos_for_match_site ms with
          | None -> []
          | Some insert_pos ->
            let range = Range.create ~start:insert_pos ~end_:insert_pos in
            let uri   = DocumentUri.of_path a.filename in
            (* Individual "Add missing case: X" actions — typed stubs via arm_text_for_case *)
            let individual_actions =
              List.map (fun case ->
                  let arm_text = arm_text_for_case ms case in
                  let edit = TextEdit.create ~range ~newText:arm_text in
                  let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
                  CodeAction.create
                    ~title:(Printf.sprintf "Add missing case: %s" case)
                    ~kind:CodeActionKind.QuickFix
                    ~edit:we
                    ()
                ) ms.ms_missing_cases
            in
            (* "Add all N missing cases" when there are multiple *)
            let bulk_action =
              if List.length ms.ms_missing_cases <= 1 then []
              else begin
                let arm_texts = List.map (arm_text_for_case ms) ms.ms_missing_cases in
                let combined = String.concat "" arm_texts in
                let edit = TextEdit.create ~range ~newText:combined in
                let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
                [CodeAction.create
                   ~title:(Printf.sprintf "Add all %d missing cases"
                             (List.length ms.ms_missing_cases))
                   ~kind:CodeActionKind.QuickFix
                   ~edit:we
                   ()]
              end
            in
            (* File-scope "Fix all incomplete T matches" when same type has
               multiple incomplete match sites *)
            let file_scope_action =
              match ms.ms_matched_type with
              | None -> []
              | Some tname ->
                let same_type_sites =
                  match List.assoc_opt tname a.type_matches with
                  | Some sites -> sites
                  | None -> []
                in
                if List.length same_type_sites <= 1 then []
                else begin
                  (* Build edits for all sites with missing cases *)
                  let all_edits = List.filter_map (fun (site : match_site) ->
                      if site.ms_missing_cases = [] then None
                      else
                        match insert_pos_for_match_site site with
                        | None -> None
                        | Some ipos ->
                          let r = Range.create ~start:ipos ~end_:ipos in
                          let arm_texts = List.map (arm_text_for_case site) site.ms_missing_cases in
                          Some (TextEdit.create ~range:r
                                  ~newText:(String.concat "" arm_texts))
                    ) same_type_sites
                  in
                  if all_edits = [] then []
                  else
                    let we = WorkspaceEdit.create
                      ~changes:[(uri, all_edits)] () in
                    [CodeAction.create
                       ~title:(Printf.sprintf
                           "Fix all incomplete `%s` matches in file" tname)
                       ~kind:CodeActionKind.RefactorRewrite
                       ~edit:we
                       ()]
                end
            in
            individual_actions @ bulk_action @ file_scope_action
        end
      ) a.match_sites
  in
  (* ---- Add-type-annotation actions (P1.7 enhanced) ---- *)
  (* Look up the smallest type_map entry containing a point. *)
  let type_at_point rhs_sp =
    let rhs_line = rhs_sp.Ast.start_line - 1 in
    let rhs_char = rhs_sp.Ast.start_col in
    let candidates = Hashtbl.fold (fun sp ty acc ->
        if Pos.span_contains sp ~line:rhs_line ~character:rhs_char
        then (sp, ty) :: acc else acc
      ) a.type_map []
    in
    match candidates with
    | [] -> None
    | _ ->
      let (_, ty) = List.fold_left (fun (bs, bt) (sp, ty) ->
          if Pos.span_smaller sp bs then (sp, ty) else (bs, bt)
        ) (List.hd candidates) (List.tl candidates)
      in
      Some ty
  in
  (* Scan forward from [from_ofs] to find the "do" keyword (word-boundary aware).
     Returns the byte offset of 'd' in "do", or None. Scans at most 400 chars. *)
  let find_do_after from_ofs =
    let src = a.src in
    let len = String.length src in
    let is_ident_char c =
      let k = Char.code c in
      (k >= 97 && k <= 122) || (k >= 65 && k <= 90) || k = 95 || (k >= 48 && k <= 57)
    in
    let limit = min len (from_ofs + 400) in
    let rec find i =
      if i + 2 > limit then None
      else if src.[i] = 'd' && src.[i+1] = 'o'
           && (i = 0 || not (is_ident_char src.[i-1]))
           && (i + 2 >= len || not (is_ident_char src.[i+2]))
      then Some i
      else find (i + 1)
    in
    find from_ofs
  in
  (* Convert a byte offset in a.src to (line, col) 0-indexed. *)
  let ofs_to_lsp_pos ofs =
    let e_line = ref 0 and e_col = ref 0 in
    let cl = ref 0 and cc = ref 0 in
    String.iteri (fun i _ch ->
        if i = ofs then begin e_line := !cl; e_col := !cc end;
        if a.src.[i] = '\n' then begin incr cl; cc := 0 end
        else incr cc
      ) a.src;
    Position.create ~line:!e_line ~character:!e_col
  in
  let make_annotation_action site =
    if not (Pos.span_contains site.as_name_span ~line ~character) then None
    else begin
      let uri = DocumentUri.of_path a.filename in
      match site.as_kind with

      | AnnLet ->
        (* Insert ": Type" after binding name *)
        (match type_at_point site.as_rhs_span with
         | None -> None
         | Some ty ->
           let ty_str = Tc.pp_ty ty in
           let insert_line = site.as_name_span.Ast.start_line - 1 in
           let insert_col  = site.as_name_span.Ast.end_col in
           let pos   = Position.create ~line:insert_line ~character:insert_col in
           let range = Range.create ~start:pos ~end_:pos in
           let edit  = TextEdit.create ~range ~newText:(": " ^ ty_str) in
           let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
           Some (CodeAction.create ~title:"Add type annotation"
                   ~kind:CodeActionKind.RefactorRewrite ~edit:we ()))

      | AnnFnReturn ->
        (* Look up fn type from type_map via fn_name.span; extract return type *)
        (match type_at_point site.as_rhs_span with
         | None -> None
         | Some ty ->
           let (_, ret_str) = unwrap_arrows ty in
           (* Find the "do" keyword after the fn name to determine insert position *)
           let fn_ofs =
             offset_of_pos a.src
               (site.as_name_span.Ast.start_line - 1)
               site.as_name_span.Ast.start_col
           in
           (match find_do_after fn_ofs with
            | None -> None
            | Some do_ofs ->
              let pos   = ofs_to_lsp_pos do_ofs in
              let range = Range.create ~start:pos ~end_:pos in
              let edit  = TextEdit.create ~range
                            ~newText:("-> " ^ ret_str ^ " ") in
              let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              Some (CodeAction.create ~title:"Add return type annotation"
                      ~kind:CodeActionKind.RefactorRewrite ~edit:we ())))

      | AnnFnParam ->
        (* Look up param type from type_map via param_name.span *)
        (match type_at_point site.as_rhs_span with
         | None -> None
         | Some ty ->
           let ty_str = Tc.pp_ty ty in
           let insert_line = site.as_name_span.Ast.start_line - 1 in
           let insert_col  = site.as_name_span.Ast.end_col in
           let pos   = Position.create ~line:insert_line ~character:insert_col in
           let range = Range.create ~start:pos ~end_:pos in
           let edit  = TextEdit.create ~range ~newText:(": " ^ ty_str) in
           let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
           Some (CodeAction.create ~title:"Add parameter type annotation"
                   ~kind:CodeActionKind.RefactorRewrite ~edit:we ()))
    end
  in
  let annotation_actions = List.filter_map make_annotation_action a.annotation_sites in
  (* Batch "Annotate all unannotated let bindings in file" action *)
  let batch_annotation_action =
    (* Only show when cursor is on an AnnLet site and there are 2+ AnnLet sites *)
    let cursor_on_ann_let =
      List.exists (fun (site : annotation_site) ->
          site.as_kind = AnnLet &&
          Pos.span_contains site.as_name_span ~line ~character
        ) a.annotation_sites
    in
    let let_sites = List.filter (fun (s : annotation_site) -> s.as_kind = AnnLet)
                      a.annotation_sites in
    if not cursor_on_ann_let || List.length let_sites < 2 then []
    else begin
      let uri = DocumentUri.of_path a.filename in
      let edits = List.filter_map (fun (site : annotation_site) ->
          match type_at_point site.as_rhs_span with
          | None -> None
          | Some ty ->
            let ty_str = Tc.pp_ty ty in
            let insert_line = site.as_name_span.Ast.start_line - 1 in
            let insert_col  = site.as_name_span.Ast.end_col in
            let pos   = Position.create ~line:insert_line ~character:insert_col in
            let range = Range.create ~start:pos ~end_:pos in
            Some (TextEdit.create ~range ~newText:(": " ^ ty_str))
        ) let_sites
      in
      if edits = [] then []
      else
        let we = WorkspaceEdit.create ~changes:[(uri, edits)] () in
        [CodeAction.create
           ~title:(Printf.sprintf "Annotate all %d unannotated bindings in file"
                     (List.length let_sites))
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:we ()]
    end
  in
  (* ---- Remove-unused-binding actions (from diagnostics context) ---- *)
  let extract_name_from_msg msg =
    (* "Unused variable `x`.\n..." → Some "x" *)
    let prefix = "Unused variable `" in
    let plen = String.length prefix in
    if String.length msg >= plen && String.sub msg 0 plen = prefix then
      let rest = String.sub msg plen (String.length msg - plen) in
      (match String.index_opt rest '`' with
       | Some i -> Some (String.sub rest 0 i)
       | None   -> None)
    else
      None
  in
  let diag_cursor_overlap (diag : Lsp.Types.Diagnostic.t) =
    let sl = diag.range.Lsp.Types.Range.start.line in
    let el = diag.range.Lsp.Types.Range.end_.line in
    let sc = diag.range.Lsp.Types.Range.start.character in
    let ec = diag.range.Lsp.Types.Range.end_.character in
    if line > sl && line < el then true
    else if line = sl && line = el then character >= sc && character < ec
    else if line = sl then character >= sc
    else if line = el then character < ec
    else false
  in
  let unused_binding_actions =
    List.concat_map (fun (diag : Lsp.Types.Diagnostic.t) ->
        let has_code = match diag.code with
          | Some (`String "unused_binding") -> true
          | _ -> false
        in
        if not has_code || not (diag_cursor_overlap diag) then []
        else
          let diag_line = diag.range.Lsp.Types.Range.start.line in
          let diag_char = diag.range.Lsp.Types.Range.start.character in
          let msg = match diag.message with `String s -> s | _ -> "" in
          (match extract_name_from_msg msg with
           | None -> []
           | Some name ->
             (* Prefix with underscore: insert "_" before the name *)
             let pfx_pos    = Position.create ~line:diag_line ~character:diag_char in
             let pfx_range  = Range.create ~start:pfx_pos ~end_:pfx_pos in
             let pfx_edit   = TextEdit.create ~range:pfx_range ~newText:"_" in
             let pfx_uri    = DocumentUri.of_path a.filename in
             let pfx_we     = WorkspaceEdit.create ~changes:[(pfx_uri, [pfx_edit])] () in
             let pfx_action = CodeAction.create
               ~title:(Printf.sprintf "Prefix with underscore `_%s`" name)
               ~kind:CodeActionKind.QuickFix
               ~edit:pfx_we
               () in
             (* Remove unused binding: look up consumption for full let span *)
             let remove_actions =
               List.filter_map (fun (c : consumption) ->
                   if c.con_name <> name || c.con_uses <> [] then None
                   else begin
                     let sp = c.con_def in
                     let del_start = Position.create
                       ~line:(sp.Ast.start_line - 1) ~character:0 in
                     let del_end   = Position.create
                       ~line:(sp.Ast.start_line) ~character:0 in
                     let del_range = Range.create ~start:del_start ~end_:del_end in
                     let del_edit  = TextEdit.create ~range:del_range ~newText:"" in
                     let del_uri   = DocumentUri.of_path a.filename in
                     let del_we    = WorkspaceEdit.create ~changes:[(del_uri, [del_edit])] () in
                     Some (CodeAction.create
                       ~title:(Printf.sprintf "Remove unused binding `%s`" name)
                       ~kind:CodeActionKind.QuickFix
                       ~edit:del_we
                       ())
                   end
                 ) a.consumption
             in
             (* P1.8: Assign to _: replace the name with just `_`, discarding result *)
             let assign_end_char = diag_char + String.length name in
             let assign_pos    = Position.create ~line:diag_line ~character:diag_char in
             let assign_end_ps = Position.create ~line:diag_line ~character:assign_end_char in
             let assign_range  = Range.create ~start:assign_pos ~end_:assign_end_ps in
             let assign_edit   = TextEdit.create ~range:assign_range ~newText:"_" in
             let assign_uri    = DocumentUri.of_path a.filename in
             let assign_we     = WorkspaceEdit.create ~changes:[(assign_uri, [assign_edit])] () in
             let assign_action = CodeAction.create
               ~title:"Assign to `_` (discard result)"
               ~kind:CodeActionKind.QuickFix
               ~edit:assign_we
               () in
             pfx_action :: assign_action :: remove_actions)
      ) diagnostics
  in
  (* ---- P2.10: Remove-unused-import actions ---- *)
  (* Helper: delete the line that contains [lsp_range_start].
     Produces a TextEdit that removes characters from column 0 of that line
     through column 0 of the next line (i.e. the whole line including newline). *)
  let delete_line (lsp_line : int) =
    let del_start = Position.create ~line:lsp_line ~character:0 in
    let del_end   = Position.create ~line:(lsp_line + 1) ~character:0 in
    let del_range = Range.create ~start:del_start ~end_:del_end in
    TextEdit.create ~range:del_range ~newText:""
  in
  (* Helper: given the byte offset of a name in a `use Mod.{a, b, c}` import,
     remove just that name (plus the adjacent comma/space) from the brace list.
     Returns a TextEdit, or None if the context cannot be parsed (fall back to
     whole-line deletion). *)
  let remove_name_from_import_list name_start_ofs name_len =
    let src = a.src in
    let src_len = String.length src in
    let name_end_ofs = name_start_ofs + name_len in
    (* Scan backwards to find ',' or '{' *)
    let rec scan_back i =
      if i < 0 then None
      else match src.[i] with
        | '{' -> Some (`OpenBrace i)
        | ',' -> Some (`CommaBefore i)
        | ' ' | '\t' -> scan_back (i - 1)
        | _ -> None
    in
    (* Scan forwards from name end to find ',' or '}' *)
    let rec scan_fwd i =
      if i >= src_len then None
      else match src.[i] with
        | '}' -> Some (`CloseBrace i)
        | ',' -> Some (`CommaAfter i)
        | ' ' | '\t' -> scan_fwd (i + 1)
        | _ -> None
    in
    match scan_back (name_start_ofs - 1), scan_fwd name_end_ofs with
    | Some (`OpenBrace _), Some (`CommaAfter comma_ofs) ->
      (* First name: remove "name, " (and trailing spaces) *)
      let del_end_ofs =
        let j = ref (comma_ofs + 1) in
        while !j < src_len && (src.[!j] = ' ' || src.[!j] = '\t') do incr j done;
        !j
      in
      let start_line = ref 0 and start_col = ref 0 in
      let cur_l = ref 0 and cur_c = ref 0 in
      String.iteri (fun i _ ->
          if i = name_start_ofs then begin start_line := !cur_l; start_col := !cur_c end;
          if src.[i] = '\n' then begin incr cur_l; cur_c := 0 end else incr cur_c
        ) src;
      let end_line = ref 0 and end_col = ref 0 in
      let cur_l2 = ref 0 and cur_c2 = ref 0 in
      String.iteri (fun i _ ->
          if i = del_end_ofs then begin end_line := !cur_l2; end_col := !cur_c2 end;
          if src.[i] = '\n' then begin incr cur_l2; cur_c2 := 0 end else incr cur_c2
        ) src;
      let r = Range.create
        ~start:(Position.create ~line:!start_line ~character:!start_col)
        ~end_:(Position.create ~line:!end_line ~character:!end_col) in
      Some (TextEdit.create ~range:r ~newText:"")
    | Some (`CommaBefore comma_ofs), _ ->
      (* Non-first name: remove ", name" (comma + optional spaces + name) *)
      let del_start_ofs = comma_ofs in
      let start_line = ref 0 and start_col = ref 0 in
      let cur_l = ref 0 and cur_c = ref 0 in
      String.iteri (fun i _ ->
          if i = del_start_ofs then begin start_line := !cur_l; start_col := !cur_c end;
          if src.[i] = '\n' then begin incr cur_l; cur_c := 0 end else incr cur_c
        ) src;
      let end_line = ref 0 and end_col = ref 0 in
      let cur_l2 = ref 0 and cur_c2 = ref 0 in
      String.iteri (fun i _ ->
          if i = name_end_ofs then begin end_line := !cur_l2; end_col := !cur_c2 end;
          if src.[i] = '\n' then begin incr cur_l2; cur_c2 := 0 end else incr cur_c2
        ) src;
      let r = Range.create
        ~start:(Position.create ~line:!start_line ~character:!start_col)
        ~end_:(Position.create ~line:!end_line ~character:!end_col) in
      Some (TextEdit.create ~range:r ~newText:"")
    | _ -> None
  in
  let unused_import_actions =
    List.concat_map (fun (diag : Lsp.Types.Diagnostic.t) ->
        let has_code = match diag.code with
          | Some (`String "unused_import") -> true
          | _ -> false
        in
        if not has_code || not (diag_cursor_overlap diag) then []
        else begin
          let uri   = DocumentUri.of_path a.filename in
          let msg   = match diag.message with `String s -> s | _ -> "" in
          let diag_lsp_line = diag.range.Lsp.Types.Range.start.line in
          let diag_lsp_char = diag.range.Lsp.Types.Range.start.character in
          (* Messages from warn_unused_imports:
             "Unused import: nothing from `X` is used." — whole-module import
             "Unused import `name` from `X`."           — specific name *)
          let is_whole_module =
            let prefix = "Unused import: nothing from" in
            let plen = String.length prefix in
            String.length msg >= plen && String.sub msg 0 plen = prefix
          in
          (* Extract the name from "Unused import `name` from `Mod`" messages *)
          let extract_import_name m =
            let prefix = "Unused import `" in
            let plen = String.length prefix in
            if String.length m >= plen && String.sub m 0 plen = prefix then
              let rest = String.sub m plen (String.length m - plen) in
              match String.index_opt rest '`' with
              | Some i -> Some (String.sub rest 0 i)
              | None -> None
            else None
          in
          if is_whole_module then
            (* Delete the entire import line *)
            let edit = delete_line diag_lsp_line in
            let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
            [CodeAction.create
               ~title:"Remove unused import"
               ~kind:CodeActionKind.QuickFix
               ~edit:we ()]
          else begin
            match extract_import_name msg with
            | None ->
              (* Fallback: delete whole line *)
              let edit = delete_line diag_lsp_line in
              let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              [CodeAction.create
                 ~title:"Remove unused import"
                 ~kind:CodeActionKind.QuickFix
                 ~edit:we ()]
            | Some name ->
              (* Specific name: try to remove just the name from the import list;
                 fall back to whole-line removal if context can't be parsed. *)
              let name_ofs = offset_of_pos a.src diag_lsp_line diag_lsp_char in
              let smart_edit = remove_name_from_import_list name_ofs (String.length name) in
              let edit = match smart_edit with
                | Some e -> e
                | None   -> delete_line diag_lsp_line
              in
              let we = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              [CodeAction.create
                 ~title:(Printf.sprintf "Remove unused import `%s`" name)
                 ~kind:CodeActionKind.QuickFix
                 ~edit:we ()]
          end
        end
      ) diagnostics
  in
  (* ---- P3.4: Introduce / Remove Debug.inspect ---- *)
  (* Helper: find the smallest type_map span that contains the cursor,
     returning (span, lsp_start_position, lsp_end_position). *)
  let innermost_expr_span_at ~line ~character =
    let candidates = Hashtbl.fold (fun sp _ acc ->
        if Pos.span_contains sp ~line ~character then sp :: acc
        else acc
      ) a.type_map []
    in
    match candidates with
    | [] -> None
    | _ ->
      let best = List.fold_left (fun best sp ->
          if Pos.span_smaller sp best then sp else best
        ) (List.hd candidates) (List.tl candidates)
      in
      Some best
  in
  (* "Wrap with inspect": wrap the innermost expression at cursor. *)
  let wrap_inspect_actions =
    match innermost_expr_span_at ~line ~character with
    | None -> []
    | Some sp ->
      (* Only offer if the span is within this file *)
      if sp.Ast.file <> a.filename && sp.Ast.file <> "" && sp.Ast.file <> "<unknown>"
      then []
      else begin
        (* Extract the source text of the expression for the label hint *)
        let expr_start_ofs = offset_of_pos a.src (sp.Ast.start_line - 1) sp.Ast.start_col in
        let expr_end_ofs   = offset_of_pos a.src (sp.Ast.end_line - 1) sp.Ast.end_col in
        let expr_text =
          if expr_end_ofs > expr_start_ofs && expr_end_ofs <= String.length a.src
          then String.sub a.src expr_start_ofs (expr_end_ofs - expr_start_ofs)
          else "expr"
        in
        (* Use first 20 chars of the expression as the label, sanitised *)
        let raw_label = if String.length expr_text > 20
                        then String.sub expr_text 0 20 ^ "..."
                        else expr_text in
        let label = String.concat "" (List.map (fun c ->
            if c = '"' || c = '\\' || c = '\n' || c = '\r' || c = '\t'
            then "_" else String.make 1 c) (List.init (String.length raw_label)
                                              (String.get raw_label))) in
        let uri    = DocumentUri.of_path a.filename in
        let s_line = sp.Ast.start_line - 1 in
        let s_col  = sp.Ast.start_col in
        let e_line = sp.Ast.end_line - 1 in
        let e_col  = sp.Ast.end_col in
        let prefix_range = Range.create
          ~start:(Position.create ~line:s_line ~character:s_col)
          ~end_:(Position.create ~line:s_line ~character:s_col) in
        let suffix_range = Range.create
          ~start:(Position.create ~line:e_line ~character:e_col)
          ~end_:(Position.create ~line:e_line ~character:e_col) in
        let prefix_edit = TextEdit.create ~range:prefix_range ~newText:"inspect(" in
        let suffix_edit = TextEdit.create ~range:suffix_range
            ~newText:(Printf.sprintf ", \"%s\")" label) in
        let we = WorkspaceEdit.create ~changes:[(uri, [prefix_edit; suffix_edit])] () in
        [CodeAction.create
           ~title:"Wrap with inspect"
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:we ()]
      end
  in
  (* "Remove inspect": detect `inspect(inner, "label")` around cursor and unwrap. *)
  let remove_inspect_actions =
    let src = a.src in
    let src_len = String.length src in
    let cursor_ofs = offset_of_pos src line character in
    (* Scan backwards for "inspect(" — look within same line *)
    let line_start_ofs = offset_of_pos src line 0 in
    let inspect_keyword = "inspect(" in
    let iklen = String.length inspect_keyword in
    (* Find last occurrence of "inspect(" before cursor on same line *)
    let inspect_start =
      let result = ref None in
      let i = ref (min cursor_ofs (src_len - iklen)) in
      while !i >= line_start_ofs do
        if !i + iklen <= src_len
           && String.sub src !i iklen = inspect_keyword then begin
          result := Some !i;
          i := -1
        end else
          decr i
      done;
      !result
    in
    match inspect_start with
    | None -> []
    | Some start_ofs ->
      (* Find matching closing paren, skipping nested parens *)
      let inner_start = start_ofs + iklen in
      let depth = ref 1 in
      let i = ref inner_start in
      while !i < src_len && !depth > 0 do
        (match src.[!i] with
         | '(' -> incr depth
         | ')' -> decr depth
         | _ -> ());
        if !depth > 0 then incr i else ()
      done;
      if !depth <> 0 then []
      else begin
        let close_ofs = !i in
        (* The inspect call spans [start_ofs, close_ofs] inclusive.
           Find the first argument (before the first top-level comma). *)
        let comma_ofs =
          let d = ref 0 in
          let c = ref None in
          let j = ref inner_start in
          while !j < close_ofs && !c = None do
            (match src.[!j] with
             | '(' | '[' | '{' -> incr d
             | ')' | ']' | '}' -> decr d
             | ',' when !d = 0 -> c := Some !j
             | _ -> ());
            if !c = None then incr j
          done;
          !c
        in
        let inner_end = match comma_ofs with
          | Some co -> co  (* inner expression is [inner_start, co) *)
          | None    -> close_ofs  (* no comma → whole inner part *)
        in
        (* Trim whitespace from inner expression boundaries *)
        let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
        let inner_s = ref inner_start in
        while !inner_s < inner_end && is_ws src.[!inner_s] do incr inner_s done;
        let inner_e = ref (inner_end - 1) in
        while !inner_e >= !inner_s && is_ws src.[!inner_e] do decr inner_e done;
        let inner_text =
          if !inner_e >= !inner_s
          then String.sub src !inner_s (!inner_e - !inner_s + 1)
          else ""
        in
        (* Compute LSP positions for the full inspect(…) range *)
        let mk_lsp_pos ofs =
          let l = ref 0 and c = ref 0 in
          let cl = ref 0 and cc = ref 0 in
          String.iteri (fun i _ ->
              if i = ofs then begin l := !cl; c := !cc end;
              if src.[i] = '\n' then begin incr cl; cc := 0 end else incr cc
            ) src;
          Position.create ~line:!l ~character:!c
        in
        let call_start_pos = mk_lsp_pos start_ofs in
        let call_end_pos   = mk_lsp_pos (close_ofs + 1) in
        let call_range     = Range.create ~start:call_start_pos ~end_:call_end_pos in
        let uri  = DocumentUri.of_path a.filename in
        let edit = TextEdit.create ~range:call_range ~newText:inner_text in
        let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
        [CodeAction.create
           ~title:"Remove inspect"
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:we ()]
      end
  in
  (* ---- Registry-driven fixes from diagnostics context ---- *)
  let registry_actions = apply_fix_registry a diagnostics in
  (* ---- Naming convention rename actions (P2.8) ---- *)
  let naming_actions =
    List.filter_map (fun (nv : naming_violation) ->
        if not (Pos.span_contains nv.nv_span ~line ~character) then None
        else begin
          let def_line = nv.nv_span.Ast.start_line - 1 in
          let def_char = nv.nv_span.Ast.start_col in
          let edits = rename_at a ~line:def_line ~character:def_char
                        ~new_name:nv.nv_suggested in
          if edits = [] then None
          else begin
            let uri = DocumentUri.of_path a.filename in
            let we  = WorkspaceEdit.create ~changes:[(uri, edits)] () in
            let kind_str = match nv.nv_kind with
              | `Function -> "function"
              | `Type -> "type"
            in
            Some (CodeAction.create
              ~title:(Printf.sprintf "Rename %s to `%s`" kind_str nv.nv_suggested)
              ~kind:CodeActionKind.RefactorRewrite
              ~edit:we
              ())
          end
        end
      ) a.naming_violations
  in
  (* ---- De Morgan rewrite actions (P3.10) ---- *)
  let src_slice (sp : Ast.span) =
    let s = offset_of_pos a.src (sp.Ast.start_line - 1) sp.Ast.start_col in
    let e = offset_of_pos a.src (sp.Ast.end_line   - 1) sp.Ast.end_col in
    let n = String.length a.src in
    if s >= 0 && e > s && e <= n then String.sub a.src s (e - s) else ""
  in
  let demorgan_actions =
    List.filter_map (fun (dm : demorgan_site) ->
        if not (Pos.span_contains dm.dm_span ~line ~character) then None
        else begin
          let ls = src_slice dm.dm_left_span in
          let rs = src_slice dm.dm_right_span in
          if ls = "" || rs = "" then None
          else begin
            let (title, new_text) = match dm.dm_form with
              | `NegatedBinop "&&" ->
                ("Apply De Morgan: !(a && b) \xe2\x86\x92 !(a) || !(b)",
                 Printf.sprintf "!(%s) || !(%s)" ls rs)
              | `NegatedBinop "||" ->
                ("Apply De Morgan: !(a || b) \xe2\x86\x92 !(a) && !(b)",
                 Printf.sprintf "!(%s) && !(%s)" ls rs)
              | `PairOfNegs "&&" ->
                ("Apply De Morgan: !a && !b \xe2\x86\x92 !(a || b)",
                 Printf.sprintf "!(%s || %s)" ls rs)
              | `PairOfNegs "||" ->
                ("Apply De Morgan: !a || !b \xe2\x86\x92 !(a && b)",
                 Printf.sprintf "!(%s && %s)" ls rs)
              | _ -> ("", "")
            in
            if title = "" then None
            else begin
              let range = Pos.span_to_lsp_range dm.dm_span in
              let edit  = TextEdit.create ~range ~newText:new_text in
              let uri   = DocumentUri.of_path a.filename in
              let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              Some (CodeAction.create
                ~title
                ~kind:CodeActionKind.RefactorRewrite
                ~edit:we
                ())
            end
          end
        end
      ) a.demorgan_sites
  in
  make_linear_actions @ exhaustion_actions @ annotation_actions
  @ batch_annotation_action @ unused_binding_actions @ unused_import_actions
  @ wrap_inspect_actions @ remove_inspect_actions
  @ naming_actions @ demorgan_actions
  @ registry_actions

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
