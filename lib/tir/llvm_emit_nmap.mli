(** NativeArray map/map2 inline-loop codegen.  See [llvm_emit_nmap.ml]. *)

(** Per-width descriptor resolved from an inline-loop synthetic name.
    Opaque: [Llvm_emit]'s four driving arms only pass it through. *)
type nmap_width

(** Decode a synthetic `__native_<w>_map[2]_inline` name into
    (width, is_map2, unboxed).  [None] for any other name. *)
val decode_nmap_inline_call : string -> (nmap_width * bool * bool) option

(** Emit the one-array inline map loop. *)
val emit_native_map_inline_loop :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx ->
  width:nmap_width ->
  unboxed:bool ->
  arr_atom:Tir.atom ->
  apply_name:string ->
  clo_reg:string -> string * string

(** Emit the two-array inline map2 loop. *)
val emit_native_map2_inline_loop :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx ->
  width:nmap_width ->
  unboxed:bool ->
  arr1_atom:Tir.atom ->
  arr2_atom:Tir.atom ->
  apply_name:string ->
  clo_reg:string -> string * string


(** Decode a [__native_<w>_arr_fold_inline(_unboxed)] name into its width and
    unboxed flag; [None] for anything else. *)
val decode_nfold_inline_call : string -> (nmap_width * bool) option

(** Emit the fold inline loop; returns the boundary type ([double] or [i64]) and
    the final accumulator. *)
val emit_native_fold_inline_loop :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx ->
  width:nmap_width ->
  unboxed:bool ->
  acc_atom:Tir.atom ->
  arr_atom:Tir.atom ->
  apply_name:string ->
  clo_reg:string ->
  string * string

(** Decode a [__native_<w>_arr_summap(2)_inline(_unboxed)] name into its
    width, array count (1 or 2) and unboxed flag; [None] for anything else. *)
val decode_nsummap_inline_call : string -> (nmap_width * int * bool) option

(** Emit the fused [sum(map(..))] / [sum(map2(..))] loop; returns the boundary
    type ([double] or [i64]) and the sum. *)
val emit_native_summap_inline_loop :
  emit_atom:(Llvm_ctx.ctx -> Tir.atom -> string * string) ->
  Llvm_ctx.ctx ->
  width:nmap_width ->
  unboxed:bool ->
  arr_atoms:Tir.atom list ->
  apply_name:string ->
  clo_reg:string ->
  string * string
