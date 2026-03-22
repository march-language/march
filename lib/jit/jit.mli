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

(** Call a (ptr -> ptr) function pointer. *)
val call_ptr_to_ptr : nativeint -> nativeint -> nativeint

(** Read a 32-bit signed integer from [ptr + byte_offset].
    Used to inspect march_hdr.tag (i32 at offset 8). *)
val read_i32_at : nativeint -> int -> int

(** Read a 64-bit integer from [ptr + byte_offset].
    Used to read i64 fields (Int, Bool, Unit, Float-as-bits). *)
val read_i64_at : nativeint -> int -> int64

(** Read a pointer from [ptr + byte_offset].
    Used to read heap-pointer fields (String, List, Option, …). *)
val read_ptr_at : nativeint -> int -> nativeint

(** Read a march_string* as an OCaml string.
    Layout: {rc:i64, len:i64, data:char[]}; len at offset 8, data at offset 16. *)
val read_march_string : nativeint -> string
