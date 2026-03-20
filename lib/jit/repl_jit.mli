(* lib/jit/repl_jit.mli *)

(** Persistent state for the compiled REPL. *)
type t

(** Create a JIT context.
    [runtime_so] is the path to the pre-compiled march_runtime.so.
    [clang] is the clang binary path (default "clang"). *)
val create : runtime_so:string -> ?clang:string -> unit -> t

(** Compile and execute a REPL expression.
    Returns the LLVM IR return type and a string representation of the result.
    Raises [Failure] on compile or link error. *)
val run_expr :
  t ->
  type_map:(March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t ->
  March_ast.Ast.module_ ->
  March_tir.Tir.ty * string

(** Compile and execute a REPL declaration (let binding or function def).
    [is_fn_decl]: true if the original input was a DFn, false for DLet.
    [bind_name]: the variable/function name being bound.
    Updates the JIT state with the new binding.
    Raises [Failure] on compile or link error. *)
val run_decl :
  t ->
  type_map:(March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t ->
  is_fn_decl:bool ->
  bind_name:string ->
  March_ast.Ast.module_ ->
  unit

(** Clean up: close all open dl handles, remove temp files. *)
val cleanup : t -> unit
