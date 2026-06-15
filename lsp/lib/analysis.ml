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

(** A `use`/`import` declaration, simplified for auto-import bookkeeping. *)
type import_sel =
  | ISAll                    (** use M.* / import M — all members bare *)
  | ISNames of Ast.name list (** use M.{a,b} — listed members bare (names keep spans) *)
  | ISExcept of string list  (** import M, except: [..] — all but listed, bare *)
  | ISSingle                 (** use M — qualified access only, nothing bare *)

type import_info = {
  ii_module : string;     (** dotted module path, e.g. "Map" or "Collections.Map" *)
  ii_sel    : import_sel;
  ii_span   : Ast.span;   (** span of the whole use/import declaration *)
}

(** A node in the per-file call graph (one per top-level function), for
    textDocument/callHierarchy. *)
type cg_node = {
  cg_name      : string;
  cg_name_span : Ast.span;            (** the function-name token (selectionRange) *)
  cg_full_span : Ast.span;            (** the whole function declaration (range) *)
  cg_calls     : (string * Ast.span) list;  (** (callee name, call-site span) within the body *)
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

(** An unclosed HTML tag inside a ~H sigil. *)
type html_issue = {
  hi_open_span   : Ast.span;  (** the `<tag` open — diagnostic range *)
  hi_tag         : string;    (** tag name (lower-cased) *)
  hi_insert_span : Ast.span;  (** zero-width position of the sigil's closing quote *)
  hi_closer      : string;    (** all closing tags for this sigil, innermost-first *)
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

(** What kind of performance issue a [perf_insight] reports. *)
type perf_insight_kind =
  | NonTailCall    of { pi_fn_name : string; pi_blocking : string }
      (** A recursive call that is not in tail position — the stack grows. *)
  | ActorSendCopy  of { pi_value_desc : string; pi_ty : string }
      (** A non-linear value sent via [send()] — will be deep-copied. *)
  | ClosureCapture of { pi_count : int; pi_names : string list }
      (** A lambda that closes over [pi_count] values — larger allocation. *)
  (* Phase 3 — TIR pipeline insights (function-level, emitted after async TIR pass) *)
  | StackPromoted of { pi_count : int }
      (** Escape analysis promoted [pi_count] heap allocations to the stack. *)
  | FbipReuse of { pi_count : int }
      (** Perceus detected [pi_count] in-place memory reuse opportunities (FBIP). *)
  | TirIndirectCall of { pi_fn_name : string; pi_count : int }
      (** [pi_count] calls in this function go through a function pointer. *)
  (* Phase 2 — AST heuristics (synchronous, no TIR pass needed) *)
  | IndirectCall of { pi_callee : string }
      (** A call whose callee is a parameter — dispatched through a pointer. *)
  | RecursiveAlloc of { pi_alloc : string }
      (** An allocation inside an arm of a self-recursive function (GC pressure). *)

(** A performance insight produced by static AST analysis. *)
type perf_insight = {
  pi_span    : Ast.span;
  pi_kind    : perf_insight_kind;
  pi_message : string;
}

(** Per-function counts from the TIR optimization pipeline.
    Used for code lens annotations and TIR-level perf insights. *)
type tir_fn_insight = {
  tfi_fn_name        : string;   (** source function name *)
  tfi_stack_allocs   : int;      (** EStackAlloc nodes — values promoted to stack by escape analysis *)
  tfi_reuse_ops      : int;      (** EReuse nodes — in-place updates by Perceus/FBIP *)
  tfi_indirect_calls : int;      (** ECallPtr nodes surviving known_call — indirect dispatch *)
  tfi_heap_allocs    : int;      (** EAlloc nodes — remaining heap allocations *)
}

(** A code lens annotation that appears above a function definition.

    A lens may be a plain informational annotation (perf summary — no command)
    or an actionable lens that carries an LSP [Command]: a stable command id
    plus JSON arguments the client passes back via [workspace/executeCommand].
    [cl_command]/[cl_args] are [None]/[] for the perf-summary lenses. *)
type code_lens_item = {
  cl_range   : Lsp.Types.Range.t;  (** Position of the function name (for the lens line) *)
  cl_title   : string;             (** Title text shown on the lens *)
  cl_command : string option;      (** LSP command id, e.g. "march.runTest" (None = informational) *)
  cl_args    : Yojson.Safe.t list; (** Arguments for the command, e.g. [file_uri; test_name] *)
}

(** One ~H sigil, with the byte offsets needed to map an in-content offset
    back to a source position via [ofs_to_pos src (hs_base_ofs + o)]. *)
type h_sigil = {
  hs_content   : string;    (** raw text between the quotes (interpolation + tags verbatim) *)
  hs_base_ofs  : int;       (** byte offset in src of hs_content.[0] *)
  hs_close_ofs : int;       (** byte offset of the closing quote *)
  hs_span      : Ast.span;  (** the ESigil span (start = the `~`) *)
}

(** Full analysis result for one document. *)
type t = {
  src         : string;
  filename    : string;
  doc         : Utf16.doc;
  (** Line index + source for UTF-16<->byte column conversion. *)
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
  impl_sites  : (string, Ast.span list) Hashtbl.t;
  (** Interface name → spans of `impl <iface> for ...` declarations
      (for textDocument/implementation). *)
  actors      : (string * Ast.actor_def) list;
  (** Actor definitions: name → def. *)
  doc_map     : (string, string) Hashtbl.t;
  (** Function name → doc string (from [fn_doc] field). *)
  refs_map    : (string, Ast.span list) Hashtbl.t;
  (** Inverted index: variable name → all use-site spans. *)
  sym_defs    : (int, Ast.span) Hashtbl.t;
  (** Local binder id → its definition span. *)
  sym_uses    : (Ast.span, int) Hashtbl.t;
  (** Use-site span → resolved local binder id (locals only). *)
  sym_id_uses : (int, Ast.span list) Hashtbl.t;
  (** Local binder id → all its use-site spans. *)
  sym_name    : (int, string) Hashtbl.t;
  (** Local binder id → name (for rename validation/display). *)
  sym_scope   : (int, Ast.span) Hashtbl.t;
  (** Local binder id → span it is visible within (for scope-precise completion). *)
  call_sites  : call_site list;
  (** All call sites collected for signature-help queries. *)
  call_graph  : cg_node list;
  (** Per-function call-graph nodes for textDocument/callHierarchy. *)
  imports     : import_info list;
  (** `use`/`import` declarations in this file, for auto-import on completion. *)
  module_index : (string * string list) list;
  (** Importable modules (stdlib + deps) → their public function/value names,
      the candidate pool for auto-import on completion. *)
  consumption : consumption list;
  (** Linear/affine binding consumption records — used for make-linear actions. *)
  reuse_hints : Ast.span list;
  (** Variable-name spans of bindings eligible for FBIP in-place reuse
      (allocating RHS, consumed exactly once) — rendered as inlay hints. *)
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
  html_issues : html_issue list;
  (** Unclosed HTML tags found inside ~H sigils (detection + close quickfix). *)
  h_sigils : h_sigil list;
  (** Every ~H sigil in the file, for HTML-aware features. *)
  type_matches : (string * match_site list) list;
  (** All match sites grouped by matched type name (for bulk file-scope fixes). *)
  naming_violations : naming_violation list;
  (** Functions/types that violate the naming convention (camelCase fn, snake_case type). *)
  demorgan_sites   : demorgan_site list;
  (** Sites eligible for De Morgan rewriting: !(a&&b), !(a||b), !a&&!b, !a||!b. *)
  perf_insights    : perf_insight list;
  (** AST-level performance insights: non-tail calls, actor send copies, large closures. *)
  tir_fn_insights  : tir_fn_insight list;
  (** TIR-pipeline function-level insights: stack promotions, FBIP reuse, indirect calls. *)
  code_lens_items  : code_lens_item list;
  (** Code lens annotations for display above function definitions. *)
  decls            : Ast.decl list;
  (** Raw (pre-desugar) user declarations — retained for AST-driven code
      actions (pipe, extract/inline variable, capture, typed holes, actor
      and protocol scaffolding). *)
  protocols        : (string * Ast.protocol_def) list;
  (** Session-type protocol definitions: name → def (for scaffolding). *)
  param_name_map   : (string, string list) Hashtbl.t;
  (** Precomputed function-name → ordered param-names table, built once from
      [decls] and reused on every inlay-hint request for parameter-name hints. *)
}

(* ------------------------------------------------------------------ *)
(* Stdlib loading                                                      *)
(* ------------------------------------------------------------------ *)

let find_stdlib_dir () =
  let exe_dir = Filename.dirname Sys.executable_name in
  let candidates = [
    "stdlib";
    Filename.concat exe_dir "../stdlib";
    Filename.concat exe_dir "../../stdlib";
    Filename.concat exe_dir "../../../stdlib";
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
  | Ast.ESigil (_, _, sp) -> sp
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
(* Performance insights (Phase 1, AST level)                          *)
(* ------------------------------------------------------------------ *)

(** Operators whose results count as "pending work" after a call returns,
    preventing tail-call optimisation. *)
let march_operators =
  ["+"; "-"; "*"; "/"; "%"; "&&"; "||"; "=="; "!="; "<>"; "<"; ">"; "<="; ">=";
   "++"; "^"; "not"]

let is_march_operator name = List.mem name march_operators

(** Names bound by a pattern (used to extend the scope in closures). *)
let rec pat_bound_names (pat : Ast.pattern) =
  match pat with
  | Ast.PatVar n -> [n.txt]
  | Ast.PatAs (p, n, _) -> n.txt :: pat_bound_names p
  | Ast.PatTuple (ps, _) | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) ->
    List.concat_map pat_bound_names ps
  | Ast.PatRecord (fs, _) ->
    List.concat_map (fun (_, p) -> pat_bound_names p) fs
  | _ -> []

(** Visit every sub-expression of [e] (including [e] itself), pre-order. *)
let rec iter_expr (f : Ast.expr -> unit) (e : Ast.expr) =
  f e;
  match e with
  | Ast.EApp (g, args, _) -> iter_expr f g; List.iter (iter_expr f) args
  | Ast.ECon (_, args, _) | Ast.EAtom (_, args, _) | Ast.ETuple (args, _) ->
    List.iter (iter_expr f) args
  | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> iter_expr f body
  | Ast.EBlock (es, _) -> List.iter (iter_expr f) es
  | Ast.ELet (b, _) -> iter_expr f b.Ast.bind_expr
  | Ast.EMatch (subj, brs, _) ->
    iter_expr f subj;
    List.iter (fun (br : Ast.branch) ->
        (match br.branch_guard with Some g -> iter_expr f g | None -> ());
        iter_expr f br.branch_body) brs
  | Ast.ECond (arms, _) ->
    List.iter (fun (c, b) -> iter_expr f c; iter_expr f b) arms
  | Ast.EIf (c, t, el, _) -> iter_expr f c; iter_expr f t; iter_expr f el
  | Ast.EPipe (l, r, _) | Ast.ESend (l, r, _) -> iter_expr f l; iter_expr f r
  | Ast.ERecord (fs, _) -> List.iter (fun (_, e2) -> iter_expr f e2) fs
  | Ast.ERecordUpdate (e2, fs, _) ->
    iter_expr f e2; List.iter (fun (_, e3) -> iter_expr f e3) fs
  | Ast.EField (e2, _, _) | Ast.EAnnot (e2, _, _)
  | Ast.ESpawn (e2, _) | Ast.EAssert (e2, _) | Ast.ESigil (_, e2, _)
  | Ast.EDbg (Some e2, _) -> iter_expr f e2
  | Ast.ELit _ | Ast.EVar _ | Ast.EHole _ | Ast.EResultRef _
  | Ast.EDbg (None, _) -> ()

(** Collect free variable names in [body] that are not the lambda's own
    [params].  These are the values the closure must capture. *)
let lambda_free_vars (params : Ast.param list) (body : Ast.expr) : string list =
  let param_names = List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) params in
  let fvs : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  let rec go (bound : string list) (e : Ast.expr) =
    match e with
    | Ast.EVar n ->
      if not (List.mem n.txt bound) && not (is_march_operator n.txt)
      then Hashtbl.replace fvs n.txt ()
    | Ast.ELam (ps, lbody, _) ->
      let inner = List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) ps @ bound in
      go inner lbody
    | Ast.ELetFn (name, ps, _, fbody, _) ->
      let inner = name.txt :: List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) ps @ bound in
      go inner fbody
    | Ast.EBlock (es, _) ->
      let rec go_block bound = function
        | [] -> ()
        | (Ast.ELet (b, _)) :: rest ->
          go bound b.Ast.bind_expr;
          go_block (pat_bound_names b.Ast.bind_pat @ bound) rest
        | (Ast.ELetFn (name, ps, _, fbody, _)) :: rest ->
          let inner = name.txt :: List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) ps @ bound in
          go inner fbody;
          go_block (name.txt :: bound) rest
        | e :: rest -> go bound e; go_block bound rest
      in
      go_block bound es
    | Ast.ELet (b, _) -> go bound b.Ast.bind_expr
    | Ast.EMatch (subj, branches, _) ->
      go bound subj;
      List.iter (fun (br : Ast.branch) ->
          let names = pat_bound_names br.Ast.branch_pat in
          go (names @ bound) br.Ast.branch_body
        ) branches
    | Ast.EApp (f, args, _) -> go bound f; List.iter (go bound) args
    | Ast.EIf (c, t, f, _) -> go bound c; go bound t; go bound f
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> go bound a; go bound b
    | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
      List.iter (go bound) es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> go bound e) fs
    | Ast.ERecordUpdate (e, fs, _) ->
      go bound e; List.iter (fun (_, e2) -> go bound e2) fs
    | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
    | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) | Ast.EAssert (e, _) ->
      go bound e
    | _ -> ()
  in
  go param_names body;
  Hashtbl.fold (fun k () acc -> k :: acc) fvs []

