(** The type language, its printer and the message renderer.

    Interface for {!Typecheck_types}, added 2026-08-27 by the same pass that
    gave the four highest-churn compiler files one (see
    [specs/progress/2026-08-25-mli-interfaces-top-churn-files.md]).

    {2 This module is [include]d, so this interface is load-bearing at a
        distance}

    [Typecheck] does [include Typecheck_types], not [open], so every name
    declared here becomes part of [Typecheck]'s own surface and is reached by
    consumers through [let open Typecheck] and through the [Tc.] / [TC.] / [T.]
    aliases no grep can see.  Anything omitted here disappears from [Typecheck]
    too, which is why the curation is minimal: 23 values were exported before
    this file existed, 19 still are.

    Four are hidden, all of them local helpers with no reference anywhere
    outside this file:

    - [tvar_display_name] — feeds [pp_ty]'s [Unbound] case only;
    - [record_field_sig] and [recover_record_name] — the [_record_names]
      lookup path, used only by [pp_ty];
    - [free_vars_block] — the [Ast.EBlock] arm of the [free_vars_expr]
      recursion.  Its two siblings [free_vars_expr] and [free_vars_pattern]
      do have external callers and stay exported; splitting the family is
      slightly unpleasant but the block case genuinely has none.

    {2 The mutable cells stay exported on purpose}

    [_counter], [_tvar_names], [_tvar_ctr] and [_record_names] are all
    declared here even though only [_counter] and [_record_names] have
    external references (they are marshalled by [bin/main.ml] for the REPL
    cache).  [include] aliases these cells rather than copying them, and that
    aliasing is what keeps the marshalled state pointing at the cells the
    checker actually mutates.  Rather than split the group on a grep result,
    all four are declared; the two without callers are cheap insurance in a
    place where getting it wrong is silent.

    [Ast], [Err] and [StringSet] are re-exported because the [include] is what
    supplies those aliases to [Typecheck] and to everything reading its types. *)

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
val span_of_reason : reason -> Ast.span option
val string_of_reason : reason -> string
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
val fresh_id : unit -> int
val fresh_var : int -> ty
val repr : ty -> ty
val occurs : int -> int -> ty -> bool
val _tvar_names : (int, string) Hashtbl.t
val _tvar_ctr : int ref
val _record_names : (string, string option) Hashtbl.t
val register_record_name : name:string -> string list -> unit
val pp_ty : ?parens:bool -> ty -> string
val pp_ty_pretty : ?indent:int -> ?width:int -> ty -> string
val find_arg_mismatch :
  'a -> ty list -> ty list -> (int * 'a * ty * ty) option
val pp_session_ty : session_ty -> string
type message_part =
    MPText of string
  | MPCode of string
  | MPType of ty
  | MPBreak
  | MPBullet of message_part list
val render_parts : message_part list -> string
val span_of_expr : Ast.expr -> Ast.span
val free_vars_expr : string list -> Ast.expr -> string list
val free_vars_pattern : Ast.pattern -> string list
