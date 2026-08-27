(** Monomorphization of the typed IR: specialize generic functions per
    instantiated type, and mangle the specialized names.

    Interface for {!Mono}, added 2026-08-27 by the pass that gave the
    highest-churn compiler files one (see
    [specs/progress/2026-08-25-mli-interfaces-top-churn-files.md]).

    21 values were exported before this file existed; 14 still are.  [Mono] is
    not [include]d by anything, so hiding here is local and checkable.

    {2 What is hidden}

    Seven values, none referenced outside this file:

    - [build_subst], [default_residual_in_subst], [retype_known_vars],
      [find_first_call] and [ensure_atom_fns] — worklist machinery internal to
      {!monomorphize};
    - [subst_branch] and [subst_fn_def] — two members of the [subst_*]
      recursion with no external caller.  Their siblings [subst_ty],
      [subst_var], [subst_atom] and [subst_expr] all have one ([inline.ml],
      [cprop.ml], [repl_jit.ml]) and stay exported.

    [ensure_atom_fns] is worth calling out: its inferred type is
    [(string, 'a) Hashtbl.t -> (string, 'b) Hashtbl.t -> (string * 'a * 'c list)
    Queue.t -> ...], three unconstrained variables over the caller's private
    worklist tables.  That is not a signature anyone should be writing against,
    and hiding it removes the question rather than answering it.

    {2 What stays}

    [monomorphize] has 14 referencing files, and the [mangle_*] pair is the
    naming contract [tir_names.ml] and the codegen tests depend on.  [ty_subst]
    stays a manifest type alias because six exported functions name it. *)

val resolve_impl_by_type : (string * string) list -> string -> string option
val has_tvar : Tir.ty -> bool
type ty_subst = (string * Tir.ty) list
val subst_ty : ty_subst -> Tir.ty -> Tir.ty
val default_residual_tvars : Tir.ty -> Tir.ty
val subst_var : ty_subst -> Tir.var -> Tir.var
val subst_atom : ty_subst -> Tir.atom -> Tir.atom
val subst_expr : ty_subst -> Tir.expr -> Tir.expr
val mangle_ty : Tir.ty -> string
val mangle_name : string -> Tir.ty list -> string
val match_ty : Tir.ty -> Tir.ty -> ty_subst -> ty_subst
module SSet :
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
val atom_ty : Tir.atom -> Tir.ty
val rewrite_calls :
  (string, Tir.fn_def) Hashtbl.t ->
  (string, unit) Hashtbl.t ->
  (string * Tir.fn_def * ty_subst) Queue.t ->
  (string, (string * string) list) Hashtbl.t ->
  (string, string) Hashtbl.t ->
  SSet.t -> Tir.expr -> Tir.expr
val refine_field_types : Tir.expr -> Tir.expr
val monomorphize :
  ?iface_methods:(string, (string * string) list) Hashtbl.t ->
  Tir.tir_module -> Tir.tir_module
