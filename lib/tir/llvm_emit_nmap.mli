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