(** Walk [e] collecting perf insights for lambdas with ≥3 captures. *)
(* Collect every lambda in [body] with its genuine local capture set (≥2
   values), as (span, sorted-caps). [is_global] excludes top-level/stdlib names. *)
(* Each entry: (lambda span, lambda-body span, sorted genuine captures). *)
let collect_lambda_captures is_global (body : Ast.expr)
  : (Ast.span * Ast.span * string list) list =
  let found = ref [] in
  (* [iter_expr] is the canonical generic visitor: it descends INTO ELam bodies
     (so nested lambdas are still collected, matching the old [walk lbody]) and
     covers every form including ECond and ESigil (the ~H interpolation) that
     the old hand walk fell through on. *)
  iter_expr (fun e ->
      match e with
      | Ast.ELam (params, lbody, sp) ->
        let caps =
          lambda_free_vars params lbody
          |> List.filter (fun nm -> not (is_global nm))
          |> List.sort_uniq String.compare
        in
        if List.length caps >= 2 then
          found := (sp, span_of_expr lbody, caps) :: !found
      | _ -> ())
    body;
  !found

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
        let msg = Printf.sprintf
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
    let b = Printf.sprintf "constructor `%s` wraps it" name.Ast.txt in
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
  let fn_name = fn.Ast.fn_name.txt in
  List.fold_left (fun acc (cl : Ast.fn_clause) ->
      tco_check fn_name None cl.Ast.fc_body acc
    ) acc fn.Ast.fn_clauses

(** Convert a [perf_insight] to an LSP [Diagnostic.t]. *)
let perf_insight_to_diag (pi : perf_insight) : Lsp.Types.Diagnostic.t =
  let range = Pos.span_to_lsp_range pi.pi_span in
  let severity, code = match pi.pi_kind with
    | NonTailCall _    -> Lsp.Types.DiagnosticSeverity.Warning, "perf/non-tail-call"
    | ActorSendCopy _  -> Lsp.Types.DiagnosticSeverity.Warning, "perf/actor-send-copy"
    | ClosureCapture _ -> Lsp.Types.DiagnosticSeverity.Hint,    "perf/closure-capture"
    | StackPromoted _  -> Lsp.Types.DiagnosticSeverity.Hint,    "perf/stack-promoted"
    | FbipReuse _      -> Lsp.Types.DiagnosticSeverity.Hint,    "perf/fbip-reuse"
    | TirIndirectCall _ -> Lsp.Types.DiagnosticSeverity.Hint,   "perf/indirect-call"
    | IndirectCall _    -> Lsp.Types.DiagnosticSeverity.Hint,   "perf/indirect-call"
    | RecursiveAlloc _  -> Lsp.Types.DiagnosticSeverity.Hint,   "perf/recursive-alloc"
  in
  Lsp.Types.Diagnostic.create
    ~range
    ~severity
    ~message:(`String pi.pi_message)
    ~source:"march"
    ~code:(`String code)
    ()

(** Parameter names bound by a function clause (named or bare-pattern). *)
let clause_param_names (cl : Ast.fn_clause) : string list =
  List.filter_map (function
      | Ast.FPNamed p -> Some p.Ast.param_name.Ast.txt
      | Ast.FPPat (Ast.PatVar n) -> Some n.Ast.txt
      | _ -> None
    ) cl.Ast.fc_params

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

(** True when [e] contains a call to [fn_name] (self-recursion). *)
let rec contains_call fn_name (e : Ast.expr) =
  match e with
  | Ast.EApp (Ast.EVar n, args, _) ->
    n.Ast.txt = fn_name || List.exists (contains_call fn_name) args
  | Ast.EApp (f, args, _) ->
    contains_call fn_name f || List.exists (contains_call fn_name) args
  | Ast.ELet (b, _) -> contains_call fn_name b.Ast.bind_expr
  | Ast.EBlock (es, _) -> List.exists (contains_call fn_name) es
  | Ast.EMatch (subj, brs, _) ->
    contains_call fn_name subj ||
    List.exists (fun (br : Ast.branch) -> contains_call fn_name br.Ast.branch_body) brs
  | Ast.EIf (c, t, f, _) ->
    contains_call fn_name c || contains_call fn_name t || contains_call fn_name f
  | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) ->
    contains_call fn_name x || contains_call fn_name y
  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
    List.exists (contains_call fn_name) es
  | Ast.ERecord (fs, _) -> List.exists (fun (_, e) -> contains_call fn_name e) fs
  | Ast.ERecordUpdate (e, fs, _) ->
    contains_call fn_name e || List.exists (fun (_, e) -> contains_call fn_name e) fs
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
  | Ast.EDbg (Some e, _) | Ast.EAssert (e, _) -> contains_call fn_name e
  | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> contains_call fn_name body
  | _ -> false

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
          add_all (recursive_alloc_check fn_name cl.Ast.fc_body [])
        ) fn.Ast.fn_clauses
    | Ast.DLet (_, b, _) ->
      add_all (closure_capture_check is_global b.Ast.bind_expr []);
      add_all (send_copy_check type_map b.Ast.bind_expr [])
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

(* Scan HTML [content] and return the open tags left unclosed, as
   (tag, offset-of-'<'-in-content), innermost-first. Skips `${…}` interpolation,
   `<!-- … -->` comments, `<!doctype …>`, void elements and self-closing tags;
   quoted attribute values are respected so `>` inside them is ignored. *)
let scan_html_unclosed (content : string) : (string * int) list =
  let n = String.length content in
  let is_nc c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '-' || c = '_' in
  let stack = ref [] in
  let unclosed = ref [] in   (* tags skipped over by a mismatched close *)
  let i = ref 0 in
  while !i < n do
    let c = content.[!i] in
    if c = '$' && !i + 1 < n && content.[!i + 1] = '{' then begin
      i := !i + 2; let d = ref 1 in
      while !d > 0 && !i < n do
        (match content.[!i] with '{' -> incr d | '}' -> decr d | _ -> ()); incr i
      done
    end
    else if c = '<' && !i + 3 < n && content.[!i+1]='!' && content.[!i+2]='-' && content.[!i+3]='-' then begin
      i := !i + 4;
      while !i + 2 < n && not (content.[!i]='-' && content.[!i+1]='-' && content.[!i+2]='>') do incr i done;
      if !i + 2 < n then i := !i + 3 else i := n
    end
    else if c = '<' && !i + 1 < n && content.[!i+1] = '!' then begin
      while !i < n && content.[!i] <> '>' do incr i done;
      if !i < n then incr i
    end
    else if c = '<' && !i + 1 < n && content.[!i+1] = '/' then begin
      let j = ref (!i + 2) in let ns = !j in
      while !j < n && is_nc content.[!j] do incr j done;
      let tag = String.lowercase_ascii (String.sub content ns (!j - ns)) in
      while !j < n && content.[!j] <> '>' do incr j done;
      i := (if !j < n then !j + 1 else n);
      if List.exists (fun (t, _) -> t = tag) !stack then begin
        (* Pop down to the match; any tags above it were never closed. *)
        let rec pop = function
          | (t, o) :: r ->
            if t = tag then r
            else (unclosed := (t, o) :: !unclosed; pop r)
          | [] -> [] in
        stack := pop !stack
      end
    end
    else if c = '<' && !i + 1 < n &&
            (let d = content.[!i+1] in (d>='a'&&d<='z')||(d>='A'&&d<='Z')) then begin
      let ofs = !i in
      let j = ref (!i + 1) in let ns = !j in
      while !j < n && is_nc content.[!j] do incr j done;
      let tag = String.lowercase_ascii (String.sub content ns (!j - ns)) in
      let inq = ref false and q = ref ' ' in
      while !j < n && (!inq || content.[!j] <> '>') do
        let ch = content.[!j] in
        (if !inq then (if ch = !q then inq := false)
         else if ch = '"' || ch = '\'' then (inq := true; q := ch));
        incr j
      done;
      let self = !j < n && !j > 0 && content.[!j - 1] = '/' in
      i := (if !j < n then !j + 1 else n);
      if not self && not (List.mem tag html_void_elements) then
        stack := (tag, ofs) :: !stack
    end
    else incr i
  done;
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
  let c = s.hs_content in
  let n = String.length c in
  let is_nc ch =
    (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
    || (ch >= '0' && ch <= '9') || ch = '-' || ch = '_' in
  let name_span name_ofs name_len =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + name_ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + name_len } in
  let acc = ref [] and i = ref 0 in
  while !i < n do
    let ch = c.[!i] in
    (* ${…} interpolation: skip balanced braces *)
    if ch = '$' && !i + 1 < n && c.[!i + 1] = '{' then begin
      i := !i + 2; let d = ref 1 in
      while !d > 0 && !i < n do
        (match c.[!i] with '{' -> incr d | '}' -> decr d | _ -> ()); incr i
      done
    end
    (* <!-- … --> comment *)
    else if ch = '<' && !i + 3 < n
            && c.[!i+1] = '!' && c.[!i+2] = '-' && c.[!i+3] = '-' then begin
      i := !i + 4;
      while !i + 2 < n
            && not (c.[!i] = '-' && c.[!i+1] = '-' && c.[!i+2] = '>') do incr i done;
      i := (if !i + 2 < n then !i + 3 else n)
    end
    (* <!…> declaration/doctype *)
    else if ch = '<' && !i + 1 < n && c.[!i+1] = '!' then begin
      while !i < n && c.[!i] <> '>' do incr i done;
      if !i < n then incr i
    end
    (* </tag> close tag — skip *)
    else if ch = '<' && !i + 1 < n && c.[!i+1] = '/' then begin
      let j = ref (!i + 2) in
      while !j < n && is_nc c.[!j] do incr j done;
      while !j < n && c.[!j] <> '>' do incr j done;
      i := (if !j < n then !j + 1 else n)
    end
    (* <tag …> open tag *)
    else if ch = '<' && !i + 1 < n
            && (let d = c.[!i+1] in (d>='a'&&d<='z')||(d>='A'&&d<='Z')) then begin
      let ns = !i + 1 in let j = ref ns in
      while !j < n && is_nc c.[!j] do incr j done;
      let name_ofs = ns and name_len = !j - ns in
      let tag = String.lowercase_ascii (String.sub c ns name_len) in
      (* Advance past attributes, respecting quoted values. *)
      let inq = ref false and q = ref ' ' in
      while !j < n && (!inq || c.[!j] <> '>') do
        let d = c.[!j] in
        (if !inq then (if d = !q then inq := false)
         else if d = '"' || d = '\'' then (inq := true; q := d));
        incr j
      done;
      let self = !j < n && !j > 0 && c.[!j - 1] = '/' in
      i := (if !j < n then !j + 1 else n);
      if not self then
        acc := (tag, name_span name_ofs name_len) :: !acc
    end
    else incr i
  done;
  List.rev !acc

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
  let c = s.hs_content in
  let n = String.length c in
  (* A name char for tag names (tag_nc) or attribute names (attr_nc). *)
  let tag_nc ch =
    (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
    || (ch >= '0' && ch <= '9') || ch = '-' || ch = '_' in
  (* Attribute name chars: additionally allow ':' (XML namespaces). *)
  let attr_nc ch = tag_nc ch || ch = ':' in
  (* Build a single-line Ast.span for an attribute name token at content-
     relative byte offset [ofs] with length [len]. *)
  let attr_name_span ofs len =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + len } in
  let acc = ref [] in
  let i = ref 0 in
  while !i < n do
    let ch = c.[!i] in
    (* ${…} interpolation at top level: skip balanced braces. *)
    if ch = '$' && !i + 1 < n && c.[!i + 1] = '{' then begin
      i := !i + 2; let d = ref 1 in
      while !d > 0 && !i < n do
        (match c.[!i] with '{' -> incr d | '}' -> decr d | _ -> ()); incr i
      done
    end
    (* <!-- … --> comment *)
    else if ch = '<' && !i + 3 < n
            && c.[!i+1] = '!' && c.[!i+2] = '-' && c.[!i+3] = '-' then begin
      i := !i + 4;
      while !i + 2 < n
            && not (c.[!i] = '-' && c.[!i+1] = '-' && c.[!i+2] = '>') do incr i done;
      i := (if !i + 2 < n then !i + 3 else n)
    end
    (* <!…> declaration/doctype *)
    else if ch = '<' && !i + 1 < n && c.[!i+1] = '!' then begin
      while !i < n && c.[!i] <> '>' do incr i done;
      if !i < n then incr i
    end
    (* </tag> close tag — skip *)
    else if ch = '<' && !i + 1 < n && c.[!i+1] = '/' then begin
      let j = ref (!i + 2) in
      while !j < n && tag_nc c.[!j] do incr j done;
      while !j < n && c.[!j] <> '>' do incr j done;
      i := (if !j < n then !j + 1 else n)
    end
    (* <tag …> open tag — scan attribute region for duplicates. *)
    else if ch = '<' && !i + 1 < n
            && (let d = c.[!i+1] in (d>='a'&&d<='z')||(d>='A'&&d<='Z')) then begin
      (* Skip past the tag name. *)
      let j = ref (!i + 1) in
      while !j < n && tag_nc c.[!j] do incr j done;
      (* Now scan the attribute region until we hit the closing '>'. *)
      (* seen: association list of lowercase attr-name -> unit to detect dupes. *)
      let seen = Hashtbl.create 4 in
      let inq = ref false and q = ref ' ' in
      while !j < n && (!inq || c.[!j] <> '>') do
        let d = c.[!j] in
        if !inq then begin
          if d = !q then inq := false;
          incr j
        end
        (* ${…} interpolation inside attribute region — skip. *)
        else if d = '$' && !j + 1 < n && c.[!j + 1] = '{' then begin
          j := !j + 2; let depth = ref 1 in
          while !depth > 0 && !j < n do
            (match c.[!j] with '{' -> incr depth | '}' -> decr depth | _ -> ());
            incr j
          done
        end
        (* Start of a quoted value (following '='). *)
        else if d = '"' || d = '\'' then begin
          inq := true; q := d; incr j
        end
        (* Attribute name: starts with a letter, '_', or ':'. *)
        else if (d >= 'a' && d <= 'z') || (d >= 'A' && d <= 'Z')
                || d = '_' || d = ':' then begin
          let name_ofs = !j in
          while !j < n && attr_nc c.[!j] do incr j done;
          let name_len = !j - name_ofs in
          let name = String.lowercase_ascii (String.sub c name_ofs name_len) in
          if Hashtbl.mem seen name then begin
            (* Second (or later) occurrence — emit a duplicate-attr entry. *)
            let span = attr_name_span name_ofs name_len in
            acc := (span,
                    Printf.sprintf "Duplicate attribute `%s`" name,
                    "html/duplicate-attr") :: !acc
          end else
            Hashtbl.add seen name ()
          (* Note: j already advanced past the name; loop continues with
             whatever comes next (whitespace, '=', '>', etc.). *)
        end
        else incr j
      done;
      (* Advance past the '>'. *)
      i := (if !j < n then !j + 1 else n)
    end
    else incr i
  done;
  List.rev !acc

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
  unknown_tag_results @ dup_attr_results

