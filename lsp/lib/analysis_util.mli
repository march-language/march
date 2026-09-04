(** Shared AST/type helpers for march-lsp.

    Interface for {!Analysis_util}, added 2026-08-27 by the same pass that gave
    the compiler's highest-churn files one (see
    [specs/progress/2026-08-25-mli-interfaces-top-churn-files.md]).

    {2 This module sits in the middle of an [include] chain}

    [Analysis_util] does [include Analysis_types], and [Analysis] in turn does
    [include Analysis_util].  [Analysis] has no interface of its own, so
    everything declared here is re-exported all the way out to [Server],
    [Query_cli], [Depot] and the [lsp/test/] suites under the [Analysis.] name.
    Anything omitted here disappears from [Analysis] too — a breakage at two
    removes.  The curation is therefore minimal: 36 values were exported before
    this file existed, 33 still are.

    Three are hidden, all with no reference anywhere outside this file:

    - [march_operators] — the literal operator list behind
      [is_march_operator], which is the name consumers actually call;
    - [pat_bound_names] — the pattern-binder walk used by [iter_expr]'s block
      and match arms;
    - [span_byte_bounds] — the offset pair [slice_span] is built on.

    {2 The [Analysis_types] re-exports are manifest, not fresh declarations}

    Every [type foo = Analysis_types.foo = { ... }] below must keep its
    [Analysis_types.] equation.  Writing the record inline instead would
    declare a *new* nominal type, and [Code_actions_ast] / [Code_actions_diag]
    — which name [Analysis_types.t] directly to avoid a dependency cycle back
    through [Analysis] — would stop type-checking against it. *)

module Lsp = Linol_lsp.Lsp
module Ast = March_ast.Ast
module Tc = March_typecheck.Typecheck
module Err = March_errors.Errors
module Pos = Position
type call_site =
  Analysis_types.call_site = {
  cs_fn_name : string option;
  cs_span : Ast.span;
  cs_args : Ast.expr list;
}
type consume_modes =
  Analysis_types.consume_modes = {
  cm_fn_name : string;
  cm_consumes : bool list;
}
type import_sel =
  Analysis_types.import_sel =
    ISAll
  | ISNames of Ast.name list
  | ISExcept of string list
  | ISSingle
type import_info =
  Analysis_types.import_info = {
  ii_module : string;
  ii_sel : import_sel;
  ii_span : Ast.span;
}
type cg_node =
  Analysis_types.cg_node = {
  cg_name : string;
  cg_name_span : Ast.span;
  cg_full_span : Ast.span;
  cg_calls : (string * Ast.span) list;
}
type match_site =
  Analysis_types.match_site = {
  ms_span : Ast.span;
  ms_missing_cases : string list;
  ms_matched_type : string option;
  ms_ctor_sigs : (string * Ast.ty list) list;
}
type annotation_kind =
  Analysis_types.annotation_kind =
    AnnLet
  | AnnFnReturn
  | AnnFnParam
type annotation_site =
  Analysis_types.annotation_site = {
  as_name_span : Ast.span;
  as_rhs_span : Ast.span;
  as_kind : annotation_kind;
}
type html_issue =
  Analysis_types.html_issue = {
  hi_open_span : Ast.span;
  hi_tag : string;
  hi_insert_span : Ast.span;
  hi_closer : string;
}
type consumption =
  Analysis_types.consumption = {
  con_name : string;
  con_def : Ast.span;
  con_uses : Ast.span list;
}
type naming_violation =
  Analysis_types.naming_violation = {
  nv_name : string;
  nv_suggested : string;
  nv_span : Ast.span;
  nv_kind : [ `Function | `Type ];
}
type demorgan_site =
  Analysis_types.demorgan_site = {
  dm_span : Ast.span;
  dm_form : [ `NegatedBinop of string | `PairOfNegs of string ];
  dm_left_span : Ast.span;
  dm_right_span : Ast.span;
}
type perf_insight_kind =
  Analysis_types.perf_insight_kind =
    NonTailCall of { pi_fn_name : string; pi_blocking : string; }
  | ActorSendCopy of { pi_value_desc : string; pi_ty : string; }
  | ClosureCapture of { pi_count : int; pi_names : string list; }
  | StackPromoted of { pi_count : int; }
  | FbipReuse of { pi_count : int; }
  | TirIndirectCall of { pi_fn_name : string; pi_count : int; }
  | IndirectCall of { pi_callee : string; }
  | RecursiveAlloc of { pi_alloc : string; }
  | Parallelizable of { pi_op : string; pi_par : string;
      pi_name_span : Ast.span;
    }
