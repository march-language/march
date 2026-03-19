(** Hooks for debug commands injected when the REPL is launched at a breakpoint. *)
type debug_hooks = {
  dh_back      : int -> int;
  (** Step back [n] frames; returns the new position index. *)
  dh_forward   : int -> int;
  (** Step forward [n] frames; returns the new position index. *)
  dh_goto      : int -> int;
  (** Jump to absolute frame index; returns clamped position. *)
  dh_where     : unit -> string list;
  (** One-line "file:line:col — expr" description of the current frame. *)
  dh_stack     : unit -> string list;
  (** Human-readable call-stack lines. *)
  dh_trace     : int -> string list;
  (** Last [n] trace frames formatted as strings. *)
  dh_diff      : int -> string list -> string list;
  (** Env diff vs [n] frames back; [baseline_names] excluded. Returns formatted lines. *)
  dh_find      : (March_eval.Eval.env -> bool) -> int option;
  (** Search backward for first frame where predicate holds; returns frame idx. *)
  dh_replay    : March_eval.Eval.env -> March_eval.Eval.value option;
  (** Re-evaluate the current expression with a modified env. *)
  dh_frame_env : unit -> March_eval.Eval.env option;
  (** Return the env of the currently selected trace frame, if any. *)
  dh_actors    : unit -> string list;
  (** Summary of all actors with message counts. *)
  dh_actor     : int -> int option -> string list;
  (** Message history for actor [pid]; optionally jump to message [n]. *)
  dh_save_trace : string -> (unit, string) result;
  (** Save trace to file; returns Ok () or Error msg. *)
  dh_load_trace : string -> (unit, string) result;
  (** Load trace from file; returns Ok () or Error msg. *)
}

val run :
  ?stdlib_decls:March_ast.Ast.decl list ->
  ?debug_hooks:debug_hooks option ->
  ?initial_env:March_eval.Eval.env option ->
  unit -> unit
