(** The type environment: what is in scope, and how it is entered and left.

    Interface for {!Typecheck_env}, added 2026-08-27 by the same pass that gave
    the four highest-churn compiler files one (see
    [specs/progress/2026-08-25-mli-interfaces-top-churn-files.md]).

    {2 This module is [include]d, so this interface is load-bearing at a
        distance}

    [Typecheck] does [include Typecheck_env], not [open], which means every
    name declared here becomes part of [Typecheck]'s own surface and is reached
    by consumers through [let open Typecheck] and through the [Tc.] / [TC.] /
    [T.] aliases that no grep can see.  Anything omitted here disappears from
    [Typecheck] too.  So the curation below is deliberately minimal: of the 42
    values the module exported before this file existed, 40 are still exported.
    Only [edit_distance] and [suggest_module_name] are hidden — both are used
    solely by the [suggest_*] helpers in this file, and nothing anywhere else
    refers to either.

    That near-zero reduction is the correct answer, not a lazy one.  This band
    was lifted verbatim out of [Typecheck] as a coherent unit on 2026-08-26, so
    unlike the older files it never had time to accumulate accidental surface.

    The record types are all left manifest.  [env] in particular is threaded
    through the entire checker by field access; making it abstract would be a
    rewrite, not an interface.

    The mutable cells declared in the implementation stay single physical
    cells: [include] aliases them rather than copying them, and declaring them
    here does not change that. *)

