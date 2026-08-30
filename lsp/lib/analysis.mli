(** Analysis of a single March buffer for the LSP server.

    [analyse] parses, desugars and typechecks a source string and returns a
    [t] holding everything the server's request handlers read: diagnostics,
    document symbols, completions, definitions, hover types, inlay hints,
    semantic tokens, folding ranges and the ~H sigil information.

    This interface is deliberately NARROWER than what [analysis.ml] defines:
    of the 167 values the implementation infers, 108 are internal to the pass
    and are hidden here.  What remains is what the server, the code-action
    engines and the tests actually call.

    The type declarations are exported in full — callers read [t]'s fields
    directly, so narrowing those would be a separate and much larger change.

    If something here really must become public, widen this file on purpose.
    The sibling modules ([Code_actions_ast], [Code_actions_diag],
    [Analysis_util], [Query], the server) consume [Analysis] through THIS
    signature, so a value they need must be listed. *)

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
val iter_expr : (Ast.expr -> unit) -> Ast.expr -> unit
val local_symbol_at : t -> line:int -> character:int -> int option
val references_at :
  t ->
  include_declaration:bool ->
  line:int -> character:int -> Lsp.Types.Location.t list
val rename_at :
  t ->
  line:int -> character:int -> new_name:string -> Lsp.Types.TextEdit.t list
type fix_gen = t -> Lsp.Types.Diagnostic.t -> Lsp.Types.CodeAction.t list
val fix_registry : (string, fix_gen) Hashtbl.t
val apply_fix_registry :
  t -> Lsp.Types.Diagnostic.t list -> Lsp.Types.CodeAction.t list
type scoped_syms = {
  ss_defs : (int, Ast.span) Hashtbl.t;
  ss_uses : (Ast.span, int) Hashtbl.t;
  ss_id_uses : (int, Ast.span list) Hashtbl.t;
  ss_name : (int, string) Hashtbl.t;
  ss_scope : (int, Ast.span) Hashtbl.t;
}
val build_linearity_map :
  Ast.decl list -> string list -> (string * Ast.linearity) list
type html_event =
    HEOpenTag of { tag : string; name_ofs : int; name_len : int;
      self_closing : bool; attrs : (string * int * int) list;
    }
  | HECloseTag of { tag : string; name_ofs : int; name_len : int; }
  | HEInterp of { brace_ofs : int; }
val ofs_to_pos : string -> int -> int * int
val pos_to_ofs : string -> int -> int -> int
type island_ref = {
  isl_name : string;
  isl_name_span : Ast.span;
  isl_has_props : bool;
}
val islands_in_sigil : src:string -> h_sigil -> island_ref list
type lens_command =
    RunShell of { description : string; shell : string; }
  | DebugEcho of { description : string; debug_command : string;
      dap : string; args : Yojson.Safe.t list;
    }
  | Unknown of string
val resolve_lens_command :
  command:string -> args:Yojson.Safe.t list -> lens_command
val analyse : filename:String.t -> src:string -> t
module Tir = March_tir.Tir
val run_tir_pass : t -> t
val type_at : t -> line:int -> character:int -> string option
val definition_at :
  t -> line:int -> character:int -> Lsp.Types.Location.t option
val prefix_at : t -> line:int -> character:int -> string
val auto_import_candidates :
  module_index:(string * string list) list ->
  imports:import_info list -> prefix:string -> (string * string) list
val compute_import_edit :
  imports:import_info list ->
  fallback_line:int ->
  module_:string -> name:string -> Lsp.Types.TextEdit.t option
val completions_at :
  t -> line:int -> character:int -> Lsp.Types.CompletionItem.t list
val inlay_hints_for :
  ?perf_annotations:bool ->
  ?param_names:bool -> t -> Lsp.Types.Range.t -> Lsp.Types.InlayHint.t list
