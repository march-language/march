(** Hooks for debug commands injected when the REPL is launched at a breakpoint. *)
type debug_hooks = {
  dh_back      : int -> int;
  (** Step back [n] frames; returns the new position index. *)
  dh_forward   : int -> int;
  (** Step forward [n] frames; returns the new position index. *)
  dh_where     : unit -> string list;
  (** One-line "file:line:col — expr" description of the current frame. *)
  dh_stack     : unit -> string list;
  (** Human-readable call-stack lines. *)
  dh_trace     : int -> string list;
  (** Last [n] trace frames formatted as strings. *)
  dh_replay    : March_eval.Eval.env -> March_eval.Eval.value option;
  (** Re-evaluate the current expression with a modified env. *)
  dh_frame_env : unit -> March_eval.Eval.env option;
  (** Return the env of the currently selected trace frame, if any. *)
}

val run :
  ?stdlib_decls:March_ast.Ast.decl list ->
  ?debug_hooks:debug_hooks option ->
  ?initial_env:March_eval.Eval.env option ->
  unit -> unit