type lin_entry = {
  le_name : string;
  le_lin : Typecheck_types.Ast.linearity;
  le_used : bool ref;
  le_first_use : Typecheck_types.Ast.span option ref;
}
type ctor_info = {
  ci_type : string;
  ci_params : string list;
  ci_arg_tys : Typecheck_types.Ast.ty list;
  ci_vis : Typecheck_types.Ast.visibility;
  ci_module : string;
  ci_is_actor_msg : bool;
}
type import_entry = {
  ie_span : Typecheck_types.Ast.span;
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
val import_index_add_prefix : import_index -> string -> import_entry -> unit
type proto_info = {
  pi_def : Typecheck_types.Ast.protocol_def;
  pi_projections : (string * Typecheck_types.session_ty) list;
  pi_span : Typecheck_types.Ast.span;
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
val qualify_ref_name : string -> string -> string
type env = {
  vars : Typecheck_types.scheme StrMap.t;
  types : int StrMap.t;
  ctors : ctor_info list StrMap.t;
  records :
    (string list * (string * Typecheck_types.Ast.ty) list)
    StrMap.t;
  level : int;
  lin : lin_entry list;
  errors : Typecheck_types.Err.ctx;
  pending_constraints : Typecheck_types.constraint_ list ref;
  type_map :
    (Typecheck_types.Ast.span,
     Typecheck_types.ty)
    Hashtbl.t;
  refs : ref_record list ref;
  current_decl : string ref;
  scheme_witnesses :
    (int list,
     Typecheck_types.constraint_ list *
     Typecheck_types.ty)
    Hashtbl.t;
  inst_witnesses :
    (Typecheck_types.Ast.span,
     int list * Typecheck_types.ty list)
    Hashtbl.t;
  interfaces : Typecheck_types.Ast.interface_def StrMap.t;
  sigs : (string * Typecheck_types.Ast.sig_def) list;
  mod_needs : string list;
  mod_need_scopes : (string * string option) list;
  module_caps : (string * string list) list;
  protocols : proto_info StrMap.t;
  impls :
    (Typecheck_types.ty *
     Typecheck_types.Ast.span * string option)
    list StrMap.t;
  import_tracker : import_entry list ref;
  import_idx : import_index;
  local_fns : unit StrMap.t;
  fn_arities : (int * Typecheck_types.Ast.span) StrMap.t;
  qual_fn_names : unit StrMap.t;
  plain_let_names : Typecheck_types.StringSet.t;
  proof_caps : (string * string) list;
  always_linear_types : string list;
  current_module : string;
  root_cap_allowed : bool;
  cur_fn_public : bool;
  cap_qual_prefix : string;
  enclosing_package : string;
  no_panic_mod : bool;
  no_panic_modules : string list;
  nonexhaustive_match_spans :
    Typecheck_types.Ast.span list ref;
  cap_producer_ivars :
    (int, Typecheck_types.Ast.span) Hashtbl.t;
  cap_narrow_factory_fns :
    (string, Typecheck_types.Ast.span) Hashtbl.t;
  cap_dicts : (string * string) list;
  cap_dict_decl_sites :
    (Typecheck_types.Ast.span * string * string) list ref;
  cap_impl_sites :
    (Typecheck_types.Ast.span *
     Typecheck_types.ty * Typecheck_types.ty * bool * string)
    list ref;
  cap_dict_sites : Typecheck_types.Ast.span list ref;
  mint_cap_sites :
    (Typecheck_types.Ast.span *
     Typecheck_types.ty * bool * string)
    list ref;
  cap_narrow_sites :
    (Typecheck_types.Ast.span *
     Typecheck_types.ty)
    list ref;
  json_cap_sites :
    (Typecheck_types.Ast.span *
     Typecheck_types.ty * string)
    list ref;
  pure_mod : bool;
  no_extern_mod : bool;
  deterministic_mod : bool;
  cap_closures : (string, string list) Hashtbl.t;
  own_cap_closures : (string, string list) Hashtbl.t;
  body_cap_closures : (string, string list) Hashtbl.t;
  stdlib_fns : (string, unit) Hashtbl.t;
  ceiling_extra_roots : (string, unit) Hashtbl.t;
  fn_refs : (string, string list) Hashtbl.t;
  fn_row_bodies :
    (string, (string list * Typecheck_types.Ast.expr) list)
    Hashtbl.t;
  fn_grant_points :
    (string, string list * Typecheck_types.Ast.span)
    Hashtbl.t;
  local_mods : string list StrMap.t;
  offer_conts :
    (Typecheck_types.session_ty ref *
     (string * Typecheck_types.session_ty) list)
    list ref;
  offer_labels :
    (string *
     (Typecheck_types.session_ty ref *
      (string * Typecheck_types.session_ty) list))
    list;
  offer_unrefined : Typecheck_types.session_ty ref list ref;
}
val make_env :
  Typecheck_types.Err.ctx ->
  (Typecheck_types.Ast.span,
   Typecheck_types.ty)
  Hashtbl.t -> env
val enter_level : env -> env
val leave_level : env -> env
val with_no_caller : env -> (unit -> 'a) -> 'a
val offer_ref_unrefined :
  env -> Typecheck_types.session_ty ref -> bool
val offer_catchall_depth : int ref
val offer_unrefined_message : string -> string
val demote_to_monomorphic : Typecheck_types.ty -> unit
val demote_vault_handle_vars : Typecheck_types.ty -> unit
val tag_cap_producer_result :
  env ->
  Typecheck_types.ty ->
  Typecheck_types.Ast.span -> unit
val ty_has_tagged_cap_producer :
  env -> Typecheck_types.ty -> bool
val test_build : bool ref

val lookup_var :
  StrMap.key -> env -> Typecheck_types.scheme option
val lookup_type : StrMap.key -> env -> int option
val cap_bare_name : string -> string
val resolve_cap_dict_type : env -> string -> string option
val resolves_always_linear : string -> env -> bool
val lookup_ctor : StrMap.key -> env -> ctor_info option
val lookup_ctor_same_module : string -> env -> ctor_info option
val lookup_ctor_in_type : StrMap.key -> string -> env -> ctor_info option
val lookup_ctor_in_type_unique :
  StrMap.key -> string -> env -> ctor_info option
val add_ctor :
  string -> ctor_info -> ctor_info list StrMap.t -> ctor_info list StrMap.t
val split_qualified : string -> (string * string) option
val inject_iface_exports_ref :
  (string -> March_modules.Module_registry.module_exports -> env -> env) ref
val load_module_into_env :
  string -> March_modules.Module_registry.module_exports -> env -> env
val resolve_qualified_var :
  string -> env -> env * Typecheck_types.scheme option
val resolve_qualified_type : string -> env -> env * int option
val resolve_qualified_ctor : string -> env -> env * ctor_info option
val suggest_var_in_scope : string -> env -> string option
val is_confirmed_private_qualified : string -> env -> bool
val qualified_error_msg : string -> env -> string
val all_ctors_named : string -> env -> string list
val all_ctor_candidates_named : string -> env -> (string * string) list
val suggest_ctors : string -> env -> (string * string) list
val bind_var :
  StrMap.key -> Typecheck_types.scheme -> env -> env
val bind_vars :
  (StrMap.key * Typecheck_types.scheme) list -> env -> env
val bind_linear :
  StrMap.key ->
  Typecheck_types.Ast.linearity ->
  Typecheck_types.ty -> env -> env
val generalize :
  int ->
  Typecheck_types.ty ->
  Typecheck_types.scheme
val instantiate :
  ?use_span:Typecheck_types.Ast.span ->
  int ->
  env ->
  Typecheck_types.scheme ->
  Typecheck_types.ty
