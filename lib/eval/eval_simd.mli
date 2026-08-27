(** Simd 128-bit vector ops and NativeArray narrow-width (f32/i32/u8) helpers.

    Unusually for this pass, nothing here turned out to be internal: all 29
    values have a caller in [Eval_builtins], and a handful of them
    ([fma32_single_round], [simd_f32_is_highbit], [simd_u8_is_highbit],
    [simd_hfold], [simd_bounds_check]) are read by [Llvm_emit_simd] as well, so
    that the compiled and interpreted backends round and wrap identically. This
    interface therefore restricts nothing — it exists so that the next value
    added here is added on purpose.

    Boundary rule for the narrow-width helpers: integer stores wrap mod 2^w
    two's-complement, float stores round to nearest-even binary32, and neither
    ever traps. *)

(** {1 NativeArray narrow-width helpers} *)

val f32_round : float -> float
val fma32_single_round : float -> float -> float -> float
val i32_wrap : int -> int
val u8_wrap : int -> int

(** {1 Simd lane primitives}

    The bitwise [simd_f{32,64}_*] family reinterprets the float as its bit
    pattern, so [simd_f32_allones] is the all-ones mask, not a numeric value. *)

val simd_minnum_f : float -> float -> float
val simd_maxnum_f : float -> float -> float
val simd_f32_allones : float
val simd_f32_zero : float
val simd_f64_allones : float
val simd_f64_zero : float
val simd_f32_is_highbit : float -> bool
val simd_f64_is_highbit : float -> bool
val simd_f32_and : float -> float -> float
val simd_f32_or : float -> float -> float
val simd_f32_xor : float -> float -> float
val simd_f32_not : float -> float
val simd_f64_and : float -> float -> float
val simd_f64_or : float -> float -> float
val simd_f64_xor : float -> float -> float
val simd_f64_not : float -> float
val simd_i32_is_highbit : int -> bool
val simd_i64_is_highbit : int64 -> bool
val simd_u8_is_highbit : int -> bool

(** {1 Whole-vector operations} *)

(** [simd_first_set p v] is the index of the first lane satisfying [p], or -1. *)
val simd_first_set : ('a -> bool) -> 'a array -> int

val simd_any : ('a -> bool) -> 'a array -> bool
val simd_all : ('a -> bool) -> 'a array -> bool

(** [simd_select p mask a b] takes lane [i] from [a] when [p mask.(i)], else
    from [b]. *)
val simd_select : ('a -> bool) -> 'a array -> 'a array -> 'a array -> 'a array

val simd_hfold : ('a -> 'a -> 'a) -> 'a array -> 'a

(** [simd_bounds_check who idx width len] panics if the access is out of
    range; [who] names the builtin in the message. *)
val simd_bounds_check : string -> int -> int -> int -> unit