type perf_insight =
  Analysis_types.perf_insight = {
  pi_span : Ast.span;
  pi_kind : perf_insight_kind;
  pi_message : string;
}
type tir_fn_insight =
  Analysis_types.tir_fn_insight = {
  tfi_fn_name : string;
  tfi_stack_allocs : int;
  tfi_reuse_ops : int;
  tfi_indirect_calls : int;
  tfi_heap_allocs : int;
}
type code_lens_item =
  Analysis_types.code_lens_item = {
  cl_range : Lsp.Types.Range.t;
  cl_title : string;
  cl_command : string option;
  cl_args : Yojson.Safe.t list;
}
type h_sigil =
  Analysis_types.h_sigil = {
  hs_content : string;
  hs_base_ofs : int;
  hs_close_ofs : int;
  hs_span : Ast.span;
}
type t =
  Analysis_types.t = {
  src : string;
  filename : string;
  doc : Utf16.doc;
  type_map : (Ast.span, Tc.ty) Hashtbl.t;
  def_map : (string, Ast.span) Hashtbl.t;
  use_map : (Ast.span, string) Hashtbl.t;
  vars : (string * Tc.scheme) list;
  types : (string * int) list;
  ctors : (string * string) list;
  interfaces : (string * Ast.interface_def) list;
  impls : (string * Tc.ty) list;
  impl_sites : (string, Ast.span list) Hashtbl.t;
  actors : (string * Ast.actor_def) list;
  doc_map : (string, string) Hashtbl.t;
  refs_map : (string, Ast.span list) Hashtbl.t;
  sym_defs : (int, Ast.span) Hashtbl.t;
  sym_uses : (Ast.span, int) Hashtbl.t;
  sym_id_uses : (int, Ast.span list) Hashtbl.t;
  sym_name : (int, string) Hashtbl.t;
  sym_scope : (int, Ast.span) Hashtbl.t;
  call_sites : call_site list;
  call_graph : cg_node list;
  imports : import_info list;
  module_index : (string * string list) list;
  consumption : consumption list;
  reuse_hints : Ast.span list;
  match_sites : match_site list;
  diagnostics : Lsp.Types.Diagnostic.t list;
  ctor_arities : (string * int) list;
  fold_ranges : (int * int * string) list;
  annotation_sites : annotation_site list;
  unused_fns : string list;
  html_issues : html_issue list;
  h_sigils : h_sigil list;
  type_matches : (string * match_site list) list;
  naming_violations : naming_violation list;
  demorgan_sites : demorgan_site list;
  perf_insights : perf_insight list;
  consume_modes : consume_modes list;
  no_alloc_candidates : (string * Ast.span * Ast.span * string) list;
  tir_fn_insights : tir_fn_insight list;
  code_lens_items : code_lens_item list;
  decls : Ast.decl list;
  depot_source_decls : Ast.decl list;
  depot_schemas : Depot.schema list;
  depot_col_occs : Depot.col_occ list;
  depot_table_occs : Depot.table_occ list;
  protocols : (string * Ast.protocol_def) list;
  transitions_index : (string * Ast.transition list) list;
  always_linear_names : string list;
  param_name_map : (string, string list) Hashtbl.t;
  proof_cap_defs : (string, Ast.span) Hashtbl.t;
}
val find_uses : string -> Ast.expr -> Ast.span list -> Ast.span list
val span_of_expr : Ast.expr -> Ast.span
val is_march_operator : string -> bool
val iter_expr : (Ast.expr -> unit) -> Ast.expr -> unit
val lambda_free_vars : Ast.param list -> Ast.expr -> string list
val collect_lambda_captures :
  (String.t -> bool) -> Ast.expr -> (Ast.span * Ast.span * string list) list
val perf_insight_to_diag : perf_insight -> Lsp.Types.Diagnostic.t
val clause_param_names : Ast.fn_clause -> string list
val contains_call : string -> Ast.expr -> bool
val unwrap_arrows : Tc.ty -> string list * string
val local_symbol_at : t -> line:int -> character:int -> int option
val span_in_user_file : t -> Ast.span -> bool
val locations_of_spans : t -> Ast.span list -> Lsp.Types.Location.t list
val symbol_spans_at :
  t -> line:int -> character:int -> (Ast.span option * Ast.span list) option
val references_at :
  t ->
  include_declaration:bool ->
  line:int -> character:int -> Lsp.Types.Location.t list
val rename_at :
  t ->
  line:int -> character:int -> new_name:string -> Lsp.Types.TextEdit.t list
val offset_of_pos : string -> int -> int -> int
val slice_span : string -> Ast.span -> string
val indent_of_line : string -> int -> string
val iter_decl_exprs : (Ast.expr -> unit) -> Ast.decl -> unit
val all_exprs : Ast.decl list -> Ast.expr list
val smallest_expr_at :
  t ->
  line:int -> character:int -> pred:(Ast.expr -> bool) -> Ast.expr option
val find_name_ofs : string -> string -> int -> int option
val find_end_before_span : string -> Ast.span -> int option
type fix_gen = t -> Lsp.Types.Diagnostic.t -> Lsp.Types.CodeAction.t list
val fix_registry : (string, fix_gen) Hashtbl.t
val apply_fix_registry :
  t -> Lsp.Types.Diagnostic.t list -> Lsp.Types.CodeAction.t list
val surface_ty : Ast.ty -> string
val split_arrow : Ast.ty -> Ast.ty list * Ast.ty
val scheme_ty : Tc.scheme -> Tc.ty
val ty_head_name : Tc.ty -> string option
val ty_arrow_arity : Tc.ty -> int
val is_ident_name : string -> bool
val substitute_idents : string -> (string * string) list -> string
