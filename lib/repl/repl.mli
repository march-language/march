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

(** Compute a content hash of stdlib decls (MD5 of marshalled form). *)
val stdlib_content_hash : March_ast.Ast.decl list -> string

(** Pre-register stdlib type constructors into the typecheck env. *)
val preregister_stdlib_types :
  March_typecheck.Typecheck.env ->
  March_ast.Ast.decl list ->
  March_typecheck.Typecheck.env

(** Typecheck and eval stdlib decls into the REPL env. *)
val load_decls_into_env :
  March_eval.Eval.env ->
  March_typecheck.Typecheck.env ->
  March_ast.Ast.decl list ->
  March_eval.Eval.env * March_typecheck.Typecheck.env

(** Load a cached typecheck env from disk. *)
val load_cached_tc_env :
  content_hash:string ->
  type_map:(March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t ->
  March_typecheck.Typecheck.env option

(** Save a typecheck env to disk cache. *)
val save_cached_tc_env :
  content_hash:string ->
  March_typecheck.Typecheck.env ->
  unit

(** Precompile stdlib to a cached .so via the JIT context. *)
val maybe_precompile_stdlib :
  March_jit.Repl_jit.t option ->
  stdlib_decls:March_ast.Ast.decl list ->
  type_map:(March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t ->
  unit

val run :
  ?stdlib_decls:March_ast.Ast.decl list ->
  ?debug_hooks:debug_hooks option ->
  ?initial_env:March_eval.Eval.env option ->
  ?jit_ctx:March_jit.Repl_jit.t option ->
  ?preload_file:string option ->
  unit -> unit