val document_symbols :
  t -> [> `DocumentSymbol of Lsp.Types.DocumentSymbol.t list ]
val find_impls_of : t -> string -> string list
val doc_for : t -> string -> string option
val doc_name_at : t -> line:int -> character:int -> string option
val name_at : t -> line:int -> character:int -> string option
val implementation_at :
  t -> line:int -> character:int -> Lsp.Types.Location.t list
val type_definition_at :
  t -> line:int -> character:int -> Lsp.Types.Location.t option
val document_highlights_at :
  t -> line:int -> character:int -> Lsp.Types.DocumentHighlight.t list
val linked_editing_ranges_at :
  t -> line:int -> character:int -> Ast.span list
val prepare_rename_at :
  t -> line:int -> character:int -> Lsp.Types.Range.t option
val signature_help_at :
  t -> line:int -> character:int -> (string * string list * int) option
val code_actions_at :
  Analysis_util.t ->
  line:int ->
  character:int ->
  ?diagnostics:Analysis_util.Lsp.Types.Diagnostic.t list ->
  unit -> Analysis_util.Lsp.Types.CodeAction.t list
val actor_info_at : t -> line:int -> character:int -> string option
val perf_insight_at : t -> line:int -> character:int -> string option
val query_type_at : t -> line:int -> utf16_char:int -> string option
val query_doc_name_at : t -> line:int -> utf16_char:int -> string option
val query_perf_insight_at : t -> line:int -> utf16_char:int -> string option
val query_actor_info_at : t -> line:int -> utf16_char:int -> string option
val query_typestate_hover_at :
  t -> line:int -> utf16_char:int -> string option
val query_signature_help_at :
  t -> line:int -> utf16_char:int -> (string * string list * int) option
val query_completions_at :
  t -> line:int -> utf16_char:int -> Lsp.Types.CompletionItem.t list
val query_definition_at :
  t -> line:int -> utf16_char:int -> Pos.Lsp.Types.Location.t option
val query_references_at :
  t ->
  include_declaration:bool ->
  line:int -> utf16_char:int -> Pos.Lsp.Types.Location.t list
val query_rename_at :
  t ->
  line:int ->
  utf16_char:int -> new_name:string -> Pos.Lsp.Types.TextEdit.t list
val query_prepare_rename_at :
  t -> line:int -> utf16_char:int -> Pos.Lsp.Types.Range.t option
val query_implementation_at :
  t -> line:int -> utf16_char:int -> Pos.Lsp.Types.Location.t list
val query_type_definition_at :
  t -> line:int -> utf16_char:int -> Pos.Lsp.Types.Location.t option
val query_document_highlights_at :
  t -> line:int -> utf16_char:int -> Lsp.Types.DocumentHighlight.t list
val query_linked_editing_ranges_at :
  t -> line:int -> utf16_char:int -> Pos.Lsp.Types.Range.t list
val query_selection_range_at :
  t -> line:int -> utf16_char:int -> Pos.Lsp.Types.Range.t list
val query_inline_values :
  t ->
  range_start_line:int ->
  range_end_line:int ->
  stopped_line:int ->
  [> `InlineValueEvaluatableExpression of
       Lsp.Types.InlineValueEvaluatableExpression.t
   | `InlineValueText of Lsp.Types.InlineValueText.t
   | `InlineValueVariableLookup of Lsp.Types.InlineValueVariableLookup.t ]
  list
val query_prepare_call_hierarchy_at :
  t ->
  line:int ->
  utf16_char:int ->
  (string * Pos.Lsp.Types.Range.t * Pos.Lsp.Types.Range.t) option
val query_incoming_calls :
  t ->
  string ->
  ((string * Pos.Lsp.Types.Range.t * Pos.Lsp.Types.Range.t) *
   Pos.Lsp.Types.Range.t list)
  list
val query_outgoing_calls :
  t ->
  string ->
  ((string * Pos.Lsp.Types.Range.t * Pos.Lsp.Types.Range.t) *
   Pos.Lsp.Types.Range.t list)
  list
val query_import_text_edit :
  t -> module_:string -> name:string -> Pos.Lsp.Types.TextEdit.t option
val bundleable_fn_at : t -> line:int -> character:int -> string option
val project_diagnostics :
  (string * string) list -> (string * Lsp.Types.Diagnostic.t list) list
val autoclose_tag_at :
  t -> line:int -> character:int -> Lsp.Types.TextEdit.t option
val analyse_resilient : prev:t option -> filename:String.t -> src:string -> t
