(** March debugger — replay.

    Implements `:let x = expr` (rebinding a variable in the cursor frame's env)
    and `:replay` (re-executing from the cursor position with a modified env).

    After replay, the trace is truncated at the replay start point and
    new frames are appended from the replayed execution.

    Side effects during replay:
    - stdout: output is prefixed with [replay]
    - Actor state: restored from the cursor frame's actor snapshot before replay *)

module Eval = March_eval.Eval

(** Rebind [name] to [value] in [env]. *)
let rebind_in_env (name : string) (value : Eval.value) (env : Eval.env) : Eval.env =
  (name, value) :: (List.remove_assoc name env)

(** Re-execute the expression at cursor position with [new_env].
    Restores actor state from cursor frame's snapshot.
    Truncates trace at cursor and appends new frames.
    Returns the new result value. *)
let replay_from (ctx : Eval.debug_ctx) (new_env : Eval.env) : Eval.value option =
  match Eval.ring_get ctx.dc_trace ctx.dc_pos with
  | None -> None
  | Some frame ->
    Eval.restore_actors frame.tf_actor;
    Eval.ring_drop_newest ctx.dc_trace ctx.dc_pos;
    ctx.dc_pos <- 0;
    (try
       let v = Eval.eval_expr new_env frame.tf_expr in
       Some v
     with
     | Eval.Eval_error _    -> None
     | Eval.Match_failure _ -> None)
