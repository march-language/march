(** Bidirectional Hindley-Milner type inference, plus the checks layered on
    top of it: linearity, exhaustiveness, capabilities and effect ceilings,
    session-type projection, panic/pure/deterministic surfaces, and tail-call
    enforcement.

    The type language ([ty], [scheme], [env] and friends) is the module's real
    contract — TIR lowering, the LSP, the REPL and the search index all read
    it — so it stays fully visible here, along with the [check_module*] family
    the drivers call and the pretty-printers everything shares.

    Inference itself is deliberately closed. [unify], [instantiate_ctor],
    [infer_pattern], [check_exhaustiveness], the capability walkers and the
    several hundred helpers behind them are not exported: they are mutually
    recursive, they read and write module-level state, and calling one from
    outside a [check_module] run would see that state half-built. Reach for
    [check_module_with_env] or one of its siblings instead, and if something
    here really must become public, widen this file on purpose.

    Since Phase 6 of the file decomposition (2026-08-26) and Target B of its
    follow-up (2026-08-27) much of what this interface fronts is no longer
    defined in [typecheck.ml]: the type language and the AST walkers are
    [Typecheck_types], the environment is [Typecheck_env], the builtin tables
    are [Typecheck_builtins], exhaustiveness is [Typecheck_exhaustive], the
    capability / [needs] checker is [Typecheck_caps], tail-call enforcement is
    [Typecheck_tailcall], unification and surface-type conversion are
    [Typecheck_unify], session-type projection is [Typecheck_session],
    declaration dependency ordering is [Typecheck_reorder], and the
    module-level [cap] checkers with their panic-surface tables are
    [Typecheck_modcaps].
    Each is [include]d back into [Typecheck] at the position its band used to
    occupy, so THIS file remains the single contract and nothing below moved,
    was renamed or changed meaning — including the mutable cells
    ([_counter], [_record_names], [stdlib_source_files], [cap_strict_ceiling]),
    which [include] aliases rather than copies. When you need a name that is
    not here, widen this file rather than reaching for the sibling module
    directly. *)

module Ast = March_ast.Ast
module Err = March_errors.Errors
module StringSet :
  sig
    type elt = String.t
    type t = Set.Make(String).t
    val empty : t
    val add : elt -> t -> t
    val singleton : elt -> t
    val remove : elt -> t -> t
    val union : t -> t -> t
    val inter : t -> t -> t
    val disjoint : t -> t -> bool
    val diff : t -> t -> t
    val cardinal : t -> int
    val elements : t -> elt list
    val min_elt : t -> elt
    val min_elt_opt : t -> elt option
    val max_elt : t -> elt
    val max_elt_opt : t -> elt option
    val choose : t -> elt
    val choose_opt : t -> elt option
    val find : elt -> t -> elt
    val find_opt : elt -> t -> elt option
    val find_first : (elt -> bool) -> t -> elt
    val find_first_opt : (elt -> bool) -> t -> elt option
    val find_last : (elt -> bool) -> t -> elt
    val find_last_opt : (elt -> bool) -> t -> elt option
    val iter : (elt -> unit) -> t -> unit
    val fold : (elt -> 'acc -> 'acc) -> t -> 'acc -> 'acc
    val map : (elt -> elt) -> t -> t
    val filter : (elt -> bool) -> t -> t
    val filter_map : (elt -> elt option) -> t -> t
    val partition : (elt -> bool) -> t -> t * t
    val split : elt -> t -> t * bool * t
    val is_empty : t -> bool
    val mem : elt -> t -> bool
    val equal : t -> t -> bool
    val compare : t -> t -> int
    val subset : t -> t -> bool
    val for_all : (elt -> bool) -> t -> bool
    val exists : (elt -> bool) -> t -> bool
    val to_list : t -> elt list
    val of_list : elt list -> t
    val to_seq_from : elt -> t -> elt Seq.t
    val to_seq : t -> elt Seq.t
    val to_rev_seq : t -> elt Seq.t
    val add_seq : elt Seq.t -> t -> t
    val of_seq : elt Seq.t -> t
  end
