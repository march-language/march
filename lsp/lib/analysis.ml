(** Document analysis pipeline for march-lsp.

    Runs parse → desugar → typecheck on a buffer, then builds lookup
    tables that the hover / definition / completion / inlay-hint handlers
    can query. *)

(* The module aliases ([Lsp], [Ast], [Tc], [Err], [Pos]) and the analysis
   result types moved verbatim to [analysis_types.ml]; [include] re-exports
   all of them, so [Analysis.t] and every companion keep their names. *)
include Analysis_util  (* which itself re-exports [Analysis_types] *)

(* ------------------------------------------------------------------ *)
(* Stdlib loading                                                      *)
(* ------------------------------------------------------------------ *)

let find_stdlib_dir () =
  match Sys.getenv_opt "MARCH_STDLIB" with
  | Some dir when Sys.file_exists dir -> Some dir
  | _ ->
    let exe_dir = Filename.dirname Sys.executable_name in
    let candidates = [
      "stdlib";
      Filename.concat exe_dir "../stdlib";
      Filename.concat exe_dir "../../stdlib";
      Filename.concat exe_dir "../../../stdlib";
      Filename.concat exe_dir "../../../../stdlib";
      Filename.concat exe_dir "../share/march/stdlib";
      Filename.concat exe_dir "../share/march";
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
           (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
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

(* Route stdlib loading through the process-lifetime memo so the parse/desugar
   happens once, not on every keystroke. *)
let () =
  Stdlib_cache.set_stdlib_dir find_stdlib_dir;
  Stdlib_cache.set_loader load_stdlib

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
    (* Editors render diagnostics in a hover popover, and at least Zed shows
       only the FIRST LINE of the message there — which is where most people
       actually read a diagnostic. A note placed after a newline is therefore
       invisible exactly where it is most useful (it still shows in the
       project-diagnostics panel, which is a different, rarely-open view).
       The motivating case is the `Option`/`Result` field-access hint, whose
       entire purpose is to say how to unwrap: telling the reader only that
       their expression "is not a record" while hiding the fix defeats it.

       So flatten the message and its notes onto ONE line — clients soft-wrap
       it — including newlines *inside* a note, which would truncate at the
       same place. The CLI renderer reads [d.notes] directly and keeps its own
       indented multi-line layout, so this is a client-presentation change
       only. *)
    let flatten s =
      String.concat " "
        (List.filter (fun x -> x <> "")
           (List.map String.trim (String.split_on_char '\n' s)))
    in
    let message =
      if d.notes = [] then d.message
      else
        String.concat " "
          (flatten d.message :: List.map (fun n -> "note: " ^ flatten n) d.notes)
    in
    let code = Option.map (fun s -> `String s) d.code in
    let relatedInformation =
      let infos = List.filter_map (fun (lbl : Err.label) ->
        if lbl.lbl_span.Ast.start_line <= 0 then None
        else begin
          let lbl_file = lbl.lbl_span.Ast.file in
          let uri =
            if lbl_file = "" || lbl_file = "<unknown>" then
              Lsp.Types.DocumentUri.of_path filename
            else
              Lsp.Types.DocumentUri.of_path lbl_file
          in
          let location = Lsp.Types.Location.create
            ~uri ~range:(Pos.span_to_lsp_range lbl.lbl_span) in
          Some (Lsp.Types.DiagnosticRelatedInformation.create
            ~location ~message:lbl.lbl_message)
        end
      ) d.labels in
      if infos = [] then None else Some infos
    in
    Some (Lsp.Types.Diagnostic.create
      ~range
      ~severity:(severity_to_lsp d.severity)
      ~message:(`String message)
      ~source:"march"
      ?code
      ?relatedInformation
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

  | Ast.DType (_, name, _, typedef, _)
  | Ast.DAlwaysLinearType (_, name, _, typedef, _) ->
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

  | Ast.DTransitions (_, arms, _) ->
    List.iter (fun (a : Ast.transition) ->
      Hashtbl.replace use_map a.tr_via.span a.tr_via.txt
    ) arms

  | Ast.DUse _ | Ast.DAlias _ | Ast.DNeeds _ | Ast.DProofCap _ | Ast.DOpts _
  | Ast.DProtocol _ | Ast.DExtern _ | Ast.DSig _
  | Ast.DDeriving _ | Ast.DSatisfy _ | Ast.DDescribe _ -> ()

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

  | Ast.EField (base, field, _) ->
    (* Record the qualified name in use_map so that go-to-definition and
       find-references work for module-qualified access like File.with_lines
       or HttpServer.req_body.  Walk the base expression to build the full
       dot-separated prefix (handles chained access: A.B.fn). *)
    let rec module_prefix = function
      | Ast.EVar n            -> Some n.txt
      | Ast.ECon (n, [], _)   -> Some n.txt
      | Ast.EField (inner, f, _) ->
        (match module_prefix inner with
         | Some p -> Some (p ^ "." ^ f.txt)
         | None   -> None)
      | _ -> None
    in
    (match module_prefix base with
     | Some prefix ->
       Hashtbl.replace use_map field.span (prefix ^ "." ^ field.txt)
     | None -> ());
    collect_expr ~def_map ~use_map ~calls base

  | Ast.EAnnot (e, _, _) | Ast.EDbg (Some e, _)
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

  | Ast.ESigil (_, content, _) ->
    collect_expr ~def_map ~use_map ~calls content

  | Ast.ELetQ (p, r, c, _) | Ast.ELetStar (p, r, c, _) ->
    collect_pat_defs ~def_map ~use_map p;
    collect_expr ~def_map ~use_map ~calls r;
    collect_expr ~def_map ~use_map ~calls c

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
  | Ast.PatOr (ps, _) ->
    List.iter (collect_pat_defs ~def_map ~use_map) ps
  | Ast.PatWild _ | Ast.PatLit _ -> ()

(* ------------------------------------------------------------------ *)
(* Scope-aware local symbol resolution                                 *)
(* ------------------------------------------------------------------ *)
(* For function-LOCAL binders only (let-in-block, fn/lambda/let-fn      *)
(* params, match-arm binders) assign a unique id per binding and a      *)
(* use->id map resolved through a lexical scope stack. Top-level and    *)
(* stdlib names are left to the name-based def_map/use_map. This is what *)
(* makes go-to-def / references / rename scope-correct under shadowing. *)

type scoped_syms = {
  ss_defs    : (int, Ast.span) Hashtbl.t;
  ss_uses    : (Ast.span, int) Hashtbl.t;
  ss_id_uses : (int, Ast.span list) Hashtbl.t;
  ss_name    : (int, string) Hashtbl.t;
  ss_scope   : (int, Ast.span) Hashtbl.t;  (* binder id -> span it is visible in *)
}

let collect_scoped (decls : Ast.decl list) : scoped_syms =
  let ss_defs = Hashtbl.create 64 in
  let ss_uses = Hashtbl.create 64 in
  let ss_id_uses = Hashtbl.create 64 in
  let ss_name = Hashtbl.create 64 in
  let ss_scope = Hashtbl.create 64 in
  let next_id = ref 0 in
  (* Record the scope span each binder in [frame] is visible within. *)
  let set_scope frame sp =
    List.iter (fun (_, id) -> Hashtbl.replace ss_scope id sp) frame
  in
  (* A scope is a stack of frames (innermost first); each frame maps a name to
     the binder id currently in scope for it. *)
  let fresh (n : Ast.name) : string * int =
    incr next_id;
    let id = !next_id in
    Hashtbl.replace ss_defs id n.Ast.span;
    Hashtbl.replace ss_name id n.Ast.txt;
    (n.Ast.txt, id)
  in
  let resolve scope txt =
    let rec go = function
      | [] -> None
      | frame :: rest ->
        (match List.assoc_opt txt frame with Some id -> Some id | None -> go rest)
    in
    go scope
  in
  let record_use scope (n : Ast.name) =
    match resolve scope n.Ast.txt with
    | None -> ()  (* not a local: top-level/stdlib, handled by name maps *)
    | Some id ->
      Hashtbl.replace ss_uses n.Ast.span id;
      let prev = try Hashtbl.find ss_id_uses id with Not_found -> [] in
      Hashtbl.replace ss_id_uses id (n.Ast.span :: prev)
  in
  let rec pat_binders (pat : Ast.pattern) : (string * int) list =
    match pat with
    | Ast.PatVar n -> [ fresh n ]
    | Ast.PatAs (p, n, _) -> fresh n :: pat_binders p
    | Ast.PatCon (_, ps) | Ast.PatTuple (ps, _) -> List.concat_map pat_binders ps
    | Ast.PatAtom (_, ps, _) -> List.concat_map pat_binders ps
    | Ast.PatRecord (fields, _) ->
      List.concat_map (fun (_, p) -> pat_binders p) fields
    | Ast.PatOr (ps, _) -> List.concat_map pat_binders ps
    | Ast.PatWild _ | Ast.PatLit _ -> []
  in
  let param_binder (p : Ast.param) = fresh p.Ast.param_name in
  let fn_param_binders (fps : Ast.fn_param list) : (string * int) list =
    List.concat_map (fun fp ->
      match fp with
      | Ast.FPPat pat -> pat_binders pat
      | Ast.FPNamed p | Ast.FPDefault (p, _) -> [ param_binder p ]
    ) fps
  in
  let rec walk scope (e : Ast.expr) =
    match e with
    | Ast.EVar n -> record_use scope n
    | Ast.ELam (params, body, sp) ->
      let frame = List.map param_binder params in
      set_scope frame sp;
      walk (frame :: scope) body
    | Ast.ELetFn (name, params, _, body, sp) ->
      let fb = fresh name in
      let frame = List.map param_binder params in
      set_scope (fb :: frame) sp;
      walk (frame :: ([ fb ] :: scope)) body
    | Ast.EMatch (subj, branches, msp) ->
      walk scope subj;
      List.iter (fun (br : Ast.branch) ->
        let frame = pat_binders br.Ast.branch_pat in
        set_scope frame msp;  (* over-approx: visible across the match *)
        let scope' = frame :: scope in
        Option.iter (walk scope') br.Ast.branch_guard;
        walk scope' br.Ast.branch_body) branches
    | Ast.EBlock (exprs, bsp) ->
      (* Thread a growing frame so a `let` is visible to later siblings. *)
      let cur = ref [] in
      List.iter (fun e ->
        match e with
        | Ast.ELet (b, _) ->
          walk (!cur :: scope) b.Ast.bind_expr;   (* RHS sees prior, not itself *)
          let bs = pat_binders b.Ast.bind_pat in
          set_scope bs bsp;
          cur := bs @ !cur
        | Ast.ELetFn (name, params, _, body, sp) ->
          let fb = fresh name in
          set_scope [ fb ] bsp;                    (* name visible in the block *)
          cur := fb :: !cur;                       (* visible to siblings + self *)
          let frame = List.map param_binder params in
          set_scope frame sp;                      (* params only in its body *)
          walk (frame :: (!cur :: scope)) body
        | other -> walk (!cur :: scope) other
      ) exprs
    | Ast.ELet (b, _) -> walk scope b.Ast.bind_expr
    | Ast.EApp (f, args, _) -> walk scope f; List.iter (walk scope) args
    | Ast.ECon (_, args, _) -> List.iter (walk scope) args
    | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) -> List.iter (walk scope) es
    | Ast.ERecord (fields, _) -> List.iter (fun (_, e) -> walk scope e) fields
    | Ast.ERecordUpdate (e, fields, _) ->
      walk scope e; List.iter (fun (_, e2) -> walk scope e2) fields
    | Ast.EField (base, _, _) -> walk scope base
    | Ast.EAnnot (e, _, _) | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) -> walk scope e
    | Ast.EIf (c, e1, e2, _) -> walk scope c; walk scope e1; walk scope e2
    | Ast.ECond (arms, _) ->
      List.iter (fun (ce, be) -> walk scope ce; walk scope be) arms
    | Ast.EPipe (e1, e2, _) | Ast.ESend (e1, e2, _) -> walk scope e1; walk scope e2
    | Ast.EAssert (e, _) -> walk scope e
    | Ast.ESigil (_, content, _) -> walk scope content
    | Ast.ELetQ (p, r, c, _) | Ast.ELetStar (p, r, c, _) ->
      walk scope r;
      let bs = pat_binders p in
      walk (bs :: scope) c
    | Ast.ELit _ | Ast.EHole _ | Ast.EDbg (None, _) | Ast.EResultRef _ -> ()
  in
  let walk_clause (cl : Ast.fn_clause) =
    let frame = fn_param_binders cl.Ast.fc_params in
    set_scope frame cl.Ast.fc_span;
    let scope = [ frame ] in
    Option.iter (walk scope) cl.Ast.fc_guard;
    walk scope cl.Ast.fc_body
  in
  let rec walk_decl (decl : Ast.decl) =
    match decl with
    | Ast.DFn (fn, _) -> List.iter walk_clause fn.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> walk [] b.Ast.bind_expr
    | Ast.DActor (_, _, adef, _) ->
      walk [] adef.Ast.actor_init;
      List.iter (fun (h : Ast.actor_handler) -> walk [] h.Ast.ah_body)
        adef.Ast.actor_handlers
    | Ast.DMod (_, _, decls, _) -> List.iter walk_decl decls
    | Ast.DImpl (impl, _) ->
      List.iter (fun (_, (fn : Ast.fn_def)) -> List.iter walk_clause fn.Ast.fn_clauses)
        impl.Ast.impl_methods
    | Ast.DApp (app, _) ->
      walk [] app.Ast.app_body;
      Option.iter (walk []) app.Ast.app_on_start;
      Option.iter (walk []) app.Ast.app_on_stop
    | Ast.DTest (tdef, _) -> walk [] tdef.Ast.test_body
    | Ast.DSetup (body, _) | Ast.DSetupAll (body, _) -> walk [] body
    | _ -> ()
  in
  List.iter walk_decl decls;
  { ss_defs; ss_uses; ss_id_uses; ss_name; ss_scope }

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

(** Names whose binding is linear or affine {i according to the type system}.

    This is the source for the [linear]/[affine] semantic-token modifiers.

    It deliberately does NOT use [build_consumption_map]'s use counts. Use
    counts answer "how many times does this name appear?", which is a different
    question from "is this value linear?" — an ordinary [let x = 1] mentioned
    once is not linear, and painting it [linear] in the editor misrepresents
    the exact guarantee a reader is trying to verify. Linearity here comes from
    the three places the language actually states it:

    - an explicit [linear] / [affine] qualifier on a binding or parameter
      ([bind_lin] / [param_lin]),
    - a [linear T] / [affine T] type annotation ([TyLinear]),
    - a type declared [always_linear type], which makes every binding of that
      type linear with no per-site annotation ([always_linear] argument).

    A binding whose linearity is only {i inferred} (unannotated, of a type not
    declared always-linear) is not reported. That is a deliberate
    false-negative: under-reporting leaves a token uncolored, while
    over-reporting asserts a guarantee the compiler never made. *)
let build_linearity_map (decls : Ast.decl list) (always_linear : string list)
  : (string * Ast.linearity) list =
  let result = ref [] in
  let rec lin_of_ty (t : Ast.ty) : Ast.linearity option =
    match t with
    | Ast.TyLinear (Ast.Unrestricted, inner) -> lin_of_ty inner
    | Ast.TyLinear (l, _) -> Some l
    | Ast.TyCon (n, _) when List.mem n.Ast.txt always_linear -> Some Ast.Linear
    | Ast.TyRefine (inner, _, _) -> lin_of_ty inner
    | _ -> None
  in
  (* An explicit qualifier wins; otherwise fall back to the annotation. *)
  let resolve (lin : Ast.linearity) (ty : Ast.ty option) : Ast.linearity option =
    match lin with
    | Ast.Linear | Ast.Affine -> Some lin
    | Ast.Unrestricted -> (match ty with Some t -> lin_of_ty t | None -> None)
  in
  let record name lin = result := (name, lin) :: !result in
  let rec pat_names (p : Ast.pattern) acc =
    match p with
    | Ast.PatVar n -> n.Ast.txt :: acc
    | Ast.PatAs (p2, n, _) -> n.Ast.txt :: pat_names p2 acc
    | Ast.PatTuple (ps, _) | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) ->
      List.fold_left (fun a p -> pat_names p a) acc ps
    | Ast.PatRecord (fs, _) ->
      List.fold_left (fun a (_, p) -> pat_names p a) acc fs
    | _ -> acc
  in
  let check_binding (b : Ast.binding) =
    match resolve b.Ast.bind_lin b.Ast.bind_ty with
    | Some l -> List.iter (fun n -> record n l) (pat_names b.Ast.bind_pat [])
    | None -> ()
  in
  let check_param (p : Ast.param) =
    match resolve p.Ast.param_lin p.Ast.param_ty with
    | Some l -> record p.Ast.param_name.Ast.txt l
    | None -> ()
  in
  (* A clause parameter is a bare pattern (no type to read), a named param, or
     a named param with a default — only the latter two can carry linearity. *)
  let check_fn_param (fp : Ast.fn_param) =
    match fp with
    | Ast.FPNamed p | Ast.FPDefault (p, _) -> check_param p
    | Ast.FPPat _ -> ()
  in
  let rec scan_expr (e : Ast.expr) =
    match e with
    | Ast.ELet (b, _) -> check_binding b; scan_expr b.Ast.bind_expr
    | Ast.EBlock (es, _) -> List.iter scan_expr es
    | Ast.ELam (ps, body, _) -> List.iter check_param ps; scan_expr body
    | Ast.ELetFn (_, ps, _, body, _) -> List.iter check_param ps; scan_expr body
    | Ast.EMatch (subj, brs, _) ->
      scan_expr subj;
      List.iter (fun (br : Ast.branch) -> scan_expr br.Ast.branch_body) brs
    | Ast.EApp (f, args, _) -> scan_expr f; List.iter scan_expr args
    | Ast.EIf (c, t, f, _) -> scan_expr c; scan_expr t; scan_expr f
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> scan_expr a; scan_expr b
    | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
    | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) -> scan_expr e
    | _ -> ()
  in
  let rec scan_decls ds =
    List.iter (function
      | Ast.DFn (fn, _) ->
        List.iter (fun (cl : Ast.fn_clause) ->
            List.iter check_fn_param cl.Ast.fc_params;
            scan_expr cl.Ast.fc_body)
          fn.Ast.fn_clauses
      | Ast.DLet (_, b, _) -> check_binding b; scan_expr b.Ast.bind_expr
      | Ast.DMod (_, _, inner, _) -> scan_decls inner
      | _ -> ()
    ) ds
  in
  scan_decls decls;
  !result

(** Variable-name spans of bindings eligible for FBIP in-place reuse: a value
    binding whose right-hand side allocates (constructor / record / tuple) and
    that is consumed exactly once in its scope. The single last use lets Perceus
    reuse the cell in place. This is the AST-level heuristic; the precise signal
    is Perceus's [EReuse] (TIR pass, [tir_fn_insight.tfi_reuse_ops]). *)
let build_reuse_hints (decls : Ast.decl list) : Ast.span list =
  let result = ref [] in
  let is_alloc = function
    | Ast.ECon (_, _ :: _, _) | Ast.ERecord _
    | Ast.ETuple _ | Ast.ERecordUpdate _ -> true
    | _ -> false
  in
  let rec scan_expr (e : Ast.expr) =
    match e with
    | Ast.ELet (b, _) -> scan_expr b.bind_expr
    | Ast.EBlock (es, _) ->
      let rec scan_block = function
        | [] -> ()
        | Ast.ELet (b, _) :: rest ->
          (match b.bind_pat with
           | Ast.PatVar n when is_alloc b.bind_expr ->
             let rest_expr = match rest with
               | [e] -> e
               | []  -> Ast.ELit (Ast.LitBool false, Ast.dummy_span)
               | es  -> Ast.EBlock (es, Ast.dummy_span)
             in
             if List.length (find_uses n.txt rest_expr []) = 1 then
               result := n.span :: !result
           | _ -> ());
          scan_expr b.bind_expr;
          scan_block rest
        | e :: rest -> scan_expr e; scan_block rest
      in
      scan_block es
    | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> scan_expr body
    | Ast.EMatch (subj, brs, _) ->
      scan_expr subj;
      List.iter (fun (br : Ast.branch) -> scan_expr br.branch_body) brs
    | Ast.EApp (f, args, _) -> scan_expr f; List.iter scan_expr args
    | Ast.EIf (c, t, f, _) -> scan_expr c; scan_expr t; scan_expr f
    | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) -> scan_expr x; scan_expr y
    | _ -> ()
  in
  List.iter (function
    | Ast.DFn (fn, _) ->
      List.iter (fun (cl : Ast.fn_clause) -> scan_expr cl.fc_body) fn.fn_clauses
    | Ast.DLet (_, b, _) -> scan_expr b.bind_expr
    | _ -> ()
  ) decls;
  !result

(** Build the per-file call graph: one node per top-level function, recording
    its name/full spans and every (callee, call-site) within its body. *)
let build_call_graph (decls : Ast.decl list) : cg_node list =
  let collect_calls (body : Ast.expr) : (string * Ast.span) list =
    let acc = ref [] in
    let rec go (e : Ast.expr) =
      (match e with
       | Ast.EApp (Ast.EVar n, _, sp) -> acc := (n.Ast.txt, sp) :: !acc
       | _ -> ());
      match e with
      | Ast.EApp (f, args, _) -> go f; List.iter go args
      | Ast.ELet (b, _) -> go b.Ast.bind_expr
      | Ast.EBlock (es, _) -> List.iter go es
      | Ast.EMatch (subj, brs, _) ->
        go subj; List.iter (fun (br : Ast.branch) -> go br.Ast.branch_body) brs
      | Ast.EIf (c, t, f, _) -> go c; go t; go f
      | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) -> go x; go y
      | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
        List.iter go es
      | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> go e) fs
      | Ast.ERecordUpdate (e, fs, _) -> go e; List.iter (fun (_, e) -> go e) fs
      | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
      | Ast.EDbg (Some e, _) | Ast.EAssert (e, _) -> go e
      | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> go b
      | _ -> ()
    in
    go body; List.rev !acc
  in
  let nodes = ref [] in
  let rec scan (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, dspan) ->
      let calls =
        List.concat_map (fun (cl : Ast.fn_clause) -> collect_calls cl.Ast.fc_body)
          fn.Ast.fn_clauses
      in
      nodes := { cg_name = fn.Ast.fn_name.Ast.txt;
                 cg_name_span = fn.Ast.fn_name.Ast.span;
                 cg_full_span = dspan;
                 cg_calls = calls } :: !nodes
    | Ast.DMod (_, _, ds, _) -> List.iter scan ds
    | _ -> ()
  in
  List.iter scan decls;
  !nodes

(** Collect `use`/`import` declarations (including those in nested modules). *)
let build_imports (decls : Ast.decl list) : import_info list =
  let rec scan (d : Ast.decl) =
    match d with
    | Ast.DUse (u, sp) ->
      let m = String.concat "." (List.map (fun (n : Ast.name) -> n.Ast.txt) u.Ast.use_path) in
      let sel = match u.Ast.use_sel with
        | Ast.UseAll       -> ISAll
        | Ast.UseSingle    -> ISSingle
        | Ast.UseNames ns  -> ISNames ns
        | Ast.UseExcept ns -> ISExcept (List.map (fun (n : Ast.name) -> n.Ast.txt) ns)
      in
      [ { ii_module = m; ii_sel = sel; ii_span = sp } ]
    | Ast.DMod (_, _, ds, _) -> List.concat_map scan ds
    | _ -> []
  in
  List.concat_map scan decls

