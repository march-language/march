(** SIMD codegen: the `simd_<type>_<op>` builtin family.  See
    [llvm_emit_simd.ml]. *)

(** Per-vector-type LLVM shape: vector type string, runtime [kind] tag,
    lane count, LLVM element type, whether the March-level boundary type for
    scalar lane traffic is `double`, and the runtime native-array fn prefix. *)
type simd_ty = {
  s_vec : string;
  s_kind : int;
  s_lanes : int;
  s_elem : string;
  s_boundary_float : bool;
  s_arr_prefix : string;
}

(** The five supported vector types, keyed by their March name ("f32x4", ...). *)
val simd_tys : (string * simd_ty) list

(** Decode ["simd_f32x4_add"] into its shape record and the op ["add"].
    Total: a name that is not shaped "simd_<known-type>_<op>" gives [None]
    and the general [EApp] arm handles it. *)
val decode_simd_call : string -> (simd_ty * string) option

(** Declare an LLVM intrinsic into the module preamble on first use. *)
val ensure_intrinsic_declared :
  Llvm_ctx.ctx -> name:string -> sig_:string -> unit

(** Body of [Llvm_emit.emit_expr]'s SIMD intercept arm.  Only call when
    [decode_simd_call] on the callee's name returned [Some]. *)
val emit_simd_call :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx -> Tir.var -> Tir.atom list -> string * string
