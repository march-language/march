(** The delta-rule builtin environment.  See eval_builtins.ml.

    [base_env] is the export (plus [reset_cap_authority]): the helpers behind it are implementation
    detail, and hiding them here is what keeps "is this helper already
    defined somewhere?" answerable. *)

val base_env : Eval_types.env

(** Clear the run-time authority (launch layers and the current slot) for a
    fresh program launch (ocap phase 4). *)
val reset_cap_authority : unit -> unit
