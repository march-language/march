(** Session-typed channel runtime and multi-party (MPST) runtime, as the
    tree-walking interpreter implements them.

    [Eval_builtins] dispatches the [chan_*] / [mpst_*] builtins straight to
    these, and [Eval] [include]s the module so they are also reachable as
    [Eval.chan_send] and friends. The endpoint-id counter behind [chan_new] is
    the one value here nothing outside this file touches, and is now private —
    a caller that bumped it would hand out a duplicate id. *)

open Eval_types

(** [chan_new proto role_a role_b] allocates a fresh pair of endpoints for the
    two-party protocol [proto]. *)
val chan_new : string -> string -> string -> chan_endpoint * chan_endpoint

val chan_send : chan_endpoint -> value -> value
val chan_recv : chan_endpoint -> value
val chan_close : chan_endpoint -> value

(** [mpst_new proto roles] returns one endpoint value per role, in [roles]
    order. The [string] argument to [mpst_send] / [mpst_recv] is the peer
    role. *)
val mpst_new : string -> string list -> value list

val mpst_send : mpst_endpoint -> string -> value -> value
val mpst_recv : mpst_endpoint -> string -> value
val mpst_close : mpst_endpoint -> value
