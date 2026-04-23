(* lib/jit/jit_orc.mli

   ORCv2 LLJIT backend for March's REPL JIT.  Opt-in via the
   MARCH_JIT_BACKEND=orc environment variable; default is the
   clang-driver + dlopen path in [Repl_jit.compile_fragment].

   libLLVM.dylib is loaded lazily on the first [create] call, so
   the default (non-ORC) build pays no startup cost. *)

(** Opaque handle to an LLJIT instance. *)
type t

(** Create a new LLJIT instance.  Loads libLLVM.dylib on first call;
    the location can be overridden with the MARCH_LLVM_LIB env var.
    Raises [Failure] if libLLVM cannot be found or LLJIT setup fails. *)
val create : unit -> t

(** Parse an LLVM IR string and add the resulting module to the LLJIT.
    [name] is used only for diagnostics (MemoryBuffer identifier). *)
val add_ir : t -> ir:string -> name:string -> unit

(** Look up a symbol by name.  Returns the address as a nativeint.
    Raises [Failure] if the symbol is not found. *)
val lookup : t -> string -> nativeint

(** Tear down the LLJIT instance.  Frees all code produced from
    [add_ir] calls. *)
val dispose : t -> unit
