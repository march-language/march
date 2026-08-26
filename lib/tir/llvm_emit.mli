(** LLVM IR emission: the core expression emitter plus the public backend API.

    See [llvm_emit.ml]'s module doc for the pass itself and for the Wave-3
    split into [Llvm_ctx] / [Llvm_builtins] / [Llvm_eq] / [Llvm_data] /
    [Llvm_case] / [Llvm_calls] / [Llvm_tco] / [Llvm_toplevel] / [Llvm_repl].

    That split left this file re-exporting most of those modules' surfaces
    bare, for API stability. Those 33 re-exports had no caller anywhere and
    have been deleted; everything they named is still reachable under its
    defining module's own name ([Llvm_ctx.fresh], [Llvm_data.emit_load_field],
    [Llvm_builtins.is_int_arith], …), which is where new code should reach for
    it. What remains below is the surface that is genuinely used from outside
    [march_tir]. [emit_expr] itself has no external caller: the sibling
    emitters that need it receive it as a labelled [~emit_expr] callback
    threaded from here. *)

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

(** {1 Builtin dispatch}

    [emit_expr] selects a builtin's emit arm with a
    [when Builtin_name.is Builtin_name.Task_await f.Tir.v_name] guard. Guards
    are opaque to the compiler, so [builtin_group] exists as the
    exhaustiveness surface they cannot provide: it has no wildcard, and adding
    a constructor to [Builtin_name.t] without classifying it there is a
    non-exhaustive-match error. It doubles as documentation of which topic
    section of [llvm_emit.ml] emits a given builtin. *)

type builtin_group = Bg_arith | Bg_task | Bg_record

val builtin_group : Builtin_name.t -> builtin_group

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
