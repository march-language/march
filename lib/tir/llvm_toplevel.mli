(** Top-level LLVM emission: target configuration, function emission, the
    constructor-tag table, and the module driver.

    Interface for {!Llvm_toplevel}, added 2026-08-27 by the pass that gave the
    highest-churn compiler files one (see
    [specs/progress/2026-08-25-mli-interfaces-top-churn-files.md]).

    21 values were exported before this file existed; 18 still are.
    [Llvm_toplevel] is not [include]d by anything, so hiding here is local and
    checkable.

    {2 What is hidden}

    Three values, each with an internal caller and no external one:
    [buffer_contains] (an idempotence guard used before appending to the
    preamble), [native_triple] (the lazy host-triple probe behind
    {!target_triple}), and [native_vec_param_idxs] (a vector-ABI helper used
    by {!emit_fn}).

    {2 What stays}

    [emit_module] has 17 referencing files and [build_ctor_info] 15; the
    [target_*] family is read by [bin/main.ml] and pinned in
    [llvm_emit.mli]. *)

type arch = X86_64 | Arm64
type target_config =
    Native
  | LinuxGnu of { arch : arch; glibc_min : string; }
  | Wasm64Wasi
  | Wasm32Wasi
  | Wasm32Unknown
  | Js
val is_wasm_target : target_config -> bool
val is_wasm32 : target_config -> bool
external get_native_triple : unit -> string = "march_tir_native_triple"
val target_triple : target_config -> string
val target_is_linux : target_config -> bool
val zig_target : target_config -> string option
val target_ptr_size : target_config -> int
val target_ptr_ty : target_config -> string
val target_int_ty : target_config -> string
val emit_preamble : ?target:target_config -> ?repl:bool -> Buffer.t -> unit
val is_leaf_callee : string -> bool
val expr_has_call : Tir.expr -> bool
val emit_fn :
  emit_expr:(Llvm_ctx.ctx -> Tir.expr -> string * string) ->
  Llvm_ctx.ctx -> Tir.fn_def -> unit
val fn_declare_str : Tir.fn_def -> string
val emit_atom_show_table : Llvm_ctx.ctx -> unit

(** Per-constructor heap tags for a [type_def list], in declaration order,
    exactly as {!build_ctor_info} installs them: [type_name -> tag list].

    Exported for the REPL's heap pretty-printer, which reads a tag out of a
    live value and must map it back to a constructor name.  "tag = index in
    the ctor list" holds only for ordinary variants; actor-message types and
    same-short-name colliding types are numbered from global counters that
    walk the list front to back, so the caller must pass the SAME list in the
    SAME order the code being interpreted was compiled with.

    {!build_ctor_info} consumes this function, so the two cannot drift. *)
val variant_ctor_tags :
  collision_set:(string, string list) Hashtbl.t ->
  Tir.type_def list ->
  (string, int list) Hashtbl.t

val build_ctor_info :
  Llvm_ctx.ctx -> Tir.tir_module -> unit
val emit_module :
  emit_expr:(Llvm_ctx.ctx -> Tir.expr -> string * string) ->
  ?fast_math:bool ->
  ?pmap_threshold:int ->
  ?target:target_config ->
  ?hot_reload:Hot_reload.config option ->
  ?impl_hashes:(string, string) Hashtbl.t ->
  ?remote_impl_hashes:(string, string) Hashtbl.t ->
  ?remote_sig_hashes:(string, string) Hashtbl.t ->
  ?emit_main:bool ->
  ?cap_attrib:(String.t * string) list ->
  ?cap_decls:(string * string) list -> Tir.tir_module -> string
