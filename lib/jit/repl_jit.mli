(* lib/jit/repl_jit.mli *)

(** Persistent state for the compiled REPL. *)
type t

(** Which code-generation pipeline the REPL JIT uses for a fragment.
    [`Clang] emits a .so and dlopens it; [`Orc] parses IR directly into an
    in-process LLJIT. See [current_backend] / [set_backend_for_tests]. *)
type backend = [ `Clang | `Orc ]

(** The backend that will be used for the next fragment. Resolved lazily
    on first use (env var, else ORC iff libLLVM is present, else clang) and
    cached; see [repl_jit.ml] for the exact resolution order. *)
val current_backend : unit -> backend

(** Test-only override of the resolved backend, e.g. to run the same test
    against both backends. *)
val set_backend_for_tests : backend -> unit

(** Create a JIT context.
    [runtime_so] is the path to the pre-compiled march_runtime.so.
    [clang] is the clang binary path (default "clang"). *)
val create : runtime_so:string -> ?clang:string -> unit -> t

(** Number of IR fragments compiled so far in this session.  Exposed for
    tests: it lets them assert that an identical :reset-style replay of a
    declaration takes the skip fast path (count unchanged) rather than
    recompiling. *)
val fragment_count : t -> int

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

(** Register a user-declared type (DType) so that subsequent [run_expr] calls
    can pretty-print values of that type.  Type declarations are evaluated in
    the tree-walking interpreter and never reach the JIT via [run_decl]; this
    function bridges the gap by lowering the AST type into TIR and storing it
    in the JIT context's type table. *)
val register_user_type_decl : t -> March_ast.Ast.decl -> unit

(** Compile a :load-ed DMod's functions into the JIT dylib so ORC can resolve
    module-qualified names (e.g. Counter.create) in subsequent REPL fragments.
    [tc_env] must be the type environment before the DMod was added.
    Silently ignores non-DMod decls. *)
val register_module_decl :
  t ->
  tc_env:March_typecheck.Typecheck.env ->
  March_ast.Ast.decl ->
  unit

(** Whole-program JIT — the engine behind `march --jit file.march`.

    Lowers the user module (the stdlib prelude must already be in place via
    [precompile_stdlib]), compiles it through the active backend, and runs
    [main] the way the native build does: [march_spawn_main] on a thunk that
    supplies one erased (null) capability per declared parameter, then
    [march_run_scheduler].  [tc_env] is the pre-user typecheck environment
    (the stdlib seed env).

    Does NOT propagate [main]'s value as the process exit code — neither does
    the native build, whose `@main` returns a hard 0.

    A module with no [main] is a no-op returning [()] — the interpreter is
    silent and exits 0 for such a file, and --jit must not differ.  Detected
    before any emission or scheduler spawn.

    Raises [Failure] on compile or link error; [bin/main.ml]'s --jit arm turns
    that into one `march --jit: <msg>` line and exit 1, never a backtrace. *)
val run_program :
  t ->
  tc_env:March_typecheck.Typecheck.env ->
  March_ast.Ast.module_ ->
  unit

(** Clean up: close all open dl handles, remove temp files. *)
val cleanup : t -> unit
