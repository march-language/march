(** The March tree-walking interpreter — evaluation of a typechecked module.

    This interface is deliberately NARROWER than what [eval.ml] defines: of the
    240 values the implementation infers, 171 are internal to the pass and are
    hidden here.  What remains is what the rest of the tree actually uses — the
    driver ([run_module], [eval_module_env]), the REPL and JIT
    ([eval_expr], [eval_decl], [apply], [lookup], [install_global_tail]), the
    actor/scheduler surface the runtime tests reach into ([actor_registry],
    [crash_actor], [monitor_actor], [reset_scheduler_state]), and value
    printing ([value_to_string], [value_to_string_pretty]).

    The type declarations are exported in full: callers pattern-match on
    [value] and read [actor_inst] fields directly, so narrowing those would be
    a different and much larger change.

    If something here really must become public, widen this file on purpose —
    that is the point of its existing.  The sibling modules
    ([Eval_builtins], [Eval_runtime], [Eval_net], …) consume [Eval] through
    THIS signature too, so a value they need must be listed. *)

type 'a ring =
  'a Eval_types.ring = {
  mutable rb_arr : 'a option array;
  mutable rb_head : int;
  mutable rb_size : int;
  rb_cap : int;
}
type value =
  Eval_types.value =
    VInt of int
  | VFloat of float
  | VString of string
  | VBool of bool
  | VAtom of string
  | VUnit
  | VTuple of value list
  | VRecord of (string * value) list
  | VCon of string * value list
  | VClosure of env * string list * March_ast.Ast.expr * string
  | VBuiltin of string * (value list -> value)
  | VPid of int
  | VTask of int
  | VCancelToken of bool ref
  | VTimerRef of timer_entry
  | VWorkPool
  | VCap of int * int
  | VActorId of int
  | VChan of chan_endpoint
  | VMChan of mpst_endpoint
  | VForeign of string * string * bool * March_ast.Ast.ty list *
      March_ast.Ast.ty
  | VMultiarity of (int * value) list
  | VNativeIntArr of int array
  | VNativeFloatArr of float array
  | VNativeF32Arr of float array
  | VNativeI32Arr of int array
  | VNativeU8Arr of int array
  | VF32x4 of float array
  | VF64x2 of float array
  | VI32x4 of int array
  | VI64x2 of int64 array
  | VU8x16 of int array
  | VTypedArray of value array
  | VVaultHandle of int
  | VRingBuf of value ring
  | VResource of int64
and chan_endpoint =
  Eval_types.chan_endpoint = {
  ce_id : int;
  ce_role : string;
  ce_proto : string;
  mutable ce_closed : bool;
  ce_out_q : value Queue.t;
  ce_in_q : value Queue.t;
}
and mpst_endpoint =
  Eval_types.mpst_endpoint = {
  me_id : int;
  me_role : string;
  me_proto : string;
  mutable me_closed : bool;
  me_out_qs : (string, value Queue.t) Hashtbl.t;
  me_in_qs : (string, value Queue.t) Hashtbl.t;
}
and timer_entry =
  Eval_types.timer_entry = {
  tt_fire_at : float;
  tt_target : int;
  tt_msg : value;
  mutable tt_cancelled : bool;
}
and env = (string * value) list
type vault_row =
  Eval_runtime.vault_row = {
  vr_value : Eval_types.value;
  vr_expiry : float option;
}
type vault_shard =
  Eval_runtime.vault_shard = {
  vs_data : (string, vault_row) Hashtbl.t;
  vs_mutex : Mutex.t;
}
type vault_table =
  Eval_runtime.vault_table = {
  vt_id : int;
  vt_name : string;
  vt_shards : vault_shard array;
}
val vault_make_table : int -> string -> vault_table
val vault_registry : (int, vault_table) Hashtbl.t
val vault_next_id : int ref
val vault_shard_for : string -> vault_shard array -> vault_shard
val value_to_string : Eval_types.value -> string
type monitor_down_reason =
  Eval_runtime.monitor_down_reason =
    Normal
  | Killed
  | Crash of string
