(** Perceus reference-count insertion over the typed IR.

    Interface for {!Perceus}, added 2026-08-27 by the pass that gave the
    highest-churn compiler files one (see
    [specs/progress/2026-08-25-mli-interfaces-top-churn-files.md]).  At 66
    commits in six months this is the most-edited file in [lib/tir/].

    36 values were exported before this file existed; 25 still are.  Unlike
    [Typecheck_env] and [Typecheck_types], [Perceus] is not [include]d by
    anything, so hiding here is a local, checkable change rather than one that
    acts at a distance.

    {2 What is hidden, and why it was safe}

    Eleven values, none of them referenced anywhere outside this file:

    - the whole RC-statistics family — [rc_counts] and its type,
      [zero_counts], [add_counts], [count_rc_ops_expr], [count_rc_ops_module],
      [print_perceus_stats], and the [_perceus_debug] lazy flag that gates
      them.  These exist to serve one [if Lazy.force _perceus_debug] block at
      the end of {!perceus}; the type went with them because nothing outside
      names it either;
    - [fresh_rc_var] — the RC temporary generator.  Note that its counter
      [_rc_fresh_ctr] stays exported: [lower_state.ml] resets it and
      [test_snapshots.ml] needs that reset to keep TIR golden snapshots
      deterministic across run order.  The counter is API, the generator is
      not;
    - [collect_moved_vars] and [collect_actor_sent_vars] — per-function
      analyses whose results are stashed in {!env} by [preprocess_fn];
    - [wrap_incrcs] and [rename_borrowed_shadows] — internal steps of the
      per-function RC walk.

    {2 What stays, and why the list is still long}

    The Perceus pass is split across five sibling files
    ([perceus_liveness], [perceus_elide], [perceus_fbip], [perceus_scrut] and
    [borrow]) that call back into this one, and several helpers
    ([same_arity], [needs_rc], [is_apply_fn], [name_free_in]) are used far
    outside [lib/tir/] — [needs_rc] reaches [lsp/lib/analysis.ml], and
    [perceus] itself has 32 referencing files.  Everything with a caller was
    kept; nothing was hidden by editing a consumer.

    [env] and [live_set] are left manifest because exposed functions
    ([empty_env], [find_inc_vars], [insert_rc_expr], [elide_expr],
    [live_before]) name them in their own types. *)

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
module StringMap :
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
val _rc_fresh_ctr : int ref
type env = {
  borrow_map : Borrow.borrow_map;
  type_defs : Tir.type_def list;
  collision_set : (string, string list) Hashtbl.t;
  extern_names : StringSet.t;
  current_fn_name : string;
  closure_fvs : StringSet.t;
  actor_sent : StringSet.t;
  moved_vars : StringSet.t;
  borrowed_field_vars : StringSet.t;
  var_ctx : Tir.var StringMap.t;
}
val empty_env : env
val scrutinee_shares_payload_storage : env -> Tir.ty -> bool
val collect_closure_fvs : Tir.fn_def -> StringSet.t
val incrc_for :
  env -> Tir.var -> Tir.atom -> Tir.expr
val decrc_for :
  env -> Tir.var -> Tir.atom -> Tir.expr
val needs_rc : Tir.ty -> bool
val is_apply_fn : string -> bool
val vars_of_atom :
  Tir.atom -> Perceus_liveness.StringSet.t
val vars_of_atoms :
  Tir.atom list -> Perceus_liveness.StringSet.t
val fbip_arity_marker : string
val same_arity : Tir.ty -> int -> bool
type live_set = Perceus_liveness.live_set
val live_before :
  Tir.expr ->
  Perceus_liveness.live_set -> Perceus_liveness.live_set
val name_free_in : string -> Tir.expr -> bool
val find_inc_vars :
  ?include_borrowed_fields:bool ->
  env -> Tir.atom list -> live_set -> Tir.var list
val insert_rc_expr :
  env -> Tir.expr -> live_set -> Tir.expr * StringSet.t
val dup_field_results : Tir.expr -> Tir.expr
val insert_apply_fn_clo_drop :
  repl:bool -> Tir.expr -> Tir.expr
val insert_rc :
  module_env:env ->
  ?repl:bool ->
  ?borrowed:StringSet.t -> Tir.fn_def -> Tir.fn_def
val elide_expr : Tir.expr -> Tir.expr
val elide_cancel_pairs : Tir.fn_def -> Tir.fn_def
val fbip_expr : Tir.expr -> Tir.expr
val insert_fbip : Tir.fn_def -> Tir.fn_def
val preprocess_fn : Tir.fn_def -> Tir.fn_def
val perceus :
  ?repl:bool ->
  ?repl_vars:string list ->
  ?borrow_map:Borrow.borrow_map ->
  Tir.tir_module -> Tir.tir_module
