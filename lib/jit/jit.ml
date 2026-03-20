(* lib/jit/jit.ml *)

type dl_handle = nativeint

external dlopen : string -> dl_handle = "march_dlopen"
external dlsym : dl_handle -> string -> nativeint = "march_dlsym"
external dlclose : dl_handle -> unit = "march_dlclose"
external call_void_to_ptr : nativeint -> nativeint = "march_call_void_to_ptr"
external call_void_to_void : nativeint -> unit = "march_call_void_to_void"
external call_void_to_int : nativeint -> int64 = "march_call_void_to_int"
external call_void_to_float : nativeint -> float = "march_call_void_to_float"
external call_ptr_to_ptr : nativeint -> nativeint -> nativeint = "march_call_ptr_to_ptr"