type actor_inst =
  Eval_runtime.actor_inst = {
  ai_name : string;
  ai_def : March_ast.Ast.actor_def;
  ai_env_ref : Eval_types.env ref;
  mutable ai_state : Eval_types.value;
  mutable ai_alive : bool;
  mutable ai_terminal_reason : monitor_down_reason;
  mutable ai_monitors : (int * int) list;
  mutable ai_mailbox : Eval_types.value Queue.t;
  mutable ai_supervisor : int option;
  mutable ai_restart_count : (float * int) list;
  mutable ai_epoch : int;
  mutable ai_resources : (string * (unit -> unit)) list;
  mutable ai_linear_values :
    (Eval_types.value * Eval_types.value) list;
  mutable ai_mbox_limit : int;
  mutable ai_mbox_policy : int;
}
val actor_defs_tbl :
  (string, March_ast.Ast.actor_def * Eval_types.env ref) Hashtbl.t
val actor_registry : (int, actor_inst) Hashtbl.t
type dyn_child_entry =
  Eval_runtime.dyn_child_entry = {
  dce_pid : int;
  dce_actor_name : string;
  dce_restart : string;
}
type dyn_sup_state =
  Eval_runtime.dyn_sup_state = {
  ds_name : string;
  ds_strategy : string;
  ds_max_restarts : int;
  ds_window_secs : int;
  ds_vpid : int;
  mutable ds_children : dyn_child_entry list;
  mutable ds_restart_count : (float * int) list;
}
val dyn_sup_registry : (string, dyn_sup_state) Hashtbl.t
val crash_actor : int -> string -> unit
val monitor_actor : watcher_pid:int -> target_pid:int -> int
val demonitor_actor : int -> unit
val register_resource_ocaml : int -> string -> (unit -> unit) -> unit
val next_pid : int ref
val process_registry : (string, int) Hashtbl.t
val pid_to_registry_name : (int, string) Hashtbl.t
val impl_tbl : (string * string, Eval_types.value) Hashtbl.t
type log_value =
  Eval_runtime.log_value =
    LogStr of string
  | LogInt of int
  | LogFloat of float
  | LogBool of bool
  | LogAtom of string
  | LogNull
val test_capture_buf : Buffer.t option ref
val ring_create : int -> 'a Eval_types.ring
val ring_push : 'a Eval_types.ring -> 'a -> unit
val ring_get : 'a Eval_types.ring -> int -> 'a option
exception Match_failure of string
exception Assert_failure of string
exception BlockedOnReceive
val chan_send :
  Eval_types.chan_endpoint ->
  Eval_types.value -> Eval_types.value
type http_outcome =
  Eval_net.http_outcome =
    HttpRespond of string
  | HttpWsUpgrade of Eval_types.value
  | HttpDrop
type ws_wait_dir =
  Eval_net.ws_wait_dir =
    Ws_wait_read
  | Ws_wait_write
external caml_march_gzip_encode : string -> int -> string
  = "caml_march_gzip_encode"
external caml_march_gzip_decode : string -> string = "caml_march_gzip_decode"
external caml_march_deflate_encode : string -> string
  = "caml_march_deflate_encode"
external caml_march_deflate_decode : string -> string
  = "caml_march_deflate_decode"
external caml_march_zstd_encode : string -> int -> string
  = "caml_march_zstd_encode"
external caml_march_zstd_decode : string -> string = "caml_march_zstd_decode"
external caml_march_brotli_encode : string -> int -> int -> string
  = "caml_march_brotli_encode"
external caml_march_brotli_decode : string -> string
  = "caml_march_brotli_decode"
type task_entry = {
  te_id : int;
  mutable te_result : value option;
  te_thunk : value;
  mutable te_cancelled : bool;
}
val doc_registry : (string, string) Hashtbl.t
val module_registry : (string, value) Hashtbl.t
val module_loader : (string -> unit) option ref
val ensure_module_loaded : string -> unit
val tap_drain : unit -> value list
val lookup_doc : string -> string option
val shutdown_requested : bool ref
val signal_watchers : value option array
val signal_pending : bool array
val signal_seen : bool array
val handle_os_signal : int -> unit
val pmap_threshold_value : int ref
val http_fetch_hook :
  (string -> string -> string -> string -> (string, string) result) option
  ref
