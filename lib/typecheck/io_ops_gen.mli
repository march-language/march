(** Per-IO-capability dictionary shapes, derived from the compiler's builtin
    tables.  See the implementation header for why these are structural
    records rather than a generated stdlib module, and for the three language
    properties that force their shape. *)

open Typecheck_types

val march_ty : ?arg:bool -> Typecheck_types.ty -> string
(** Render a type as March SURFACE syntax. A multi-argument function is spelled
    curried ([A -> B -> C]); [(A, B) -> C] would be a function of one tuple.
    [~arg:true] parenthesises an arrow in argument position. *)

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

val dispatch_prefix : string
val dispatch_name : string -> string

val is_dispatch_name : string -> bool
(** True for a generated dispatch wrapper.  The capability-passing pass must
    skip these: a wrapper calls the operation it wraps, so rewriting that call
    would make it dispatch to itself forever. *)

val ops_empty_name : string -> string
(** Name of the generated all-[None] dictionary base for a capability. *)

val dispatch_wrappers_source : unit -> string
(** March source for the dispatch wrappers, injected into a `--test` build.
    Source rather than hand-built TIR so that it is typechecked: the shape
    leans on Option's niche encoding twice and a wrong decode would be a silent
    miscompile. *)

val render : unit -> string
(** Human-readable listing behind `march --emit-io-ops`. *)
