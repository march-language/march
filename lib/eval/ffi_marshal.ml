(** OCaml externals for the interpreter ↔ march_value bridge.
    Mirrors ffi_marshal.c.  All int64 values are march_value words.
    Called from eval.ml's FFI marshal layer. *)

(* Reset the runtime pointer cache when a new .so is dlopened. *)
external reset : unit -> unit = "march_ffi_marshal_reset"

(* ── Scalar encoding ──────────────────────────────────────────────── *)
(* Int/Bool tagged word: (n<<1)|1 *)
external make_int   : int64 -> int64 = "march_ffi_make_int"
external get_int    : int64 -> int64 = "march_ffi_get_int"
(* Float: bitcast double ↔ int64 *)
external make_float : float -> int64 = "march_ffi_make_float"
external get_float  : int64 -> float = "march_ffi_get_float"
(* None niche = 0, Some niche = identity *)
external none       : unit  -> int64 = "march_ffi_none"
external some       : int64 -> int64 = "march_ffi_some"
(* Inline heap check *)
external is_heap    : int64 -> bool  = "march_ffi_is_heap_inline"

(* ── Heap operations (require dlopened runtime) ──────────────────── *)
(* String/Bytes constructors — take OCaml string, return march_value *)
external str_new         : string -> int64  = "march_ffi_str_new"
external bytes_new       : string -> int64  = "march_ffi_bytes_new"
(* Borrow + copy — return OCaml string copy; call before dropping the march_value *)
external str_borrow_copy  : int64 -> string = "march_ffi_str_borrow_copy"
external bytes_borrow_copy: int64 -> string = "march_ffi_bytes_borrow_copy"

(* Boxed Option (Float/Unit payloads) and Result constructors *)
external none_boxed  : unit  -> int64 = "march_ffi_none_boxed"
external some_boxed  : int64 -> int64 = "march_ffi_some_boxed"
external ok          : int64 -> int64 = "march_ffi_ok"
external err         : int64 -> int64 = "march_ffi_err"

(* Variant / record field access *)
external variant_tag   : int64 -> int          = "march_ffi_variant_tag"
external variant_field : int64 -> int -> int64 = "march_ffi_variant_field"
external record_field  : int64 -> int -> int64 = "march_ffi_record_field"

(* Variant / record constructors (fields as int64 array) *)
external make_variant : int -> int64 array -> int64   = "march_ffi_make_variant"
external make_record  : string -> int64 array -> int64 = "march_ffi_make_record"

(* Reference counting *)
external dup  : int64 -> unit = "march_ffi_dup"
external drop : int64 -> unit = "march_ffi_drop"

(* ── `raises` env sentinel ──────────────────────────────────────── *)
(** Allocate a zeroed march_env-compatible C struct. Caller must free. *)
external alloc_env   : unit -> nativeint = "march_ffi_alloc_env"
external free_env    : nativeint -> unit = "march_ffi_free_env"
external env_raised  : nativeint -> bool = "march_ffi_env_raised"
external env_err     : nativeint -> int64 = "march_ffi_env_err"
(* Address of the sentinel as int64 for prepending to GP arg array. *)
external env_ptr_i64 : nativeint -> int64 = "march_ffi_env_ptr_i64"