val ring_drop_newest : 'a ring -> int -> unit
type actor_inst_snapshot = {
  ais_name : string;
  ais_state : value;
  ais_alive : bool;
  ais_terminal_reason : monitor_down_reason;
}
type actor_state_snapshot = {
  ass_defs : (string * (March_ast.Ast.actor_def * env ref)) list;
  ass_instances : (int * actor_inst_snapshot) list;
  ass_next_pid : int;
}
type trace_frame = {
  tf_expr : March_ast.Ast.expr;
  tf_env : env;
  tf_result : value option;
  tf_exn : string option;
  tf_actor : actor_state_snapshot;
  tf_span : March_ast.Ast.span;
  tf_depth : int;
}
type actor_msg_event = {
  ame_pid : int;
  ame_actor_name : string;
  ame_msg : value;
  ame_state_before : value;
  ame_state_after : value option;
  ame_frame_idx : int;
}
type step_mode = Run | Pause | StepInto | StepOver of int | StepOut of int
type debug_ctx = {
  dc_trace : trace_frame ring;
  mutable dc_pos : int;
  mutable dc_enabled : bool;
  mutable dc_depth : int;
  mutable dc_on_dbg : (env -> unit) option;
  mutable dc_actor_log : actor_msg_event list;
  mutable dc_breakpoints : (string * int, unit) Hashtbl.t;
  mutable dc_step : step_mode;
  mutable dc_on_pause : (env -> March_ast.Ast.span -> unit) option;
  mutable dc_last_line : (string * int) option;
}
val snapshot_actors : unit -> actor_state_snapshot
val restore_actors : actor_state_snapshot -> unit
val debug_ctx : debug_ctx option ref
exception Eval_error of string
val interface_method_hint : March_ast.Ast.module_ -> string -> string option
exception Yield
type march_frame = { mf_name : string; mf_file : string; mf_line : int; }
val get_march_stack : unit -> march_frame list
val clear_march_stack : unit -> unit
val set_reduction_counting : bool -> unit
val arm_reduction_budget : int -> unit
val reductions_used : int -> int
val eval_error : ('a, unit, string, 'b) format4 -> 'a
val match_pattern :
  value -> March_ast.Ast.pattern -> (string * value) list option
val value_to_string_pretty :
  ?width:int ->
  ?max_items:int -> ?max_depth:int -> Eval_types.value -> string
type actor_info = {
  ai_pid : int;
  ai_name : string;
  ai_alive : bool;
  ai_state_str : string;
}
val increment_epoch : int -> unit
val list_actors : unit -> actor_info list
external _ffi_dlopen : string -> nativeint = "march_eval_dlopen"
external _ffi_dlsym : nativeint -> string -> nativeint = "march_eval_dlsym"
external _ffi_dyncall_i : nativeint -> int64 array -> int -> int64
  = "march_eval_dyncall_i"
external _ffi_dyncall_d : nativeint -> int64 array -> int -> float
  = "march_eval_dyncall_d"
external _ffi_dyncall_fi :
  nativeint -> int64 array -> int -> float array -> int -> int64
  = "march_eval_dyncall_fi"
external _ffi_dyncall_fd :
  nativeint -> int64 array -> int -> float array -> int -> float
  = "march_eval_dyncall_fd"
external _ffi_dlopen_extra : string -> unit = "march_eval_dlopen_extra"
val ffi_runtime_so : (unit -> string option) ref
val ffi_shim_so : string option ref
val base_env : Eval_types.env
val global_tail : env ref
val global_tbl : (string, value) Hashtbl.t
val install_global_tail : env -> unit
val clear_global_tail : unit -> unit
val assoc_str : string -> env -> value option
val lookup : string -> env -> value
val apply : value -> value list -> value
val eval_expr : env -> March_ast.Ast.expr -> value
val reset_scheduler_state : unit -> unit
val run_scheduler : unit -> unit
val task_builtins : env
val eval_with_reduction_tracking : value -> value * int
type stub = { mutable sv : value; }
val eval_decl : env -> March_ast.Ast.decl -> env
val eval_module_env : March_ast.Ast.module_ -> env
val eval_stdlib_decls : March_ast.Ast.decl list -> unit
val letstar_repl_bind :
  env ->
  March_ast.Ast.pattern ->
  March_ast.Ast.expr -> ((string * value) list, string) result
val run_module : March_ast.Ast.module_ -> unit
type test_result = TestPass | TestFail of string | TestError of string
val run_tests :
  ?verbose:bool ->
  ?quiet:bool ->
  ?dot_stream:bool ->
  ?filter:string ->
  ?capture_io:bool ->
  March_ast.Ast.module_ -> int * int * (string * string) list
val run_doctests :
  ?verbose:bool ->
  ?quiet:bool ->
  ?filter:string ->
  parse_expr:(string -> March_ast.Ast.expr) ->
  March_ast.Ast.module_ -> int * int * (string * string) list

val march_bytes_of_string : string -> Eval_types.value

val f32_round : float -> float
