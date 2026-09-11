(** Kind — the per-type table.

    One record per MONOMORPHIC type answering every "what can a value of this
    type do?" question the backend asks: how it is laid out, how it is
    represented, whether Perceus counts it, whether Borrow may borrow it,
    whether it can sit in a niche slot, and what it (deeply) contains.

    A [table] is a VALUE built once per module from the module's type
    definitions and threaded explicitly.  It replaces the per-call-site
    predicates that used to live in [Rc_types] and [Repr] and the
    process-global unboxed registry [Repr] carried between the Milestone-3
    unboxing work and this module's introduction.

    Design: specs/2026-09-10-type-kinds-design.md. *)

(** Runtime representation of a [TCon] — moved here from [Repr] verbatim.
    [Repr.repr] is a type-equal re-export so [Repr.Boxed] &c. keep compiling. *)
type repr =
  | Boxed                                           (* heap cell with RC header + tag *)
  | Newtype of Tir.ty                               (* represented as raw payload *)
  | Niche   of { payload : Tir.ty; tagged : bool } (* None=0, Some(x)=x *)
  | Unboxed of { ctor : string; fields : Tir.ty list }
    (* inline LLVM struct value; no cell, no RC *)

(** Where a value of the type lives.  Informational in this version: no pass
    reads it.  It must simply be total over [Tir.ty]. *)
type layout =
  | Imm              (** i64 register: Int, Bool, Unit, Atom *)
  | Flt              (** double register; boxed at an erased slot *)
  | Vec of int       (** SIMD vector; the int is the runtime kind tag *)
  | Agg of string    (** inline LLVM struct value; the ["%ub.T"] name *)
  | Heap             (** RC'd pointer: String, TPtr, boxed TCon, closure *)
  | Cell             (** tuple / record: heap cell, RC reconciled per field *)
  | Erased           (** TVar: uniform slot, conservatively heap *)

type kind = {
  layout       : layout;
  repr         : repr;         (** [Boxed] for every non-[TCon] *)
  llvm_ty      : string;       (** the one LLVM spelling; was [Llvm_ctx.llvm_ty] *)
  needs_rc     : bool;         (** Perceus's question — was [Rc_types.needs_rc] *)
  borrowable   : bool;         (** Borrow's question — was [Rc_types.borrow_eligible];
                                   deliberately differs from [needs_rc] on four
                                   constructors, see the module doc in kind.ml *)
  niche_ok     : bool;         (** never raw 0, so usable as a niche payload *)
  needs_tag    : bool;         (** scalar that must be [(v<<1)|1] in a ptr slot *)
  closure_free : bool;         (** DEEP: no [TFn] reachable through fields *)
  float_free   : bool;         (** DEEP: no [TFloat] reachable through fields *)
}

type table

(** Build the table for a module.  [unboxing:false] classifies every type
    Boxed (what the REPL/JIT need, and what [MARCH_NO_UNBOX] selects).
    [externs] excludes types crossing an extern signature from unboxing. *)
val build :
  ?externs:Tir.extern_decl list ->
  ?unboxing:bool ->
  collision_set:(string, string list) Hashtbl.t ->
  Tir.type_def list -> table

(** Same unboxed decision, new [type_defs], fresh memo.  The pipeline decides
    the unboxed set once (after Defun) and later passes may still ADD type
    definitions; rebinding keeps the emitter on the passes' answer while
    letting shape lookups see the final list. *)
val rebind :
  ?collision_set:(string, string list) Hashtbl.t ->
  table -> Tir.type_def list -> table

(** No type definitions, nothing unboxed. *)
val empty : table

val type_defs : table -> Tir.type_def list
val collision_set : table -> (string, string list) Hashtbl.t

(** The kind of a monomorphic type.  Memoised per table. *)
val of_ty : table -> Tir.ty -> kind

(* ── The individual classifiers behind [of_ty] ───────────────────────────
   Exposed so the transitional wrappers in [Repr] / [Rc_types] can answer
   one question without computing the whole record.  Each is the verbatim
   port of the function it replaces; [of_ty] is defined in terms of them. *)

val repr_of : table -> Tir.ty -> repr
val niche_payload_ok : table -> Tir.ty -> bool
val payload_needs_tag : table -> Tir.ty -> bool
val needs_rc_of : table -> Tir.ty -> bool
val borrowable_of : table -> Tir.ty -> bool
val llvm_ty_of : table -> Tir.ty -> string

(* ── Shape helpers, unchanged in meaning from [Repr] ─────────────────── *)

val find_variant : table -> string -> (string * Tir.ty list) list option
val is_actor_struct_type : table -> string -> bool
val is_niche_shaped : table -> string -> bool
val niche_repr_of_concrete : table -> string -> repr option

(* ── Unboxed-aggregate registry queries, unchanged in meaning ───────── *)

val unboxed_of_type_name : table -> string -> (string * Tir.ty list) option
val unboxed_of_llvm_ty : table -> string -> (string * string * Tir.ty list) option
val unboxed_types : table -> (string * string * Tir.ty list) list
val unboxed_llvm_name : string -> string
val is_scalar_field : Tir.ty -> bool
val max_unboxed_arity : int