(** Return matched (open-name-span, close-name-span) pairs in one ~H sigil.
    Adapts the [scan_html_unclosed] walk: on a successful close-tag match, pop
    the matching open off the stack and record both tag-NAME spans (mapped to
    absolute source positions via [ofs_to_pos]).  Void and self-closing tags
    are skipped, as are [${…}] interpolations and [<!-- … -->] comments. *)
let tag_pairs_in_sigil ~(src : string) (s : h_sigil) : (Ast.span * Ast.span) list =
  let c = s.hs_content in
  let n = String.length c in
  let is_nc ch =
    (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
    || (ch >= '0' && ch <= '9') || ch = '-' || ch = '_' in
  (* Build a single-line Ast.span for a tag-name at content-relative byte
     offset [name_ofs] with length [name_len]. *)
  let name_span name_ofs name_len =
    let (l, col) = ofs_to_pos src (s.hs_base_ofs + name_ofs) in
    { Ast.file = ""; start_line = l; start_col = col;
      end_line = l; end_col = col + name_len } in
  (* Stack entries: (lowercase-tag-name, name-offset-in-content, name-len) *)
  let stack = ref [] and pairs = ref [] and i = ref 0 in
  while !i < n do
    let ch = c.[!i] in
    (* ${…} interpolation: skip balanced braces *)
    if ch = '$' && !i + 1 < n && c.[!i + 1] = '{' then begin
      i := !i + 2; let d = ref 1 in
      while !d > 0 && !i < n do
        (match c.[!i] with '{' -> incr d | '}' -> decr d | _ -> ()); incr i
      done
    end
    (* <!-- … --> comment *)
    else if ch = '<' && !i + 3 < n
            && c.[!i+1] = '!' && c.[!i+2] = '-' && c.[!i+3] = '-' then begin
      i := !i + 4;
      while !i + 2 < n
            && not (c.[!i] = '-' && c.[!i+1] = '-' && c.[!i+2] = '>') do incr i done;
      i := (if !i + 2 < n then !i + 3 else n)
    end
    (* <!doctype …> or other declarations *)
    else if ch = '<' && !i + 1 < n && c.[!i+1] = '!' then begin
      while !i < n && c.[!i] <> '>' do incr i done;
      if !i < n then incr i
    end
    (* </tag> close tag *)
    else if ch = '<' && !i + 1 < n && c.[!i+1] = '/' then begin
      let ns = !i + 2 in let j = ref ns in
      while !j < n && is_nc c.[!j] do incr j done;
      let close_name_ofs = ns and close_name_len = !j - ns in
      let tag = String.lowercase_ascii (String.sub c ns close_name_len) in
      while !j < n && c.[!j] <> '>' do incr j done;
      i := (if !j < n then !j + 1 else n);
      (* Pop down to the matching open; skip any unmatched opens above it. *)
      let rec pop = function
        | (t, o, ln) :: r when t = tag ->
          pairs := (name_span o ln, name_span close_name_ofs close_name_len)
                   :: !pairs;
          r
        | _ :: r -> pop r
        | [] -> [] in
      stack := pop !stack
    end
    (* <tag …> open tag *)
    else if ch = '<' && !i + 1 < n
            && (let d = c.[!i+1] in (d>='a'&&d<='z')||(d>='A'&&d<='Z')) then begin
      let ns = !i + 1 in let j = ref ns in
      while !j < n && is_nc c.[!j] do incr j done;
      let name_ofs = ns and name_len = !j - ns in
      let tag = String.lowercase_ascii (String.sub c ns name_len) in
      (* Advance past attributes, respecting quoted values so '>' inside a
         quoted attribute string does not terminate the tag early. *)
      let inq = ref false and q = ref ' ' in
      while !j < n && (!inq || c.[!j] <> '>') do
        let d = c.[!j] in
        (if !inq then (if d = !q then inq := false)
         else if d = '"' || d = '\'' then (inq := true; q := d));
        incr j
      done;
      let self = !j < n && !j > 0 && c.[!j - 1] = '/' in
      i := (if !j < n then !j + 1 else n);
      if not self && not (List.mem tag html_void_elements) then
        stack := (tag, name_ofs, name_len) :: !stack
    end
    else incr i
  done;
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
    if String.uppercase_ascii name = "H" then begin
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
  let i = ref 0 in
  while !i < n do
    if !i + 7 <= n && String.sub c !i 7 = "<island" then begin
      let tag_end =
        match find_from ">" !i with -1 -> n | e -> e
      in
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

(* Collect unclosed-tag issues across all ~H sigils in [decls]. *)
let collect_html_issues ~(src : string) (decls : Ast.decl list) : html_issue list =
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
    (collect_h_sigils ~src decls);
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
      tir_fn_insights   = [];
      code_lens_items   = [];
      decls             = [];
      protocols         = [];
      param_name_map    = build_param_name_map [] }
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
            | _                     -> Ast.dummy_span
          in
          is_user_file sp
        ) raw_ast.Ast.mod_decls
    in
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
    let html_issues = collect_html_issues ~src user_decls in
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
    let diags =
      (Err.sorted errors |> List.filter_map (diag_to_lsp ~filename))
      @ !dead_code_diags
      @ unused_fn_diags
      @ perf_diags
      @ html_diags
      @ html_lint_diags
      @ island_diags
    in
    { src; filename; doc; type_map; def_map; use_map;
      vars       = vars_list;
      types      = Tc.StrMap.bindings final_env.Tc.types;
      ctors      = Tc.StrMap.fold (fun name cis acc ->
                     match cis with ci :: _ -> (name, ci.Tc.ci_type) :: acc | [] -> acc)
                     final_env.Tc.ctors [];
      interfaces = Tc.StrMap.bindings final_env.Tc.interfaces;
      impls      = Tc.StrMap.fold (fun k vs acc ->
                     List.fold_left (fun a v -> (k, v) :: a) acc vs)
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
      tir_fn_insights  = [];
      code_lens_items  = build_action_lenses ~filename user_decls;
      decls            = user_decls;
      protocols        =
        List.filter_map (function
            | Ast.DProtocol (n, pd, _) -> Some (n.Ast.txt, pd)
            | _ -> None) user_decls;
      param_name_map   = build_param_name_map user_decls }

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
  (string, tir_fn_insight list * code_lens_item list * perf_insight list) Hashtbl.t
  = Hashtbl.create 16

