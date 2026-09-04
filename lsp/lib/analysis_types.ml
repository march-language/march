(** Analysis result types for march-lsp.

    Extracted verbatim from [analysis.ml] so that the code-action engines
    ([Code_actions_ast], [Code_actions_diag]) can name {!t} and its
    companions without depending on [Analysis] itself, which would be a
    dependency cycle. [Analysis] re-exports everything here with
    [include Analysis_util], so [Analysis.t] and friends keep working
    unchanged for every consumer. *)

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

(** Per-parameter ownership at a callee, read off the compiler's own borrow
    inference ([March_tir.Borrow.infer_module]) rather than guessed from syntax.

    [cm_consumes] is positional: [true] means calling this function TAKES
    OWNERSHIP of that argument — the caller's reference is transferred and the
    value is gone after the call. [false] means the parameter is borrowed (read
    without taking ownership) or is not a heap value at all, for which ownership
    is meaningless.

    Both conditions matter. The borrow map initialises non-borrow-eligible
    parameters to "not borrowed", so an [Int] parameter is nominally owned;
    reporting that as "consumed" would bury the real signal under noise on every
    numeric argument. A parameter is recorded here as consuming only when it is
    both un-borrowed AND RC-tracked. *)
type consume_modes = {
  cm_fn_name : string;      (** callee name, as it appears in TIR *)
  cm_consumes : bool list;  (** positional: true = this call consumes the argument *)
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
  | AnnFnReturn  (** fn foo(x) do e end  →  fn foo(x) : T do e end.
                     Not `-> T`: that is a parse error in March, and this
                     comment described the arrow form for a while after the
                     emitter itself was corrected (see the `: ` edit below). *)
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
  | Parallelizable of { pi_op : string; pi_par : string; pi_name_span : Ast.span }
      (** A pure [List.map]/[List.filter] ([pi_op]) that could become its
          parallel form [pi_par] ([pmap]/[pfilter]). [pi_name_span] covers just
          the method-name token, for the "Convert to parallel" code action. *)

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
  consume_modes    : consume_modes list;
  (** Per-callee argument ownership from borrow inference — drives the
      "consumed" inlay hint. Populated by the TIR pass; empty until it runs. *)
  no_alloc_candidates : (string * Ast.span * Ast.span) list;
  (** Functions the @[no_alloc] checker verified allocation-free that are in
      the generation scope for the "Add `@[no_alloc]`" quick fix: (name, name
      span, declaration span).  Same predicate `forge fix --contracts` uses,
      so the editor offers the action exactly where forge would insert it. *)
  tir_fn_insights  : tir_fn_insight list;
  (** TIR-pipeline function-level insights: stack promotions, FBIP reuse, indirect calls. *)
  code_lens_items  : code_lens_item list;
  (** Code lens annotations for display above function definitions. *)
  decls            : Ast.decl list;
  (** Raw (pre-desugar) user declarations — retained for AST-driven code
      actions (pipe, extract/inline variable, capture, typed holes, actor
      and protocol scaffolding). *)
  depot_source_decls : Ast.decl list;
  (** [decls] plus resolved imported decls — the schema-extraction surface
      for the Depot pass. Empty when not a forge project / no imports. *)
  depot_schemas : Depot.schema list;
  (** All [Depot.Schema.define] schemas visible from this file. *)
  depot_col_occs : Depot.col_occ list;
  (** Every column-name string literal in a Query.where_*/order_* call,
      resolved to its schema table. *)
  depot_table_occs : Depot.table_occ list;
  (** Every table-name string literal in a Query.from_table/Migration.* call. *)
  protocols        : (string * Ast.protocol_def) list;
  (** Session-type protocol definitions: name → def (for scaffolding). *)
  transitions_index : (string * Ast.transition list) list;
  (** Always-linear handle name → declared transition arms (from [DTransitions]). *)
  always_linear_names : string list;
  (** Names declared with [always_linear type] (for hover enrichment). *)
  param_name_map   : (string, string list) Hashtbl.t;
  (** Precomputed function-name → ordered param-names table, built once from
      [decls] and reused on every inlay-hint request for parameter-name hints. *)
  proof_cap_defs   : (string, Ast.span) Hashtbl.t;
  (** Proof-capability name → span of its [proof cap Foo] declaration.
      Used by go-to-definition and find-references for Cap(X) type references. *)
}
