(** LLVM IR emission: the core expression emitter plus the public backend API.

    See [llvm_emit.ml]'s module doc for the pass itself and for the Wave-3
    split into [Llvm_ctx] / [Llvm_builtins] / [Llvm_eq] / [Llvm_data] /
    [Llvm_case] / [Llvm_calls] / [Llvm_tco] / [Llvm_toplevel] / [Llvm_repl].

    That split left this file re-exporting most of those modules' surfaces
    bare, for API stability. In practice only the values below are reached from
    outside [march_tir]; the rest stays available to in-library callers under
    its defining module's own name ([Llvm_ctx.fresh], [Llvm_data.emit_load_field],
    [Llvm_builtins.is_int_arith], …), which is where new code should reach for
    it. [emit_expr] itself has no external caller: the sibling emitters that
    need it receive it as a labelled [~emit_expr] callback threaded from here. *)

(** {1 Targets} *)

type arch = Llvm_toplevel.arch = X86_64 | Arm64

type target_config =
  Llvm_toplevel.target_config =
    Native
  | LinuxGnu of { arch : arch; glibc_min : string; }
  | Wasm64Wasi
  | Wasm32Wasi
  | Wasm32Unknown
  | Js

val is_wasm_target : target_config -> bool
val target_triple : target_config -> string
val target_is_linux : target_config -> bool

(** Cross-compilation target string for the bundled zig cc, when one applies. *)
val zig_target : target_config -> string option

(** {1 Whole-module emission} *)

val emit_module :
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

val emit_preamble : ?target:target_config -> ?repl:bool -> Buffer.t -> unit

(** Symbol name an [extern] declaration links against. *)
val mangle_extern : string -> string

(** {1 REPL / JIT fragment emission}

    Driven by [lib/jit/repl_jit.ml], which compiles one entry at a time into a
    fresh module linked against the slots the session has already defined. *)

type session_wraps =
  Llvm_ctx.session_wraps = {
  sw_defined : (string, unit) Hashtbl.t;
  sw_pending : (string, unit) Hashtbl.t;
}

type repl_slot_info =
  Llvm_repl.repl_slot_info = {
  rs_bare : string;
  rs_slot : int;
  rs_ty : Tir.ty;
}

val emit_repl_expr :
  ?fast_math:bool ->
  n:int ->
  ret_ty:Tir.ty ->
  prev_slots:repl_slot_info list ->
  fns:Tir.fn_def list ->
  ?extern_fns:Tir.fn_def list ->
  ?store_as_slot:int option ->
  ?session_wraps:session_wraps ->
  types:Tir.type_def list -> Tir.expr -> string

val emit_repl_decl :
  ?fast_math:bool ->
  n:int ->
  name:string ->
  val_ty:Tir.ty ->
  dest_slot:int ->
  prev_slots:repl_slot_info list ->
  fns:Tir.fn_def list ->
  ?extern_fns:Tir.fn_def list ->
  ?session_wraps:session_wraps ->
  types:Tir.type_def list -> Tir.expr -> string

val emit_repl_fn_with_closure_slot :
  ?fast_math:bool ->
  n:int ->
  bind_name:string ->
  dest_slot:int ->
  prev_slots:repl_slot_info list ->
  ?helper_fns:Tir.fn_def list ->
  ?extern_fns:Tir.fn_def list ->
  ?session_wraps:session_wraps ->
  types:Tir.type_def list -> Tir.fn_def -> string

val emit_fns_fragment :
  types:Tir.type_def list ->
  fns:Tir.fn_def list ->
  ?extern_fns:Tir.fn_def list ->
  ?session_wraps:session_wraps ->
  repl:bool -> unit -> string

(** {1 Re-exports kept only to stay compilable}

    The 33 values below are re-export bindings left over from the Wave-3 split
    ([let emit_fn = Llvm_toplevel.emit_fn], and so on). None has a caller —
    not inside this file, not elsewhere in [march_tir], not outside it —
    because every in-library user already names the defining module directly.
    Hiding them turns each into an unused-value error under the project's
    warnings-as-errors, so they are declared here with this note rather than
    deleted; removing the [let] lines and these [val]s together is a separate,
    equally safe follow-up. Do not read this block as public API. *)

(** Hiding this type makes [s_kind] an unused-field error; the type itself has
    no caller outside this module. *)
type simd_ty = {
  s_vec : string;
  s_kind : int;
  s_lanes : int;
  s_elem : string;
  s_boundary_float : bool;
  s_arr_prefix : string;
}

(** Likewise an unused-type-declaration error if hidden. *)
type repl_globals = Llvm_repl.repl_globals

val alloc_size : int -> int
val apply_ty_subst : (string * Tir.ty) list -> Tir.ty -> Tir.ty
val build_ctor_info : Llvm_ctx.ctx -> Tir.tir_module -> unit
val emit_atom_val : Llvm_ctx.ctx -> Tir.atom -> string
val emit_fn : Llvm_ctx.ctx -> Tir.fn_def -> unit
val emit_load_tag : Llvm_ctx.ctx -> string -> string
val emit_main_wrapper : Buffer.t -> unit
val emit_prev_global_bridges : Llvm_ctx.ctx -> (string * string) list -> unit
val emit_prev_slot_bridges : Llvm_ctx.ctx -> repl_slot_info list -> unit
val emit_reduction_check : Llvm_ctx.ctx -> unit

val emit_repl_fn :
  ?fast_math:bool ->
  n:int ->
  prev_slots:repl_slot_info list ->
  ?extern_fns:Tir.fn_def list ->
  types:Tir.type_def list -> Tir.fn_def -> string

val emit_repl_globals_decl : Buffer.t -> (string * string) list -> unit
val emit_slot_loader_fns : Llvm_ctx.ctx -> repl_slot_info list -> unit
val emit_store_to_slot : Llvm_ctx.ctx -> int -> string -> Tir.ty -> unit

val emit_untag_known_scalar :
  Llvm_ctx.ctx -> raw:string -> unt:string -> string -> string

val ensure_shape_globals : Llvm_ctx.ctx -> string -> string * string
val field_load_llty : Tir.ty -> string
val fn_declare_str : Tir.fn_def -> string
val fnv1a_64 : string -> int64
val is_wasm32 : target_config -> bool
val llvm_escape_string : string -> string

val llvm_param_ty :
  ?type_defs:Tir.type_def list ->
  ?collision_set:(string, string list) Hashtbl.t -> Tir.ty -> string

val llvm_ty_of_tir : Tir.ty -> string

val make_ctx :
  ?fast_math:bool ->
  ?pmap_threshold:int ->
  ?repl:bool ->
  ?hot_reload:Hot_reload.config option ->
  ?hr_names:Hot_reload.Name_table.t ->
  ?type_defs:Tir.type_def list -> unit -> Llvm_ctx.ctx

val ok_payload_ty : Tir.ty -> Tir.ty
val repr_audit_report : unit -> unit
val resolve_ctor_fields : Llvm_ctx.ctx -> Tir.ty -> string -> int -> Tir.ty list
val shape_desc : (string * Tir.ty) list -> string
val simd_kind_of_vec : string -> int
val target_arch : target_config -> arch option
val target_int_ty : target_config -> string
val target_ptr_size : target_config -> int
val target_ptr_ty : target_config -> string