let run_tir_pass (a : t) : t =
  (* Skip if there are errors — the TIR pipeline would fail on broken source. *)
  let has_errors = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
      d.severity = Some Lsp.Types.DiagnosticSeverity.Error
    ) a.diagnostics
  in
  if has_errors then a
  else
    let cache_key = March_cas.Blake3.hash_string a.src in
    (* Preserve the actionable Run/Debug lenses already built in [analyse]
       (those carry a command); the TIR pass only ADDS informational perf
       lenses, it must not drop the action lenses. *)
    let action_lenses =
      List.filter (fun cl -> cl.cl_command <> None) a.code_lens_items
    in
    match Hashtbl.find_opt tir_pass_cache cache_key with
    | Some (tir_fn_insights, code_lens_items, tir_perf_insights) ->
      { a with tir_fn_insights;
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
      (* Run: lower → mono → defun → known_call → perceus → escape *)
      let tir = March_tir.Lower.lower_module ~type_map:a.type_map desugared in
      let tir = March_tir.Mono.monomorphize tir in
      let tir = March_tir.Defun.defunctionalize tir in
      let tir = March_tir.Known_call.run ~changed:(ref false) tir in
      let tir = March_tir.Perceus.perceus tir in
      let tir = March_tir.Escape.escape_analysis tir in
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
        (tir_fn_insights, code_lens_items, tir_perf_insights);
      { a with
        tir_fn_insights;
        code_lens_items = action_lenses @ code_lens_items;
        perf_insights = a.perf_insights @ tir_perf_insights;
      }
    with _ ->
      (* TIR pipeline failed (e.g. unsupported construct) — return analysis unchanged *)
      a

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

(* Raw inferred type of the smallest user-file span containing the cursor.
   Only considers current-file spans (the type_map is shared with stdlib whose
   spans collide on line/col). *)
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

let type_at (a : t) ~line ~character : string option =
  Option.map Tc.pp_ty (ty_at a ~line ~character)

(* Smallest local-binder use/def span containing the cursor -> its symbol id.
   [None] means the cursor is not on a function-local binding (top-level/stdlib,
   resolved by the name-based maps instead). *)
let local_symbol_at (a : t) ~line ~character : int option =
  let best = ref None in
  let consider sp id =
    if Pos.span_contains sp ~line ~character then
      match !best with
      | Some (bsp, _) when not (Pos.span_smaller sp bsp) -> ()
      | _ -> best := Some (sp, id)
  in
  Hashtbl.iter (fun sp id -> consider sp id) a.sym_uses;
  Hashtbl.iter (fun id sp -> consider sp id) a.sym_defs;
  Option.map snd !best

(* A span belongs to the file being analysed (not stdlib). Position scans that
   find "the name under the cursor" MUST filter by this: stdlib decls share the
   same (line,col) coordinate space, so an unfiltered scan can match a stdlib
   span that merely collides with the cursor's line/col. *)
let span_in_user_file (a : t) (sp : Ast.span) : bool =
  sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"

let definition_at (a : t) ~line ~character : Lsp.Types.Location.t option =
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

let keywords = [
  "mod"; "end"; "do"; "fn"; "let"; "match"; "if"; "then"; "else";
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

let completions_at (a : t) ~line ~character =
  match dot_completions a ~line ~character with
  | Some items -> items   (* in `receiver.`: only the receiver's members *)
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
  (* Rank by category via sortText: locals < keywords < top-level/stdlib values
     < types < constructors < interfaces < sigils < auto-imports. *)
  let rank s items =
    List.map (fun it -> { it with CompletionItem.sortText = Some s }) items
  in
  rank "0" local_items
  @ rank "1" kw_items
  @ rank "2" var_items
  @ rank "3" type_items
  @ rank "4" ctor_items
  @ rank "5" iface_items
  @ rank "6" sigil_items
  @ auto_items
  ) (* end match island_items *)

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
      ) a.perf_insights
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

let locations_of_spans (a : t) (spans : Ast.span list) : Lsp.Types.Location.t list =
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
    ) spans

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

(* Resolve the symbol under the cursor to (definition span option, use spans).
   Shared by find-references and documentHighlight so the two never diverge.
   Locals resolve by scope (shadow-correct); everything else by name. *)
let symbol_spans_at (a : t) ~line ~character
    : (Ast.span option * Ast.span list) option =
  match local_symbol_at a ~line ~character with
  | Some id ->
    let use_spans = try Hashtbl.find a.sym_id_uses id with Not_found -> [] in
    Some (Hashtbl.find_opt a.sym_defs id, use_spans)
  | None ->
    let name_opt =
      let from_use =
        Hashtbl.fold (fun sp name found ->
            match found with
            | Some _ -> found
            | None   ->
              if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
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
              if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
              else None
          ) a.def_map None
    in
    match name_opt with
    | None -> None
    | Some name ->
      let use_spans =
        match Hashtbl.find_opt a.refs_map name with
        | Some spans -> spans
        | None       -> []
      in
      Some (Hashtbl.find_opt a.def_map name, use_spans)

let references_at (a : t) ~include_declaration ~line ~character
    : Lsp.Types.Location.t list =
  match symbol_spans_at a ~line ~character with
  | None -> []
  | Some (def_opt, use_spans) ->
    let all_spans =
      if include_declaration then
        match def_opt with Some d -> d :: use_spans | None -> use_spans
      else use_spans
    in
    locations_of_spans a all_spans

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
  | None ->
  match symbol_spans_at a ~line ~character with
  | None -> []
  | Some (def_opt, use_spans) ->
    (match def_opt with Some d -> d :: use_spans | None -> use_spans)
    |> List.filter (fun sp -> sp <> Ast.dummy_span && span_in_user_file a sp)

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

(* ==================================================================== *)
(* AST-driven code action helpers (Phase 2+).                           *)
(*                                                                       *)
(* These walk the retained raw user AST ([a.decls]) to power the         *)
(* refactoring actions that need structural information: pipe            *)
(* introduce/remove, extract/inline variable, expand/collapse function   *)
(* capture, typed-hole fills, and actor/protocol scaffolding.            *)
(* ==================================================================== *)

(** Byte [start, end) of a span within [src]. *)
let span_byte_bounds src (sp : Ast.span) =
  let s = offset_of_pos src (sp.Ast.start_line - 1) sp.Ast.start_col in
  let e = offset_of_pos src (sp.Ast.end_line   - 1) sp.Ast.end_col in
  (s, e)

(** Source text covered by [sp], or "" if out of bounds. *)
let slice_span src (sp : Ast.span) =
  let (s, e) = span_byte_bounds src sp in
  if e > s && s >= 0 && e <= String.length src then String.sub src s (e - s)
  else ""

(** Leading whitespace (indentation) of the source line [line0] (0-indexed). *)
let indent_of_line src line0 =
  let start = offset_of_pos src line0 0 in
  let n = String.length src in
  let buf = Buffer.create 8 in
  let i = ref start in
  while !i < n && (src.[!i] = ' ' || src.[!i] = '\t') do
    Buffer.add_char buf src.[!i]; incr i
  done;
  Buffer.contents buf

(** Visit every expression occurring in declaration [d] (recursing into
    nested modules). *)
let rec iter_decl_exprs (f : Ast.expr -> unit) (d : Ast.decl) =
  match d with
  | Ast.DFn (fn, _) ->
    List.iter (fun (cl : Ast.fn_clause) ->
        (match cl.fc_guard with Some g -> iter_expr f g | None -> ());
        iter_expr f cl.fc_body) fn.fn_clauses
  | Ast.DLet (_, b, _) -> iter_expr f b.Ast.bind_expr
  | Ast.DActor (_, _, adef, _) ->
    iter_expr f adef.Ast.actor_init;
    List.iter (fun (h : Ast.actor_handler) -> iter_expr f h.ah_body)
      adef.Ast.actor_handlers
  | Ast.DTest (t, _) -> iter_expr f t.Ast.test_body
  | Ast.DDescribe (_, decls, _) -> List.iter (iter_decl_exprs f) decls
  | Ast.DMod (_, _, decls, _) -> List.iter (iter_decl_exprs f) decls
  | _ -> ()

(** All sub-expressions across [decls]. *)
let all_exprs (decls : Ast.decl list) : Ast.expr list =
  let acc = ref [] in
  List.iter (iter_decl_exprs (fun e -> acc := e :: !acc)) decls;
  !acc

(** The smallest expression satisfying [pred] that contains the cursor. *)
let smallest_expr_at (a : t) ~line ~character ~(pred : Ast.expr -> bool)
    : Ast.expr option =
  let cands =
    List.filter (fun e ->
        let sp = span_of_expr e in
        (sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>")
        && Pos.span_contains sp ~line ~character
        && pred e)
      (all_exprs a.decls)
  in
  match cands with
  | [] -> None
  | x :: xs ->
    Some (List.fold_left (fun best e ->
        if Pos.span_smaller (span_of_expr e) (span_of_expr best) then e else best)
        x xs)

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

(** Render a surface [Ast.ty] back to March source syntax (best-effort,
    used for generated scaffolds). *)
let rec surface_ty (t : Ast.ty) : string =
  match t with
  | Ast.TyCon (n, [])   -> n.Ast.txt
  | Ast.TyCon (n, args) ->
    n.Ast.txt ^ "(" ^ String.concat ", " (List.map surface_ty args) ^ ")"
  | Ast.TyVar n         -> n.Ast.txt
  | Ast.TyArrow (a, b)  -> surface_ty a ^ " -> " ^ surface_ty b
  | Ast.TyTuple ts      -> "(" ^ String.concat ", " (List.map surface_ty ts) ^ ")"
  | Ast.TyRecord fs     ->
    "{ " ^ String.concat ", "
             (List.map (fun (n, t) -> n.Ast.txt ^ ": " ^ surface_ty t) fs) ^ " }"
  | Ast.TyLinear (_, t) -> "linear " ^ surface_ty t
  | Ast.TyNat n         -> string_of_int n
  | Ast.TyNatOp (op, a, b) ->
    surface_ty a ^ (match op with Ast.NatAdd -> " + " | Ast.NatMul -> " * ")
    ^ surface_ty b
  | Ast.TyChan (r, p)   -> "Chan(" ^ r.Ast.txt ^ ", " ^ p.Ast.txt ^ ")"

(** Split a surface arrow type into (param types, return type). *)
let rec split_arrow (t : Ast.ty) : Ast.ty list * Ast.ty =
  match t with
  | Ast.TyArrow (a, b) -> let ps, r = split_arrow b in (a :: ps, r)
  | _ -> ([], t)

let scheme_ty = function Tc.Mono t -> t | Tc.Poly (_, _, t) -> t

(** Head type-constructor name of a resolved [Tc.ty], if any. *)
let ty_head_name (t : Tc.ty) : string option =
  match Tc.repr t with
  | Tc.TCon (n, _) -> Some n
  | _ -> None

(** Number of leading arrows (arity) of a resolved [Tc.ty]. *)
let rec ty_arrow_arity (t : Tc.ty) : int =
  match Tc.repr t with
  | Tc.TArrow (_, rest) -> 1 + ty_arrow_arity rest
  | _ -> 0

(** Is [name] a plain identifier (vs. an operator like `+`, `==`, `|>`)? *)
let is_ident_name name =
  String.length name > 0 &&
  (let c = name.[0] in
   (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_')

(* ==================================================================== *)
(* AST-driven code actions (Phase 2+).                                  *)
(* ==================================================================== *)

(** Replace whole-identifier occurrences in [text] per the (name → replacement)
    [subs] table. Identifier-aware (won't match substrings); does not track
    shadowing — adequate for inlining a small single-clause function body. *)
let substitute_idents (text : string) (subs : (string * string) list) : string =
  let buf = Buffer.create (String.length text) in
  let n = String.length text in
  let is_id c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_' || c = '\''
  in
  let i = ref 0 in
  while !i < n do
    let c = text.[!i] in
    if is_id c && (!i = 0 || not (is_id text.[!i - 1])) then begin
      let j = ref !i in
      while !j < n && is_id text.[!j] do incr j done;
      let word = String.sub text !i (!j - !i) in
      (match List.assoc_opt word subs with
       | Some repl -> Buffer.add_string buf repl
       | None -> Buffer.add_string buf word);
      i := !j
    end else begin Buffer.add_char buf c; incr i end
  done;
  Buffer.contents buf

let ast_code_actions (a : t) ~line ~character : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  let uri = DocumentUri.of_path a.filename in
  let src = a.src in
  let mk_we edits = WorkspaceEdit.create ~changes:[(uri, edits)] () in
  let range_of_span (sp : Ast.span) =
    Range.create
      ~start:(Position.create ~line:(sp.Ast.start_line - 1) ~character:sp.Ast.start_col)
      ~end_:(Position.create ~line:(sp.Ast.end_line - 1) ~character:sp.Ast.end_col)
  in
  let at sp = Pos.span_contains sp ~line ~character in

  (* ---- P1.2: Introduce pipe ---- *)
  (* f(arg0, rest...)  →  arg0 |> f(rest...)  *)
  let introduce_pipe_actions =
    let pred = function
      | Ast.EApp (callee, _ :: _, _) ->
        (match callee with
         | Ast.EVar n -> is_ident_name n.Ast.txt
         | Ast.EField _ -> true
         | _ -> false)
      | _ -> false
    in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EApp (callee, arg0 :: rest, sp)) ->
      let callee_text = slice_span src (span_of_expr callee) in
      let arg0_text   = slice_span src (span_of_expr arg0) in
      if callee_text = "" || arg0_text = "" then []
      else begin
        let rest_text = List.map (fun e -> slice_span src (span_of_expr e)) rest in
        let new_text =
          Printf.sprintf "%s |> %s(%s)" arg0_text callee_text
            (String.concat ", " rest_text)
        in
        let edit = TextEdit.create ~range:(range_of_span sp) ~newText:new_text in
        [CodeAction.create ~title:"Introduce pipe"
           ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
      end
    | _ -> []
  in

  (* ---- P1.2: Remove pipe ---- *)
  (* a |> f(b) |> g()  →  g(f(a, b))  *)
  let remove_pipe_actions =
    (* Pick the LARGEST pipe chain containing the cursor so the whole chain
       collapses in one action. *)
    let pipes =
      List.filter (function
          | Ast.EPipe (_, _, sp) -> at sp
          | _ -> false)
        (all_exprs a.decls)
    in
    match pipes with
    | [] -> []
    | x :: xs ->
      let outer =
        List.fold_left (fun best e ->
            if Pos.span_smaller (span_of_expr best) (span_of_expr e) then e else best)
          x xs
      in
      let rec to_call (e : Ast.expr) : string =
        match e with
        | Ast.EPipe (l, r, _) ->
          let lt = to_call l in
          (match r with
           | Ast.EApp (callee, args, _) ->
             let callee_text = slice_span src (span_of_expr callee) in
             let arg_texts = List.map (fun e -> slice_span src (span_of_expr e)) args in
             Printf.sprintf "%s(%s)" callee_text (String.concat ", " (lt :: arg_texts))
           | Ast.EVar n -> Printf.sprintf "%s(%s)" n.Ast.txt lt
           | _ -> Printf.sprintf "%s(%s)" (slice_span src (span_of_expr r)) lt)
        | _ -> slice_span src (span_of_expr e)
      in
      let sp = span_of_expr outer in
      let edit = TextEdit.create ~range:(range_of_span sp) ~newText:(to_call outer) in
      [CodeAction.create ~title:"Remove pipe"
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- P1.3: Extract variable ---- *)
  let extract_var_actions =
    let pred = function
      | Ast.EApp _ | Ast.ECon _ | Ast.EField _ | Ast.ERecord _
      | Ast.ERecordUpdate _ | Ast.ETuple _ | Ast.EAtom _ | Ast.EPipe _ -> true
      | _ -> false
    in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      let sp = span_of_expr e in
      let expr_text = slice_span src sp in
      if expr_text = "" then []
      else begin
        (* Suggest a name from the inferred type, else a generic one. *)
        let name =
          match Hashtbl.find_opt a.type_map sp with
          | Some ty ->
            (match ty_head_name ty with
             | Some h when is_ident_name h -> String.lowercase_ascii h
             | _ -> "value")
          | None -> "value"
        in
        let indent = indent_of_line src (sp.Ast.start_line - 1) in
        let insert_pos =
          Position.create ~line:(sp.Ast.start_line - 1) ~character:0 in
        let insert_edit =
          TextEdit.create
            ~range:(Range.create ~start:insert_pos ~end_:insert_pos)
            ~newText:(Printf.sprintf "%slet %s = %s\n" indent name expr_text)
        in
        let replace_edit =
          TextEdit.create ~range:(range_of_span sp) ~newText:name in
        [CodeAction.create ~title:"Extract variable"
           ~kind:CodeActionKind.RefactorExtract
           ~edit:(mk_we [insert_edit; replace_edit]) ()]
      end
  in

  (* ---- P1.4: Inline variable ---- *)
  let inline_var_actions =
    (* Locate a `let <name> = rhs` whose name is under the cursor. *)
    let found = ref None in
    let rec scan_block (es : Ast.expr list) =
      List.iter (fun e -> match e with
          | Ast.ELet (b, let_sp) ->
            (match b.Ast.bind_pat with
             | Ast.PatVar nm when at nm.Ast.span ->
               found := Some (nm, b.Ast.bind_expr, let_sp)
             | _ -> ());
            scan_one b.Ast.bind_expr
          | _ -> scan_one e) es
    and scan_one e =
      match e with
      | Ast.EBlock (es, _) -> scan_block es
      | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> scan_one body
      | Ast.EMatch (subj, brs, _) ->
        scan_one subj;
        List.iter (fun (br : Ast.branch) -> scan_one br.branch_body) brs
      | Ast.EIf (c, t, el, _) -> scan_one c; scan_one t; scan_one el
      | Ast.EApp (f, args, _) -> scan_one f; List.iter scan_one args
      | Ast.EPipe (l, r, _) | Ast.ESend (l, r, _) -> scan_one l; scan_one r
      | Ast.ELet (b, _) -> scan_one b.Ast.bind_expr
      | _ -> ()
    in
    List.iter (fun d -> iter_decl_exprs (fun e ->
        match e with Ast.EBlock (es, _) -> scan_block es | _ -> ()) d) a.decls;
    match !found with
    | None -> []
    | Some (nm, rhs, let_sp) ->
      (* Use spans gathered by the (proven) consumption pass. *)
      let uses =
        List.fold_left (fun acc (c : consumption) ->
            if c.con_name = nm.Ast.txt && c.con_def = let_sp then c.con_uses @ acc
            else acc) [] a.consumption
      in
      if uses = [] then []
      else begin
        let rhs_text = slice_span src (span_of_expr rhs) in
        (* Parenthesize compound RHS so precedence is preserved at use sites. *)
        let needs_parens = match rhs with
          | Ast.EPipe _ | Ast.EIf _ | Ast.EMatch _ | Ast.ELam _ | Ast.EAnnot _ -> true
          | Ast.EApp (Ast.EVar n, _ :: _, _) -> not (is_ident_name n.Ast.txt)
          | _ -> false
        in
        let value = if needs_parens then "(" ^ rhs_text ^ ")" else rhs_text in
        let use_edits =
          List.map (fun (sp : Ast.span) ->
              TextEdit.create ~range:(range_of_span sp) ~newText:value) uses
        in
        (* Delete the whole let line(s). *)
        let del_edit =
          TextEdit.create
            ~range:(Range.create
                      ~start:(Position.create ~line:(let_sp.Ast.start_line - 1) ~character:0)
                      ~end_:(Position.create ~line:let_sp.Ast.end_line ~character:0))
            ~newText:""
        in
        [CodeAction.create
           ~title:(Printf.sprintf "Inline variable `%s`" nm.Ast.txt)
           ~kind:CodeActionKind.RefactorInline
           ~edit:(mk_we (del_edit :: use_edits)) ()]
      end
  in

  (* ---- P1.9: Collapse function capture (eta-contraction) ---- *)
  (* fn (x) -> f(x)  →  f  *)
  let collapse_capture_actions =
    let pred = function Ast.ELam _ -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.ELam (params, Ast.EApp (callee, args, _), sp))
      when List.length params = List.length args && params <> [] ->
      let param_names = List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) params in
      let args_are_params =
        List.for_all2 (fun pn a -> match a with
            | Ast.EVar n -> n.Ast.txt = pn
            | _ -> false) param_names args
      in
      (* The callee must not itself mention the bound params. *)
      let callee_text = slice_span src (span_of_expr callee) in
      let callee_ok =
        match callee with
        | Ast.EVar n -> not (List.mem n.Ast.txt param_names)
        | Ast.EField _ -> true
        | _ -> false
      in
      if args_are_params && callee_ok && callee_text <> "" then
        [CodeAction.create
           ~title:(Printf.sprintf "Collapse to `%s`" callee_text)
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:callee_text])
           ()]
      else []
    | _ -> []
  in

  (* ---- P1.9: Expand function capture (eta-expansion) ---- *)
  (* a function-valued identifier `f`  →  fn (_x0, _x1) -> f(_x0, _x1) *)
  let expand_capture_actions =
    (* Spans of identifiers appearing in callee position — expanding those
       would be wrong (it would wrap the function being applied). *)
    let callee_spans = Hashtbl.create 16 in
    List.iter (function
        | Ast.EApp (callee, _, _) ->
          Hashtbl.replace callee_spans (span_of_expr callee) ()
        | _ -> ())
      (all_exprs a.decls);
    let pred = function
      | Ast.EVar _ as e -> not (Hashtbl.mem callee_spans (span_of_expr e))
      | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EVar n as e) when is_ident_name n.Ast.txt ->
      let sp = span_of_expr e in
      let arity =
        match Hashtbl.find_opt a.type_map sp with
        | Some ty -> ty_arrow_arity ty
        | None ->
          (match List.assoc_opt n.Ast.txt a.vars with
           | Some sch -> ty_arrow_arity (scheme_ty sch)
           | None -> 0)
      in
      if arity <= 0 || arity > 8 then []
      else begin
        let ps = List.init arity (fun i -> Printf.sprintf "_x%d" i) in
        let new_text =
          Printf.sprintf "fn (%s) -> %s(%s)"
            (String.concat ", " ps) n.Ast.txt (String.concat ", " ps)
        in
        [CodeAction.create ~title:"Expand to lambda"
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:new_text]) ()]
      end
    | _ -> []
  in

  (* ---- P2.1: Typed hole fills ---- *)
  let hole_fill_actions =
    let pred = function Ast.EHole _ -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EHole (_, sp)) ->
      let expected = Option.map Tc.repr (Hashtbl.find_opt a.type_map sp) in
      let suggestions =
        match expected with
        | None -> []
        | Some ty ->
          let head = ty_head_name ty in
          (* Literals for base types. *)
          let lits = match head with
            | Some "Int"    -> ["0"]
            | Some "Float"  -> ["0.0"]
            | Some "String" -> ["\"\""]
            | Some "Bool"   -> ["true"; "false"]
            | Some "Char"   -> ["' '"]
            | Some "Unit"   -> ["()"]
            | _ -> []
          in
          (* Constructors producing the expected type. Prefer the unqualified
             form; skip module-qualified duplicates ("Mod.Ctor"). *)
          let ctors = match head with
            | None -> []
            | Some h ->
              List.filter_map (fun (cname, parent) ->
                  if String.contains cname '.' then None
                  else if parent = h || parent = h ^ "()" then
                    let ar = try List.assoc cname a.ctor_arities with Not_found -> 0 in
                    if ar = 0 then Some cname
                    else Some (Printf.sprintf "%s(%s)" cname
                                 (String.concat ", " (List.init ar (fun _ -> "?"))))
                  else None) a.ctors
          in
          (* In-scope (non-function) variables whose head type matches. *)
          let vars = match head with
            | None -> []
            | Some h ->
              List.filter_map (fun (vn, sch) ->
                  if String.length vn > 0 && vn.[0] = '_' then None
                  else if String.contains vn '.' then None
                  else
                    let ty = scheme_ty sch in
                    match ty_head_name ty with
                    | Some vh when vh = h && is_ident_name vn
                                && ty_arrow_arity ty = 0
                                && not (List.mem_assoc vn a.ctors) -> Some vn
                    | _ -> None) a.vars
          in
          let all = lits @ ctors @ vars in
          (* De-dup preserving order, cap the count. *)
          let seen = Hashtbl.create 16 in
          List.filter (fun s ->
              if Hashtbl.mem seen s then false
              else (Hashtbl.add seen s (); true)) all
      in
      let suggestions = List.filteri (fun i _ -> i < 12) suggestions in
      List.map (fun s ->
          CodeAction.create
            ~title:(Printf.sprintf "Fill hole with `%s`" s)
            ~kind:CodeActionKind.QuickFix
            ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:s]) ())
        suggestions
    | _ -> []
  in

  (* ---- P1.5: Auto-import (use ModuleName) ---- *)
  let auto_import_actions =
    (* Build an index of unqualified-name → modules that define it, from the
       qualified entries in def_map (keys like "List.map"). *)
    let head_name e = match e with
      | Ast.EVar n -> Some (n.Ast.txt, n.Ast.span)
      | Ast.ECon (n, _, _) -> Some (n.Ast.txt, n.Ast.span)
      | Ast.EField (Ast.ECon (m, [], _), fld, fsp) ->
        Some (m.Ast.txt ^ "." ^ fld.Ast.txt, fsp)
      (* `name(args)` and `Mod.fn(args)` — peer through the call to the callee. *)
      | Ast.EApp (Ast.EVar n, _, _) -> Some (n.Ast.txt, n.Ast.span)
      | Ast.EApp (Ast.EField (Ast.ECon (m, [], _), fld, fsp), _, _) ->
        Some (m.Ast.txt ^ "." ^ fld.Ast.txt, fsp)
      | _ -> None
    in
    let pred e = head_name e <> None in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      (match head_name e with
       | None -> []
       | Some (qname, _) ->
         (* Resolve the base name that may need importing. *)
         let base, modpath =
           match String.index_opt qname '.' with
           | Some i -> (String.sub qname 0 i, Some (String.sub qname 0 i))
           | None -> (qname, None)
         in
         (* Already resolvable? Then no import needed. *)
         let in_scope =
           List.mem_assoc base a.vars
           || List.mem_assoc base a.ctors
           || List.mem_assoc base a.types
           || (match modpath with Some m -> List.mem_assoc m a.types | None -> false)
         in
         if in_scope then []
         else begin
           (* Find modules that define `base` as `Mod.base`. *)
           let modules =
             Hashtbl.fold (fun k _ acc ->
                 match String.rindex_opt k '.' with
                 | Some i when String.sub k (i + 1) (String.length k - i - 1) = base ->
                   let m = String.sub k 0 i in
                   if List.mem m acc then acc else m :: acc
                 | _ -> acc) a.def_map []
           in
           let modules = List.sort String.compare modules in
           (* Insert `use Mod.{base}` at the top of the first user decl's line. *)
           let insert_line =
             List.fold_left (fun best d ->
                 let sp = match d with
                   | Ast.DFn (fn, _) -> fn.fn_name.span
                   | Ast.DLet (_, _, sp) | Ast.DType (_, _, _, _, sp)
                   | Ast.DActor (_, _, _, sp) | Ast.DImpl (_, sp)
                   | Ast.DUse (_, sp) -> sp
                   | Ast.DMod (n, _, _, _) -> n.Ast.span
                   | _ -> Ast.dummy_span
                 in
                 if sp.Ast.start_line > 0 && sp.Ast.start_line - 1 < best
                 then sp.Ast.start_line - 1 else best)
               max_int a.decls
           in
           let insert_line = if insert_line = max_int then 0 else insert_line in
           let indent = indent_of_line src insert_line in
           List.map (fun m ->
               let pos = Position.create ~line:insert_line ~character:0 in
               let edit = TextEdit.create
                   ~range:(Range.create ~start:pos ~end_:pos)
                   ~newText:(Printf.sprintf "%suse %s.{%s}\n" indent m base) in
               CodeAction.create
                 ~title:(Printf.sprintf "Import `%s` from `%s`" base m)
                 ~kind:CodeActionKind.QuickFix ~edit:(mk_we [edit]) ())
             modules
         end)
  in

  (* ---- P1.6: Generate interface impl scaffold ---- *)
  let impl_scaffold_actions =
    let impl_at =
      List.find_map (function
          | Ast.DImpl (idef, sp) when at sp -> Some (idef, sp)
          | _ -> None) a.decls
    in
    match impl_at with
    | None -> []
    | Some (idef, sp) ->
      (match List.assoc_opt idef.Ast.impl_iface.Ast.txt a.interfaces with
       | None -> []
       | Some iface ->
         let implemented =
           List.map (fun (n, _) -> n.Ast.txt) idef.Ast.impl_methods in
         let missing =
           List.filter (fun (md : Ast.method_decl) ->
               not (List.mem md.Ast.md_name.txt implemented))
             iface.Ast.iface_methods
         in
         if missing = [] then []
         else begin
           let indent = indent_of_line src (sp.Ast.start_line - 1) ^ "  " in
           let stub (md : Ast.method_decl) =
             let params, _ret = split_arrow md.Ast.md_ty in
             let param_list =
               List.mapi (fun i pt -> Printf.sprintf "p%d: %s" i (surface_ty pt)) params in
             Printf.sprintf "%sfn %s(%s) do ? end\n"
               indent md.Ast.md_name.txt (String.concat ", " param_list)
           in
           let body = String.concat "" (List.map stub missing) in
           (* Insert just before the impl block's closing `end`. *)
           (match find_end_before_span src sp with
            | None -> []
            | Some end_ofs ->
              let l = ref 0 and c = ref 0 and cl = ref 0 and cc = ref 0 in
              String.iteri (fun i _ ->
                  if i = end_ofs then begin l := !cl; c := !cc end;
                  if src.[i] = '\n' then begin incr cl; cc := 0 end else incr cc) src;
              let pos = Position.create ~line:!l ~character:!c in
              let edit = TextEdit.create
                  ~range:(Range.create ~start:pos ~end_:pos) ~newText:body in
              [CodeAction.create
                 ~title:(Printf.sprintf "Implement %d missing method(s)"
                           (List.length missing))
                 ~kind:CodeActionKind.QuickFix ~edit:(mk_we [edit]) ()])
         end)
  in

  (* ---- P3.1: Actor boilerplate (client wrappers) ---- *)
  let actor_boilerplate_actions =
    let actor_at =
      List.find_map (function
          | Ast.DActor (_, n, adef, sp) when at n.Ast.span || at sp ->
            Some (n.Ast.txt, adef, sp)
          | _ -> None) a.decls
    in
    match actor_at with
    | None -> []
    | Some (name, adef, sp) ->
      let wrappers =
        List.map (fun (h : Ast.actor_handler) ->
            let msg = h.Ast.ah_msg.txt in
            let params =
              List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) h.Ast.ah_params in
            let plist = String.concat ", " ("pid" :: params) in
            let payload =
              if params = [] then msg
              else Printf.sprintf "%s(%s)" msg (String.concat ", " params) in
            Printf.sprintf "  fn %s(%s) do send(pid, %s) end\n"
              (String.lowercase_ascii msg) plist payload)
          adef.Ast.actor_handlers
      in
      let body =
        Printf.sprintf "\nmod %sClient do\n%send\n" name (String.concat "" wrappers) in
      (* Insert after the actor declaration's last line. *)
      let pos = Position.create ~line:sp.Ast.end_line ~character:0 in
      let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:body in
      [CodeAction.create
         ~title:(Printf.sprintf "Generate %sClient module" name)
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- P3.2: Session-type scaffolding ---- *)
  let session_scaffold_actions =
    let proto_at =
      List.find_map (function
          | Ast.DProtocol (n, pd, sp) when at n.Ast.span || at sp ->
            Some (n.Ast.txt, pd, sp)
          | _ -> None) a.decls
    in
    match proto_at with
    | None -> []
    | Some (name, pd, sp) ->
      let rec steps_text indent ss =
        String.concat ""
          (List.map (fun (st : Ast.protocol_step) -> match st with
               | Ast.ProtoMsg (from, _to, ty) ->
                 Printf.sprintf "%s-- %s sends %s\n%ssend(ch, ?)\n%slet _ = receive(ch)\n"
                   indent from.Ast.txt (surface_ty ty) indent indent
               | Ast.ProtoLoop inner ->
                 Printf.sprintf "%sloop do\n%s%send\n" indent
                   (steps_text (indent ^ "  ") inner) indent
               | Ast.ProtoChoice (role, branches) ->
                 Printf.sprintf "%s-- choice by %s\n%smatch receive(ch) do\n%s%send\n"
                   indent role.Ast.txt indent
                   (String.concat ""
                      (List.map (fun (lbl, inner) ->
                           Printf.sprintf "%s  %s ->\n%s" indent lbl.Ast.txt
                             (steps_text (indent ^ "    ") inner)) branches))
                   indent)
             ss)
      in
      let body =
        Printf.sprintf "\nfn handle_%s(ch) do\n%s  close(ch)\nend\n"
          (String.lowercase_ascii name) (steps_text "  " pd.Ast.proto_steps) in
      let pos = Position.create ~line:sp.Ast.end_line ~character:0 in
      let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:body in
      [CodeAction.create
         ~title:(Printf.sprintf "Generate %s session handler" name)
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- P2.7 / case-to-match: convert `if` to `match` ---- *)
  let if_to_match_actions =
    let pred = function Ast.EIf _ -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EIf (cond, t, el, sp))
      when slice_span src (span_of_expr t) <> ""
        && slice_span src (span_of_expr el) <> ""
        && slice_span src (span_of_expr cond) <> "" ->
      let t_text = slice_span src (span_of_expr t) in
      (* Equality-chain form: if subj == K do .. else if subj == K2 .. *)
      let eq_parts e = match e with
        | Ast.EApp (Ast.EVar op, [Ast.EVar subj; rhs], _) when op.Ast.txt = "==" ->
          Some (subj.Ast.txt, slice_span src (span_of_expr rhs))
        | _ -> None
      in
      let new_text =
        match eq_parts cond with
        | Some (subj, k0) ->
          let buf = Buffer.create 128 in
          Buffer.add_string buf (Printf.sprintf "match %s do\n" subj);
          let rec emit kpat body rest =
            Buffer.add_string buf (Printf.sprintf "  %s -> %s\n" kpat
                                     (slice_span src (span_of_expr body)));
            match rest with
            | Ast.EIf (c2, t2, e2, _) ->
              (match eq_parts c2 with
               | Some (s2, k2) when s2 = subj -> emit k2 t2 e2
               | _ -> Buffer.add_string buf (Printf.sprintf "  _ -> %s\n"
                                               (slice_span src (span_of_expr rest))))
            | _ -> Buffer.add_string buf (Printf.sprintf "  _ -> %s\n"
                                            (slice_span src (span_of_expr rest)))
          in
          emit k0 t el;
          Buffer.add_string buf "end";
          Buffer.contents buf
        | None ->
          let e_text = slice_span src (span_of_expr el) in
          Printf.sprintf "match %s do\n  true -> %s\n  false -> %s\nend"
            (slice_span src (span_of_expr cond)) t_text e_text
      in
      [CodeAction.create ~title:"Convert if to match"
         ~kind:CodeActionKind.RefactorRewrite
         ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:new_text]) ()]
    | _ -> []
  in

  (* ---- P3.3: Linear consumption audit ---- *)
  (* Flag a linear binding (a `linear` function parameter, or a `let linear`
     binding) that is never consumed, or report how many times it is. *)
  let linear_audit_actions =
    (* Collect (name, name_span, body_expr) for every linear parameter. *)
    let lin_params = ref [] in
    let scan_clause (cl : Ast.fn_clause) =
      List.iter (function
          | Ast.FPNamed p | Ast.FPDefault (p, _)
            when p.Ast.param_lin = Ast.Linear || p.Ast.param_lin = Ast.Affine ->
            lin_params := (p.Ast.param_name, cl.fc_body) :: !lin_params
          | _ -> ()) cl.fc_params
    in
    let rec scan_decl (d : Ast.decl) =
      match d with
      | Ast.DFn (fn, _) -> List.iter scan_clause fn.fn_clauses
      | Ast.DMod (_, _, ds, _) -> List.iter scan_decl ds
      | _ -> ()
    in
    List.iter scan_decl a.decls;
    List.filter_map (fun ((nm : Ast.name), body) ->
        if not (Pos.span_contains nm.Ast.span ~line ~character) then None
        else begin
          let uses = find_uses nm.Ast.txt body [] in
          if uses = [] then
            Some (CodeAction.create
                    ~title:(Printf.sprintf
                              "Linear `%s` is never consumed (must be used exactly once)"
                              nm.Ast.txt)
                    ~kind:CodeActionKind.QuickFix
                    ~edit:(mk_we []) ())
          else
            Some (CodeAction.create
                    ~title:(Printf.sprintf "Linear `%s` is consumed at %d site(s)"
                              nm.Ast.txt (List.length uses))
                    ~kind:CodeActionKind.QuickFix
                    ~edit:(mk_we []) ())
        end)
      !lin_params
  in

  (* ---- Destruct / case-split: variant-typed expr -> exhaustive match ---- *)
  let destruct_actions =
    let pred = function
      | Ast.EVar _ | Ast.EField _ | Ast.EApp _ -> true
      | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      let sp = span_of_expr e in
      (match Option.map Tc.repr (Hashtbl.find_opt a.type_map sp) with
       | Some (Tc.TCon (tyname, _)) ->
         (* Constructors of [tyname], bare names only (drop qualified dups). *)
         let seen = Hashtbl.create 8 in
         let ctors =
           List.filter_map (fun (cname, parent) ->
               if parent = tyname && not (String.contains cname '.')
                  && not (Hashtbl.mem seen cname)
               then (Hashtbl.add seen cname (); Some cname) else None)
             a.ctors in
         let subj = slice_span src sp in
         if ctors = [] || subj = "" then []
         else begin
           let indent = indent_of_line src (sp.Ast.start_line - 1) in
           let arms =
             List.map (fun c ->
                 let ar = try List.assoc c a.ctor_arities with Not_found -> 0 in
                 let binders =
                   if ar = 0 then ""
                   else "(" ^ String.concat ", "
                          (List.init ar (fun i -> Printf.sprintf "x%d" i)) ^ ")" in
                 Printf.sprintf "%s  %s%s -> ?" indent c binders) ctors in
           let new_text =
             Printf.sprintf "match %s do\n%s\n%send" subj
               (String.concat "\n" arms) indent in
           [CodeAction.create
              ~title:(Printf.sprintf "Destruct `%s` into a match" subj)
              ~kind:CodeActionKind.RefactorRewrite
              ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:new_text]) ()]
         end
       | _ -> [])
  in

  (* ---- Extract function: selected expr -> top-level fn capturing free locals ---- *)
  let extract_fn_actions =
    let pred = function
      | Ast.EApp _ | Ast.ECon _ | Ast.EField _ | Ast.ERecord _
      | Ast.ERecordUpdate _ | Ast.ETuple _ | Ast.EPipe _ | Ast.EIf _
      | Ast.EMatch _ | Ast.EAtom _ -> true
      | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      let sp = span_of_expr e in
      let expr_text = slice_span src sp in
      if expr_text = "" then []
      else begin
        (* Scoped free-variable analysis: collect EVar uses not bound within e. *)
        let pat_names p =
          let acc = ref [] in
          let rec go = function
            | Ast.PatVar n -> acc := n.Ast.txt :: !acc
            | Ast.PatAs (p, n, _) -> go p; acc := n.Ast.txt :: !acc
            | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) | Ast.PatTuple (ps, _) ->
              List.iter go ps
            | Ast.PatRecord (fs, _) -> List.iter (fun (_, p) -> go p) fs
            | _ -> () in
          go p; !acc
        in
        let frees = ref [] in
        let rec fv bound (e : Ast.expr) =
          match e with
          | Ast.EVar n -> if not (List.mem n.Ast.txt bound) then frees := (n.Ast.txt, n.Ast.span) :: !frees
          | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
          | Ast.EApp (g, args, _) -> fv bound g; List.iter (fv bound) args
          | Ast.ECon (_, args, _) | Ast.EAtom (_, args, _) | Ast.ETuple (args, _) ->
            List.iter (fv bound) args
          | Ast.ELam (ps, body, _) ->
            let b = List.fold_left (fun b (p : Ast.param) -> p.Ast.param_name.txt :: b) bound ps in
            fv b body
          | Ast.ELetFn (n, ps, _, body, _) ->
            let b = n.Ast.txt :: List.fold_left (fun b (p : Ast.param) -> p.Ast.param_name.txt :: b) bound ps in
            fv b body
          | Ast.EBlock (es, _) ->
            ignore (List.fold_left (fun b e -> match e with
                | Ast.ELet (bd, _) -> fv b bd.Ast.bind_expr; pat_names bd.Ast.bind_pat @ b
                | _ -> fv b e; b) bound es)
          | Ast.ELet (bd, _) -> fv bound bd.Ast.bind_expr
          | Ast.EMatch (s, brs, _) ->
            fv bound s;
            List.iter (fun (br : Ast.branch) ->
                let b = pat_names br.branch_pat @ bound in
                (match br.branch_guard with Some g -> fv b g | None -> ());
                fv b br.branch_body) brs
          | Ast.EIf (c, t, el, _) -> fv bound c; fv bound t; fv bound el
          | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> fv bound c; fv bound b) arms
          | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> fv bound a; fv bound b
          | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> fv bound e) fs
          | Ast.ERecordUpdate (e, fs, _) -> fv bound e; List.iter (fun (_, e) -> fv bound e) fs
          | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
          | Ast.EAssert (e, _) | Ast.ESigil (_, e, _) | Ast.EDbg (Some e, _) -> fv bound e
        in
        fv [] e;
        (* Keep only locals (names not in the module/global env), de-duped, in use order. *)
        let seen = Hashtbl.create 16 in
        let params =
          List.rev !frees
          |> List.filter_map (fun (name, span) ->
              if Hashtbl.mem seen name then None
              else if List.mem_assoc name a.vars then (Hashtbl.add seen name (); None)
              else begin
                Hashtbl.add seen name ();
                let ty_s = match Hashtbl.find_opt a.type_map span with
                  | Some ty -> Some (Tc.pp_ty (Tc.repr ty)) | None -> None in
                Some (name, ty_s)
              end)
        in
        let param_text =
          String.concat ", "
            (List.map (fun (n, t) -> match t with Some t -> n ^ ": " ^ t | None -> n) params) in
        let arg_text = String.concat ", " (List.map fst params) in
        (* Insert the new function before the enclosing top-level fn. *)
        let enclosing_line = ref None in
        let rec scan_decl (d : Ast.decl) =
          match d with
          | Ast.DFn (fn, _) ->
            List.iter (fun (cl : Ast.fn_clause) ->
                let bsp = span_of_expr cl.Ast.fc_body in
                if Pos.span_contains bsp ~line ~character then
                  enclosing_line := Some fn.Ast.fn_name.Ast.span.Ast.start_line) fn.Ast.fn_clauses
          | Ast.DMod (_, _, ds, _) -> List.iter scan_decl ds
          | _ -> () in
        List.iter scan_decl a.decls;
        match !enclosing_line with
        | None -> []
        | Some fn_line ->
          let indent = indent_of_line src (fn_line - 1) in
          let new_fn =
            Printf.sprintf "%sfn extracted(%s) do\n%s  %s\n%send\n\n"
              indent param_text indent expr_text indent in
          let insert_pos = Position.create ~line:(fn_line - 1) ~character:0 in
          let insert_edit =
            TextEdit.create ~range:(Range.create ~start:insert_pos ~end_:insert_pos) ~newText:new_fn in
          let call_text = Printf.sprintf "extracted(%s)" arg_text in
          let replace_edit = TextEdit.create ~range:(range_of_span sp) ~newText:call_text in
          [CodeAction.create ~title:"Extract function"
             ~kind:CodeActionKind.RefactorExtract
             ~edit:(mk_we [insert_edit; replace_edit]) ()]
      end
  in

  (* ---- Organize imports: sort + de-duplicate `use` declarations ---- *)
  let organize_imports_actions =
    (* Collect every `use` declaration (including inside nested modules). *)
    let uses = ref [] in
    let rec scan (d : Ast.decl) =
      match d with
      | Ast.DUse (_, sp) -> uses := sp :: !uses
      | Ast.DMod (_, _, ds, _) -> List.iter scan ds
      | _ -> () in
    List.iter scan a.decls;
    let use_spans =
      List.rev !uses
      |> List.filter (fun (sp : Ast.span) ->
          sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>")
      |> List.sort (fun (a : Ast.span) b ->
          compare (a.Ast.start_line, a.Ast.start_col) (b.Ast.start_line, b.Ast.start_col))
    in
    if List.length use_spans < 2 then []
    else begin
      let texts = List.map (fun sp -> String.trim (slice_span src sp)) use_spans in
      (* Sorted + de-duplicated, first-occurrence wins. *)
      let seen = Hashtbl.create 16 in
      let organized =
        List.sort_uniq String.compare
          (List.filter (fun t ->
               if t = "" || Hashtbl.mem seen t then false
               else (Hashtbl.add seen t (); true)) texts)
      in
      (* Only offer if it actually changes the order or removes duplicates. *)
      if organized = texts then []
      else begin
        let first = List.hd use_spans in
        let indent = indent_of_line src (first.Ast.start_line - 1) in
        let block = String.concat ("\n" ^ indent) organized in
        (* Replace the first use with the organized block; delete the rest's lines. *)
        let first_edit =
          TextEdit.create ~range:(range_of_span first) ~newText:block in
        let delete_edits =
          List.filter_map (fun (sp : Ast.span) ->
              if sp == first then None
              else
                let r = Range.create
                    ~start:(Position.create ~line:(sp.Ast.start_line - 1) ~character:0)
                    ~end_:(Position.create ~line:sp.Ast.end_line ~character:0) in
                Some (TextEdit.create ~range:r ~newText:""))
            use_spans
        in
        [CodeAction.create ~title:"Organize imports"
           ~kind:CodeActionKind.SourceOrganizeImports
           ~edit:(mk_we (first_edit :: delete_edits)) ()]
      end
    end
  in

  (* ---- Generate doc comment (Feature 20) ---- *)
  (* Cursor on an undocumented function name → insert a scaffolded doc string. *)
  let doc_comment_actions =
    let found = ref None in
    let rec scan (d : Ast.decl) =
      match d with
      | Ast.DFn (fn, dsp) when fn.Ast.fn_doc = None && at fn.Ast.fn_name.Ast.span ->
        found := Some (fn, dsp)
      | Ast.DMod (_, _, ds, _) -> List.iter scan ds
      | _ -> ()
    in
    List.iter scan a.decls;
    match !found with
    | None -> []
    | Some (fn, dsp) ->
      let pnames = match fn.Ast.fn_clauses with cl :: _ -> clause_param_names cl | [] -> [] in
      let args =
        if pnames = [] then ""
        else "\n\nArguments:\n" ^ String.concat "\n" (List.map (fun n -> "- " ^ n) pnames)
      in
      let ret = match fn.Ast.fn_ret_ty with Some _ -> "\n\nReturns: TODO" | None -> "" in
      let indent = String.make dsp.Ast.start_col ' ' in
      let scaffold =
        Printf.sprintf "doc \"TODO: describe %s.%s%s\"\n%s" fn.Ast.fn_name.Ast.txt args ret indent
      in
      let pos = Position.create ~line:(dsp.Ast.start_line - 1) ~character:dsp.Ast.start_col in
      let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:scaffold in
      [CodeAction.create ~title:"Generate doc comment"
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- Inline function (Feature 10b) ---- *)
  (* Cursor on a call f(args) where f is a single-clause, non-recursive function
     with simple-name params → substitute the body, params → arg expressions. *)
  let inline_fn_actions =
    let pred = function Ast.EApp (Ast.EVar _, _, _) -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EApp (Ast.EVar fname, args, callsp)) ->
      let target = ref None in
      let rec scan (d : Ast.decl) =
        match d with
        | Ast.DFn (fn, _) when fn.Ast.fn_name.Ast.txt = fname.Ast.txt -> target := Some fn
        | Ast.DMod (_, _, ds, _) -> List.iter scan ds
        | _ -> ()
      in
      List.iter scan a.decls;
      (match !target with
       | Some fn when List.length fn.Ast.fn_clauses = 1 ->
         let cl = List.hd fn.Ast.fn_clauses in
         let pnames = clause_param_names cl in
         if List.length pnames = List.length args
            && List.length pnames = List.length cl.Ast.fc_params  (* all params are simple names *)
            && not (contains_call fn.Ast.fn_name.Ast.txt cl.Ast.fc_body)  (* non-recursive *)
         then begin
           let arg_texts =
             List.map (fun e ->
                 let t = slice_span src (span_of_expr e) in
                 match e with Ast.EVar _ | Ast.ELit _ -> t | _ -> "(" ^ t ^ ")") args
           in
           let body_text = slice_span src (span_of_expr cl.Ast.fc_body) in
           let substituted = substitute_idents body_text (List.combine pnames arg_texts) in
           let edit =
             TextEdit.create ~range:(range_of_span callsp) ~newText:("(" ^ substituted ^ ")")
           in
           [CodeAction.create ~title:(Printf.sprintf "Inline function `%s`" fname.Ast.txt)
              ~kind:CodeActionKind.RefactorInline ~edit:(mk_we [edit]) ()]
         end else []
       | _ -> [])
    | _ -> []
  in

  (* ---- Auto-alias for a repeated module prefix (Feature 13a) ---- *)
  (* Cursor on a qualified `A.B.foo` whose multi-segment module prefix `A.B`
     appears >= 3 times → insert `alias A.B` and rewrite uses to `B.foo`. *)
  let auto_alias_actions =
    let rec module_prefix = function
      | Ast.EVar n          -> Some n.Ast.txt
      | Ast.ECon (n, [], _) -> Some n.Ast.txt
      | Ast.EField (inner, f, _) ->
        (match module_prefix inner with Some p -> Some (p ^ "." ^ f.Ast.txt) | None -> None)
      | _ -> None
    in
    let rec root_span = function
      | Ast.EVar n          -> Some n.Ast.span
      | Ast.ECon (n, _, _)  -> Some n.Ast.span
      | Ast.EField (inner, _, _) -> root_span inner
      | _ -> None
    in
    (* (prefix, field, full-chain span) for every qualified field access. The
       node's own span covers only the field, so span the whole `A.B.foo`. *)
    let quals =
      List.filter_map (fun e -> match e with
          | Ast.EField (base, field, _) ->
            (match module_prefix base, root_span base with
             | Some p, Some rs when String.contains p '.' ->
               let full = { Ast.file = rs.Ast.file;
                            start_line = rs.Ast.start_line; start_col = rs.Ast.start_col;
                            end_line = field.Ast.span.Ast.end_line;
                            end_col = field.Ast.span.Ast.end_col } in
               Some (p, field, full)
             | _ -> None)
          | _ -> None)
        (all_exprs a.decls)
    in
    let count p = List.length (List.filter (fun (p', _, _) -> p' = p) quals) in
    match List.find_opt (fun (_, _, sp) -> at sp) quals with
    | Some (prefix, _, _) when count prefix >= 3 ->
      let short =
        match List.rev (String.split_on_char '.' prefix) with s :: _ -> s | [] -> prefix in
      (* Rewrite each `prefix.field` → `short.field`. *)
      let rewrites =
        List.filter_map (fun (p, field, sp) ->
            if p = prefix
            then Some (TextEdit.create ~range:(range_of_span sp)
                         ~newText:(short ^ "." ^ field.Ast.txt))
            else None) quals
      in
      (* Insert `alias <prefix>` before the first declaration of the module
         body (the file's top module body is stored directly in [a.decls]). *)
      let decl_line (d : Ast.decl) = match d with
        | Ast.DFn (fn, _)         -> fn.Ast.fn_name.Ast.span.Ast.start_line
        | Ast.DType (_, _, _, _, sp) | Ast.DLet (_, _, sp)
        | Ast.DApp (_, sp) | Ast.DImpl (_, sp) | Ast.DAlias (_, sp) -> sp.Ast.start_line
        | Ast.DMod (n, _, _, _) | Ast.DActor (_, n, _, _) -> n.Ast.span.Ast.start_line
        | _ -> max_int
      in
      let first = List.fold_left (fun acc d -> min acc (decl_line d)) max_int a.decls in
      if first = max_int then []
      else begin
        let indent = String.make 2 ' ' in
        let pos = Position.create ~line:(first - 1) ~character:0 in
        let alias_edit =
          TextEdit.create ~range:(Range.create ~start:pos ~end_:pos)
            ~newText:(Printf.sprintf "%salias %s\n" indent prefix)
        in
        [CodeAction.create
           ~title:(Printf.sprintf "Add `alias %s` and shorten %d use(s)"
                     prefix (List.length rewrites))
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:(mk_we (alias_edit :: rewrites)) ()]
      end
    | _ -> []
  in

  (* ---- Extract closure captures into a record (data clump in a closure) ---- *)
  (* Cursor on a lambda capturing >=2 genuine local values → insert a record
     `let captured = { a = a, b = b }` before the enclosing statement and rewrite
     the body's captures to `captured.a`. Globals/top-level fns are not captures. *)
  (* Multi-site extract: when the cursor lambda shares its genuine capture set
     with ≥1 other closure in the same function, offer to group those values
     into ONE shared record and rewrite EVERY sharing closure's body. This
     mirrors the closure-capture hint, which only fires for a repeated clump. *)
  let extract_captures_actions =
    let is_global n = List.mem_assoc n a.vars in
    (* Inclusive span ⊇ span (boundary-safe: `let f = <lambda>` ends exactly
       where the lambda ends). *)
    let contains (outer : Ast.span) (inner : Ast.span) =
      (outer.Ast.start_line < inner.Ast.start_line
       || (outer.Ast.start_line = inner.Ast.start_line && outer.Ast.start_col <= inner.Ast.start_col))
      && (outer.Ast.end_line > inner.Ast.end_line
          || (outer.Ast.end_line = inner.Ast.end_line && outer.Ast.end_col >= inner.Ast.end_col))
    in
    let span_size (s : Ast.span) =
      (s.Ast.end_line - s.Ast.start_line, s.Ast.end_col - s.Ast.start_col)
    in
    match smallest_expr_at a ~line ~character ~pred:(function Ast.ELam _ -> true | _ -> false) with
    | Some (Ast.ELam (params, body, lam_sp)) ->
      let caps =
        lambda_free_vars params body
        |> List.filter (fun n -> not (is_global n))
        |> List.sort_uniq String.compare
      in
      if List.length caps < 2 then []
      else begin
        (* Find the innermost function-clause body containing the cursor lambda —
           the scope shared by all sibling closures. *)
        let fn_bodies =
          let acc = ref [] in
          let rec go (d : Ast.decl) = match d with
            | Ast.DFn (fn, _) ->
              List.iter (fun (cl : Ast.fn_clause) -> acc := cl.Ast.fc_body :: !acc) fn.Ast.fn_clauses
            | Ast.DMod (_, _, decls, _) | Ast.DDescribe (_, decls, _) -> List.iter go decls
            | _ -> ()
          in
          List.iter go a.decls; !acc
        in
        let scope =
          List.fold_left (fun best b ->
              let bsp = span_of_expr b in
              if contains bsp lam_sp then
                match best with
                | Some (bestsp, _) when span_size bestsp <= span_size bsp -> best
                | _ -> Some (bsp, b)
              else best)
            None fn_bodies
        in
        match scope with
        | None -> []
        | Some (_, scope_body) ->
          (* Every closure in this function with the IDENTICAL capture set. *)
          let group =
            collect_lambda_captures is_global scope_body
            |> List.filter (fun (_, _, cs) -> cs = caps)
          in
          if List.length group < 2 then []   (* lone closure: no warning, no extract *)
          else begin
            (* Each closure's innermost enclosing block statement. *)
            let stmt_of (lsp : Ast.span) =
              let target = ref None in
              iter_expr (fun e ->
                  match e with
                  | Ast.EBlock (es, _) ->
                    List.iter (fun el ->
                        let esp = span_of_expr el in
                        if contains esp lsp then target := Some esp) es
                  | _ -> ()) scope_body;
              !target
            in
            let stmts = List.filter_map (fun (lsp, _, _) -> stmt_of lsp) group in
            if List.length stmts <> List.length group then []
            else begin
              (* Insert the shared record before the EARLIEST sharing closure —
                 after the captured locals are bound, in scope for all of them. *)
              let earliest =
                List.fold_left (fun best s ->
                    match best with
                    | Some b when (b.Ast.start_line, b.Ast.start_col) <= (s.Ast.start_line, s.Ast.start_col) -> best
                    | _ -> Some s) None stmts
              in
              match earliest with
              | None -> []
              | Some stmt_sp ->
                let indent = String.make stmt_sp.Ast.start_col ' ' in
                let record = "{ " ^ String.concat ", " (List.map (fun c -> c ^ " = " ^ c) caps) ^ " }" in
                let ins_pos = Position.create ~line:(stmt_sp.Ast.start_line - 1) ~character:0 in
                let insert_edit =
                  TextEdit.create ~range:(Range.create ~start:ins_pos ~end_:ins_pos)
                    ~newText:(Printf.sprintf "%slet captured = %s\n" indent record) in
                let body_edits =
                  List.map (fun (_, bsp, _) ->
                      let body_text = slice_span src bsp in
                      let rewritten =
                        substitute_idents body_text (List.map (fun c -> (c, "captured." ^ c)) caps) in
                      TextEdit.create ~range:(range_of_span bsp) ~newText:rewritten) group
                in
                [CodeAction.create
                   ~title:(Printf.sprintf
                             "Extract %d captured values into a shared record (%d closures)"
                             (List.length caps) (List.length group))
                   ~kind:CodeActionKind.RefactorRewrite
                   ~edit:(mk_we (insert_edit :: body_edits)) ()]
            end
          end
      end
    | _ -> []
  in

  introduce_pipe_actions @ remove_pipe_actions
  @ extract_var_actions @ inline_var_actions
  @ collapse_capture_actions @ expand_capture_actions
  @ hole_fill_actions @ auto_import_actions
  @ impl_scaffold_actions @ actor_boilerplate_actions
  @ session_scaffold_actions @ if_to_match_actions
  @ linear_audit_actions @ destruct_actions @ extract_fn_actions
  @ organize_imports_actions
  @ doc_comment_actions @ inline_fn_actions @ auto_alias_actions
  @ extract_captures_actions

(** Generate code actions relevant to the cursor position [line, character].
    Produces cursor- and diagnostic-driven quick fixes and refactorings;
    see [ast_code_actions] for the AST-driven refactorings (pipe, extract,
    inline, capture, holes, scaffolding). *)
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
    (* March match arms are `pattern -> body` with NO leading `|` (arms separate
       on newline). A leading `|` after the existing newline is a double
       separator → parse error. *)
    match List.assoc_opt case ms.ms_ctor_sigs with
    | None | Some [] ->
      Printf.sprintf "%s ->\n    ?\n" case
    | Some arg_tys ->
      let base_names = List.map name_from_ast_ty arg_tys in
      let names = dedup_names base_names in
      Printf.sprintf "%s(%s) ->\n    ?\n" case (String.concat ", " names)
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
  (* A rendered type is annotatable only if it has a valid surface form in
     annotation position. Named record types now recover their declared name in
     [Tc.pp_ty] and render as a bare identifier (e.g. `R`), which is a valid
     annotation — so those are allowed through. Only *anonymous*/unnameable
     structural records still print as `{ … }`, which March's parser rejects
     after `->` or `:`; refuse those so we never emit an annotation that would
     break the file. The `{` test distinguishes the two cases. *)
  let annotatable_ty_str s = not (String.contains s '{') in
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
           (* Anonymous record types render as `{ … }`, which March's parser
              does not accept in annotation position — skip rather than produce
              an edit that would break the file. *)
           if not (annotatable_ty_str ty_str) then None
           else
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
           if not (annotatable_ty_str ret_str) then None
           else
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
              (* March return type syntax is `: T` before `do` — NOT `-> T`
                 (`fn f() -> Int do` is a parse error). *)
              let edit  = TextEdit.create ~range
                            ~newText:(": " ^ ret_str ^ " ") in
              let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              Some (CodeAction.create ~title:"Add return type annotation"
                      ~kind:CodeActionKind.RefactorRewrite ~edit:we ())))

      | AnnFnParam ->
        (* Look up param type from type_map via param_name.span *)
        (match type_at_point site.as_rhs_span with
         | None -> None
         | Some ty ->
           let ty_str = Tc.pp_ty ty in
           if not (annotatable_ty_str ty_str) then None
           else
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
  (* ---- P3.8: Batch "Fix all" — prefix every unused binding in the file ---- *)
  let batch_fix_all_actions =
    let prefix_edits =
      List.filter_map (fun (diag : Lsp.Types.Diagnostic.t) ->
          match diag.code with
          | Some (`String "unused_binding") ->
            let pos = diag.range.Lsp.Types.Range.start in
            Some (TextEdit.create
                    ~range:(Range.create ~start:pos ~end_:pos) ~newText:"_")
          | _ -> None)
        a.diagnostics
    in
    if List.length prefix_edits < 2 then []
    else
      let uri = DocumentUri.of_path a.filename in
      [CodeAction.create
         ~title:(Printf.sprintf "Fix all: prefix %d unused bindings with `_`"
                   (List.length prefix_edits))
         ~kind:CodeActionKind.SourceFixAll
         ~edit:(WorkspaceEdit.create ~changes:[(uri, prefix_edits)] ()) ()]
  in
  (* ---- Close unclosed HTML tags in a ~H sigil ---- *)
  (* One action per sigil that has unclosed tags, offered when the cursor is on
     any of its unclosed-tag spans; inserts all closers (innermost-first) at the
     sigil's closing quote. *)
  let html_close_actions =
    let uri = DocumentUri.of_path a.filename in
    let groups = Hashtbl.create 4 in   (* insert_span → (closer, count, cursor_hit) *)
    List.iter (fun (hi : html_issue) ->
        let (closer, cnt, hit) =
          try Hashtbl.find groups hi.hi_insert_span
          with Not_found -> (hi.hi_closer, 0, false) in
        let hit = hit || Pos.span_contains hi.hi_open_span ~line ~character in
        Hashtbl.replace groups hi.hi_insert_span (closer, cnt + 1, hit))
      a.html_issues;
    Hashtbl.fold (fun (insert_span : Ast.span) (closer, cnt, hit) acc ->
        if not hit then acc
        else begin
          let pos = Position.create
              ~line:(insert_span.Ast.start_line - 1) ~character:insert_span.Ast.start_col in
          let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:closer in
          let title =
            if cnt = 1 then Printf.sprintf "Close unclosed tag (`%s`)" closer
            else Printf.sprintf "Close %d unclosed tags (`%s`)" cnt closer in
          CodeAction.create ~title ~kind:CodeActionKind.QuickFix
            ~edit:(WorkspaceEdit.create ~changes:[(uri, [edit])] ()) () :: acc
        end)
      groups []
  in
  make_linear_actions @ exhaustion_actions @ annotation_actions
  @ batch_annotation_action @ unused_binding_actions @ unused_import_actions
  @ wrap_inspect_actions @ remove_inspect_actions
  @ naming_actions @ demorgan_actions
  @ batch_fix_all_actions
  @ ast_code_actions a ~line ~character
  @ registry_actions
  @ html_close_actions

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
          (* Find the nearest '<' that starts an open (not close) tag. *)
          let i = ref (pn - 2) in
          (* skip back over any attribute text, respecting quotes *)
          while !i >= 0 && pre.[!i] <> '<' do decr i done;
          if !i < 0 then None
          else begin
            let lt = !i in
            (* Must be '<' followed by a letter — open tag, not '</' or '<!--' *)
            if lt + 1 >= pn then None
            else begin
              let first = pre.[lt + 1] in
              if not ((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z'))
              then None
              else begin
                (* Parse the tag name *)
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