type reason =
    RAnnotation of Ast.span
  | RFnReturn of string * Ast.span
  | RFnArg of Ast.span * int
  | RMatchArm of Ast.span
  | RLetBind of Ast.span
  | RBuiltin of string
  | RBecause of reason * string
type ty =
    TCon of string * ty list
  | TVar of tvar ref
  | TArrow of ty * ty
  | TTuple of ty list
  | TRecord of (string * ty) list
  | TLin of Ast.linearity * ty
  | TNat of int
  | TNatOp of Ast.nat_op * ty * ty
  | TChan of session_ty ref
  | TError
  | TRefine of ty * string * Ast.expr
and session_ty =
    SSend of ty * session_ty
  | SRecv of ty * session_ty
  | SChoose of (string * session_ty) list
  | SOffer of (string * session_ty) list
  | SEnd
  | SRec of string * session_ty
  | SVar of string
  | SError
  | SMSend of string * ty * session_ty
  | SMRecv of string * ty * session_ty
and tvar = Unbound of int * int | Link of ty
type constraint_ =
    CNum of ty
  | COrd of ty
  | CInterface of string * ty
  | CADTBound of string * ty
  | CTNatBound of ty
type scheme = Mono of ty | Poly of int list * constraint_ list * ty
val _counter : int ref
val fresh_var : int -> ty
val repr : ty -> ty
val _record_names : (string, string option) Hashtbl.t
val pp_ty : ?parens:bool -> ty -> string
val pp_ty_pretty : ?indent:int -> ?width:int -> ty -> string
val pp_session_ty : session_ty -> string
type message_part =
    MPText of string
  | MPCode of string
  | MPType of ty
  | MPBreak
  | MPBullet of message_part list
