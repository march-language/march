(** The delta-rule builtin environment.  See eval_builtins.ml.

    [base_env] is the sole export: the helpers behind it are implementation
    detail, and hiding them here is what keeps "is this helper already
    defined somewhere?" answerable. *)

val base_env : Eval_types.env
