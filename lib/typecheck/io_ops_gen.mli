(** Per-IO-capability dictionary shapes, derived from the compiler's builtin
    tables.  See the implementation header for why these are structural
    records rather than a generated stdlib module, and for the three language
    properties that force their shape. *)

open Typecheck_types

val all_caps : unit -> string list
(** Every IO capability owning at least one builtin, sorted. *)

val ops_of_cap : string -> string list
(** Every builtin requiring this capability, sorted. *)

val dict_fields : string -> (string * ty) list
(** The capability's dictionary as sorted [(field, Option(op_ty))] pairs. *)

val shadowed_by_stdlib : string list
(** Builtins a stdlib March function shadows, so the builtin is dead and the
    table's type is not the operation a user's call resolves to.  Cross-checked
    against the stdlib sources by a test. *)

val excluded_ops : string -> string list
(** Operations of this capability that cannot be intercepted — polymorphic
    builtins (rank-2 types) and builtins shadowed by a stdlib March function
    (dead as builtins).  A mock silently does not cover these. *)

val dict_ty : string -> ty option
(** The dictionary record type, or [None] when nothing is interceptable. *)

val render : unit -> string
(** Human-readable listing behind `march --emit-io-ops`. *)
