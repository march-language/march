(* lib/jit/jit.mli *)

(** A handle to a loaded shared library. *)
type dl_handle

(** Open a shared library. Raises [Failure] on error.
    Symbols are loaded with RTLD_GLOBAL so later fragments see them. *)
val dlopen : string -> dl_handle

(** Look up a symbol in a shared library. Raises [Failure] if not found. *)
val dlsym : dl_handle -> string -> nativeint

(** Close a shared library handle. *)
val dlclose : dl_handle -> unit

(** Call a (void -> ptr) function pointer. Returns the result pointer as nativeint. *)
val call_void_to_ptr : nativeint -> nativeint

(** Call a (void -> void) function pointer. *)
val call_void_to_void : nativeint -> unit

(** Call a (void -> i64) function pointer. *)
val call_void_to_int : nativeint -> int64

(** Call a (void -> double) function pointer. *)
val call_void_to_float : nativeint -> float
