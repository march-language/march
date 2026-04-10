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
  tc_env:March_typecheck.Typecheck.env ->
  March_ast.Ast.module_ ->
  March_tir.Tir.ty * string

(** Compile and execute a REPL declaration (let binding or function def).
    [is_fn_decl]: true if the original input was a DFn, false for DLet.
    [bind_name]: the variable/function name being bound.
    Updates the JIT state with the new binding.
    Raises [Failure] on compile or link error. *)
val run_decl :
  t ->
  tc_env:March_typecheck.Typecheck.env ->
  is_fn_decl:bool ->
  bind_name:string ->
  March_ast.Ast.module_ ->
  unit

(** Pre-compile stdlib functions to a cached .so in ~/.cache/march/.
    [content_hash] is a hex string derived from the stdlib source content
    (see [Repl.stdlib_content_hash]).  Uses a source-level hash so that
    cache hits are handled without TIR lowering.
    After this call all stdlib functions are marked as already compiled,
    so subsequent JIT fragments don't need to re-emit them. *)
val precompile_stdlib :
  t ->
  content_hash:string ->
  stdlib_decls:March_ast.Ast.decl list ->
  type_map:(March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t ->
  unit

(** Clean up: close all open dl handles, remove temp files. *)
val cleanup : t -> unit