(** Index importable modules → their member short-names, derived from the
    qualified entries (`Mod.member`) the typecheck env already holds for the
    stdlib and deps. This is the candidate pool for auto-import. *)
let module_index_of_vars (vars : (string * 'a) list) : (string * string list) list =
  let tbl = Hashtbl.create 256 in
  List.iter (fun (key, _) ->
      match String.rindex_opt key '.' with
      | Some d when d > 0 && d < String.length key - 1 ->
        let short = String.sub key (d + 1) (String.length key - d - 1) in
        if short.[0] >= 'a' && short.[0] <= 'z' then begin
          let m = String.sub key 0 d in
          Hashtbl.replace tbl m
            (short :: (try Hashtbl.find tbl m with Not_found -> []))
        end
      | _ -> ()
    ) vars;
  Hashtbl.fold (fun k v acc -> (k, List.sort_uniq compare v) :: acc) tbl []

(** True when [module_] already makes [name] available as a bare identifier. *)
let module_imports_bare (imports : import_info list) ~module_ ~name : bool =
  List.exists (fun ii ->
      ii.ii_module = module_ &&
      match ii.ii_sel with
      | ISAll -> true
      | ISExcept ns -> not (List.mem name ns)
      | ISNames ns -> List.exists (fun (n : Ast.name) -> n.Ast.txt = name) ns
      | ISSingle -> false
    ) imports

(* ------------------------------------------------------------------ *)
(* Fold-range and annotation-site collection                          *)
(* ------------------------------------------------------------------ *)

(** Walk an AST module collecting folding ranges.
    Returns (start_line_0idx, end_line_0idx, kind) triples. *)
let collect_fold_ranges (m : Ast.module_) : (int * int * string) list =
  let ranges = ref [] in
  let add (sp : Ast.span) kind =
    let sl = sp.Ast.start_line - 1 in
    let el = sp.Ast.end_line   - 1 in
    if el > sl then ranges := (sl, el, kind) :: !ranges
  in
  (* A run of imports, or a run of capability declarations, folds as one unit.
     These are the two kinds that appear as long homogeneous blocks at the top
     of a file, and they are exactly the runs `march fmt` keeps tight.
     Returns the run kind and the declaration's own span. *)
  let compact_group = function
    | Ast.DUse (_, sp) | Ast.DAlias (_, sp) -> Some (`Imports, sp)
    | Ast.DNeeds (_, sp) | Ast.DProofCap (_, _, sp) | Ast.DOpts (_, sp) ->
      Some (`Caps, sp)
    | _ -> None
  in
  (* Add one range per maximal run of same-kind declarations.  A lone import
     has nothing to collapse, and `add` drops it anyway since a one-line run
     has end_line = start_line. *)
  let add_compact_runs decls =
    let flush = function
      | Some (k, first, last) ->
        add { first with Ast.end_line = last.Ast.end_line }
          (match k with `Imports -> "imports" | `Caps -> "region")
      | None -> ()
    in
    let run =
      List.fold_left (fun run decl ->
          match compact_group decl, run with
          (* Extending the current run: keep its start, move its end. *)
          | Some (k, sp), Some (k', first, _) when k = k' -> Some (k, first, sp)
          (* Anything else ends the run; a compact decl starts a new one. *)
          | g, _ ->
            flush run;
            (match g with Some (k, sp) -> Some (k, sp, sp) | None -> None))
        None decls
    in
    flush run
  in
  let rec go_decls decls = add_compact_runs decls; List.iter go_decl decls
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
(* ------------------------------------------------------------------ *)
(* Performance insights (Phase 1, AST level)                          *)
(* ------------------------------------------------------------------ *)

(* A ClosureCapture insight fires only when the SAME genuine capture set (≥2
   values) is shared by ≥2 closures in [body] — a clump that travels together,
   which one shared record genuinely de-duplicates. A lone large closure no
   longer warns. *)
let closure_capture_check is_global (body : Ast.expr) acc =
  let groups : (string, string list * Ast.span list) Hashtbl.t = Hashtbl.create 8 in
  List.iter (fun (sp, _body_sp, caps) ->
      let key = String.concat "\000" caps in
      let (_, sps) = try Hashtbl.find groups key with Not_found -> (caps, []) in
      Hashtbl.replace groups key (caps, sp :: sps))
    (collect_lambda_captures is_global body);
  Hashtbl.fold (fun _ (caps, spans) acc ->
      if List.length spans >= 2 then begin
        let m = List.length spans in
        let names = String.concat ", " (List.map (fun s -> "`" ^ s ^ "`") caps) in
        let msg = Printf.sprintf
          "These %d values (%s) are captured together by %d closures. Group them into a record so the clump travels as one value."
          (List.length caps) names m
        in
        List.fold_left (fun acc sp ->
            { pi_span = sp;
              pi_kind = ClosureCapture { pi_count = List.length caps; pi_names = caps };
              pi_message = msg } :: acc)
          acc spans
      end else acc)
    groups acc

(** True when [ty] is a heap-allocated type that will be deep-copied on send
    (i.e., not a linear/affine value and not a scalar). *)
let is_complex_ty (ty : Tc.ty) =
  match Tc.repr ty with
  | Tc.TLin _ -> false          (* linear/affine: zero-copy ownership transfer *)
  | Tc.TCon ("Int",   []) | Tc.TCon ("Bool",  [])
  | Tc.TCon ("Float", []) | Tc.TCon ("Unit",  [])
  | Tc.TCon ("Char",  []) -> false
  | Tc.TCon _ | Tc.TTuple _ | Tc.TRecord _ -> true
  | _ -> false

let describe_ty (ty : Tc.ty) =
  match Tc.repr ty with
  | Tc.TCon (name, []) -> name
  | Tc.TCon (name, _)  -> name ^ "(...)"
  | Tc.TTuple _        -> "tuple"
  | Tc.TRecord _       -> "record"
  | other              -> Tc.pp_ty other

(** Walk [e] collecting [ActorSendCopy] insights for [send()] calls whose
    message argument is a non-linear complex type. *)
let rec send_copy_check (type_map : (Ast.span, Tc.ty) Hashtbl.t) (e : Ast.expr) acc =
  match e with
  | Ast.ESend (pid, msg, sp) ->
    let acc = send_copy_check type_map pid acc in
    let acc = send_copy_check type_map msg acc in
    let msg_sp = span_of_expr msg in
    (match Hashtbl.find_opt type_map msg_sp with
     | None -> acc
     | Some ty when not (is_complex_ty ty) -> acc
     | Some ty ->
       let value_desc = match msg with
         | Ast.EVar n -> "`" ^ n.txt ^ "`"
         | _          -> "the message value"
       in
       let ty_str = describe_ty ty in
       let msg_text = Printf.sprintf
         "%s will be deep-copied when sent (type: `%s`).\n\nIf you no longer need it after this point, declare it `linear` to transfer ownership instead of copying:\n\n    send(pid, linear %s)"
         value_desc ty_str ty_str
       in
       { pi_span    = sp;
         pi_kind    = ActorSendCopy { pi_value_desc = value_desc; pi_ty = ty_str };
         pi_message = msg_text } :: acc)
  | Ast.EApp (f, args, _) ->
    let acc = send_copy_check type_map f acc in
    List.fold_left (fun a e -> send_copy_check type_map e a) acc args
  | Ast.EBlock (es, _) ->
    List.fold_left (fun a e -> send_copy_check type_map e a) acc es
  | Ast.ELet (b, _) -> send_copy_check type_map b.Ast.bind_expr acc
  | Ast.ELetFn (_, _, _, body, _) | Ast.ELam (_, body, _) ->
    send_copy_check type_map body acc
  | Ast.EIf (c, t, f, _) ->
    send_copy_check type_map c
      (send_copy_check type_map t (send_copy_check type_map f acc))
  | Ast.EMatch (subj, brs, _) ->
    let acc = send_copy_check type_map subj acc in
    List.fold_left (fun a (br : Ast.branch) ->
        send_copy_check type_map br.Ast.branch_body a) acc brs
  | Ast.EPipe (a, b, _) ->
    send_copy_check type_map a (send_copy_check type_map b acc)
  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
    List.fold_left (fun a e -> send_copy_check type_map e a) acc es
  | Ast.ERecord (fs, _) ->
    List.fold_left (fun a (_, e) -> send_copy_check type_map e a) acc fs
  | Ast.ERecordUpdate (e, fs, _) ->
    List.fold_left (fun a (_, e2) -> send_copy_check type_map e2 a)
      (send_copy_check type_map e acc) fs
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
  | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) | Ast.EAssert (e, _) ->
    send_copy_check type_map e acc
  | _ -> acc

(** The reason string used when a call is blocked by a constructor wrapping it.
    Constructed here rather than inline because [tco_check]'s advice depends on
    recognising this case: a constructor-wrapped call is the tail-recursion-
    modulo-cons shape the compiler turns into a loop, so telling the user to
    rewrite it with an accumulator would be advice against what the compiler
    already does — and against how the stdlib producers are written. *)
let ctor_blocks name = Printf.sprintf "constructor `%s` wraps it" name

let is_ctor_blocked (b : string) =
  String.length b > 12 && String.sub b 0 12 = "constructor "

(** Was the call blocked by a short-circuit-shaped boolean operator? Those get
    different advice than the generic accumulator suggestion — see the message
    site in [tco_check]. *)
let is_boolop_blocked (b : string) =
  let has sub =
    let n = String.length sub and m = String.length b in
    let rec go i = i + n <= m && (String.sub b i n = sub || go (i + 1)) in
    go 0
  in
  has "`||`" || has "`&&`"

(** Walk [e] looking for calls to [fn_name] that are not in tail position.
    [blocking] is [None] when the expression is in tail position, or
    [Some description] when there is pending work after it returns. *)
let rec tco_check (fn_name : string) (blocking : string option) (e : Ast.expr) acc =
  match e with
  (* Self-recursive call *)
  | Ast.EApp (Ast.EVar n, args, sp) when n.txt = fn_name ->
    let acc =
      match blocking with
      | None -> acc   (* tail position — no stack growth *)
      | Some b ->
        let msg =
          if is_ctor_blocked b then
            Printf.sprintf
              "This recursive call is not in tail position — %s, so the stack grows by one frame per call and deep input can overflow it. TRMC can turn a call wrapped in a constructor into a loop, but it is OFF BY DEFAULT; enable it with `--trmc`. (This message used to say no rewrite was needed — it was wrong: the loop is not automatic.)"
              b
          else if is_boolop_blocked b then
            (* `&&`/`||` are STRICT in March (specs/lang/core-march.md 4.4.1):
               both operands are always evaluated, so the call really is not in
               tail position and the checker is right. But "use an accumulator"
               is the wrong fix for a branching search — there is no work to
               move before the call. Rewriting `a || b` as `if a do true else b
               end` puts the right-hand call in genuine tail position (an `if`
               branch inherits tail position) and skips it when the left side
               already decides the answer. *)
            Printf.sprintf
              "This recursive call is not in tail position — %s, so the stack grows by one frame per call. `&&`/`||` are strict in March: both sides are always evaluated. Rewrite `a || b` as `if a do true else b end` (and `a && b` as `if a do b else false end`) to put the right-hand call in tail position."
              b
          else
            Printf.sprintf
              "This recursive call is not in tail position — %s, so the stack grows by one frame per call.\n\nRewrite using an accumulator parameter to move the work before the recursive call."
              b
        in
        { pi_span    = sp;
          pi_kind    = NonTailCall { pi_fn_name = fn_name; pi_blocking = b };
          pi_message = msg } :: acc
    in
    (* The args themselves are not in tail position *)
    List.fold_left (fun a arg ->
        tco_check fn_name (Some "it is passed as an argument") arg a
      ) acc args

  (* Binary operator — args are not in tail position *)
  | Ast.EApp (Ast.EVar op, ([_; _] as args), _) when is_march_operator op.txt ->
    let b = Printf.sprintf "`%s` uses the result" op.txt in
    List.fold_left (fun a arg -> tco_check fn_name (Some b) arg a) acc args

  (* Any other function call — args are not in tail position *)
  | Ast.EApp (f, args, _) ->
    let acc = tco_check fn_name (Some "an outer call uses it") f acc in
    List.fold_left (fun a arg ->
        tco_check fn_name (Some "an outer call uses it") arg a
      ) acc args

  (* Block: only the last expression inherits tail ctx *)
  | Ast.EBlock (es, _) ->
    let rec go acc = function
      | []       -> acc
      | [e]      -> tco_check fn_name blocking e acc
      | e :: rest ->
        let acc = tco_check fn_name (Some "it is not the last expression") e acc in
        go acc rest
    in
    go acc es

  (* Let binding RHS is never in tail position *)
  | Ast.ELet (b, _) ->
    tco_check fn_name (Some "it is bound to a variable, not returned") b.Ast.bind_expr acc

  (* If: branches inherit tail ctx; condition is not tail *)
  | Ast.EIf (cond, t, f, _) ->
    let acc = tco_check fn_name (Some "it is the condition") cond acc in
    let acc = tco_check fn_name blocking t acc in
    tco_check fn_name blocking f acc

  (* Match: arms inherit tail ctx; scrutinee is not tail *)
  | Ast.EMatch (subj, branches, _) ->
    let acc = tco_check fn_name (Some "it is the match scrutinee") subj acc in
    List.fold_left (fun acc (br : Ast.branch) ->
        tco_check fn_name blocking br.Ast.branch_body acc
      ) acc branches

  (* Constructor wraps the result — args are not in tail position *)
  | Ast.ECon (name, args, _) ->
    let b = ctor_blocks name.Ast.txt in
    List.fold_left (fun a arg -> tco_check fn_name (Some b) arg a) acc args

  (* Tuple — elements are not in tail position *)
  | Ast.ETuple (es, _) ->
    List.fold_left (fun a e ->
        tco_check fn_name (Some "it is inside a tuple") e a
      ) acc es

  (* Record — fields are not in tail position *)
  | Ast.ERecord (fields, _) ->
    List.fold_left (fun a (_, e) ->
        tco_check fn_name (Some "it is inside a record") e a
      ) acc fields

  (* Annotation is transparent *)
  | Ast.EAnnot (e, _, _) -> tco_check fn_name blocking e acc

  (* Pipe: last stage inherits tail ctx; earlier stages do not *)
  | Ast.EPipe (a, b, _) ->
    let acc = tco_check fn_name (Some "it is piped further") a acc in
    tco_check fn_name blocking b acc

  (* Nested functions have their own scope — do not descend *)
  | Ast.ELam _ | Ast.ELetFn _ -> acc

  (* Other structural expressions *)
  | Ast.ERecordUpdate (e, fields, _) ->
    let acc = tco_check fn_name (Some "it is inside a record update") e acc in
    List.fold_left (fun a (_, e2) ->
        tco_check fn_name (Some "it is inside a record update") e2 a
      ) acc fields

  | Ast.ESend (a, b, _) ->
    let acc = tco_check fn_name (Some "it is the send target") a acc in
    tco_check fn_name (Some "it is the send message") b acc

  | Ast.EAtom (_, es, _) ->
    List.fold_left (fun a e ->
        tco_check fn_name (Some "it is inside an atom") e a
      ) acc es

  | Ast.EField (e, _, _) | Ast.ESpawn (e, _)
  | Ast.EDbg (Some e, _) | Ast.EAssert (e, _) ->
    tco_check fn_name (Some "the result is used further") e acc

  | _ -> acc

(** Check all clauses of a function definition for non-tail recursive calls. *)
let tco_check_fn (fn : Ast.fn_def) acc =
  (* `@[no_warn_recursion]` is the author asserting this recursion's depth is
     bounded. The compiler's own tail-call checker honours it, so the editor
     must too: otherwise the attribute silences the build while the hint keeps
     underlining every recursive call, which is worse than either behaviour on
     its own — the user has already answered, and we keep asking. *)
  if List.mem "no_warn_recursion" fn.Ast.fn_attrs then acc
  else
  let fn_name = fn.Ast.fn_name.txt in
  List.fold_left (fun acc (cl : Ast.fn_clause) ->
      tco_check fn_name None cl.Ast.fc_body acc
    ) acc fn.Ast.fn_clauses

(** Build a map from (simple) function name → ordered parameter names, sourced
    from user [DFn] declarations (including those nested inside [DMod]). Keyed by
    the bare function name (last path segment), so both a plain call `add(..)`
    and a qualified call `M.add(..)` resolve through the same entry.

    Precomputed once when the analysis record is constructed and cached on
    [t.param_name_map] so parameter-name inlay hints don't re-walk all
    declarations per request.

    Source/limitation: param names come ONLY from user functions in this file's
    AST ([t.decls]). Stdlib / global function param names are not available here,
    so calls into the stdlib get no parameter-name hints. The first clause of a
    multi-clause function supplies the names. *)
let build_param_name_map (decls : Ast.decl list) : (string, string list) Hashtbl.t =
  let tbl : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  let rec go decls =
    List.iter (fun (d : Ast.decl) ->
        match d with
        | Ast.DFn (fd, _) ->
          (match fd.Ast.fn_clauses with
           | cl :: _ ->
             let names = clause_param_names cl in
             (* Only register when every param has a usable name, so we never
                emit a misaligned hint for a function with pattern params. *)
             if names <> [] && List.length names = List.length cl.Ast.fc_params
             then Hashtbl.replace tbl fd.Ast.fn_name.Ast.txt names
           | [] -> ())
        | Ast.DMod (_, _, inner, _) -> go inner
        | _ -> ()
      ) decls
  in
  go decls;
  tbl

(** Phase-2 heuristic: a call whose callee is one of [params] dispatches through
    a function pointer (an indirect call). Calling a parameter is the canonical
    higher-order indirect call. *)
let indirect_call_check (params : string list) (e : Ast.expr) acc =
  let rec go e acc =
    match e with
    | Ast.EApp (Ast.EVar n, args, sp) when List.mem n.Ast.txt params ->
      let pi =
        { pi_span    = sp;
          pi_kind    = IndirectCall { pi_callee = n.Ast.txt };
          pi_message = Printf.sprintf
            "`%s` is a parameter, so this call dispatches through a function pointer (an indirect call). If the target is statically known, a direct call is faster." n.Ast.txt }
      in
      List.fold_left (fun a e -> go e a) (pi :: acc) args
    | Ast.EApp (f, args, _) ->
      List.fold_left (fun a e -> go e a) (go f acc) args
    | Ast.ELet (b, _) -> go b.Ast.bind_expr acc
    | Ast.EBlock (es, _) -> List.fold_left (fun a e -> go e a) acc es
    | Ast.EMatch (subj, brs, _) ->
      List.fold_left (fun a (br : Ast.branch) -> go br.Ast.branch_body a)
        (go subj acc) brs
    | Ast.EIf (c, t, f, _) -> go f (go t (go c acc))
    | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) -> go y (go x acc)
    | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
      List.fold_left (fun a e -> go e a) acc es
    | Ast.ERecord (fs, _) -> List.fold_left (fun a (_, e) -> go e a) acc fs
    | Ast.ERecordUpdate (e, fs, _) ->
      List.fold_left (fun a (_, e) -> go e a) (go e acc) fs
    | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
    | Ast.EDbg (Some e, _) | Ast.EAssert (e, _) -> go e acc
    | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> go body acc
    | _ -> acc
  in
  go e acc

(** Phase-2 heuristic: in a self-recursive function, allocations (constructor /
    record / tuple) inside a match/if arm run on every recursive step — a hot
    path for GC pressure (and a candidate for FBIP reuse). *)
let recursive_alloc_check fn_name (body : Ast.expr) acc =
  if not (contains_call fn_name body) then acc
  else begin
    let is_alloc = function
      | Ast.ECon (_, _ :: _, _) | Ast.ERecord _
      | Ast.ETuple _ | Ast.ERecordUpdate _ -> true
      | _ -> false
    in
    let alloc_desc = function
      | Ast.ECon (n, _, _) -> Printf.sprintf "`%s(...)`" n.Ast.txt
      | Ast.ERecord _ -> "a record"
      | Ast.ETuple _ -> "a tuple"
      | Ast.ERecordUpdate _ -> "a record update"
      | _ -> "a value"
    in
    let acc = ref acc in
    let rec walk ~in_arm e =
      if in_arm && is_alloc e then begin
        let sp = span_of_expr e in
        acc := { pi_span    = sp;
                 pi_kind    = RecursiveAlloc { pi_alloc = alloc_desc e };
                 pi_message = Printf.sprintf
                   "%s is allocated inside an arm of the recursive `%s`, so it runs on every step. If it is loop-invariant, hoist it out; otherwise consider whether FBIP reuse applies."
                   (alloc_desc e) fn_name } :: !acc
      end;
      match e with
      | Ast.EMatch (subj, brs, _) ->
        walk ~in_arm subj;
        List.iter (fun (br : Ast.branch) -> walk ~in_arm:true br.Ast.branch_body) brs
      | Ast.EIf (c, t, f, _) ->
        walk ~in_arm c; walk ~in_arm:true t; walk ~in_arm:true f
      | Ast.EApp (f, args, _) -> walk ~in_arm f; List.iter (walk ~in_arm) args
      | Ast.ELet (b, _) -> walk ~in_arm b.Ast.bind_expr
      | Ast.EBlock (es, _) -> List.iter (walk ~in_arm) es
      | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) -> walk ~in_arm x; walk ~in_arm y
      | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
        List.iter (walk ~in_arm) es
      | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> walk ~in_arm e) fs
      | Ast.ERecordUpdate (e, fs, _) ->
        walk ~in_arm e; List.iter (fun (_, e) -> walk ~in_arm e) fs
      | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
      | Ast.EDbg (Some e, _) | Ast.EAssert (e, _) -> walk ~in_arm e
      | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> walk ~in_arm b
      | _ -> ()
    in
    walk ~in_arm:false body;
    !acc
  end

(** Conservative purity check for a function argument, operating on the
    surface AST. Shares the impure-builtin whitelist with the TIR purity
    oracle ([March_tir.Purity.impure_builtins]) so there is a single source
    of truth. Returns [false] ("treat as impure") for anything not obviously
    pure — the safe bias for suggesting parallelization. *)
