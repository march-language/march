(** Rc_types — TRANSITIONAL wrappers over [Kind].

    The two RC-relevance predicates, their four-constructor divergence, and
    the ~160 lines of fix history explaining every arm now live in
    [lib/tir/kind.ml] (see its "Reference counting" section).  These
    wrappers answer from the process-global table [Repr] holds until Phase 3
    of the type-kinds plan threads a [Kind.table] to every caller.  Do not
    add logic here. *)

(** True iff [ty] is a [Repr.Unboxed] aggregate: an inline struct value with
    no heap cell, no header and therefore no refcount. *)
let is_unboxed_aggregate : Tir.ty -> bool = function
  | Tir.TCon (name, _) -> Repr.unboxed_of_type_name name <> None
  | _ -> false

(** Perceus's predicate — see [Kind.needs_rc_of]. *)
let needs_rc (ty : Tir.ty) : bool = Kind.needs_rc_of (Repr.current_or_empty ()) ty

(** Borrow's predicate — see [Kind.borrowable_of]. *)
let borrow_eligible (ty : Tir.ty) : bool = Kind.borrowable_of (Repr.current_or_empty ()) ty
