(** Compiler-inserted capability passing.  See the implementation header for
    why this lives in TIR rather than the AST, and what the threading is for.

    This is the ANALYSIS half: it answers "which functions must carry which
    capability", from the TIR call graph.  Nothing rewrites yet. *)

val cap_of_interceptable_op : string -> string option
(** The capability whose dictionary has a field for this builtin, if any.  Not
    every cap-requiring builtin qualifies: one that is polymorphic, or shadowed
    by a stdlib March function, has no dictionary field and can never be
    intercepted. *)

val cap_param_name : string -> string
(** The implicit parameter name carrying a capability. *)

val cap_ty : string -> Tir.ty
val cap_var : string -> Tir.var

val ambient_atom : string -> Tir.atom
(** A capability carrying no dictionary — what every capability is unless
    something attached one.  Both backends special-case [root_cap] to the
    sentinel. *)

val needed_caps : Tir.tir_module -> (string, string list) Hashtbl.t
(** Each function that must carry capabilities, mapped to them (sorted).
    Functions whose arity cannot safely change are excluded. *)

val actor_of_spawn : string -> string option
(** The actor name when the argument is an actor's spawn glue function. *)

val supervised_children : Tir.expr -> string list
(** The actors a spawn glue's body spawns as `supervise`-block children. *)

val actor_of_dispatch : string -> string option
(** The actor name when the argument is an actor's dispatch function. *)

val dispatch_caps : (string, string list) Hashtbl.t -> Tir.fn_def -> string list
(** Every capability an actor's dispatch reaches (sorted, de-duplicated),
    i.e. what its spawn site captures; empty when the function is not a
    dispatch or reaches none.  Takes the table from [needed_caps]. *)

val elaborate : ?dispatch:bool -> Tir.tir_module -> Tir.tir_module
(** Add the implicit capability parameters and thread them from callers.
    Threading only: nothing consumes them yet, so the program must behave
    exactly as before. *)

val dump : Tir.tir_module -> unit
(** Human-readable analysis dump, behind [MARCH_DUMP_CAP_PASSING=1].  Set
    [MARCH_DUMP_CAP_PASSING_FN=<name>] to trace one function's classification. *)