let rec ast_expr_is_pure (e : Ast.expr) : bool =
  let impure name = List.mem name March_tir.Purity.impure_builtins in
  match e with
  | Ast.ELit _ | Ast.EVar _ -> true
  | Ast.ECon (_, args, _) | Ast.ETuple (args, _) -> List.for_all ast_expr_is_pure args
  | Ast.EApp (Ast.EVar n, args, _) ->
    not (impure n.Ast.txt) && List.for_all ast_expr_is_pure args
  | Ast.EApp (Ast.EField (recv, m, _), args, _) ->
    (* Qualified call like Module.f(...) — conservative: the method name must
       not be a known impure builtin, and receiver + args must be pure. *)
    not (impure m.Ast.txt) && ast_expr_is_pure recv && List.for_all ast_expr_is_pure args
  | Ast.EApp (f, args, _) -> ast_expr_is_pure f && List.for_all ast_expr_is_pure args
  | Ast.ELam (_, body, _) -> ast_expr_is_pure body
  | Ast.EIf (c, t, f, _) -> ast_expr_is_pure c && ast_expr_is_pure t && ast_expr_is_pure f
  | Ast.ELet (b, _) -> ast_expr_is_pure b.Ast.bind_expr
  | Ast.EBlock (es, _) -> List.for_all ast_expr_is_pure es
  | Ast.EMatch (subj, brs, _) ->
    ast_expr_is_pure subj
    && List.for_all (fun (br : Ast.branch) ->
         ast_expr_is_pure br.Ast.branch_body
         && (match br.Ast.branch_guard with None -> true | Some g -> ast_expr_is_pure g)) brs
  | Ast.EField (recv, _, _) | Ast.EAnnot (recv, _, _) -> ast_expr_is_pure recv
  | _ -> false   (* ESend, ESpawn, EDbg, EAssert, ERecord*, EAtom, … → impure *)

(** Flag a pure [List.map]/[List.filter] call that could become its parallel
    form [List.pmap]/[List.pfilter]. Only direct module-qualified calls are
    matched. Folds/reduces are NEVER flagged (purity does not imply the
    associativity a parallel reduce needs). *)
let parallelizable_check (e : Ast.expr) acc =
  let acc = ref acc in
  let rec walk e =
    (* `List.map(xs, f)` parses as EApp(EField(ECon{"List"}, {"map"}, _),
       [xs; f], _) — the upper identifier `List` is an ECon. The method-name
       span covers just `map`, so the code action replaces it with `pmap`. *)
    (match e with
     | Ast.EApp (Ast.EField (Ast.ECon (m, [], _), meth, _), [_xs; f], app_sp)
       when m.Ast.txt = "List"
            && (meth.Ast.txt = "map" || meth.Ast.txt = "filter")
            && ast_expr_is_pure f ->
       let par = if meth.Ast.txt = "map" then "pmap" else "pfilter" in
       acc := { pi_span    = app_sp;
                pi_kind    = Parallelizable
                    { pi_op = meth.Ast.txt; pi_par = par; pi_name_span = meth.Ast.span };
                pi_message = Printf.sprintf
                  "This `List.%s` over a pure function could be `List.%s` to run in parallel (worth it only for large lists / heavy per-element work)."
                  meth.Ast.txt par } :: !acc
     | _ -> ());
    match e with
    | Ast.EApp (f, args, _) -> walk f; List.iter walk args
    | Ast.EMatch (subj, brs, _) ->
      walk subj; List.iter (fun (br : Ast.branch) -> walk br.Ast.branch_body) brs
    | Ast.EIf (c, t, f, _) -> walk c; walk t; walk f
    | Ast.ELet (b, _) -> walk b.Ast.bind_expr
    | Ast.EBlock (es, _) -> List.iter walk es
    | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) -> walk x; walk y
    | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) -> List.iter walk es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> walk e) fs
    | Ast.ERecordUpdate (e, fs, _) -> walk e; List.iter (fun (_, e) -> walk e) fs
    | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
    | Ast.EDbg (Some e, _) | Ast.EAssert (e, _) -> walk e
    | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> walk b
    | _ -> ()
  in
  walk e;
  !acc

(** Run all perf insight passes over [user_decls] and return the collected
    insights (Phase-1 AST passes + Phase-2 heuristics). *)
let collect_perf_insights
    ~(is_global : string -> bool)
    (type_map : (Ast.span, Tc.ty) Hashtbl.t)
    (user_decls : Ast.decl list) : perf_insight list =
  let acc = ref [] in
  let add_all pis = acc := pis @ !acc in
  let rec scan_decl (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) ->
      add_all (tco_check_fn fn []);
      let fn_name = fn.Ast.fn_name.Ast.txt in
      List.iter (fun (cl : Ast.fn_clause) ->
          add_all (closure_capture_check is_global cl.Ast.fc_body []);
          add_all (send_copy_check type_map cl.Ast.fc_body []);
          add_all (indirect_call_check (clause_param_names cl) cl.Ast.fc_body []);
          add_all (recursive_alloc_check fn_name cl.Ast.fc_body []);
          add_all (parallelizable_check cl.Ast.fc_body [])
        ) fn.Ast.fn_clauses
    | Ast.DLet (_, b, _) ->
      add_all (closure_capture_check is_global b.Ast.bind_expr []);
      add_all (send_copy_check type_map b.Ast.bind_expr []);
      add_all (parallelizable_check b.Ast.bind_expr [])
    | Ast.DMod (_, _, decls, _) ->
      List.iter scan_decl decls
    | _ -> ()
  in
  List.iter scan_decl user_decls;
  !acc

(* Interface name → spans of `impl <iface> for ...` declarations, for
   textDocument/implementation (jump from an interface to its implementations).
   The span is the interface name inside each impl. *)
let collect_impl_sites (decls : Ast.decl list) : (string, Ast.span list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  let rec go (d : Ast.decl) =
    match d with
    | Ast.DImpl (impl, _) ->
      let key = impl.Ast.impl_iface.Ast.txt in
      let prev = try Hashtbl.find tbl key with Not_found -> [] in
      Hashtbl.replace tbl key (impl.Ast.impl_iface.Ast.span :: prev)
    | Ast.DMod (_, _, ds, _) -> List.iter go ds
    | _ -> ()
  in
  List.iter go decls;
  tbl

(* ------------------------------------------------------------------ *)
(* ~H HTML sigil tag-balance checking                                  *)
(* ------------------------------------------------------------------ *)

let html_void_elements =
  [ "area"; "base"; "br"; "col"; "embed"; "hr"; "img"; "input"; "link";
    "meta"; "param"; "source"; "track"; "wbr" ]

(* Comprehensive set of known HTML elements (includes March's <island>).
   Tags with a '-' in their name are custom elements and are checked
   separately — they are always allowed. *)
let html_known_elements =
  [ (* sections *)
    "html"; "head"; "body"; "header"; "footer"; "main"; "nav";
    "section"; "article"; "aside";
    (* grouping *)
    "div"; "p"; "span"; "ul"; "ol"; "li"; "dl"; "dt"; "dd";
    "figure"; "figcaption"; "blockquote"; "pre"; "hr";
    (* text *)
    "a"; "strong"; "em"; "b"; "i"; "u"; "small"; "mark"; "code";
    "kbd"; "sub"; "sup"; "br"; "wbr"; "q"; "cite"; "time"; "abbr";
    (* headings *)
    "h1"; "h2"; "h3"; "h4"; "h5"; "h6";
    (* media *)
    "img"; "picture"; "source"; "audio"; "video"; "track"; "canvas";
    "svg"; "iframe"; "embed"; "object";
    (* tables *)
    "table"; "thead"; "tbody"; "tfoot"; "tr"; "td"; "th"; "caption";
    "colgroup"; "col";
    (* forms *)
    "form"; "input"; "textarea"; "button"; "select"; "option";
    "optgroup"; "label"; "fieldset"; "legend"; "datalist"; "output";
    "progress"; "meter";
    (* meta/head *)
    "meta"; "link"; "title"; "style"; "script"; "base"; "template";
    "slot"; "noscript";
    (* misc *)
    "details"; "summary"; "dialog"; "data"; "address"; "ins"; "del";
    "bdi"; "bdo"; "ruby"; "rt"; "rp"; "area"; "map"; "param";
    (* march island *)
    "island" ]

(* Levenshtein edit distance between two strings (standard DP). *)
let levenshtein (a : string) (b : string) : int =
  let m = String.length a and n = String.length b in
  let dp = Array.init (m + 1) (fun i -> Array.init (n + 1) (fun j ->
    if i = 0 then j else if j = 0 then i else 0)) in
  for i = 1 to m do
    for j = 1 to n do
      dp.(i).(j) <-
        if a.[i-1] = b.[j-1] then dp.(i-1).(j-1)
        else 1 + (min dp.(i-1).(j) (min dp.(i).(j-1) dp.(i-1).(j-1)))
    done
  done;
  dp.(m).(n)

(* ------------------------------------------------------------------ *)
(* Shared ~H content tokenizer                                          *)
(*                                                                      *)
(* [tokenize_h_content] walks a sigil's content ONCE and emits a flat   *)
(* list of HTML events.  It is the SINGLE source of truth for the skip  *)
(* rules that every ~H scanning pass relies on:                         *)
(*   - `${…}` interpolation with balanced-brace depth (top-level         *)
(*     interpolations are EMITTED as [HEInterp] so the unsafe-interp     *)
(*     pass can see them);                                               *)
(*   - `<!-- … -->` comments and `<!…>` declarations are skipped;         *)
(*   - open tags `<tag …>` parse a tag name, an attribute list (names    *)
(*     tokenised exactly as the legacy dup-attr scanner did, skipping    *)
(*     quoted values AND `${…}` inside the tag), and a self-closing flag *)
(*     (`/` immediately before `>`);                                     *)
(*   - close tags `</tag>` parse a tag name.                            *)
(*                                                                      *)
(* Edge cases preserved from the three historical bug fixes:            *)
(*   - a quoted attribute value containing `${…}` whose inner string     *)
(*     uses the same quote char must NOT prematurely end the value;      *)
(*   - a `>` inside a quoted attribute value must NOT end the tag;        *)
(*   - interpolation/string awareness inside the attribute region.       *)
(* ------------------------------------------------------------------ *)

type html_event =
  | HEOpenTag  of { tag : string; name_ofs : int; name_len : int;
                    self_closing : bool;
                    attrs : (string * int * int) list }
                    (* attr = (lowercase_name, name_ofs, name_len) *)
  | HECloseTag of { tag : string; name_ofs : int; name_len : int }
  | HEInterp   of { brace_ofs : int }  (* offset of the '$' starting a ${…} *)

let tokenize_h_content (content : string) : html_event list =
  let n = String.length content in
  (* Tag-name / close-name chars. *)
  let is_nc c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '-' || c = '_' in
  (* Attribute-name chars additionally allow ':' (XML namespaces). *)
  let attr_nc c = is_nc c || c = ':' in
  let events = ref [] in
  let emit e = events := e :: !events in
  let i = ref 0 in
  while !i < n do
    let c = content.[!i] in
    (* ${…} interpolation at top level: emit + skip balanced braces. *)
    if c = '$' && !i + 1 < n && content.[!i + 1] = '{' then begin
      emit (HEInterp { brace_ofs = !i });
      i := !i + 2; let d = ref 1 in
      while !d > 0 && !i < n do
        (match content.[!i] with '{' -> incr d | '}' -> decr d | _ -> ()); incr i
      done
    end
    (* <!-- … --> comment *)
    else if c = '<' && !i + 3 < n
            && content.[!i+1]='!' && content.[!i+2]='-' && content.[!i+3]='-' then begin
      i := !i + 4;
      while !i + 2 < n
            && not (content.[!i]='-' && content.[!i+1]='-' && content.[!i+2]='>') do incr i done;
      i := (if !i + 2 < n then !i + 3 else n)
    end
    (* <!…> declaration/doctype *)
    else if c = '<' && !i + 1 < n && content.[!i+1] = '!' then begin
      while !i < n && content.[!i] <> '>' do incr i done;
      if !i < n then incr i
    end
    (* </tag> close tag *)
    else if c = '<' && !i + 1 < n && content.[!i+1] = '/' then begin
      let ns = !i + 2 in let j = ref ns in
      while !j < n && is_nc content.[!j] do incr j done;
      let name_ofs = ns and name_len = !j - ns in
      let tag = String.lowercase_ascii (String.sub content ns name_len) in
      while !j < n && content.[!j] <> '>' do incr j done;
      i := (if !j < n then !j + 1 else n);
      emit (HECloseTag { tag; name_ofs; name_len })
    end
    (* <tag …> open tag *)
    else if c = '<' && !i + 1 < n
            && (let d = content.[!i+1] in (d>='a'&&d<='z')||(d>='A'&&d<='Z')) then begin
      let ns = !i + 1 in let j = ref ns in
      while !j < n && is_nc content.[!j] do incr j done;
      let name_ofs = ns and name_len = !j - ns in
      let tag = String.lowercase_ascii (String.sub content ns name_len) in
      (* Walk the attribute region until the closing '>', collecting attribute
         name-like tokens (matching the legacy dup-attr tokenizer exactly) and
         respecting quoted values + ${…} interpolations.  A ${…} inside a quoted
         value whose inner string reuses the same quote char must NOT end the
         value, and a '>' inside a quoted value must NOT end the tag. *)
      let attrs = ref [] in
      let inq = ref false and q = ref ' ' in
      while !j < n && (!inq || content.[!j] <> '>') do
        let d = content.[!j] in
        if !inq then begin
          (* ${…} inside a quoted attribute value: skip balanced braces. *)
          if d = '$' && !j + 1 < n && content.[!j + 1] = '{' then begin
            j := !j + 2; let depth = ref 1 in
            while !depth > 0 && !j < n do
              (match content.[!j] with '{' -> incr depth | '}' -> decr depth | _ -> ());
              incr j
            done
          end else begin
            if d = !q then inq := false;
            incr j
          end
        end
        (* ${…} in the attribute region (outside quotes): skip balanced braces. *)
        else if d = '$' && !j + 1 < n && content.[!j + 1] = '{' then begin
          j := !j + 2; let depth = ref 1 in
          while !depth > 0 && !j < n do
            (match content.[!j] with '{' -> incr depth | '}' -> decr depth | _ -> ());
            incr j
          done
        end
        (* Start of a quoted value. *)
        else if d = '"' || d = '\'' then begin
          inq := true; q := d; incr j
        end
        (* Attribute name: starts with a letter, '_', or ':'. *)
        else if (d >= 'a' && d <= 'z') || (d >= 'A' && d <= 'Z')
                || d = '_' || d = ':' then begin
          let a_ofs = !j in
          while !j < n && attr_nc content.[!j] do incr j done;
          let a_len = !j - a_ofs in
          let name = String.lowercase_ascii (String.sub content a_ofs a_len) in
          attrs := (name, a_ofs, a_len) :: !attrs
        end
        else incr j
      done;
      let self_closing = !j < n && !j > 0 && content.[!j - 1] = '/' in
      i := (if !j < n then !j + 1 else n);
      emit (HEOpenTag { tag; name_ofs; name_len; self_closing;
                        attrs = List.rev !attrs })
    end
    else incr i
  done;
  List.rev !events

(* Scan HTML [content] and return the open tags left unclosed, as
   (tag, offset-of-'<'-in-content), innermost-first. Skips `${…}` interpolation,
   `<!-- … -->` comments, `<!doctype …>`, void elements and self-closing tags;
   quoted attribute values are respected so `>` inside them is ignored. *)
let scan_html_unclosed (content : string) : (string * int) list =
  (* Fold the event stream: push each non-void / non-self-closing open tag
     (recording the offset of its '<', which is name_ofs - 1); on a close that
     matches something on the stack, pop down to the match and record every
     intervening open as unclosed.  Interpolation events are ignored. *)
  let stack = ref [] in
  let unclosed = ref [] in   (* tags skipped over by a mismatched close *)
  List.iter (function
    | HEInterp _ -> ()
    | HEOpenTag { tag; name_ofs; self_closing; _ } ->
      if not self_closing && not (List.mem tag html_void_elements) then
        stack := (tag, name_ofs - 1) :: !stack
    | HECloseTag { tag; _ } ->
      if List.exists (fun (t, _) -> t = tag) !stack then begin
        let rec pop = function
          | (t, o) :: r ->
            if t = tag then r
            else (unclosed := (t, o) :: !unclosed; pop r)
          | [] -> [] in
        stack := pop !stack
      end)
    (tokenize_h_content content);
  (* Tags still open at end of input, plus any skipped by mismatched closes;
     innermost-first so closers nest correctly. *)
  !stack @ List.rev !unclosed

(* Extract a ~H sigil's content from [src] given the byte offset of its `~`.
   Returns (content, content_base_offset, closing_quote_offset). Handles both
   `"…"` and `"""…"""`. *)
let extract_h_content (src : string) (start_ofs : int) (name_len : int)
    : (string * int * int) option =
  let len = String.length src in
  let k = start_ofs + 1 + name_len in   (* skip `~` + sigil name *)
  if k >= len then None
  else if k + 2 < len && src.[k]='"' && src.[k+1]='"' && src.[k+2]='"' then begin
    let cb = k + 3 in
    let j = ref cb in
    while !j + 2 < len && not (src.[!j]='"' && src.[!j+1]='"' && src.[!j+2]='"') do incr j done;
    if !j + 2 < len then Some (String.sub src cb (!j - cb), cb, !j) else None
  end
  else if src.[k] = '"' then begin
    let cb = k + 1 in
    let j = ref cb in
    while !j < len && src.[!j] <> '"' do (if src.[!j] = '\\' then incr j); incr j done;
    if !j < len then Some (String.sub src cb (!j - cb), cb, !j) else None
  end
  else None

(* Byte offset → (1-indexed line, 0-indexed col), matching Ast.span convention. *)
let ofs_to_pos (src : string) (ofs : int) : int * int =
  let line = ref 1 and col = ref 0 in
  let stop = min ofs (String.length src) in
  for k = 0 to stop - 1 do
    if src.[k] = '\n' then (incr line; col := 0) else incr col
  done;
  (!line, !col)

(* (1-indexed line, 0-indexed col) → byte offset. *)
let pos_to_ofs (src : string) (line1 : int) (col : int) : int =
  let n = String.length src in
  let cur = ref 1 and i = ref 0 in
  while !cur < line1 && !i < n do (if src.[!i] = '\n' then incr cur); incr i done;
  min (!i + col) n

(** Scan one ~H sigil and return a list of [(lowercase_tag, name_span)]
    for every open tag found (skipping [${…}] interpolations, HTML comments,
    declarations, and self-closing tags).  Void elements ARE included so
    callers can decide whether to check them.

    This is a shared helper used by [collect_html_lint] (task 3.1) and
    available for subsequent lint passes (3.2 dup attrs, 3.3 void misuse,
    3.4 XSS) that need the same tag enumeration. *)
let open_tags_in_sigil ~(src : string) (s : h_sigil) : (string * Ast.span) list =
  let name_span name_ofs name_len =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + name_ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + name_len } in
  List.filter_map (function
    | HEOpenTag { tag; name_ofs; name_len; self_closing; _ } ->
      if self_closing then None
      else Some (tag, name_span name_ofs name_len)
    | _ -> None)
    (tokenize_h_content s.hs_content)

(** Pass 3.2 — duplicate attributes within a single HTML open tag.
    Walks each sigil looking for open tags (same skipping rules as
    [open_tags_in_sigil]: ${…} interpolations, comments, declarations,
    and close tags are all skipped).  Inside each open tag's attribute
    region (from just after the tag name to the closing '>'), attribute
    names are tokenized as [A-Za-z_:][-A-Za-z0-9_:]* followed by an
    optional [=value] where value may be bare, single-quoted, or
    double-quoted.  A '${…}' interpolation inside the attribute region
    is treated as a complete token and skipped so that its content
    (which might contain '>') does not confuse the parser.
    For every attribute name that appears a second or subsequent time in
    the SAME tag, a [(name_span, message, "html/duplicate-attr")] entry
    is emitted.  Offsets are mapped to source positions via
    [ofs_to_pos src (hs_base_ofs + ofs)], exactly as the other passes
    do. *)
let dup_attrs_in_sigil ~(src : string) (s : h_sigil)
    : (Ast.span * string * string) list =
  (* Build a single-line Ast.span for an attribute name token at content-
     relative byte offset [ofs] with length [len]. *)
  let attr_name_span ofs len =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + len } in
  List.concat_map (function
    | HEOpenTag { attrs; _ } ->
      (* Within ONE open tag, flag the 2nd-and-later occurrence of each name. *)
      let seen = Hashtbl.create 4 in
      List.filter_map (fun (name, name_ofs, name_len) ->
          if Hashtbl.mem seen name then
            Some (attr_name_span name_ofs name_len,
                  Printf.sprintf "Duplicate attribute `%s`" name,
                  "html/duplicate-attr")
          else (Hashtbl.add seen name (); None))
        attrs
    | _ -> [])
    (tokenize_h_content s.hs_content)

(** Pass 3.3 — void element misuse: close tags for void elements and
    self-closing syntax on non-void, non-island elements.

    Two checks per sigil walk:
    - Close tag [</X>] where [X] is a void element →
      [(name_span, msg, "html/void-with-children")]
    - Open tag that ends with [/>] where [X] is NOT void and NOT "island" →
      [(name_span, msg, "html/self-closing-nonvoid")]

    Skips [\${…}] interpolations, [<!-- … -->] comments, [<!…>] declarations,
    and quoted attribute values — identical to the other scanners in this file. *)
let void_misuse_in_sigil ~(src : string) (s : h_sigil)
    : (Ast.span * string * string) list =
  let name_span name_ofs name_len =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + name_ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + name_len } in
  List.filter_map (function
    | HECloseTag { tag; name_ofs; name_len } ->
      (* Close tag for a void element → it cannot have children. *)
      if name_len > 0 && List.mem tag html_void_elements then
        Some (name_span name_ofs name_len,
              Printf.sprintf "`<%s>` is a void element and cannot have a closing tag." tag,
              "html/void-with-children")
      else None
    | HEOpenTag { tag; name_ofs; name_len; self_closing; _ } ->
      (* Self-closing syntax on a non-void, non-island element has no effect. *)
      if self_closing
         && not (List.mem tag html_void_elements)
         && tag <> "island" then
        Some (name_span name_ofs name_len,
              Printf.sprintf "`<%s/>` self-closing has no effect on non-void element `<%s>`; use `<%s></%s>`."
                tag tag tag tag,
              "html/self-closing-nonvoid")
      else None
    | HEInterp _ -> None)
    (tokenize_h_content s.hs_content)

(** Pass 3.4 — XSS risk: [${…}] interpolation inside [<script>] or [<style>]
    elements.  HTML auto-escaping in normal text is safe, but inside these
    raw-content elements the browser does NOT apply HTML entity decoding, so
    interpolated values can inject arbitrary JS/CSS.

    The scanner walks the sigil content tracking whether the cursor is currently
    inside a [<script>] or [<style>] element.  When [in_raw_context = true] every
    [\${] start emits an [(span, message, "html/unsafe-interpolation")] entry.
    While [in_raw_context = false] [\${…}] regions are skipped as usual
    (balanced braces).

    Tag detection:
    - [<script …>] or [<style …>] (with optional attrs) → set [in_raw_context]
    - [</script>] or [</style>]                         → clear [in_raw_context]
    - All other tags, comments, [<!…>], and attribute regions are scanned
      in the usual way (skipping quoted attr values) so we don't mistake
      attribute content for the element body. *)
let unsafe_interpolation_in_sigil ~(src : string) (s : h_sigil)
    : (Ast.span * string * string) list =
  (* Build a single-line span for the two-character "${" at content-relative
     byte offset [ofs]. *)
  let interp_span ofs =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + 2 } in
  (* Fold tracking whether we are inside a <script>/<style> element body.
     Each top-level interpolation (HEInterp; attribute-region interps are not
     emitted by the tokenizer) seen while raw is flagged. *)
  let in_raw = ref false in
  List.filter_map (function
    | HEInterp { brace_ofs } ->
      if !in_raw then
        Some (interp_span brace_ofs,
              "Interpolation inside <script>/<style> is not HTML-escaped \
               for this context; ensure the value is safe.",
              "html/unsafe-interpolation")
      else None
    | HEOpenTag { tag; _ } ->
      if tag = "script" || tag = "style" then in_raw := true;
      None
    | HECloseTag { tag; _ } ->
      if tag = "script" || tag = "style" then in_raw := false;
      None)
    (tokenize_h_content s.hs_content)