type lin_entry = {
  le_name : string;
  le_lin : Ast.linearity;
  le_used : bool ref;
  le_first_use : Ast.span option ref;
}
type ctor_info = {
  ci_type : string;
  ci_params : string list;
  ci_arg_tys : Ast.ty list;
  ci_vis : Ast.visibility;
  ci_module : string;
  ci_is_actor_msg : bool;
}
type import_entry = {
  ie_span : Ast.span;
  ie_desc : string;
  ie_matches : string -> bool;
  ie_used : bool ref;
  ie_used_names : (string, unit) Hashtbl.t;
}
type import_index = {
  ie_exact_index : (string, import_entry list) Hashtbl.t;
  ie_prefix_index : (string, import_entry list) Hashtbl.t;
}
val make_import_index : unit -> import_index
val import_index_add_exact : import_index -> string -> import_entry -> unit
type proto_info = {
  pi_def : Ast.protocol_def;
  pi_projections : (string * session_ty) list;
  pi_span : Ast.span;
}
module StrMap :
  sig
    type key = String.t
    type 'a t = 'a Map.Make(String).t
    val empty : 'a t
    val add : key -> 'a -> 'a t -> 'a t
    val add_to_list : key -> 'a -> 'a list t -> 'a list t
    val update : key -> ('a option -> 'a option) -> 'a t -> 'a t
    val singleton : key -> 'a -> 'a t
    val remove : key -> 'a t -> 'a t
    val merge :
      (key -> 'a option -> 'b option -> 'c option) -> 'a t -> 'b t -> 'c t
    val union : (key -> 'a -> 'a -> 'a option) -> 'a t -> 'a t -> 'a t
    val cardinal : 'a t -> int
    val bindings : 'a t -> (key * 'a) list
    val min_binding : 'a t -> key * 'a
    val min_binding_opt : 'a t -> (key * 'a) option
    val max_binding : 'a t -> key * 'a
    val max_binding_opt : 'a t -> (key * 'a) option
    val choose : 'a t -> key * 'a
    val choose_opt : 'a t -> (key * 'a) option
    val find : key -> 'a t -> 'a
    val find_opt : key -> 'a t -> 'a option
    val find_first : (key -> bool) -> 'a t -> key * 'a
    val find_first_opt : (key -> bool) -> 'a t -> (key * 'a) option
    val find_last : (key -> bool) -> 'a t -> key * 'a
    val find_last_opt : (key -> bool) -> 'a t -> (key * 'a) option
    val iter : (key -> 'a -> unit) -> 'a t -> unit
    val fold : (key -> 'a -> 'acc -> 'acc) -> 'a t -> 'acc -> 'acc
    val map : ('a -> 'b) -> 'a t -> 'b t
    val mapi : (key -> 'a -> 'b) -> 'a t -> 'b t
    val filter : (key -> 'a -> bool) -> 'a t -> 'a t
    val filter_map : (key -> 'a -> 'b option) -> 'a t -> 'b t
    val partition : (key -> 'a -> bool) -> 'a t -> 'a t * 'a t
    val split : key -> 'a t -> 'a t * 'a option * 'a t
    val is_empty : 'a t -> bool
    val mem : key -> 'a t -> bool
    val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool
    val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int
    val for_all : (key -> 'a -> bool) -> 'a t -> bool
    val exists : (key -> 'a -> bool) -> 'a t -> bool
    val to_list : 'a t -> (key * 'a) list
    val of_list : (key * 'a) list -> 'a t
    val to_seq : 'a t -> (key * 'a) Seq.t
    val to_rev_seq : 'a t -> (key * 'a) Seq.t
    val to_seq_from : key -> 'a t -> (key * 'a) Seq.t
    val add_seq : (key * 'a) Seq.t -> 'a t -> 'a t
    val of_seq : (key * 'a) Seq.t -> 'a t
  end
type ref_record = {
  callee : string;
  caller : string;
  ref_kind : [ `Call | `Ctor | `TypeRef ];
  ref_file : string;
  ref_line : int;
}
type env = {
  vars : scheme StrMap.t;
  types : int StrMap.t;
  ctors : ctor_info list StrMap.t;
  records : (string list * (string * Ast.ty) list) StrMap.t;
  level : int;
  lin : lin_entry list;
  errors : Err.ctx;
  pending_constraints : constraint_ list ref;
  type_map : (Ast.span, ty) Hashtbl.t;
  refs : ref_record list ref;
  current_decl : string ref;
  scheme_witnesses : (int list, constraint_ list * ty) Hashtbl.t;
  inst_witnesses : (Ast.span, int list * ty list) Hashtbl.t;
  interfaces : Ast.interface_def StrMap.t;
  sigs : (string * Ast.sig_def) list;
  mod_needs : string list;
  mod_need_scopes : (string * string option) list;
  module_caps : (string * string list) list;
  protocols : proto_info StrMap.t;
  impls : (ty * Ast.span * string option) list StrMap.t;
  import_tracker : import_entry list ref;
  import_idx : import_index;
  local_fns : unit StrMap.t;
  fn_arities : (int * Ast.span) StrMap.t;
  qual_fn_names : unit StrMap.t;
  plain_let_names : StringSet.t;
  proof_caps : (string * string) list;
  always_linear_types : string list;
  current_module : string;
  root_cap_allowed : bool;
  cur_fn_public : bool;
  cap_qual_prefix : string;
  enclosing_package : string;
  no_panic_mod : bool;
  no_panic_modules : string list;
  nonexhaustive_match_spans : Ast.span list ref;
  cap_producer_ivars : (int, Ast.span) Hashtbl.t;
  cap_narrow_factory_fns : (string, Ast.span) Hashtbl.t;
  mint_cap_sites : (Ast.span * ty * bool * string) list ref;
  cap_narrow_sites : (Ast.span * ty) list ref;
  json_cap_sites : (Ast.span * ty * string) list ref;
  pure_mod : bool;
  no_extern_mod : bool;
  deterministic_mod : bool;
  cap_closures : (string, string list) Hashtbl.t;
  own_cap_closures : (string, string list) Hashtbl.t;
  body_cap_closures : (string, string list) Hashtbl.t;
  stdlib_fns : (string, unit) Hashtbl.t;
  ceiling_extra_roots : (string, unit) Hashtbl.t;
  fn_refs : (string, string list) Hashtbl.t;
  fn_row_bodies : (string, (string list * Ast.expr) list) Hashtbl.t;
  fn_grant_points : (string, string list * Ast.span) Hashtbl.t;
  local_mods : string list StrMap.t;
  offer_conts : (session_ty ref * (string * session_ty) list) list ref;
  offer_labels :
    (string * (session_ty ref * (string * session_ty) list)) list;
  offer_unrefined : session_ty ref list ref;
}
val make_env : Err.ctx -> (Ast.span, ty) Hashtbl.t -> env
val lookup_ctor : StrMap.key -> env -> ctor_info option
val add_ctor :
  string -> ctor_info -> ctor_info list StrMap.t -> ctor_info list StrMap.t
val instantiate : ?use_span:Ast.span -> int -> env -> scheme -> ty
val stdlib_source_files : string list ref
val cap_strict_ceiling : bool ref
val builtin_cap_table : (string * string) list
val locally_declared_names_of : Ast.decl list -> (string, unit) Hashtbl.t
val builtin_interface_bindings : (string * scheme) list
val prelude_collision_builtin_names : string list
val prelude_collision_iface_arities : (string * int) list
val base_env : Err.ctx -> (Ast.span, ty) Hashtbl.t -> env
val session_ty_equal : session_ty -> session_ty -> bool
val normalize_tnat : ty -> ty
val record_use : string -> March_ast.Ast.span -> env -> unit
val bind_vars_with_linearity : (string * scheme) list -> env -> env
val span_of_expr : Ast.expr -> Ast.span
type spat =
    SPWild
  | SPCon of string * spat list
  | SPLit of Ast.literal
  | SPTup of spat list
  | SPRec of (string * spat) list
val unfold_srec : session_ty -> session_ty
val infer_expr : env -> Ast.expr -> ty
val fn_transitive_capability_closures_tbl :
  env -> (string, string list) Hashtbl.t
val check_module_needs :
  env -> Ast.name -> cap_qname_prefix:string -> Ast.decl list -> unit
val fn_capability_closures : env -> (string * string list) list
val declared_cap_scopes : env -> (string * string option) list
val fn_own_capability_closures : env -> (string * string list) list
val fn_transitive_capability_closures : env -> (string * string list) list
val subst_svar : string -> session_ty -> session_ty -> session_ty
val dual_session_ty : session_ty -> session_ty
val panic_surface_contracted : StringSet.t
val proof_based_panic_surface : bool ref
val panic_surface_suggestion : string -> string
val check_no_panic_module : Err.ctx -> env -> Ast.decl list -> unit
val check_decl : env -> Ast.decl -> env
val render_cap_chain : string list -> string
val check_module_core :
  ?errors:Err.ctx ->
  ?seed_env:env -> Ast.module_ -> Err.ctx * (Ast.span, ty) Hashtbl.t * env
val check_module :
  ?errors:Err.ctx -> Ast.module_ -> Err.ctx * (Ast.span, ty) Hashtbl.t
val check_module_with_refs :
  ?errors:Err.ctx ->
  Ast.module_ -> Err.ctx * (Ast.span, ty) Hashtbl.t * ref_record list
val check_module_with_env :
  env -> Ast.module_ -> Err.ctx * (Ast.span, ty) Hashtbl.t
val check_module_with_env_full :
  env -> Ast.module_ -> Err.ctx * (Ast.span, ty) Hashtbl.t * env
val check_module_full :
  ?errors:Err.ctx ->
  ?seed_env:env -> Ast.module_ -> Err.ctx * (Ast.span, ty) Hashtbl.t * env
val check_letq_repl : env -> Ast.pattern -> Ast.expr -> env
val check_letstar_repl : env -> Ast.pattern -> Ast.expr -> env