(** Collect HTML lint warnings for all ~H sigils.  Returns a list of
    [(span, message, diagnostic-code)] triples.  This is the shared
    accumulator — later lint passes (3.2 dup attrs, 3.3 void misuse,
    3.4 XSS) add their own results to it via [collect_html_lint] or a
    wrapper that calls it and appends. *)
let collect_html_lint ~(src : string) (sigils : h_sigil list)
    : (Ast.span * string * string) list =
  (* Pass 3.1 — unknown / misspelled tag names. *)
  let unknown_tag_results =
    List.concat_map (fun (s : h_sigil) ->
      List.filter_map (fun (tag, span) ->
        if List.mem tag html_known_elements then None
        else if String.contains tag '-' then None   (* custom element / web component *)
        else begin
          let suggestion =
            (* Nearest known tag by edit distance ≤ 2, else empty string. *)
            let best = List.fold_left (fun (bd, bt) k ->
                let d = levenshtein tag k in if d < bd then (d, k) else (bd, bt))
              (max_int, "") html_known_elements in
            match best with
            | (d, k) when d <= 2 -> Printf.sprintf " (did you mean `<%s>`?)" k
            | _ -> "" in
          Some (span,
                Printf.sprintf "Unknown HTML tag `<%s>`%s" tag suggestion,
                "html/unknown-tag")
        end)
        (open_tags_in_sigil ~src s))
    sigils
  in
  (* Pass 3.2 — duplicate attributes in a single open tag. *)
  let dup_attr_results =
    List.concat_map (dup_attrs_in_sigil ~src) sigils
  in
  (* Pass 3.3 — void element misuse (close tags on void elements;
     self-closing syntax on non-void elements). *)
  let void_misuse_results =
    List.concat_map (void_misuse_in_sigil ~src) sigils
  in
  (* Pass 3.4 — XSS risk: ${…} interpolation inside <script>/<style>. *)
  let unsafe_interp_results =
    List.concat_map (unsafe_interpolation_in_sigil ~src) sigils
  in
  unknown_tag_results @ dup_attr_results @ void_misuse_results @ unsafe_interp_results

(** Return matched (open-name-span, close-name-span) pairs in one ~H sigil.
    Adapts the [scan_html_unclosed] walk: on a successful close-tag match, pop
    the matching open off the stack and record both tag-NAME spans (mapped to
    absolute source positions via [ofs_to_pos]).  Void and self-closing tags
    are skipped, as are [${…}] interpolations and [<!-- … -->] comments. *)
let tag_pairs_in_sigil ~(src : string) (s : h_sigil) : (Ast.span * Ast.span) list =
  (* Build a single-line Ast.span for a tag-name at content-relative byte
     offset [name_ofs] with length [name_len]. *)
  let name_span name_ofs name_len =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + name_ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + name_len } in
  (* Stack entries: (lowercase-tag-name, name-offset-in-content, name-len). On a
     matching close, prepend the (open_span, close_span) pair (most-recent first,
     matching the legacy ordering). *)
  let stack = ref [] and pairs = ref [] in
  List.iter (function
    | HEInterp _ -> ()
    | HEOpenTag { tag; name_ofs; name_len; self_closing; _ } ->
      if not self_closing && not (List.mem tag html_void_elements) then
        stack := (tag, name_ofs, name_len) :: !stack
    | HECloseTag { tag; name_ofs = close_name_ofs; name_len = close_name_len } ->
      (* Pop down to the matching open; skip any unmatched opens above it. *)
      let rec pop = function
        | (t, o, ln) :: r when t = tag ->
          pairs := (name_span o ln, name_span close_name_ofs close_name_len)
                   :: !pairs;
          r
        | _ :: r -> pop r
        | [] -> [] in
      stack := pop !stack)
    (tokenize_h_content s.hs_content);
  !pairs

(** Collect folding ranges for matched HTML element pairs inside ~H sigils.
    For each (open_name_span, close_name_span) pair where the close tag's
    end_line > open tag's start_line, emit a (start_line_0idx, end_line_0idx, "region")
    triple.  Spans from [tag_pairs_in_sigil] are 1-indexed; we convert to 0-indexed
    here to match the convention used by [collect_fold_ranges]. *)
let collect_h_fold_ranges ~(src : string) (sigils : h_sigil list)
    : (int * int * string) list =
  List.concat_map (fun (s : h_sigil) ->
      List.filter_map (fun ((op, cl) : Ast.span * Ast.span) ->
          if cl.Ast.end_line > op.Ast.start_line then
            Some (op.Ast.start_line - 1, cl.Ast.end_line - 1, "region")
          else
            None
        ) (tag_pairs_in_sigil ~src s)
    ) sigils

(* Every ~H sigil in [decls], with content recovered textually from [src]. *)
let collect_h_sigils ~(src : string) (decls : Ast.decl list) : h_sigil list =
  let acc = ref [] in
  let consider name (sp : Ast.span) =
    if name = "H" then begin
      let start_ofs = pos_to_ofs src sp.Ast.start_line sp.Ast.start_col in
      match extract_h_content src start_ofs (String.length name) with
      | None -> ()
      | Some (content, cbase, close_ofs) ->
        acc := { hs_content = content; hs_base_ofs = cbase;
                 hs_close_ofs = close_ofs; hs_span = sp } :: !acc
    end
  in
  let rec ex (e : Ast.expr) =
    (match e with Ast.ESigil (name, _, sp) -> consider name sp | _ -> ());
    match e with
    | Ast.EApp (f, args, _) -> ex f; List.iter ex args
    | Ast.ECon (_, es, _) | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) -> List.iter ex es
    | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> ex b
    | Ast.EBlock (es, _) -> List.iter ex es
    | Ast.ELet (b, _) -> ex b.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      ex s; List.iter (fun (br : Ast.branch) -> ex br.Ast.branch_body) brs
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> ex c; ex b) arms
    | Ast.EIf (c, t, f, _) -> ex c; ex t; ex f
    | Ast.EPipe (a2, b2, _) | Ast.ESend (a2, b2, _) -> ex a2; ex b2
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
    | Ast.ERecordUpdate (e2, fs, _) -> ex e2; List.iter (fun (_, e) -> ex e) fs
    | Ast.EField (e2, _, _) | Ast.EAnnot (e2, _, _) | Ast.ESpawn (e2, _)
    | Ast.EAssert (e2, _) | Ast.ESigil (_, e2, _) | Ast.EDbg (Some e2, _) -> ex e2
    | _ -> ()
  in
  let rec dl (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) -> List.iter (fun (cl : Ast.fn_clause) -> ex cl.Ast.fc_body) fn.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> ex b.Ast.bind_expr
    | Ast.DActor (_, _, ad, _) ->
      ex ad.Ast.actor_init;
      List.iter (fun (h : Ast.actor_handler) -> ex h.Ast.ah_body) ad.Ast.actor_handlers
    | Ast.DTest (t, _) -> ex t.Ast.test_body
    | Ast.DDescribe (_, ds, _) | Ast.DMod (_, _, ds, _) -> List.iter dl ds
    | _ -> ()
  in
  List.iter dl decls; List.rev !acc

(** A reference to an [<island name='X' ...>] component found inside a ~H sigil. *)
type island_ref = {
  isl_name      : string;   (** module name from name='…' or name="…" *)
  isl_name_span : Ast.span; (** span of the NAME text (for def/diag/highlight) *)
  isl_has_props : bool;     (** true when a [props=] attribute is present in the tag *)
}

(** Find every [<island name='X' …>] tag in one h_sigil, returning the name's
    source span so callers can validate, navigate, or complete it. *)
let islands_in_sigil ~(src : string) (s : h_sigil) : island_ref list =
  let c = s.hs_content in
  let n = String.length c in
  let out = ref [] in
  (* Return byte offset of [pat] within c at/after [start], or -1. *)
  let find_from pat start =
    let pl = String.length pat in
    let rec go k =
      if k + pl > n then -1
      else if String.sub c k pl = pat then k
      else go (k + 1)
    in
    go start
  in
  (* Scan forward from [start] respecting quoted attribute values and
     ${...} interpolations, returning the offset of the first '>' that
     is NOT inside a quote or interpolation (i.e. the real tag-end). *)
  let tag_end_from start =
    let j = ref start in
    while !j < n && c.[!j] <> '>' do
      let ch = c.[!j] in
      if ch = '$' && !j + 1 < n && c.[!j + 1] = '{' then begin
        (* ${...} interpolation: skip balanced braces *)
        j := !j + 2; let depth = ref 1 in
        while !depth > 0 && !j < n do
          (match c.[!j] with '{' -> incr depth | '}' -> decr depth | _ -> ());
          incr j
        done
      end else if ch = '"' || ch = '\'' then begin
        (* Quoted attribute value: skip until matching close quote,
           also skipping ${...} inside the value. *)
        let q = ch in
        incr j;
        while !j < n && c.[!j] <> q do
          if c.[!j] = '$' && !j + 1 < n && c.[!j + 1] = '{' then begin
            j := !j + 2; let depth = ref 1 in
            while !depth > 0 && !j < n do
              (match c.[!j] with '{' -> incr depth | '}' -> decr depth | _ -> ());
              incr j
            done
          end else
            incr j
        done;
        if !j < n then incr j  (* skip closing quote *)
      end else
        incr j
    done;
    !j  (* offset of '>' or n if not found *)
  in
  let i = ref 0 in
  while !i < n do
    if !i + 7 <= n && String.sub c !i 7 = "<island" then begin
      let tag_end = tag_end_from !i in
      (* Try to extract name='X' or name="X" within the tag. *)
      let name_at q =
        let p = "name=" ^ String.make 1 q in
        let k = find_from p !i in
        if k < 0 || k >= tag_end then None
        else begin
          let vs = k + String.length p in
          let ve =
            match find_from (String.make 1 q) vs with
            | -1 -> tag_end
            | e  -> e
          in
          Some (String.sub c vs (ve - vs), vs, ve)
        end
      in
      (match (match name_at '\'' with None -> name_at '"' | r -> r) with
       | Some (nm, vs, _ve) ->
         let (l, col) = ofs_to_pos src (s.hs_base_ofs + vs) in
         let span =
           { Ast.file = ""; start_line = l; start_col = col;
             end_line = l; end_col = col + String.length nm }
         in
         let pk = find_from "props=" !i in
         let has_props = pk >= 0 && pk < tag_end in
         out := { isl_name = nm; isl_name_span = span; isl_has_props = has_props } :: !out
       | None -> ());
      i := tag_end + 1
    end else
      incr i
  done;
  List.rev !out

(* Collect unclosed-tag issues across a precomputed list of ~H sigils.
   Accepts the already-computed [h_sigil list] to avoid a redundant AST walk. *)
let collect_html_issues ~(src : string) (sigils : h_sigil list) : html_issue list =
  let issues = ref [] in
  List.iter (fun (s : h_sigil) ->
      let unclosed = scan_html_unclosed s.hs_content in
      if unclosed <> [] then begin
        let (cl, cc) = ofs_to_pos src s.hs_close_ofs in
        let insert_span =
          { Ast.file = ""; start_line = cl; start_col = cc; end_line = cl; end_col = cc } in
        let closer =
          String.concat "" (List.map (fun (t, _) -> "</" ^ t ^ ">") unclosed) in
        List.iter (fun (tag, ofs) ->
            let (ol, oc) = ofs_to_pos src (s.hs_base_ofs + ofs) in
            let open_span =
              { Ast.file = ""; start_line = ol; start_col = oc;
                end_line = ol; end_col = oc + 1 + String.length tag } in
            issues := { hi_open_span = open_span; hi_tag = tag;
                        hi_insert_span = insert_span; hi_closer = closer } :: !issues)
          unclosed
      end)
    sigils;
  !issues

(* ------------------------------------------------------------------ *)
(* Actionable Run / Debug code lenses                                  *)
(* ------------------------------------------------------------------ *)

(** Build a single-line lens range pinned to the start of [sp]. CodeLens
    titles render on their own line above the target, so a zero-width range
    at the declaration's first line/col is what editors expect. *)
let lens_range_of_span (sp : Ast.span) : Lsp.Types.Range.t =
  let r = Pos.span_to_lsp_range sp in
  Lsp.Types.Range.create ~start:r.Lsp.Types.Range.start ~end_:r.Lsp.Types.Range.start

(** Produce the actionable Run / Debug code lenses for a document: a
    [▶ Run] + [🐞 Debug] pair above every [test "…"] block (including those
    nested in [describe]/[mod]) and above [fn main].

    These are emitted unconditionally in [analyse] — independent of the TIR
    pipeline — so they appear even when the optimizer cannot run. The command
    ids are stable so generic clients can wire them up; arguments are
    [file_uri, test_name] for tests and [file_uri] for main. *)
let build_action_lenses ~filename (decls : Ast.decl list) : code_lens_item list =
  let file_uri =
    Lsp.Types.DocumentUri.to_string (Lsp.Types.DocumentUri.of_path filename)
  in
  let acc = ref [] in
  let add ~range ~title ~command ~args =
    acc := { cl_range = range; cl_title = title;
             cl_command = Some command; cl_args = args } :: !acc
  in
  let test_lenses ~range name =
    let args = [ `String file_uri; `String name ] in
    add ~range ~title:"▶ Run"   ~command:"march.runTest"   ~args;
    add ~range ~title:"🐞 Debug" ~command:"march.debugTest" ~args
  in
  let main_lenses ~range =
    let args = [ `String file_uri ] in
    add ~range ~title:"▶ Run"   ~command:"march.run"   ~args;
    add ~range ~title:"🐞 Debug" ~command:"march.debug" ~args
  in
  let rec walk decls =
    List.iter (fun (d : Ast.decl) ->
        match d with
        | Ast.DTest (t, sp) ->
          test_lenses ~range:(lens_range_of_span sp) t.Ast.test_name
        | Ast.DFn (fd, sp) when fd.Ast.fn_name.Ast.txt = "main" ->
          main_lenses ~range:(lens_range_of_span sp)
        | Ast.DDescribe (_, ds, _) | Ast.DMod (_, _, ds, _) -> walk ds
        | _ -> ()
      ) decls
  in
  walk decls;
  List.rev !acc

(** Outcome of resolving a code-lens command into something the server can act
    on. [RunShell] is a shell command line the server executes (forge test /
    forge run); [DebugEcho] is a structured payload the editor uses to launch
    its own interactive DAP session — the LSP must NOT block on an interactive
    debugger, so for debug commands we echo back the command + args and let the
    client drive `march dap`. [Unknown] is an unrecognised command id. *)
type lens_command =
  | RunShell  of { description : string; shell : string }
  | DebugEcho of { description : string; debug_command : string;
                   dap : string; args : Yojson.Safe.t list }
  | Unknown   of string

(** Convert a file:// URI back to a filesystem path. *)
let path_of_uri uri =
  if String.length uri >= 7 && String.sub uri 0 7 = "file://"
  then String.sub uri 7 (String.length uri - 7)
  else uri

(** Pure resolver for [workspace/executeCommand]. Maps a command id + JSON
    arguments to a [lens_command]. Kept pure (no shelling-out) so it can be
    unit-tested; the server executes the [RunShell] case. *)
let resolve_lens_command ~command ~(args : Yojson.Safe.t list) : lens_command =
  let str_arg i =
    match List.nth_opt args i with Some (`String s) -> Some s | _ -> None
  in
  match command, str_arg 0, str_arg 1 with
  | "march.runTest", Some uri, Some test_name ->
    let path = path_of_uri uri in
    (* `forge test` filters by test name via --filter=PATTERN; pass the file so
       the runner targets this suite, and the filter to scope to one test. *)
    let shell =
      Printf.sprintf "forge test --filter=%s %s"
        (Filename.quote test_name) (Filename.quote path)
    in
    RunShell { description =
                 Printf.sprintf "Running test %S in %s" test_name (Filename.basename path);
               shell }
  | "march.run", Some uri, _ ->
    let path = path_of_uri uri in
    (* `forge run` builds and runs the current project (fn main). *)
    RunShell { description = Printf.sprintf "Running %s" (Filename.basename path);
               shell = "forge run" }
  | "march.debugTest", Some uri, Some test_name ->
    DebugEcho { description =
                  Printf.sprintf "Launch debugger for test %S" test_name;
                debug_command = command;
                dap = "march dap";
                args = [ `String uri; `String test_name ] }
  | "march.debug", Some uri, _ ->
    DebugEcho { description = "Launch debugger for main";
                debug_command = command;
                dap = "march dap";
                args = [ `String uri ] }
  | _ -> Unknown command

(* ------------------------------------------------------------------ *)
(* Main analysis entry point                                           *)
(* ------------------------------------------------------------------ *)

let analyse ~filename ~src : t =
  (* [Tc]'s tvar display-name cache (`a`, `b`, … `y55`, …) is otherwise never
     reset for the LSP's lifetime — a long-lived process re-typechecking on
     every edit, unlike a one-shot compiler run. Left alone it climbs for as
     long as the server stays up, so an unresolved type variable in a small
     file can print a name like `y55` instead of `a`. Reset once per analysis
     pass so each pass's fresh variables again name from "a". *)
  Tc.reset_tvar_display_names ();
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  let parse_result =
    try
      Ok (March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
    with
    | Err.ParseError (msg, hint, pos) ->
      Error (`ParseError (msg, hint, pos))
    | March_parser.Parser.Error ->
      Error (`MenhirError (Lexing.lexeme_start_p lexbuf))
    | March_lexer.Lexer.Lexer_error msg ->
      Error (`LexerError (msg, Lexing.lexeme_start_p lexbuf))
  in
  let doc = Utf16.build src in
  let make_empty_with diag =
    { src;
      filename;
      doc;
      type_map         = Hashtbl.create 0;
      def_map          = Hashtbl.create 0;
      use_map          = Hashtbl.create 0;
      vars             = [];
      types            = [];
      ctors            = [];
      interfaces       = [];
      impls            = [];
      impl_sites       = Hashtbl.create 0;
      actors           = [];
      doc_map          = Hashtbl.create 0;
      refs_map         = Hashtbl.create 0;
      sym_defs         = Hashtbl.create 0;
      sym_uses         = Hashtbl.create 0;
      sym_id_uses      = Hashtbl.create 0;
      sym_name         = Hashtbl.create 0;
      sym_scope        = Hashtbl.create 0;
      call_sites       = [];
      call_graph       = [];
      imports          = [];
      module_index     = [];
      consumption      = [];
      reuse_hints      = [];
      match_sites      = [];
      diagnostics      = [diag];
      ctor_arities     = [];
      fold_ranges      = [];
      annotation_sites = [];
      unused_fns        = [];
      html_issues       = [];
      h_sigils          = [];
      type_matches      = [];
      naming_violations = [];
      demorgan_sites    = [];
      perf_insights     = [];
      consume_modes     = [];
      tir_fn_insights   = [];
      code_lens_items   = [];
      decls             = [];
      depot_source_decls = [];
      depot_schemas     = [];
      depot_col_occs    = [];
      depot_table_occs  = [];
      protocols         = [];
      transitions_index = [];
      always_linear_names = [];
      param_name_map    = build_param_name_map [];
      proof_cap_defs    = Hashtbl.create 0 }
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
    (* Desugar-level user errors (pipe-into-match, bad derive/satisfy, …)
       must be reported into a context, not raised: an exception escaping
       here would drop the entire publishDiagnostics notification and the
       editor would show no squiggle at all. *)
    let desugar_errors = Err.create () in
    let desugared =
      March_desugar.Desugar.desugar_module ~errors:desugar_errors raw_ast in
    let stdlib_decls = Stdlib_cache.load () in
    (* Resolve cross-file imports (user imports + forge dep imports).
       Build the extra lib-path list from:
         1. forge.toml [deps] resolved to absolute lib/ dirs
         2. MARCH_LIB_PATH env var (already handled inside resolve_imports) *)
    let forge_lib_paths =
      let start_dir =
        if filename = "" || filename = "<unknown>"
        then Sys.getcwd ()
        else Filename.dirname filename
      in
      match Forge_config.find_forge_root start_dir with
      | None      -> []
      | Some root -> Forge_config.project_lib_paths root
    in
    let (_resolve_errors, extra_decls, _user_files) =
      March_resolver.Resolver.resolve_imports
        ~extra_lib_paths:forge_lib_paths
        ~source_file:filename
        desugared
    in
    (* Incremental typecheck: the stdlib is typechecked once into a cached
       base env, and the resolved forge deps once into a deps env keyed by
       their content (Typecheck_cache). Only THIS file's own decls are checked
       per edit, layered on top via the incremental path. This replaces
       re-running the whole-module typechecker over [stdlib @ deps @ user] on
       every keystroke. *)
    let base      = Typecheck_cache.base_env () in
    let with_deps = Typecheck_cache.deps_env base ~deps:extra_decls in
    let scratch   = Typecheck_cache.derive with_deps in
    let (errors, type_map, final_env) =
      Tc.check_module_with_env_full scratch desugared
    in
    (* Merge desugar diagnostics into the typecheck context so they surface
       through the same diag_to_lsp path (user-file filter, span ordering). *)
    List.iter (Err.report errors) (Err.sorted desugar_errors);
    (* Parity with the compiler's own prelude-collision check (bin/main.ml /
       lib/modules/prelude_collision.ml) — otherwise the editor shows no
       diagnostic at all for a top-level fn the compiler now hard-rejects.
       Skip when this file IS a shipped stdlib module (matches
       [is_shipped_stdlib_file] in bin/main.ml): a stdlib file's own
       top-level names (e.g. List.reverse) are only ever loaded namespaced,
       never flattened, in real use — the LSP treats the OPEN file as an
       "entry" purely as an artifact of single-file analysis, exactly as
       `--check` does on the CLI, so the exemption is needed for the same
       reason there. *)
    let is_shipped_stdlib_file =
      List.mem (Filename.basename filename) March_modules.Stdlib_manifest.all_known
    in
    if not is_shipped_stdlib_file then
      March_modules.Prelude_collision.check ~prelude_decls:stdlib_decls
        ~ordinary_builtin_names:Tc.prelude_collision_builtin_names
        ~iface_method_arities:Tc.prelude_collision_iface_arities
        ~entry_decls:desugared.Ast.mod_decls errors;
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
            | Ast.DProtocol (_, _, sp) -> sp
            | Ast.DTest (_, sp)     -> sp
            | Ast.DDescribe (_, _, sp) -> sp
            | Ast.DUse (_, sp)      -> sp
            | Ast.DAlias (_, sp)    -> sp
            | Ast.DNeeds (_, sp)    -> sp
            | Ast.DProofCap (_, _, sp) -> sp
            | Ast.DOpts (_, sp)     -> sp
            | Ast.DTransitions (_, _, sp) -> sp
            | Ast.DAlwaysLinearType (_, _, _, _, sp) -> sp
            | Ast.DSetup (_, sp)    -> sp
            | Ast.DSetupAll (_, sp) -> sp
            | _                     -> Ast.dummy_span
          in
          is_user_file sp
        ) raw_ast.Ast.mod_decls
    in
    let depot_source_decls = user_decls @ extra_decls in
    let depot_schemas = Depot.schemas_in depot_source_decls in
    let depot_col_occs = Depot.column_occurrences depot_schemas depot_source_decls in
    let depot_table_occs = Depot.table_occurrences depot_source_decls in
    (* Populate doc_map with stdlib function docs first so that user-defined
       functions with the same name take precedence (user docs overwrite). *)
    collect_docs ~doc_map stdlib_decls;
    List.iter (collect_decl ~def_map ~use_map ~doc_map ~calls:call_sites_acc ~actors_tbl) user_decls;
    (* Scope-aware local symbol resolution (for shadow-correct def/refs/rename). *)
    let { ss_defs = sym_defs; ss_uses = sym_uses;
          ss_id_uses = sym_id_uses; ss_name = sym_name;
          ss_scope = sym_scope } =
      collect_scoped user_decls
    in
    (* Collect stdlib definitions into def_map for cross-stdlib go-to-definition.
       Use throw-away tables for use_map/doc_map/calls/actors so we don't pollute
       the user-file maps with stdlib-internal references. *)
    let _slib_use    = Hashtbl.create 0 in
    let _slib_doc    = Hashtbl.create 0 in
    let _slib_calls  = ref [] in
    let _slib_actors = Hashtbl.create 0 in
    (* Snapshot the user's definitions so the stdlib pass below (which writes the
       same def_map) cannot shadow a user symbol that happens to share a name
       with a stdlib one — go-to-definition on the user's symbol must land on
       the user's file, not the stdlib. *)
    let user_defs = Hashtbl.copy def_map in
    List.iter
      (collect_decl ~def_map ~use_map:_slib_use ~doc_map:_slib_doc
         ~calls:_slib_calls ~actors_tbl:_slib_actors)
      stdlib_decls;
    (* User definitions win over same-named stdlib definitions. *)
    Hashtbl.iter (fun name sp -> Hashtbl.replace def_map name sp) user_defs;
    let actors = Hashtbl.fold (fun k v acc -> (k, v) :: acc) actors_tbl [] in
    (* Collect proof cap declarations and references. *)
    let proof_cap_defs = Hashtbl.create 4 in
    (* Phase 1: register proof cap defs (go-to-def target), recursing into DMod. *)
    let rec register_proof_caps decls =
      List.iter (function
        | Ast.DProofCap (name, _, _) ->
          Hashtbl.replace def_map name.txt name.span;
          Hashtbl.replace proof_cap_defs name.txt name.span
        | Ast.DMod (_, _, inner, _) -> register_proof_caps inner
        | _ -> ()
      ) decls
    in
    register_proof_caps user_decls;
    (* Phase 2: index Cap(X) type annotations and DNeeds paths as uses. *)
    let rec collect_cap_ty_refs (t : Ast.ty) =
      match t with
      | Ast.TyCon ({txt="Cap"; _}, [Ast.TyCon (inner, [])]) ->
        if Hashtbl.mem proof_cap_defs inner.txt then
          Hashtbl.replace use_map inner.span inner.txt
      | Ast.TyCon (_, args) -> List.iter collect_cap_ty_refs args
      | Ast.TyArrow (a, b) -> collect_cap_ty_refs a; collect_cap_ty_refs b
      | Ast.TyTuple ts -> List.iter collect_cap_ty_refs ts
      | Ast.TyRecord fields -> List.iter (fun (_, t) -> collect_cap_ty_refs t) fields
      | Ast.TyLinear (_, t) -> collect_cap_ty_refs t
      | _ -> ()
    in
    let walk_fn_param_tys (fn : Ast.fn_def) =
      Option.iter collect_cap_ty_refs fn.Ast.fn_ret_ty;
      List.iter (fun (cl : Ast.fn_clause) ->
        List.iter (function
          | Ast.FPNamed p | Ast.FPDefault (p, _) ->
            Option.iter collect_cap_ty_refs p.Ast.param_ty
          | Ast.FPPat _ -> ()
        ) cl.Ast.fc_params
      ) fn.Ast.fn_clauses
    in
    let rec collect_proof_cap_uses (d : Ast.decl) =
      match d with
      | Ast.DNeeds (paths, _) ->
        (* Proof-cap references live in the capability path; the optional path
           scope is a string literal and never names a proof cap. *)
        List.iter (fun (path, _scope) ->
          List.iter (fun (n : Ast.name) ->
            if Hashtbl.mem proof_cap_defs n.txt then
              Hashtbl.replace use_map n.span n.txt
          ) path
        ) paths
      | Ast.DFn (fn, _) -> walk_fn_param_tys fn
      | Ast.DMod (_, _, inner, _) -> List.iter collect_proof_cap_uses inner
      | _ -> ()
    in
    List.iter collect_proof_cap_uses user_decls;
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
      Tc.StrMap.fold (fun name cis acc ->
        (* Use head of list (most recently added) for the parent type *)
        match cis with
        | ci :: _ -> (name, ci.Tc.ci_type) :: acc
        | [] -> acc
      ) final_env.Tc.ctors []
    in
    (* Build ctor → surface arg types map (for typed stub generation — P1.1) *)
    let ctor_sigs_map : (string, Ast.ty list) Hashtbl.t = Hashtbl.create 16 in
    Tc.StrMap.iter (fun name cis ->
        if not (String.contains name '.') then
          match cis with
          | ci :: _ -> Hashtbl.replace ctor_sigs_map name ci.Tc.ci_arg_tys
          | [] -> ()
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
        (* Look up scrutinee type — filter to user-file spans only to avoid
           spurious matches against stdlib spans that happen to share the
           same line/col numbers as the current file. *)
        let scrut_sp = span_of_expr scrut in
        let scrut_line = scrut_sp.Ast.start_line - 1 in
        let scrut_char = scrut_sp.Ast.start_col in
        let is_user_span (sp : Ast.span) =
          sp.Ast.file = filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"
        in
        let candidates = Hashtbl.fold (fun sp ty acc ->
            if is_user_span sp &&
               Pos.span_contains sp ~line:scrut_line ~character:scrut_char
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
          (* Use the base type constructor name for the type_ctors_map lookup.
             Tc.pp_ty renders "Option(Int)" but the map key is just "Option". *)
          let base_type_name = match Tc.repr ty with
            | Tc.TCon (name, _) -> name
            | other -> Tc.pp_ty other
          in
          (match Hashtbl.find_opt type_ctors_map base_type_name with
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
    (* Extract a single missing case name from the typecheck diagnostic message
       for a given span, as a fallback when AST analysis cannot determine it. *)
    let diag_fallback_case sp =
      let prefix = "Non-exhaustive pattern match — missing case: " in
      let plen = String.length prefix in
      List.find_map (fun (d : March_errors.Errors.diagnostic) ->
          if d.span = sp &&
             String.length d.message >= plen &&
             String.sub d.message 0 plen = prefix
          then Some (String.sub d.message plen (String.length d.message - plen))
          else None
        ) (March_errors.Errors.sorted errors)
    in
    let match_sites =
      List.map (fun sp ->
          match Hashtbl.find_opt match_span_tbl sp with
          | Some (missing, ms_matched_type, ms_ctor_sigs) ->
            (* If AST analysis produced an empty missing list (e.g. the type
               lookup failed), fall back to the diagnostic message so that the
               quickfix still appears. *)
            let effective_missing =
              if missing <> [] then missing
              else
                match diag_fallback_case sp with
                | Some c -> [c]
                | None   -> []
            in
            { ms_span = sp; ms_missing_cases = effective_missing; ms_matched_type; ms_ctor_sigs }
          | None ->
            (* Fallback: no AST info found — use the single case from typecheck *)
            { ms_span = sp;
              ms_missing_cases = (match diag_fallback_case sp with Some c -> [c] | None -> []);
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
                      ~code:(`String "dead-code/unreachable-after-diverge")
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
                ~code:(`String "dead-code/unused-private-fn")
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
    let perf_insights =
      collect_perf_insights
        ~is_global:(fun n -> Tc.StrMap.mem n final_env.Tc.vars)
        type_map user_decls in
    let perf_diags = List.map perf_insight_to_diag perf_insights in
    let h_sigils = collect_h_sigils ~src user_decls in
    let html_issues = collect_html_issues ~src h_sigils in
    let html_diags =
      List.map (fun (hi : html_issue) ->
          Lsp.Types.Diagnostic.create
            ~range:(Pos.span_to_lsp_range hi.hi_open_span)
            ~severity:Lsp.Types.DiagnosticSeverity.Warning
            ~message:(`String (Printf.sprintf "Unclosed HTML tag `<%s>` in ~H template" hi.hi_tag))
            ~source:"march"
            ~code:(`String "html/unclosed-tag")
            ())
        html_issues
    in
    let html_lint_diags =
      List.map (fun (span, msg, code) ->
          Lsp.Types.Diagnostic.create
            ~range:(Pos.span_to_lsp_range span)
            ~severity:Lsp.Types.DiagnosticSeverity.Warning
            ~message:(`String msg)
            ~source:"march"
            ~code:(`String code)
            ())
        (collect_html_lint ~src h_sigils)
    in
    let vars_list = Tc.StrMap.bindings final_env.Tc.vars in
    let mi = module_index_of_vars vars_list in
    (* Island component validation.
       Conservative policy: we ONLY flag an island name when we can
       CONFIRM it is wrong — i.e. the name IS visible in module_index
       (as a top-level, bare-named module in the typecheck env) but
       lacks the required `create` and/or `render` functions.

       We do NOT flag names that are absent from module_index.  Two
       common legitimate cases would be falsely flagged otherwise:
         1. Nested modules (e.g. `mod App do mod Counter do … end end`)
            are keyed as "App.Counter" in module_index, not "Counter".
         2. Components defined in sibling files are not loaded into the
            per-file typecheck env, so they are simply absent.

       An editor warning that fires on correct code is worse than a
       missing warning, so we err on the side of silence for the
       "unknown name" case. *)
    let island_diags =
      List.concat_map (fun (s : h_sigil) ->
        List.filter_map (fun (isl : island_ref) ->
          match List.assoc_opt isl.isl_name mi with
          | None ->
            (* Cannot confirm the module is wrong — could be a nested or
               cross-file component not visible here.  Stay silent. *)
            None
          | Some members ->
            if List.mem "create" members && List.mem "render" members then None
            else Some (Lsp.Types.Diagnostic.create
              ~range:(Pos.span_to_lsp_range isl.isl_name_span)
              ~severity:Lsp.Types.DiagnosticSeverity.Warning
              ~message:(`String (Printf.sprintf
                "`%s` is a known module but is not a valid island: \
                 it must define `create` and `render`." isl.isl_name))
              ~source:"march"
              ~code:(`String "html/unknown-island")
              ()))
          (islands_in_sigil ~src s))
        h_sigils
    in
    let depot_diags =
      let is_current_file (sp : Ast.span) =
        sp.Ast.file = filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"
      in
      let make_diag (span, msg, code) =
        if not (is_current_file span) then None
        else Some (Lsp.Types.Diagnostic.create
          ~range:(Pos.span_to_lsp_range span)
          ~severity:Lsp.Types.DiagnosticSeverity.Warning
          ~message:(`String msg)
          ~source:"march"
          ~code:(`String code)
          ())
      in
      List.filter_map make_diag (Depot.column_diagnostics depot_schemas depot_col_occs)
      @ List.filter_map make_diag (Depot.table_diagnostics depot_schemas
          (Depot.table_occurrences depot_source_decls))
      @ List.filter_map make_diag (Depot.sql_injection_diagnostics depot_source_decls)
      @ (let ops = Depot.migration_ops depot_source_decls in
         List.filter_map make_diag (Depot.schema_drift_diagnostics depot_schemas ops depot_col_occs)
         @ List.filter_map make_diag (Depot.fk_column_diagnostics depot_schemas ops))
    in
    let diags =
      let compiler_diags =
        Err.sorted errors |> List.filter_map (diag_to_lsp ~filename)
      in
      (* The typechecker's own tail-call checker already reports every
         non-tail recursive call, at the same span, saying the same thing —
         so emitting the `perf/non-tail-call` insight as well put two
         near-identical messages in one hover. Keep the compiler's (it is the
         authority on whether this is an error or a warning, and it honours
         `@[no_warn_recursion]`) and drop the duplicate. Other perf insights
         have no compiler counterpart and are unaffected. *)
      let perf_diags =
        let covered (d : Lsp.Types.Diagnostic.t) =
          List.exists (fun (c : Lsp.Types.Diagnostic.t) -> c.range = d.range)
            compiler_diags
        in
        List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
            match d.code with
            | Some (`String "perf/non-tail-call") -> not (covered d)
            | _ -> true)
          perf_diags
      in
      compiler_diags
      @ !dead_code_diags
      @ unused_fn_diags
      @ perf_diags
      @ html_diags
      @ html_lint_diags
      @ island_diags
      @ depot_diags
    in
    { src; filename; doc; type_map; def_map; use_map;
      vars       = vars_list;
      types      = Tc.StrMap.bindings final_env.Tc.types;
      ctors      = Tc.StrMap.fold (fun name cis acc ->
                     match cis with ci :: _ -> (name, ci.Tc.ci_type) :: acc | [] -> acc)
                     final_env.Tc.ctors [];
      interfaces = Tc.StrMap.bindings final_env.Tc.interfaces;
      (* [Tc.impls] values are now [(ty * span * string option)] (the
         impl-coherence feature records each impl's declaration site and
         resolved declaring-module for overlap diagnostics); the LSP model
         keeps just the type, so drop the span and module. *)
      impls      = Tc.StrMap.fold (fun k vs acc ->
                     List.fold_left (fun a (ty, _sp, _m) -> (k, ty) :: a) acc vs)
                     final_env.Tc.impls [];
      impl_sites = collect_impl_sites user_decls;
      actors;
      doc_map;
      refs_map;
      sym_defs;
      sym_uses;
      sym_id_uses;
      sym_name;
      sym_scope;
      call_sites;
      call_graph       = build_call_graph user_decls;
      imports          = build_imports user_decls;
      module_index     = mi;
      consumption;
      reuse_hints      = build_reuse_hints user_decls;
      match_sites;
      diagnostics      = diags;
      ctor_arities     = Tc.StrMap.fold (fun name cis acc ->
                           match cis with
                           | ci :: _ -> (name, List.length ci.Tc.ci_arg_tys) :: acc
                           | [] -> acc)
                           final_env.Tc.ctors [];
      fold_ranges      = collect_fold_ranges raw_ast
                         @ collect_h_fold_ranges ~src h_sigils;
      annotation_sites = collect_annotation_sites raw_ast;
      unused_fns;
      html_issues;
      h_sigils;
      type_matches;
      naming_violations;
      demorgan_sites;
      perf_insights;
      consume_modes    = [];
      tir_fn_insights  = [];
      code_lens_items  = build_action_lenses ~filename user_decls;
      decls            = user_decls;
      depot_source_decls;
      depot_schemas;
      depot_col_occs;
      depot_table_occs;
      protocols        =
        List.filter_map (function
            | Ast.DProtocol (n, pd, _) -> Some (n.Ast.txt, pd)
            | _ -> None) user_decls;
      transitions_index =
        List.filter_map (function
            | Ast.DTransitions (n, arms, _) -> Some (n.Ast.txt, arms)
            | _ -> None) user_decls;
      always_linear_names =
        List.filter_map (function
            | Ast.DAlwaysLinearType (_, n, _, _, _) -> Some n.Ast.txt
            | _ -> None) user_decls;
      param_name_map   = build_param_name_map user_decls;
      proof_cap_defs }

(* ------------------------------------------------------------------ *)
(* Phase 3: TIR pipeline analysis                                      *)
(* ------------------------------------------------------------------ *)

module Tir = March_tir.Tir

(** Count optimization nodes in a TIR expression.
    Returns (stack_allocs, reuse_ops, indirect_calls, heap_allocs). *)
let rec tir_count_nodes (e : Tir.expr) : int * int * int * int =
  let add (sa1, ru1, ic1, ha1) (sa2, ru2, ic2, ha2) =
    (sa1+sa2, ru1+ru2, ic1+ic2, ha1+ha2)
  in
  match e with
  | Tir.EStackAlloc _                -> (1, 0, 0, 0)
  | Tir.EReuse _                     -> (0, 1, 0, 0)
  | Tir.ECallPtr _                   -> (0, 0, 1, 0)
  | Tir.EAlloc _                     -> (0, 0, 0, 1)
  | Tir.ELet (_, e1, e2)             -> add (tir_count_nodes e1) (tir_count_nodes e2)
  | Tir.ELetRec (fns, body)          ->
    let acc = List.fold_left (fun a (fn : Tir.fn_def) ->
        add a (tir_count_nodes fn.fn_body)) (0,0,0,0) fns in
    add acc (tir_count_nodes body)
  | Tir.ECase (_, branches, def_opt) ->
    let acc = List.fold_left (fun a (br : Tir.branch) ->
        add a (tir_count_nodes br.br_body)) (0,0,0,0) branches in
    (match def_opt with Some d -> add acc (tir_count_nodes d) | None -> acc)
  | Tir.ESeq (e1, e2)                -> add (tir_count_nodes e1) (tir_count_nodes e2)
  | _                                -> (0, 0, 0, 0)

(** Run the full TIR pipeline on [a]'s source, then annotate [a] with
    per-function TIR insights and code lens items.  Called asynchronously
    after the synchronous [analyse] completes so the editor sees AST-level
    diagnostics immediately and TIR-level hints arrive shortly after. *)
(* Memo of the TIR-derived insight fields keyed by source text. The TIR
   pipeline (lower→mono→defun→…→escape) is expensive and produces insights
   (not artifacts), so the CAS artifact store does not fit; a source-hash memo
   makes a background fiber re-firing for unchanged text return instantly.
   Value = (tir_fn_insights, code_lens_items, tir-derived perf_insights). The
   tir perf insights are stored alone and recombined with the input analysis's
   own perf_insights on replay. *)
let tir_pass_cache :
  (string, tir_fn_insight list * code_lens_item list * perf_insight list
           * consume_modes list) Hashtbl.t
  = Hashtbl.create 16

let run_tir_pass (a : t) : t =
  (* Skip if there are errors — the TIR pipeline would fail on broken source. *)
  let has_errors = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
      d.severity = Some Lsp.Types.DiagnosticSeverity.Error
    ) a.diagnostics
  in
  if has_errors then a
  (* Idempotence. [analyse] always yields an analysis with no TIR insights, so a
     non-empty [tir_fn_insights] means this value is already the OUTPUT of a
     previous run. Without this guard a second run appends the pass's perf
     insights to a list that already contains them, and the user sees each
     insight twice. [tir_perf_insights] is a filter_map over [tir_fn_insights],
     so the empty case has nothing to duplicate and needs no guard.

     The old idempotence test tolerated this with a "<= n + 3" bound instead of
     checking equality, which is why it went unnoticed. *)
  else if a.tir_fn_insights <> [] then a
  else
    let cache_key = March_cas.Blake3.hash_string a.src in
    (* Preserve the actionable Run/Debug lenses already built in [analyse]
       (those carry a command); the TIR pass only ADDS informational perf
       lenses, it must not drop the action lenses. *)
    let action_lenses =
      List.filter (fun cl -> cl.cl_command <> None) a.code_lens_items
    in
    match Hashtbl.find_opt tir_pass_cache cache_key with
    | Some (tir_fn_insights, code_lens_items, tir_perf_insights, consume_modes) ->
      { a with tir_fn_insights;
               consume_modes;
               code_lens_items = action_lenses @ code_lens_items;
               perf_insights = a.perf_insights @ tir_perf_insights }
    | None ->
    try
      (* Re-lex and parse the original source to get a fresh Ast.module_.
         (The Analysis.t record does not store the parsed AST itself.) *)
      let lexbuf = Lexing.from_string a.src in
      lexbuf.Lexing.lex_curr_p <-
        { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = a.filename };
      let raw =
        March_parser.Parser.module_
          (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      in
      let desugared = March_desugar.Desugar.desugar_module raw in
      (* Run the SAME post-lower pipeline the build runs
         (lib/tir/contract_pipeline.ml: TRMC → mono → defun → known_call →
         … → perceus → drop → escape → opt → native_map_inline), so the
         insights, the code lenses and the @[no_alloc] verdict below describe
         the TIR the compiled program is actually built from.  `forge build`
         never passes --no-opt, so opt is on; TRMC follows the global flag. *)
      let tir = March_tir.Lower.lower_module ~type_map:a.type_map desugared in
      (* Root every declaration this file makes so the DCE inside Opt.run
         cannot prune a helper `main` never calls — its lens must still
         describe it.  A rooted function's body is optimised exactly as the
         build optimises it; only reachability differs.  Names are pre-Mono;
         the pipeline expands them to their monomorphised clones. *)
      let user_names = Hashtbl.fold (fun k _ acc -> k :: acc) a.def_map [] in
      let borrow_snapshot = ref None in
      let pipe =
        March_tir.Contract_pipeline.run
          (* Borrow inference BEFORE Perceus: this is the same map Perceus
             itself consults to decide which arguments need an EIncRC at a
             call site, so the hint reports the compiler's actual decision
             rather than a re-derivation of it. *)
          ~before_perceus:(fun pre ->
              borrow_snapshot := Some (March_tir.Borrow.infer_module pre, pre))
          ~extra_roots:user_names
          ~opt:true ~trmc:!March_tir.Trmc.enabled tir
      in
      let consume_modes =
        match !borrow_snapshot with
        | None -> []
        | Some (borrow_map, tir) ->
          List.filter_map (fun (fn : Tir.fn_def) ->
                if fn.Tir.fn_name = "" || fn.Tir.fn_name.[0] = '$' then None
                else
                  let consumes =
                    List.mapi (fun i (p : Tir.var) ->
                        (* Consuming = takes ownership AND there is ownership to
                           take. Skipping non-RC parameters is what keeps this hint
                           off every Int argument (see [consume_modes]). *)
                        (not (March_tir.Borrow.is_borrowed borrow_map fn.Tir.fn_name i))
                        && March_tir.Rc_types.needs_rc p.Tir.v_ty)
                      fn.Tir.fn_params
                  in
                  if List.exists (fun c -> c) consumes
                  then Some { cm_fn_name = fn.Tir.fn_name; cm_consumes = consumes }
                  else None)
              tir.Tir.tm_fns
      in
      let tir = pipe.March_tir.Contract_pipeline.final in
      (* Collect per-function optimization counts *)
      let tir_fn_insights =
        List.filter_map (fun (fn : Tir.fn_def) ->
            (* Skip synthetic functions generated by lower.ml (prefixed with '$') *)
            if fn.fn_name = "" || fn.fn_name.[0] = '$' then None
            else begin
              let (sa, ru, ic, ha) = tir_count_nodes fn.fn_body in
              if sa + ru + ic + ha = 0 then None
              else Some {
                tfi_fn_name        = fn.fn_name;
                tfi_stack_allocs   = sa;
                tfi_reuse_ops      = ru;
                tfi_indirect_calls = ic;
                tfi_heap_allocs    = ha;
              }
            end
          ) tir.Tir.tm_fns
      in
      (* Build code lens items — one per function with interesting TIR data.
         Map function names back to source spans via def_map. *)
      let code_lens_items =
        List.filter_map (fun (tfi : tir_fn_insight) ->
            match Hashtbl.find_opt a.def_map tfi.tfi_fn_name with
            | None -> None
            | Some sp ->
              let parts = [] in
              let parts =
                if tfi.tfi_stack_allocs > 0 then
                  Printf.sprintf "⚡ %d stack-allocated" tfi.tfi_stack_allocs :: parts
                else parts
              in
              let parts =
                if tfi.tfi_reuse_ops > 0 then
                  Printf.sprintf "♻ %d in-place" tfi.tfi_reuse_ops :: parts
                else parts
              in
              let parts =
                if tfi.tfi_indirect_calls > 0 then
                  Printf.sprintf "⚠ %d indirect call%s"
                    tfi.tfi_indirect_calls
                    (if tfi.tfi_indirect_calls > 1 then "s" else "")
                  :: parts
                else parts
              in
              if parts = [] then None
              else Some {
                cl_range   = Pos.span_to_lsp_range sp;
                cl_title   = String.concat " · " (List.rev parts);
                cl_command = None;   (* informational perf summary — not clickable *)
                cl_args    = [];
              }
          ) tir_fn_insights
      in
      (* Produce perf insights at function-definition spans (Hint severity) so
         they appear in hover and the problems panel. *)
      let tir_perf_insights =
        List.filter_map (fun (tfi : tir_fn_insight) ->
            match Hashtbl.find_opt a.def_map tfi.tfi_fn_name with
            | None -> None
            | Some sp ->
              (* We emit one combined insight per function when any of the
                 three optimizations are active.  Keep the most impactful. *)
              if tfi.tfi_stack_allocs > 0 then
                Some { pi_span    = sp;
                       pi_kind    = StackPromoted { pi_count = tfi.tfi_stack_allocs };
                       pi_message = Printf.sprintf
                         "March stack-allocates %d value%s in this function \
                          — no heap involvement and no memory-management cost \
                          for %s."
                         tfi.tfi_stack_allocs
                         (if tfi.tfi_stack_allocs > 1 then "s" else "")
                         (if tfi.tfi_stack_allocs > 1 then "them" else "it") }
              else if tfi.tfi_reuse_ops > 0 then
                Some { pi_span    = sp;
                       pi_kind    = FbipReuse { pi_count = tfi.tfi_reuse_ops };
                       pi_message = Printf.sprintf
                         "March updates %d value%s in place in this function \
                          instead of allocating new memory — no extra allocation \
                          when the input is uniquely owned."
                         tfi.tfi_reuse_ops
                         (if tfi.tfi_reuse_ops > 1 then "s" else "") }
              else if tfi.tfi_indirect_calls > 0 then
                Some { pi_span    = sp;
                       pi_kind    = TirIndirectCall { pi_fn_name  = tfi.tfi_fn_name;
                                                      pi_count    = tfi.tfi_indirect_calls };
                       pi_message = Printf.sprintf
                         "This function makes %d indirect call%s through a function \
                          pointer. If you specialize it for a specific callback, \
                          March can call it directly."
                         tfi.tfi_indirect_calls
                         (if tfi.tfi_indirect_calls > 1 then "s" else "") }
              else None
          ) tir_fn_insights
      in
      Hashtbl.replace tir_pass_cache cache_key
        (tir_fn_insights, code_lens_items, tir_perf_insights, consume_modes);
      { a with
        tir_fn_insights;
        consume_modes;
        code_lens_items = action_lenses @ code_lens_items;
        perf_insights = a.perf_insights @ tir_perf_insights;
      }
    with _ ->
      (* TIR pipeline failed (e.g. unsupported construct) — return analysis unchanged *)
      a

(* ------------------------------------------------------------------ *)
(* Query helpers                                                       *)
(* ------------------------------------------------------------------ *)

let ty_at (a : t) ~line ~character : Tc.ty option =
  let is_user_span (sp : Ast.span) =
    sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"
  in
  let candidates = Hashtbl.fold (fun sp ty acc ->
      if is_user_span sp && Pos.span_contains sp ~line ~character then (sp, ty) :: acc
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
    Some ty

(* Find the Depot schema field under the cursor, if any.

   [co_span] covers the whole string literal, opening quote through closing
   quote, so containment is a direct range test.  This used to back-compute
   the opening quote as [start_col - String.length co_col - 1], because a
   string literal's span recorded only its CLOSING quote; that is fixed, and
   the back-computation was in any case wrong for a column name containing an
   escape, where the literal's source extent is longer than its value. *)
let depot_field_at (a : t) ~line ~character
    : (Depot.col_occ * Depot.depot_field) option =
  List.find_map (fun (occ : Depot.col_occ) ->
    let sp = occ.co_span in
    let sl = sp.start_line - 1 in
    (* end_col is one past the closing quote, so [<] keeps the old inclusive
       "cursor may sit on either quote" behaviour. *)
    if line = sl && character >= sp.start_col && character < sp.end_col then
      match List.find_opt (fun (s : Depot.schema) -> s.ds_table = occ.co_table)
              a.depot_schemas with
      | Some schema ->
        List.find_opt (fun (f : Depot.depot_field) -> f.df_name = occ.co_col)
          schema.ds_fields
        |> Option.map (fun f -> (occ, f))
      | None -> None
    else None)
  a.depot_col_occs

let type_at (a : t) ~line ~character : string option =
  match depot_field_at a ~line ~character with
  | Some (_, f) -> Some f.df_type
  | None -> Option.map Tc.pp_ty (ty_at a ~line ~character)

(* Smallest local-binder use/def span containing the cursor -> its symbol id.
   [None] means the cursor is not on a function-local binding (top-level/stdlib,
   resolved by the name-based maps instead). *)
let definition_at (a : t) ~line ~character : Lsp.Types.Location.t option =
  (* Depot column string: jump to the field name in the schema definition. *)
  (match depot_field_at a ~line ~character with
   | Some (_, f) ->
     let sp = f.df_name_span in
     let path =
       if sp.Ast.file = "" || sp.Ast.file = "<unknown>" then a.filename
       else sp.Ast.file
     in
     Some (Lsp.Types.Location.create
             ~uri:(Lsp.Types.DocumentUri.of_path path)
             ~range:(Pos.span_to_lsp_range sp))
   | None ->
  (* Island component name: cursor inside <island name='X' /> in a ~H sigil.
     Try X.create, then X.render, then X (the module name) in def_map. *)
  let island_result =
    List.fold_left (fun found (s : h_sigil) ->
        match found with
        | Some _ -> found
        | None ->
          List.fold_left (fun found2 (isl : island_ref) ->
              match found2 with
              | Some _ -> found2
              | None ->
                if Pos.span_contains isl.isl_name_span ~line ~character then
                  let name = isl.isl_name in
                  let try_keys = [name ^ ".create"; name ^ ".render"; name] in
                  List.fold_left (fun hit k ->
                      match hit with
                      | Some _ -> hit
                      | None ->
                        (match Hashtbl.find_opt a.def_map k with
                         | None -> None
                         | Some def_sp ->
                           let path =
                             if def_sp.Ast.file = "" || def_sp.Ast.file = "<unknown>"
                             then a.filename
                             else def_sp.Ast.file
                           in
                           Some (Lsp.Types.Location.create
                                   ~uri:(Lsp.Types.DocumentUri.of_path path)
                                   ~range:(Pos.span_to_lsp_range def_sp)))
                    ) None try_keys
                else None
            ) found (islands_in_sigil ~src:a.src s)
      ) None a.h_sigils
  in
  match island_result with
  | Some _ -> island_result
  | None ->
  (* Local binder under the cursor resolves by scope (shadow-correct). *)
  match local_symbol_at a ~line ~character with
  | Some id ->
    (match Hashtbl.find_opt a.sym_defs id with
     | Some def_sp ->
       let path =
         if def_sp.Ast.file = "" || def_sp.Ast.file = "<unknown>" then a.filename
         else def_sp.Ast.file
       in
       let uri = Lsp.Types.DocumentUri.of_path path in
       Some (Lsp.Types.Location.create ~uri
               ~range:(Pos.span_to_lsp_range def_sp))
     | None -> None)
  | None ->
  let var_name =
    Hashtbl.fold (fun sp name found ->
        match found with
        | Some _ -> found
        | None ->
          if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
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
            if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
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
  ) (* end depot_field_at match *)

let keywords = [
  "mod"; "end"; "do"; "fn"; "let"; "match"; "if"; "else";
  "type"; "interface"; "impl"; "derive"; "use"; "alias"; "needs";
  "extern"; "app"; "actor"; "protocol"; "when"; "as";
  "true"; "false"; "linear"; "affine"; "pub";
]

(* Dot-completion: when the cursor sits in `receiver.<prefix>`, complete the
   members of the receiver's type instead of dumping the global namespace.
   Currently handles a single-identifier receiver of record type (structural
   TRecord); returns [None] for any non-dot or unresolved context so the caller
   falls back to the general completion list. *)
let dot_completions (a : t) ~line ~character : Lsp.Types.CompletionItem.t list option =
  let open Lsp.Types in
  let is_ident_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_'
  in
  let src = a.src in
  let n = String.length src in
  let ls = Utf16.line_start a.doc line in
  let off = ls + character in
  if off < 0 || off > n then None
  else begin
    (* Skip the identifier prefix currently being typed (may be empty). *)
    let i = ref off in
    while !i > 0 && is_ident_char src.[!i - 1] do decr i done;
    if not (!i > 0 && src.[!i - 1] = '.') then None
    else begin
      (* Receiver: the identifier immediately left of the dot, on this line. *)
      let k = ref (!i - 2) in
      while !k >= 0 && (src.[!k] = ' ' || src.[!k] = '\t') do decr k done;
      let rcv_end = !k in
      while !k >= 0 && is_ident_char src.[!k] do decr k done;
      let rcv_start = !k + 1 in
      if rcv_start > rcv_end || rcv_end < ls then None
      else
        match ty_at a ~line ~character:(rcv_end - ls) with
        | Some (Tc.TRecord flds) ->
          Some (List.map (fun (fname, fty) ->
              CompletionItem.create ~label:fname
                ~kind:CompletionItemKind.Field ~detail:(Tc.pp_ty fty) ()) flds)
        | _ -> None
    end
  end

(* Distinct names of function-local bindings (params, lets, lambda/match
   binders) that are in scope at the cursor and defined before it. *)
let scope_locals_at (a : t) ~line ~character : string list =
  let seen = Hashtbl.create 16 in
  let out = ref [] in
  Hashtbl.iter (fun id scope_sp ->
      if Pos.span_contains scope_sp ~line ~character then
        match Hashtbl.find_opt a.sym_defs id with
        | None -> ()
        | Some def_sp ->
          let dl = def_sp.Ast.start_line - 1 in
          let before =
            dl < line || (dl = line && def_sp.Ast.start_col <= character)
          in
          if before then begin
            let name = try Hashtbl.find a.sym_name id with Not_found -> "" in
            if name <> "" && name.[0] <> '_' && not (Hashtbl.mem seen name)
            then (Hashtbl.replace seen name (); out := name :: !out)
          end)
    a.sym_scope;
  !out

(* ------------------------------------------------------------------ *)
(* DAP inline values (textDocument/inlineValue)                        *)
(* ------------------------------------------------------------------ *)
(* While the debugger is stopped at a line, the editor requests inline  *)
(* values for the currently-visible range. We return the in-scope local *)
(* variables (bindings + uses) whose span lies within that range and    *)
(* at/above the stopped line as InlineValueVariableLookups, letting the *)
(* debugger resolve their live values. We de-duplicate by variable name *)
(* keeping the occurrence nearest the stopped line, so the editor draws *)
(* one inline value per variable instead of one per textual occurrence. *)

(* True if [sp] starts within the inclusive 0-indexed line band
   [range_start_line, range_end_line] and is at/above [stopped_line]. *)
let span_in_inline_band (sp : Ast.span)
    ~range_start_line ~range_end_line ~stopped_line : bool =
  let l = sp.Ast.start_line - 1 in  (* 0-indexed *)
  l >= range_start_line && l <= range_end_line && l <= stopped_line

(* The variables (local bindings + uses) visible within [range] and at/above
   the stopped line. [range_start_line]/[range_end_line]/[stopped_line] are
   0-indexed LSP lines. Returns InlineValueVariableLookups with byte-column
   ranges; the UTF-16 query wrapper remaps them. De-duplicated by variable
   name, keeping the occurrence whose line is closest to (but not below) the
   stopped line. Error-resilient: pulls only from the scoped symbol tables,
   never throws. *)
let inline_values_at (a : t) ~range_start_line ~range_end_line ~stopped_line
    : Lsp.Types.InlineValue.t list =
  (* name -> (best span so far, its 0-indexed line). "Best" = nearest the
     stopped line from above (largest line <= stopped_line). *)
  let best : (string, Ast.span * int) Hashtbl.t = Hashtbl.create 32 in
  let consider name sp =
    if name <> "" && name.[0] <> '_' && span_in_user_file a sp
       && span_in_inline_band sp ~range_start_line ~range_end_line ~stopped_line
    then begin
      let l = sp.Ast.start_line - 1 in
      match Hashtbl.find_opt best name with
      | Some (_, prev_l) when prev_l >= l -> ()      (* keep the closer one *)
      | _ -> Hashtbl.replace best name (sp, l)
    end
  in
  (* Every local binder id: its definition span and all its use spans are
     candidate occurrences. The scoped tables are already shadow-correct, so
     a use only appears under the name of the binding it actually resolves to. *)
  Hashtbl.iter (fun id def_sp ->
      let name = try Hashtbl.find a.sym_name id with Not_found -> "" in
      consider name def_sp;
      let uses = try Hashtbl.find a.sym_id_uses id with Not_found -> [] in
      List.iter (consider name) uses)
    a.sym_defs;
  Hashtbl.fold (fun name (sp, _) acc ->
      let lookup =
        Lsp.Types.InlineValueVariableLookup.create
          ~caseSensitiveLookup:true
          ~range:(Pos.span_to_lsp_range sp)
          ~variableName:name ()
      in
      `InlineValueVariableLookup lookup :: acc)
    best []

(* The identifier prefix immediately before the cursor. Empty when the cursor
   is not on a bare identifier (e.g. right after a `.`, which is a qualified
   access handled by dot-completion, not auto-import). *)
let prefix_at (a : t) ~line ~character : string =
  match List.nth_opt (String.split_on_char '\n' a.src) line with
  | None -> ""
  | Some text ->
    let c = min character (String.length text) in
    let is_id ch =
      (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
      || (ch >= '0' && ch <= '9') || ch = '_' || ch = '\''
    in
    let i = ref c in
    while !i > 0 && is_id text.[!i - 1] do decr i done;
    if !i > 0 && text.[!i - 1] = '.' then ""   (* qualified access, not auto-import *)
    else String.sub text !i (c - !i)

(* Auto-import candidates: members of importable modules ([module_index]) whose
   short name starts with [prefix] and that [imports] does not already bring in
   bare. Returns (short_name, module) pairs; modules sharing a name each yield an
   entry. Pure over its inputs (prefix-gated ≥2 chars, capped) so it is unit-
   testable without a loaded stdlib. *)
let auto_import_candidates ~module_index ~imports ~prefix : (string * string) list =
  if String.length prefix < 2 then []
  else begin
    let plen = String.length prefix in
    let out = ref [] in
    List.iter (fun (m, names) ->
        List.iter (fun short ->
            if String.length short >= plen
               && String.sub short 0 plen = prefix
               && String.length short > 0 && short.[0] >= 'a' && short.[0] <= 'z'
               && not (module_imports_bare imports ~module_:m ~name:short)
            then out := (short, m) :: !out
          ) names
      ) module_index;
    List.filteri (fun i _ -> i < 50) (List.sort_uniq compare !out)
  end

(* The TextEdit (byte columns) that imports [name] from [module_], computed
   purely from the file's [imports] and a [fallback_line] (1-indexed line to put
   a brand-new import on when the file has none): merge into an existing
   `use M.{...}` if present, else insert a fresh `use M.{name}` line. *)
let compute_import_edit ~imports ~fallback_line ~module_ ~name
    : Lsp.Types.TextEdit.t option =
  let open Lsp.Types in
  let zero_width line0 col =
    Range.create ~start:(Position.create ~line:line0 ~character:col)
      ~end_:(Position.create ~line:line0 ~character:col)
  in
  let named =
    List.find_opt (fun ii ->
        ii.ii_module = module_ &&
        (match ii.ii_sel with ISNames _ -> true | _ -> false)) imports
  in
  match named with
  | Some { ii_sel = ISNames (_ :: _ as names); _ } ->
    let last = List.nth names (List.length names - 1) in
    let sp = last.Ast.span in
    Some (TextEdit.create ~range:(zero_width (sp.Ast.end_line - 1) sp.Ast.end_col)
            ~newText:(", " ^ name))
  | _ ->
    (match imports with
     | _ :: _ ->
       let last =
         List.fold_left (fun acc ii ->
             if ii.ii_span.Ast.end_line > acc.ii_span.Ast.end_line then ii else acc)
           (List.hd imports) imports
       in
       let indent = String.make last.ii_span.Ast.start_col ' ' in
       Some (TextEdit.create
               ~range:(zero_width (last.ii_span.Ast.end_line - 1) last.ii_span.Ast.end_col)
               ~newText:(Printf.sprintf "\n%suse %s.{%s}" indent module_ name))
     | [] ->
       Some (TextEdit.create ~range:(zero_width (fallback_line - 1) 0)
               ~newText:(Printf.sprintf "  use %s.{%s}\n" module_ name)))

let import_text_edit (a : t) ~module_ ~name : Lsp.Types.TextEdit.t option =
  (* New imports go on the first user declaration line (>= 2 to stay inside the
     enclosing `mod`), defaulting to line 2. *)
  let fallback_line =
    Hashtbl.fold (fun _ sp acc ->
        if span_in_user_file a sp && sp.Ast.start_line >= 2
        then min acc sp.Ast.start_line else acc) a.def_map max_int
  in
  let fallback_line = if fallback_line = max_int then 2 else fallback_line in
  compute_import_edit ~imports:a.imports ~fallback_line ~module_ ~name

(** Detect if [prefix] (text from sigil start to cursor) ends with
    [name=''] or [name=""] and the nearest preceding '<' begins '<island'. *)
let is_island_name_context (prefix : string) : bool =
  (* Must end with name=single-quote or name=double-quote *)
  let n = String.length prefix in
  let suffix_match =
    (n >= 6 && String.sub prefix (n - 6) 6 = "name='")
    || (n >= 6 && String.sub prefix (n - 6) 6 = "name=\"")
  in
  if not suffix_match then false
  else begin
    (* Scan back for the nearest '<' and check the tag starts with 'island' *)
    let i = ref (n - 7) in
    while !i >= 0 && prefix.[!i] <> '<' do decr i done;
    if !i < 0 then false
    else
      let rest_len = n - !i in
      rest_len >= 7 && String.sub prefix !i 7 = "<island"
  end

(** Check whether the cursor is on a transition arm [via] position.
    Returns completions filtered to functions that are plausible transition
    functions for the handle type named in the enclosing [transitions] block. *)
let via_completions (a : t) ~line ~character : Lsp.Types.CompletionItem.t list option =
  (* Extract the current line up to the cursor *)
  let lines = String.split_on_char '\n' a.src in
  let line_text = if line < List.length lines then List.nth lines line else "" in
  let char_capped = min character (String.length line_text) in
  let prefix = String.sub line_text 0 char_capped in
  (* Check the pattern: contains "->" and ends with "via" + optional word chars *)
  let has_arrow = String.contains prefix '>' &&
    (let idx = String.rindex prefix '>' in idx > 0 && prefix.[idx-1] = '-') in
  if not has_arrow then None
  else begin
    (* Does the prefix contain " via" after the last "->"? *)
    let after_arrow =
      match String.rindex_opt prefix '>' with
      | None -> prefix
      | Some i -> String.sub prefix i (String.length prefix - i)
    in
    let trimmed = String.trim after_arrow in
    let via_pos = (* find " via" in after_arrow *)
      let len = String.length after_arrow in
      let rec find i =
        if i > len - 4 then None
        else if String.sub after_arrow i 4 = " via" then Some i
        else find (i + 1)
      in find 0
    in
    let _ = trimmed in
    match via_pos with
    | None -> None
    | Some _ ->
      (* Scan backwards in source for "transitions <name> do" *)
      let cur_ofs = pos_to_ofs a.src (line + 1) character in
      let src = a.src in
      let src_len = String.length src in
      (* Search backwards from cur_ofs for the token "transitions" *)
      let handle_name =
        let keyword = "transitions" in
        let klen = String.length keyword in
        let rec search i =
          if i < 0 then None
          else if i + klen <= src_len && String.sub src i klen = keyword then begin
            (* Skip whitespace after keyword *)
            let j = ref (i + klen) in
            while !j < src_len && (src.[!j] = ' ' || src.[!j] = '\t') do incr j done;
            (* Read the name token *)
            let start = !j in
            while !j < src_len && (let c = src.[!j] in
              (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c = '_') do incr j done;
            if !j > start then Some (String.sub src start (!j - start))
            else None
          end else search (i - 1)
        in
        search (min (cur_ofs - 1) (src_len - 1))
      in
      (match handle_name with
       | None -> None
       | Some h_name ->
         (* Filter vars to functions whose type has h_name as head of first arg
            and last result — i.e., transition-shaped: h_name(...) -> h_name(...) *)
         let open Lsp.Types in
         let open Tc in
         let rec repr = function TVar {contents = Link t; _} -> repr t | t -> t in
         let rec result_ty = function
           | TArrow (_, r) -> result_ty (repr r)
           | t -> t
         in
         let is_transition_fn scheme =
           let ty = match scheme with Mono t -> t | Poly (_, _, t) -> t in
           match repr ty with
           | TArrow (arg, _) ->
             (match repr arg with
              | TCon (name, _) ->
                let bare = match String.rindex_opt name '.' with
                  | Some i -> String.sub name (i+1) (String.length name - i - 1)
                  | None -> name in
                (bare = h_name || name = h_name) &&
                (match repr (result_ty ty) with
                 | TCon (rn, _) ->
                   let rb = match String.rindex_opt rn '.' with
                     | Some i -> String.sub rn (i+1) (String.length rn - i - 1)
                     | None -> rn in
                   rb = h_name || rn = h_name
                 | _ -> false)
              | _ -> false)
           | _ -> false
         in
         let items = List.filter_map (fun (name, scheme) ->
             if String.length name > 0 && name.[0] <> '_' && is_transition_fn scheme
             then begin
               let ty = match scheme with Mono t -> t | Poly (_, _, t) -> t in
               let detail = pp_ty ty in
               Some (CompletionItem.create ~label:name
                       ~kind:CompletionItemKind.Function ~detail ())
             end else None
           ) a.vars in
         if items = [] then None else Some items)
  end

let completions_at (a : t) ~line ~character =
  match dot_completions a ~line ~character with
  | Some items -> items   (* in `receiver.`: only the receiver's members *)
  | None ->
  (* ------------------------------------------------------------------ *)
  (* Via-position in transitions block: complete with transition fns     *)
  (* ------------------------------------------------------------------ *)
  match via_completions a ~line ~character with
  | Some items -> items
  | None ->
  (* ------------------------------------------------------------------ *)
  (* Depot column-name context: cursor inside a column-arg string        *)
  (* ------------------------------------------------------------------ *)
  let depot_col_items =
    let open Lsp.Types in
    List.find_map (fun (occ : Depot.col_occ) ->
      let sp = occ.co_span in
      (* co_span covers the whole literal; end_col is one past the closing
         quote.  See depot_field_at for why this is no longer back-computed. *)
      let sl = sp.start_line - 1 in
      if line = sl && character >= sp.start_col && character < sp.end_col then
        match List.find_opt (fun (s : Depot.schema) -> s.ds_table = occ.co_table)
                a.depot_schemas with
        | Some schema ->
          Some (List.map (fun (f : Depot.depot_field) ->
            CompletionItem.create
              ~label:f.df_name
              ~kind:CompletionItemKind.Field
              ~detail:f.df_type
              ()) schema.ds_fields)
        | None -> None
      else None)
    a.depot_col_occs
  in
  (* ------------------------------------------------------------------ *)
  (* Depot table-name context: cursor inside a from_table/Migration arg  *)
  (* ------------------------------------------------------------------ *)
  let depot_table_items =
    let open Lsp.Types in
    List.find_map (fun (occ : Depot.table_occ) ->
      let sp = occ.to_span in
      (* to_span covers the whole literal; end_col is one past the closing
         quote.  See depot_field_at for why this is no longer back-computed. *)
      let sl = sp.start_line - 1 in
      if line = sl && character >= sp.start_col && character < sp.end_col then
        Some (List.map (fun (s : Depot.schema) ->
          CompletionItem.create
            ~label:s.ds_table
            ~kind:CompletionItemKind.Value
            ()) a.depot_schemas)
      else None)
    a.depot_table_occs
  in
  (match depot_col_items with
  | Some items -> items
  | None ->
  (match depot_table_items with
  | Some items -> items
  | None ->
  (* ------------------------------------------------------------------ *)
  (* Island-name context: cursor just after <island name=' or name=''    *)
  (* ------------------------------------------------------------------ *)
  (* pos_to_ofs takes 1-indexed line; line here is 0-indexed *)
  let cur_ofs = pos_to_ofs a.src (line + 1) character in
  let island_items =
    List.find_map (fun (s : h_sigil) ->
        if s.hs_base_ofs <= cur_ofs && cur_ofs <= s.hs_close_ofs then begin
          let rel = cur_ofs - s.hs_base_ofs in
          let prefix = String.sub s.hs_content 0 rel in
          if is_island_name_context prefix then
            Some (List.filter_map (fun (name, members) ->
                if List.mem "create" members && List.mem "render" members then
                  Some (Lsp.Types.CompletionItem.create
                          ~label:name
                          ~kind:Lsp.Types.CompletionItemKind.Class ())
                else None
              ) a.module_index)
          else None
        end else None
      ) a.h_sigils
  in
  (match island_items with
  | Some items -> items
  | None ->
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
  let sigil_items = List.map (fun (label, detail, insert) ->
      CompletionItem.create ~label ~detail
        ~kind:CompletionItemKind.Snippet
        ~insertText:insert
        ~insertTextFormat:InsertTextFormat.Snippet ()
    ) [
      ("~H", "HTML template sigil → IOList", "~H\"${1:html}\"");
      ("~R", "Regex sigil", "~R\"${1:pattern}\"");
      ("~J", "JSON sigil", "~J\"${1:json}\"");
    ] in
  (* In-scope local bindings — offered first (they weren't offered at all
     before). *)
  let local_items = List.map (fun name ->
      CompletionItem.create ~label:name ~kind:CompletionItemKind.Variable ()
    ) (scope_locals_at a ~line ~character) in
  (* Auto-import candidates: un-imported qualified members matching the typed
     prefix. Ranked last; the import edit is computed lazily on resolve, so each
     item only carries the (module, name) in [data]. *)
  let auto_items =
    auto_import_candidates
      ~module_index:a.module_index ~imports:a.imports
      ~prefix:(prefix_at a ~line ~character)
    |> List.map (fun (short, m) ->
        CompletionItem.create ~label:short
          ~kind:CompletionItemKind.Function
          ~detail:(Printf.sprintf "auto-import from %s" m)
          ~sortText:"9"
          ~data:(`Assoc [("autoImport",
                          `Assoc [("module", `String m); ("name", `String short)])])
          ())
  in
  (* Rank by ORIGIN first, then category.
     
     This used to rank by category alone — locals, keywords, values, types,
     constructors, ... — which put every stdlib function above the user's own
     types and constructors, because values outrank both. Typing `B` in a
     module declaring `BTree` and `Branch` therefore offered `Base64.decode`
     and the whole of `BigInt` first, and the two names actually in scope were
     below the fold. What you defined in the file you are editing is almost
     always what you mean, so it goes first regardless of category.

     Match the edited file exactly rather than reusing [span_in_user_file],
     which also accepts empty / "<unknown>" spans — those belong to builtins,
     and promoting the entire builtin surface is the bug over again. *)
  let defined_here name =
    a.filename <> "" && a.filename <> "<unknown>" &&
    (match Hashtbl.find_opt a.def_map name with
     | Some sp -> sp.Ast.file = a.filename
     | None -> false)
  in
  let rank s items =
    List.map (fun it -> { it with CompletionItem.sortText = Some s }) items
  in
  (* [cat] is the within-band category digit; the leading digit is the band:
     0 = defined in this file, 1 = language-level, 2 = imported/stdlib. *)
  let rank_by_origin cat items =
    List.map (fun (it : CompletionItem.t) ->
        let band = if defined_here it.CompletionItem.label then "0" else "2" in
        { it with CompletionItem.sortText = Some (band ^ cat) }) items
  in
  rank "00" local_items
  @ rank "10" kw_items
  @ rank_by_origin "2" var_items
  @ rank_by_origin "3" type_items
  @ rank_by_origin "4" ctor_items
  @ rank_by_origin "5" iface_items
  @ rank "16" sigil_items
  @ auto_items
  ) (* end match island_items *)
  ) (* end match depot_table_items *)
  ) (* end match depot_col_items *)

(* ------------------------------------------------------------------ *)
(* Parameter-name inlay hints at call sites                            *)
(* ------------------------------------------------------------------ *)

(** Resolve a call's callee expression to a simple function name.
    - [EVar n]            → [n]                 (plain call: add(..))
    - [EField (_, n, _)]  → [n]                 (qualified call: M.add(..))
    Returns [None] for anything else (e.g. calling a computed function). *)
let callee_simple_name (callee : Ast.expr) : string option =
  match callee with
  | Ast.EVar n -> Some n.Ast.txt
  | Ast.EField (_, n, _) -> Some n.Ast.txt
  | _ -> None

(** Noise-reduction predicate: should the [param]-name hint on argument [arg]
    be suppressed? Rules (documented for users):
    1. Single-argument calls — one hint adds little and clutters common 1-arg
       calls like `print(x)`; suppress.
    2. The argument is a bare identifier whose name already equals the param
       name — `foo(width)` where the var IS `width` is fully redundant.
    3. The argument is a bare identifier that ends with the param name as a
       `.`-suffix or `_`-suffix match (e.g. `set(self.width)` for param
       `width`, or `make(max_width)` for param `width`) — the name is already
       visible, so the hint is redundant. *)
let suppress_param_hint ~(single_arg : bool) ~(param : string) (arg : Ast.expr) : bool =
  if single_arg then true
  else
    match arg with
    | Ast.EVar n ->
      let v = n.Ast.txt in
      v = param
      || (let suffix sep = sep ^ param in
          let ends_with s suf =
            let ls = String.length s and lf = String.length suf in
            ls >= lf && String.sub s (ls - lf) lf = suf
          in
          ends_with v (suffix ".") || ends_with v (suffix "_"))
    | Ast.EField (_, n, _) -> n.Ast.txt = param
    | _ -> false

let inlay_hints_for ?(perf_annotations = true) ?(param_names = true)
    (a : t) (range : Lsp.Types.Range.t) =
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
  (* Emit a small annotation [label] at the end of [sp]. *)
  let annotate sp label =
    if is_user_span sp && in_range sp then begin
      let pos = Pos.create
        ~line:(sp.Ast.end_line - 1) ~character:sp.Ast.end_col in
      hints := InlayHint.create
        ~position:pos ~label:(`String label) ~paddingLeft:true () :: !hints
    end
  in
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
  (* FBIP ownership annotations — the hint no other LSP can show: which
     bindings Perceus can reuse in place (♻) vs. which are deep-copied on
     send (⧉). *)
  if perf_annotations then begin
    List.iter (fun sp -> annotate sp "♻ reused") a.reuse_hints;
    List.iter (fun (pi : perf_insight) ->
        match pi.pi_kind with
        | ActorSendCopy _ -> annotate pi.pi_span "⧉ copied"
        | _ -> ()
      ) a.perf_insights;
    (* Consuming-call hints: mark arguments this call TAKES OWNERSHIP of, so
       ownership transfer is visible where it happens instead of having to be
       inferred from the callee's signature.

       Restricted to arguments that are a plain variable. A temporary
       (`f(g(x))`, `f([1,2])`) is consumed too, but nobody is surprised that a
       value with no name does not survive the call — whereas `f(xs)` ending
       the life of `xs` is exactly the thing worth seeing. Narrowing to named
       bindings is what keeps this a signal rather than decoration on every
       argument in the file. *)
    List.iter (fun (cs : call_site) ->
        match cs.cs_fn_name with
        | None -> ()
        | Some fname ->
          (match List.find_opt (fun cm -> cm.cm_fn_name = fname) a.consume_modes with
           | None -> ()
           | Some cm ->
             List.iteri (fun i (arg : Ast.expr) ->
                 match arg with
                 | Ast.EVar n when (match List.nth_opt cm.cm_consumes i with
                                    | Some true -> true | _ -> false) ->
                   annotate n.Ast.span "⊗ consumed"
                 | _ -> ())
               cs.cs_args)
      ) a.call_sites
  end;
  (* Parameter-name hints at call sites: foo(width: a, height: b).
     Emitted at the START of each positional argument as a Parameter inlay. *)
  if param_names then begin
    let pmap = a.param_name_map in
    (* Emit a Parameter hint [label] at the start of span [sp]. *)
    let param_hint sp label =
      if is_user_span sp && in_range sp then begin
        let pos = Pos.create
          ~line:(sp.Ast.start_line - 1) ~character:sp.Ast.start_col in
        hints := InlayHint.create
          ~position:pos ~label:(`String label)
          ~kind:InlayHintKind.Parameter
          ~paddingRight:true () :: !hints
      end
    in
    let handle_call callee args =
      match callee_simple_name callee with
      | None -> ()
      | Some name ->
        (match Hashtbl.find_opt pmap name with
         | None -> ()
         | Some params ->
           (* Respect arity: only pair up the args we have names for. Extra
              args (variadic) or extra params (curried/partial) are skipped. *)
           let single_arg = (match args with [_] -> true | _ -> false) in
           let rec pair ps ax =
             match ps, ax with
             | p :: ps', arg :: ax' ->
               if not (suppress_param_hint ~single_arg ~param:p arg) then
                 param_hint (span_of_expr arg) (p ^ ":");
               pair ps' ax'
             | _ -> ()
           in
           pair params args)
    in
    (* Visit each EApp call site reachable from user declarations. The generic
       [iter_expr] visitor handles the full expression grammar (so call sites
       nested in cond/sigil/spawn/etc. are covered too); we only walk decls to
       reach the top-level expressions to feed it. *)
    let walk_e = iter_expr (fun e ->
        match e with
        | Ast.EApp (callee, args, _) -> handle_call callee args
        | _ -> ())
    in
    let rec walk_decls decls = List.iter walk_decl decls
    and walk_decl (d : Ast.decl) =
      match d with
      | Ast.DFn (fd, _) ->
        List.iter (fun (cl : Ast.fn_clause) -> walk_e cl.Ast.fc_body)
          fd.Ast.fn_clauses
      | Ast.DLet (_, b, _) -> walk_e b.Ast.bind_expr
      | Ast.DMod (_, _, inner, _) -> walk_decls inner
      | Ast.DTest (td, _) -> walk_e td.Ast.test_body
      | Ast.DDescribe (_, inner, _) -> walk_decls inner
      | Ast.DSetup (e, _) | Ast.DSetupAll (e, _) -> walk_e e
      | Ast.DApp (ad, _) ->
        walk_e ad.Ast.app_body;
        (match ad.Ast.app_on_start with Some e -> walk_e e | None -> ());
        (match ad.Ast.app_on_stop with Some e -> walk_e e | None -> ())
      | _ -> ()
    in
    walk_decls a.decls
  end;
  (* Cap-requirement inlay hints: ⬡ Cap after calls to capability-requiring
     builtins.  Emitted only when the file already has DNeeds declarations —
     otherwise it's noise in cap-unaware code. *)
  let file_has_needs =
    List.exists (function Ast.DNeeds _ -> true | _ -> false) a.decls
  in
  if perf_annotations && file_has_needs then begin
    let builtin_cap_tbl = [
      "println",           "IO.Console";   "print",             "IO.Console";
      "file_exists",       "IO.FileRead";  "file_read",         "IO.FileRead";
      "file_open",         "IO.FileRead";  "file_stat",         "IO.FileRead";
      "file_read_line",    "IO.FileRead";  "file_read_chunk",   "IO.FileRead";
      "dir_exists",        "IO.FileRead";  "dir_list",          "IO.FileRead";
      "csv_open",          "IO.FileRead";  "csv_next_row",      "IO.FileRead";
      "file_write",        "IO.FileWrite"; "file_append",       "IO.FileWrite";
      "file_delete",       "IO.FileWrite"; "file_rename",       "IO.FileWrite";
      "dir_mkdir",         "IO.FileWrite"; "dir_mkdir_p",       "IO.FileWrite";
      "dir_rmdir",         "IO.FileWrite"; "dir_rm_rf",         "IO.FileWrite";
      "file_copy",         "IO.FileSystem";
      "tcp_connect",       "IO.NetConnect"; "tcp_listen",        "IO.NetListen";
      "http_get",          "IO.NetConnect"; "http_post",         "IO.NetConnect";
      "unix_time",         "IO.Clock";     "unix_time_ms",      "IO.Clock";
      "uuid_v7",           "IO.Clock";
      "random_bytes",      "IO.Random";    "stdlib_random_bytes","IO.Random";
      "process_argv",      "IO.Process";   "process_exit",      "IO.Process";
      "process_env_get",   "IO.Process";   "process_spawn",     "IO.Process";
    ] in
    let walk_cap = iter_expr (fun e ->
      match e with
      | Ast.EApp (Ast.EVar n, _, sp) ->
        (match List.assoc_opt n.Ast.txt builtin_cap_tbl with
         | Some cap -> annotate sp ("⬡ " ^ cap)
         | None -> ())
      | _ -> ())
    in
    let rec walk_cap_decls ds = List.iter walk_cap_decl ds
    and walk_cap_decl (d : Ast.decl) =
      match d with
      | Ast.DFn (fd, _) ->
        List.iter (fun cl -> walk_cap cl.Ast.fc_body) fd.Ast.fn_clauses
      | Ast.DLet (_, b, _) -> walk_cap b.Ast.bind_expr
      | Ast.DMod (_, _, inner, _) -> walk_cap_decls inner
      | Ast.DTest (td, _) -> walk_cap td.Ast.test_body
      | Ast.DDescribe (_, inner, _) -> walk_cap_decls inner
      | _ -> ()
    in
    walk_cap_decls a.decls
  end;
  !hints

let document_symbols (a : t) =
  let open Lsp.Types in
  (* textDocument/documentSymbol describes ONE document.  [def_map] spans the
     whole analysis, and the analysis has the prelude injected — so folding it
     unfiltered returned every stdlib definition as a symbol of whatever file
     happened to be open: measured at 6936 symbols for a one-function file, at
     line numbers belonging elsewhere.  The editor's outline and breadcrumbs
     are built from this, so it was not a harmless overcount.

     Identical in shape to the semantic-tokens leak fixed alongside it; both
     were invisible until the requests carrying them became reachable. *)
  let syms = Hashtbl.fold (fun name sp acc ->
      if sp.Ast.file <> a.filename then acc
      else
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
          if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
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
            if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
            else None
        ) a.def_map None
  in
  match name_opt with
  | None -> None
  | Some name -> doc_for a name

(* The (top-level) name under the cursor, filtered to user-file spans. Used by
   the server to query cross-file references/definition. Returns [None] when the
   cursor is not on a resolvable name. *)
let name_at (a : t) ~line ~character : string option =
  let from_use =
    Hashtbl.fold (fun sp name acc ->
        match acc with
        | Some _ -> acc
        | None ->
          if span_in_user_file a sp && Pos.span_contains sp ~line ~character
          then Some name else None)
      a.use_map None
  in
  match from_use with
  | Some _ -> from_use
  | None ->
    Hashtbl.fold (fun name sp acc ->
        match acc with
        | Some _ -> acc
        | None ->
          if span_in_user_file a sp && Pos.span_contains sp ~line ~character
          then Some name else None)
      a.def_map None

(* textDocument/implementation: from an interface name under the cursor, the
   `impl <iface> for ...` declaration sites. *)
let implementation_at (a : t) ~line ~character : Lsp.Types.Location.t list =
  match name_at a ~line ~character with
  | None -> []
  | Some name ->
    (match Hashtbl.find_opt a.impl_sites name with
     | None -> []
     | Some spans -> locations_of_spans a spans)

(* textDocument/typeDefinition: from an expression under the cursor, the
   definition of its (named) type. *)
let type_definition_at (a : t) ~line ~character : Lsp.Types.Location.t option =
  match ty_at a ~line ~character with
  | Some (Tc.TCon (name, _)) ->
    (match Hashtbl.find_opt a.def_map name with
     | None -> None
     | Some sp ->
       (match locations_of_spans a [sp] with l :: _ -> Some l | [] -> None))
  | _ -> None

(* textDocument/documentHighlight: occurrences of the symbol under the cursor
   within the current file (references, rendered as highlights). *)
let document_highlights_at (a : t) ~line ~character : Lsp.Types.DocumentHighlight.t list =
  (* First check: if the cursor is on an HTML tag name inside a ~H sigil,
     highlight the matching open/close pair. *)
  let tag_pair_result =
    List.find_map (fun (s : h_sigil) ->
        let pairs = tag_pairs_in_sigil ~src:a.src s in
        List.find_map (fun (op, cl) ->
            if Pos.span_contains op ~line ~character
            || Pos.span_contains cl ~line ~character then
              Some [
                Lsp.Types.DocumentHighlight.create
                  ~range:(Pos.span_to_lsp_range op)
                  ~kind:Lsp.Types.DocumentHighlightKind.Text ();
                Lsp.Types.DocumentHighlight.create
                  ~range:(Pos.span_to_lsp_range cl)
                  ~kind:Lsp.Types.DocumentHighlightKind.Text ();
              ]
            else None
          ) pairs
      ) a.h_sigils
  in
  match tag_pair_result with
  | Some hls -> hls
  | None ->
    match symbol_spans_at a ~line ~character with
    | None -> []
    | Some (def_opt, use_spans) ->
      (* The binding site is a Write; every use site is a Read. *)
      let mk kind (sp : Ast.span) =
        if sp = Ast.dummy_span then None
        else Some (Lsp.Types.DocumentHighlight.create
                     ~range:(Pos.span_to_lsp_range sp) ~kind ())
      in
      let writes =
        match def_opt with
        | Some sp -> Option.to_list (mk Lsp.Types.DocumentHighlightKind.Write sp)
        | None    -> []
      in
      let reads = List.filter_map (mk Lsp.Types.DocumentHighlightKind.Read) use_spans in
      writes @ reads

(* textDocument/linkedEditingRange: all occurrences (definition + uses) of the
   symbol under the cursor, so the editor can edit them simultaneously. *)
let linked_editing_ranges_at (a : t) ~line ~character : Ast.span list =
  (* First check: if the cursor is on an HTML tag name inside a ~H sigil,
     return the open/close tag name spans so the editor renames both at once. *)
  let tag_pair_result =
    List.find_map (fun (s : h_sigil) ->
        let pairs = tag_pairs_in_sigil ~src:a.src s in
        List.find_map (fun (op, cl) ->
            if Pos.span_contains op ~line ~character
            || Pos.span_contains cl ~line ~character then
              Some [op; cl]
            else None
          ) pairs
      ) a.h_sigils
  in
  match tag_pair_result with
  | Some spans -> spans
  | None -> []
  (* Deliberately NOTHING else — in particular NOT "the definition and every
     use of the symbol under the cursor", which this used to return.

     `linkedEditingRange` is not "find all occurrences". The client applies
     every keystroke to ALL returned ranges simultaneously, with no prompt and
     no confirmation, so the protocol is only safe for ranges that must be
     identical by construction — an open/close tag pair, which is the case
     handled above. Returning a symbol's uses turns ordinary typing into an
     implicit, un-asked-for rename: putting the cursor on `a` in
     `{ left: Some(a), ... } -> ... has_val(a, target)` returned both `a`
     spans, so typing one character silently rewrote the other occurrence too,
     on that line and on any other line a use appeared. Ranges that drift even
     slightly out of date then land mid-token and eat neighbouring characters
     (`Some(a)` becoming `Somea)`), which is how this surfaced: "typing on one
     line overwrites other lines".

     Renaming a symbol is `textDocument/rename`'s job — explicit, invoked by
     the user, and already supported here with a prepare step
     (`renameProvider` with `prepareProvider = true`), so nothing is lost by
     refusing to do it silently. *)

(* textDocument/selectionRange: the chain of nested AST spans containing the
   position, innermost first. Built from the spans the analysis already records
   (typed expressions, uses, definitions) — no raw AST needed. *)
let selection_range_at (a : t) ~line ~character : Ast.span list =
  let contains outer inner =
    (outer.Ast.start_line < inner.Ast.start_line ||
       (outer.Ast.start_line = inner.Ast.start_line &&
        outer.Ast.start_col <= inner.Ast.start_col))
    && (outer.Ast.end_line > inner.Ast.end_line ||
       (outer.Ast.end_line = inner.Ast.end_line &&
        outer.Ast.end_col >= inner.Ast.end_col))
  in
  let acc = Hashtbl.create 64 in
  let consider sp =
    if sp <> Ast.dummy_span && span_in_user_file a sp
       && Pos.span_contains sp ~line ~character
    then Hashtbl.replace acc sp ()
  in
  Hashtbl.iter (fun sp _ -> consider sp) a.type_map;
  Hashtbl.iter (fun sp _ -> consider sp) a.use_map;
  Hashtbl.iter (fun _ sp -> consider sp) a.def_map;
  let area sp =
    (sp.Ast.end_line - sp.Ast.start_line, sp.Ast.end_col - sp.Ast.start_col)
  in
  let sorted =
    Hashtbl.fold (fun sp () l -> sp :: l) acc []
    |> List.sort (fun a b -> compare (area a) (area b))
  in
  (* Walk from the smallest span outward, each step jumping to the smallest
     strictly-larger span that contains the current one. *)
  let rec build cur rest chain =
    match List.find_opt (fun sp -> contains sp cur && not (contains cur sp)) rest with
    | None -> List.rev (cur :: chain)
    | Some parent ->
      let rest' = List.filter (fun s -> s <> parent) rest in
      build parent rest' (cur :: chain)
  in
  match sorted with
  | [] -> []
  | smallest :: rest -> build smallest rest []

(* ---- Call hierarchy (per-file) ---- *)

(* prepareCallHierarchy: the call-graph node for the function under the cursor. *)
let prepare_call_hierarchy_at (a : t) ~line ~character : cg_node option =
  match name_at a ~line ~character with
  | None -> None
  | Some name -> List.find_opt (fun n -> n.cg_name = name) a.call_graph

(* incomingCalls: callers of [name] — each node that calls it, with the spans. *)
let incoming_calls (a : t) (name : string) : (cg_node * Ast.span list) list =
  List.filter_map (fun node ->
      let spans =
        List.filter_map (fun (callee, sp) -> if callee = name then Some sp else None)
          node.cg_calls
      in
      if spans = [] then None else Some (node, spans)
    ) a.call_graph

(* outgoingCalls: functions [name] calls that resolve to a known node, grouped. *)
let outgoing_calls (a : t) (name : string) : (cg_node * Ast.span list) list =
  match List.find_opt (fun n -> n.cg_name = name) a.call_graph with
  | None -> []
  | Some node ->
    let tbl = Hashtbl.create 8 in
    List.iter (fun (callee, sp) ->
        Hashtbl.replace tbl callee (sp :: (try Hashtbl.find tbl callee with Not_found -> []))
      ) node.cg_calls;
    Hashtbl.fold (fun callee spans acc ->
        match List.find_opt (fun n -> n.cg_name = callee) a.call_graph with
        | Some target -> (target, List.rev spans) :: acc
        | None -> acc
      ) tbl []

(** Validate a rename request: return the identifier range if the symbol under
    the cursor is renameable (a function-local binding, or a top-level symbol
    defined in this file), or [None] to reject (stdlib symbols, keywords,
    literals, whitespace). Used for textDocument/prepareRename. *)
let prepare_rename_at (a : t) ~line ~character : Lsp.Types.Range.t option =
  (* Smallest local-binder span (use or def) under the cursor. *)
  let smallest_local =
    let best = ref None in
    let consider sp =
      if Pos.span_contains sp ~line ~character then
        match !best with
        | Some b when not (Pos.span_smaller sp b) -> ()
        | _ -> best := Some sp
    in
    Hashtbl.iter (fun sp _ -> consider sp) a.sym_uses;
    Hashtbl.iter (fun _ sp -> consider sp) a.sym_defs;
    !best
  in
  match smallest_local with
  | Some sp -> Some (Pos.span_to_lsp_range sp)  (* locals are always renameable *)
  | None ->
    (* Top-level: find the name under the cursor and allow only if its
       definition lives in this user file (reject stdlib / unresolved). *)
    let hit =
      let from_use =
        Hashtbl.fold (fun sp name acc ->
            match acc with
            | Some _ -> acc
            | None -> if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some (sp, name) else None
          ) a.use_map None
      in
      match from_use with
      | Some _ -> from_use
      | None ->
        Hashtbl.fold (fun name sp acc ->
            match acc with
            | Some _ -> acc
            | None -> if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some (sp, name) else None
          ) a.def_map None
    in
    (match hit with
     | None -> None
     | Some (sp, name) ->
       (match Hashtbl.find_opt a.def_map name with
        | Some def_sp
          when def_sp.Ast.file = a.filename
            || def_sp.Ast.file = "" || def_sp.Ast.file = "<unknown>" ->
          Some (Pos.span_to_lsp_range sp)
        | _ -> None))

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

let register_fix code gen =
  Hashtbl.replace fix_registry code gen

(** The first backtick-quoted substring of [msg], e.g. the name in
    "Private function `foo` is never used". *)
let backtick_name (msg : string) : string option =
  match String.index_opt msg '`' with
  | None -> None
  | Some i ->
    (match String.index_from_opt msg (i + 1) '`' with
     | None -> None
     | Some j -> Some (String.sub msg (i + 1) (j - i - 1)))

(* Quickfix: "Remove unused function `f`" — delete the whole declaration of the
   private function named in the `dead-code/unused-private-fn` diagnostic. *)
let remove_unused_fn_fix (a : t) (diag : Lsp.Types.Diagnostic.t)
    : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  let msg = match diag.message with `String s -> s | _ -> "" in
  match backtick_name msg with
  | None -> []
  | Some name ->
    let dsp = ref None in
    let rec scan (d : Ast.decl) = match d with
      | Ast.DFn (fn, sp) when fn.Ast.fn_name.Ast.txt = name -> dsp := Some sp
      | Ast.DMod (_, _, ds, _) -> List.iter scan ds
      | _ -> ()
    in
    List.iter scan a.decls;
    (match !dsp with
     | None -> []
     | Some sp ->
       let del = TextEdit.create
         ~range:(Range.create
                   ~start:(Position.create ~line:(sp.Ast.start_line - 1) ~character:0)
                   ~end_:(Position.create ~line:sp.Ast.end_line ~character:0))
         ~newText:"" in
       let uri = DocumentUri.of_path a.filename in
       [CodeAction.create ~title:(Printf.sprintf "Remove unused function `%s`" name)
          ~kind:CodeActionKind.QuickFix ~diagnostics:[diag]
          ~isPreferred:true
          ~edit:(WorkspaceEdit.create ~changes:[(uri, [del])] ()) ()])

(* Quickfix: "Remove unreachable code" — delete the line range of the dead
   statement flagged by `dead-code/unreachable-after-diverge`. Line-based so it
   is correct regardless of column encoding. *)
let remove_unreachable_fix (a : t) (diag : Lsp.Types.Diagnostic.t)
    : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  let r = diag.range in
  let del = TextEdit.create
    ~range:(Range.create
              ~start:(Position.create ~line:r.start.line ~character:0)
              ~end_:(Position.create ~line:(r.end_.line + 1) ~character:0))
    ~newText:"" in
  let uri = DocumentUri.of_path a.filename in
  [CodeAction.create ~title:"Remove unreachable code"
     ~kind:CodeActionKind.QuickFix ~diagnostics:[diag]
     ~isPreferred:true
     ~edit:(WorkspaceEdit.create ~changes:[(uri, [del])] ()) ()]

(* The following diagnostic codes have registered fix generators. Dead-code
   removals are diagnostic-driven quickfixes (lightbulb on the warning); the
   others return [] and are handled by cursor-position inline handlers. *)
let () =
  register_fix "non_exhaustive_match"  (fun _a _diag -> []);
  register_fix "unused_binding"        (fun _a _diag -> []);
  register_fix "dead-code/unused-private-fn"         remove_unused_fn_fix;
  register_fix "dead-code/unreachable-after-diverge" remove_unreachable_fix;
  register_fix "unused_import"         (fun _a _diag -> [])

(* The two code-action engines moved verbatim to [code_actions_ast.ml]
   (AST-driven refactorings) and [code_actions_diag.ml] (cursor- and
   diagnostic-driven quick fixes).  [Code_actions_diag] calls into
   [Code_actions_ast]; this [include] republishes [code_actions_at] here
   with its original name and signature. *)
include Code_actions_diag

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

let typestate_hover_at (a : t) ~line ~character : string option =
  match ty_at a ~line ~character with
  | None -> None
  | Some ty ->
    let open Tc in
    let rec repr = function TVar {contents = Link t; _} -> repr t | t -> t in
    (match repr ty with
     | TCon (handle_name, _args) when a.transitions_index <> [] ->
       let bare = match String.rindex_opt handle_name '.' with
         | Some i -> String.sub handle_name (i+1) (String.length handle_name - i - 1)
         | None   -> handle_name
       in
       (match List.find_opt (fun (k, _) -> k = handle_name || k = bare)
                a.transitions_index with
        | None -> None
        | Some (_, all_arms) ->
          (* Determine current state from last type argument *)
          let state_s = match repr ty with
            | TCon (_, args) when args <> [] ->
              pp_ty (repr (List.nth args (List.length args - 1)))
            | _ -> "?"
          in
          let resource_s = match repr ty with
            | TCon (_, arg0 :: _) -> pp_ty (repr arg0)
            | _ -> bare
          in
          let from_arms = List.filter (fun (arm : Ast.transition) ->
              arm.tr_from.txt = state_s
            ) all_arms in
          let is_linear = List.mem bare a.always_linear_names ||
                          List.mem handle_name a.always_linear_names in
          let buf = Buffer.create 64 in
          if is_linear then
            Buffer.add_string buf "**always-linear** — must be consumed, not dropped\n\n";
          Buffer.add_string buf
            (Printf.sprintf "Typestate: resource `%s`, state **`%s`**" resource_s state_s);
          if from_arms <> [] then begin
            Buffer.add_string buf
              (Printf.sprintf "\n\nTransitions from `%s`:\n" state_s);
            List.iter (fun (arm : Ast.transition) ->
              Buffer.add_string buf
                (Printf.sprintf "- `%s` → `%s`  via `%s`\n"
                   arm.tr_from.txt arm.tr_to.txt arm.tr_via.txt)
            ) from_arms
          end else if all_arms <> [] then
            Buffer.add_string buf
              (Printf.sprintf "\n\nNo declared transitions from `%s`" state_s);
          Some (Buffer.contents buf))
     | _ -> None)

(** Return the performance insight message for the smallest span that
    contains the cursor, or [None] if no insight applies. *)
let perf_insight_at (a : t) ~line ~character : string option =
  let is_user_span (sp : Ast.span) =
    sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"
  in
  let candidates = List.filter (fun (pi : perf_insight) ->
      is_user_span pi.pi_span &&
      Pos.span_contains pi.pi_span ~line ~character
    ) a.perf_insights
  in
  match candidates with
  | [] -> None
  | _ ->
    (* Return the insight with the smallest span (most specific) *)
    let best = List.fold_left (fun best pi ->
        if Pos.span_smaller pi.pi_span best.pi_span then pi else best
      ) (List.hd candidates) (List.tl candidates)
    in
    Some best.pi_message

(* ---------------------------------------------------------------------- *)
(* UTF-16 query wrappers.                                                  *)
(* Editors (and the CLI) pass UTF-16 character columns; the internal query *)
(* functions work in byte columns (matching March spans). These wrappers   *)
(* convert the incoming column and remap any outbound ranges back to       *)
(* UTF-16, so callers never touch encoding.                                *)
(* ---------------------------------------------------------------------- *)

let byte_col_of (a : t) ~line ~utf16_char =
  Utf16.lsp_char_to_byte_col a.doc ~line ~utf16_char

let query_type_at (a : t) ~line ~utf16_char =
  type_at a ~line ~character:(byte_col_of a ~line ~utf16_char)

let query_doc_name_at (a : t) ~line ~utf16_char =
  doc_name_at a ~line ~character:(byte_col_of a ~line ~utf16_char)

let query_perf_insight_at (a : t) ~line ~utf16_char =
  perf_insight_at a ~line ~character:(byte_col_of a ~line ~utf16_char)

let query_actor_info_at (a : t) ~line ~utf16_char =
  actor_info_at a ~line ~character:(byte_col_of a ~line ~utf16_char)

let query_typestate_hover_at (a : t) ~line ~utf16_char =
  typestate_hover_at a ~line ~character:(byte_col_of a ~line ~utf16_char)

let query_signature_help_at (a : t) ~line ~utf16_char =
  signature_help_at a ~line ~character:(byte_col_of a ~line ~utf16_char)

let query_completions_at (a : t) ~line ~utf16_char =
  completions_at a ~line ~character:(byte_col_of a ~line ~utf16_char)

let query_definition_at (a : t) ~line ~utf16_char =
  match definition_at a ~line ~character:(byte_col_of a ~line ~utf16_char) with
  | None -> None
  | Some l -> Some (Pos.remap_location a.doc l)

let query_references_at (a : t) ~include_declaration ~line ~utf16_char =
  references_at a ~include_declaration ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> List.map (Pos.remap_location a.doc)

let query_rename_at (a : t) ~line ~utf16_char ~new_name =
  rename_at a ~line ~character:(byte_col_of a ~line ~utf16_char) ~new_name
  |> List.map (Pos.remap_text_edit a.doc)

let query_prepare_rename_at (a : t) ~line ~utf16_char =
  prepare_rename_at a ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> Option.map (Pos.remap_range a.doc)

let query_implementation_at (a : t) ~line ~utf16_char =
  implementation_at a ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> List.map (Pos.remap_location a.doc)

let query_type_definition_at (a : t) ~line ~utf16_char =
  type_definition_at a ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> Option.map (Pos.remap_location a.doc)

let query_document_highlights_at (a : t) ~line ~utf16_char =
  document_highlights_at a ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> List.map (fun (h : Lsp.Types.DocumentHighlight.t) ->
         { h with Lsp.Types.DocumentHighlight.range =
                    Pos.remap_range a.doc h.Lsp.Types.DocumentHighlight.range })

let query_linked_editing_ranges_at (a : t) ~line ~utf16_char =
  linked_editing_ranges_at a ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> List.map (fun sp -> Pos.remap_range a.doc (Pos.span_to_lsp_range sp))

let query_selection_range_at (a : t) ~line ~utf16_char =
  selection_range_at a ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> List.map (fun sp -> Pos.remap_range a.doc (Pos.span_to_lsp_range sp))

(* DAP inline values. The line band is encoding-independent, so only the
   outbound lookup ranges need UTF-16 remapping. *)
let query_inline_values (a : t) ~range_start_line ~range_end_line ~stopped_line =
  inline_values_at a ~range_start_line ~range_end_line ~stopped_line
  |> List.map (function
    | `InlineValueVariableLookup (l : Lsp.Types.InlineValueVariableLookup.t) ->
      `InlineValueVariableLookup
        { l with Lsp.Types.InlineValueVariableLookup.range =
                   Pos.remap_range a.doc l.Lsp.Types.InlineValueVariableLookup.range }
    | `InlineValueText (t : Lsp.Types.InlineValueText.t) ->
      `InlineValueText
        { t with Lsp.Types.InlineValueText.range =
                   Pos.remap_range a.doc t.Lsp.Types.InlineValueText.range }
    | `InlineValueEvaluatableExpression (e : Lsp.Types.InlineValueEvaluatableExpression.t) ->
      `InlineValueEvaluatableExpression
        { e with Lsp.Types.InlineValueEvaluatableExpression.range =
                   Pos.remap_range a.doc e.Lsp.Types.InlineValueEvaluatableExpression.range })

(* Call hierarchy query wrappers — return (name, range, selectionRange) tuples
   already remapped to UTF-16, ready for the server to wrap as CallHierarchyItems. *)
let cg_item (a : t) (n : cg_node) =
  (n.cg_name,
   Pos.remap_range a.doc (Pos.span_to_lsp_range n.cg_full_span),
   Pos.remap_range a.doc (Pos.span_to_lsp_range n.cg_name_span))

let query_prepare_call_hierarchy_at (a : t) ~line ~utf16_char =
  prepare_call_hierarchy_at a ~line ~character:(byte_col_of a ~line ~utf16_char)
  |> Option.map (cg_item a)

let query_incoming_calls (a : t) (name : string) =
  incoming_calls a name
  |> List.map (fun (node, spans) ->
         (cg_item a node,
          List.map (fun sp -> Pos.remap_range a.doc (Pos.span_to_lsp_range sp)) spans))

let query_outgoing_calls (a : t) (name : string) =
  outgoing_calls a name
  |> List.map (fun (node, spans) ->
         (cg_item a node,
          List.map (fun sp -> Pos.remap_range a.doc (Pos.span_to_lsp_range sp)) spans))

let query_import_text_edit (a : t) ~module_ ~name =
  import_text_edit a ~module_ ~name |> Option.map (Pos.remap_text_edit a.doc)

(* The name of the function under the cursor that is eligible for the
   "introduce parameter object" refactor: a single-clause function with ≥2
   fully-annotated parameters (the `forge refactor bundle` preconditions).
   [character] is a byte column. The actual project-wide rewrite is performed
   by the march_refactor engine in the server. *)
let bundleable_fn_at (a : t) ~line ~character : string option =
  let result = ref None in
  let rec scan (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _)
      when Pos.span_contains fn.Ast.fn_name.Ast.span ~line ~character ->
      (match fn.Ast.fn_clauses with
       | [cl] ->
         let ps = cl.Ast.fc_params in
         if List.length ps >= 2
            && List.for_all (function Ast.FPNamed _ -> true | _ -> false) ps
         then result := Some fn.Ast.fn_name.Ast.txt
       | _ -> ())
    | Ast.DMod (_, _, ds, _) -> List.iter scan ds
    | _ -> ()
  in
  List.iter scan a.decls;
  !result

(* Project-level diagnostics (Feature 17): analyse each (file, source) and
   return its UTF-16-remapped diagnostics. Per-file analysis resolves imported
   modules (so cross-file import errors surface); a shared whole-project type
   environment is a future refinement. *)
let project_diagnostics (sources : (string * string) list)
    : (string * Lsp.Types.Diagnostic.t list) list =
  List.map (fun (path, src) ->
      let a = analyse ~filename:path ~src in
      (path, List.map (Pos.remap_diagnostic a.doc) a.diagnostics))
    sources

(* textDocument/onTypeFormatting: when the user types '>' finishing an open
   HTML tag inside a ~H sigil, return a TextEdit inserting the matching </tag>
   at the cursor.  Returns None when the '>' does not close a real, non-void,
   non-self-closing, non-island open tag.

   [line] is 0-indexed; [character] is a BYTE column (callers in the public
   query_* wrapper convert UTF-16 before calling here). *)
let autoclose_tag_at (a : t) ~line ~character : Lsp.Types.TextEdit.t option =
  (* pos_to_ofs takes 1-indexed line *)
  let cur = pos_to_ofs a.src (line + 1) character in
  let is_nc c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '-' || c = '_'
  in
  List.find_map (fun (s : h_sigil) ->
      if s.hs_base_ofs <= cur && cur <= s.hs_close_ofs then begin
        let rel = cur - s.hs_base_ofs in
        let pre = String.sub s.hs_content 0 rel in
        let pn  = String.length pre in
        (* The character just before the cursor must be '>'. *)
        if pn = 0 || pre.[pn - 1] <> '>' then None
        else begin
          (* Scan FORWARD through [pre] with ${…}/quote-aware skip rules,
             tracking the last '<tag' that was encountered at the top level
             (not inside an interpolation or quoted attribute value).
             The last such open-tag position is the tag whose '>' we just typed. *)
          let last_open_lt = ref (-1) in  (* offset of last real '<tag' *)
          let k = ref 0 in
          while !k < pn - 1 do  (* pn-1 is the trailing '>' itself *)
            let ch = pre.[!k] in
            (* ${…} interpolation: skip balanced braces *)
            if ch = '$' && !k + 1 < pn && pre.[!k + 1] = '{' then begin
              k := !k + 2; let depth = ref 1 in
              while !depth > 0 && !k < pn do
                (match pre.[!k] with '{' -> incr depth | '}' -> decr depth | _ -> ());
                incr k
              done
            end
            (* Quoted attribute value: skip until matching close quote,
               also skipping ${…} inside the value. *)
            else if (ch = '"' || ch = '\'') then begin
              let q = ch in
              incr k;
              while !k < pn && pre.[!k] <> q do
                if pre.[!k] = '$' && !k + 1 < pn && pre.[!k + 1] = '{' then begin
                  k := !k + 2; let depth = ref 1 in
                  while !depth > 0 && !k < pn do
                    (match pre.[!k] with '{' -> incr depth | '}' -> decr depth | _ -> ());
                    incr k
                  done
                end else
                  incr k
              done;
              if !k < pn then incr k  (* skip closing quote *)
            end
            (* '<' at top level — check if it's a real open tag. *)
            else if ch = '<' then begin
              if !k + 1 < pn then begin
                let nx = pre.[!k + 1] in
                if (nx >= 'a' && nx <= 'z') || (nx >= 'A' && nx <= 'Z') then
                  last_open_lt := !k
              end;
              incr k
            end
            else incr k
          done;
          if !last_open_lt < 0 then None
          else begin
            let lt = !last_open_lt in
            if lt + 1 >= pn then None
            else begin
              (* Parse the tag name at lt+1. *)
              let j = ref (lt + 1) in
              while !j < pn && is_nc pre.[!j] do incr j done;
              let tag = String.lowercase_ascii (String.sub pre (lt + 1) (!j - lt - 1)) in
              (* Self-closing: char before '>' is '/' *)
              let self_closing = pn >= 2 && pre.[pn - 2] = '/' in
              (* Void element *)
              let is_void = List.mem tag html_void_elements in
              (* Island element (self-renders; skip) *)
              let is_island = tag = "island" in
              if self_closing || is_void || is_island then None
              else begin
                let open Lsp.Types in
                let pos = Position.create ~line ~character in
                let range = Range.create ~start:pos ~end_:pos in
                Some (TextEdit.create ~range ~newText:("</" ^ tag ^ ">"))
              end
            end
          end
        end
      end else None
    ) a.h_sigils

(* ---------------------------------------------------------------------- *)
(* Error-resilient analysis.                                               *)
(* When an edit leaves the buffer unparseable, [analyse] returns empty     *)
(* maps and every IDE feature goes dark. Instead, fall back to the last    *)
(* good analysis's symbol maps while surfacing the current parse error and *)
(* keeping the current source/doc (so the error's position is correct).    *)
(*                                                                         *)
(* [parsed_ok] is a heuristic proxy for "the parse produced usable maps".  *)
(* A pure parse/lex failure yields empty maps; a parses-but-type-errors    *)
(* buffer still populates maps and is used as-is. Phase 5's recovering     *)
(* parser will replace this with partial maps from a single pass.          *)
(* ---------------------------------------------------------------------- *)
let analyse_resilient ~prev ~filename ~src : t =
  let fresh = analyse ~filename ~src in
  let parsed_ok =
    Hashtbl.length fresh.type_map > 0
    || fresh.vars <> []
    || Hashtbl.length fresh.def_map > 0
  in
  match prev with
  | Some p when not parsed_ok ->
    { p with src; filename; doc = Utf16.build src;
             diagnostics = fresh.diagnostics }
  | _ -> fresh
