(** Interpreter runtime state and value-rendering helpers shared by the
    evaluator, the builtin table, and the protocol runtimes.

    This module holds the interpreter's mutable world: the vault (ETS-like)
    tables, the actor and supervisor registries, the logger, the process and
    monitor id counters. [Eval] [include]s it and [Eval_builtins],
    [Eval_net] and [Eval_prim] [open] it, so nearly all of it is genuinely
    shared — 72 of the 82 values it used to export have a caller elsewhere.

    What is now private is the supervision machinery's internals: the three
    restart strategies ([one_for_one_restart], [one_for_all_restart],
    [rest_for_one_restart]), the two supervisor notifications
    ([notify_supervisor], [notify_dyn_supervisor]), the [monitor_down_*]
    message constructors, [fresh_monitor_id], [capture_reg_names_pending] and
    [march_hash_mask]. Those run *inside* a crash cascade and read state that is
    half-torn-down while they do; the supported entry points are
    [crash_actor] / [crash_actor_with_reason], which drive them in the right
    order. *)

open Eval_types

(** {1 Vault — sharded in-memory key-value tables} *)

val vault_num_stripes : int

type vault_row = { vr_value : value; vr_expiry : float option }
type vault_shard = { vs_data : (string, vault_row) Hashtbl.t; vs_mutex : Mutex.t }

type vault_table = {
  vt_id : int;
  vt_name : string;
  vt_shards : vault_shard array;
}

val vault_make_table : int -> string -> vault_table
val vault_registry : (int, vault_table) Hashtbl.t
val vault_name_registry : (string, int) Hashtbl.t
val vault_next_id : int ref
val vault_row_live : vault_row -> bool
val vault_decode_key : string -> value
val vault_key_of_value : value -> string
val vault_lookup : int -> vault_table
val vault_shard_for : string -> vault_shard array -> vault_shard

(** {1 Value rendering} *)

val is_list_value : value -> bool
val list_elems : value list -> value -> value list
val display_tag : string -> string
val value_to_string : value -> string
val value_display : value -> string
val show_dispatch : value -> string
val type_name_of_value : value -> string option
val type_tag_of : value -> string option

(** {1 Actors, supervision and monitors} *)

type monitor_down_reason = Normal | Killed | Crash of string

type actor_inst = {
  ai_name : string;
  ai_def : March_ast.Ast.actor_def;
  ai_env_ref : env ref;
  mutable ai_state : value;
  mutable ai_alive : bool;
  mutable ai_terminal_reason : monitor_down_reason;
  mutable ai_monitors : (int * int) list;
  mutable ai_mailbox : value Queue.t;
  mutable ai_supervisor : int option;
  mutable ai_restart_count : (float * int) list;
  mutable ai_epoch : int;
  mutable ai_resources : (string * (unit -> unit)) list;
  mutable ai_linear_values : (value * value) list;
  mutable ai_mbox_limit : int;
  mutable ai_mbox_policy : int;
}

val actor_defs_tbl : (string, March_ast.Ast.actor_def * env ref) Hashtbl.t
val actor_registry : (int, actor_inst) Hashtbl.t
val pending_timers : timer_entry list ref
val named_registry : (string, int) Hashtbl.t
val reg_names_pending : (int, string list) Hashtbl.t

type dyn_child_entry = {
  dce_pid : int;
  dce_actor_name : string;
  dce_restart : string;
}

type dyn_sup_state = {
  ds_name : string;
  ds_strategy : string;
  ds_max_restarts : int;
  ds_window_secs : int;
  ds_vpid : int;
  mutable ds_children : dyn_child_entry list;
  mutable ds_restart_count : (float * int) list;
}

val dyn_sup_registry : (string, dyn_sup_state) Hashtbl.t
val dyn_sup_vpid_map : (int, string) Hashtbl.t

val spawn_child_actor : ?crashed_pid:int option -> string -> int -> int

(** [crash_actor pid reason] tears the actor down and runs whatever
    supervision applies — restart strategy, monitor DOWN messages, resource
    release — in the order the OTP semantics require. Prefer these over the
    private helpers behind them. *)
val crash_actor : int -> string -> unit

val crash_actor_with_reason : int -> string -> monitor_down_reason -> unit
val mailbox_enqueue : actor_inst -> value -> unit
val dropped_messages_count : int ref
val monitor_actor : watcher_pid:int -> target_pid:int -> int
val demonitor_actor : int -> unit
val register_resource_ocaml : int -> string -> (unit -> unit) -> unit

(** {1 Processes, pids and calls} *)

val next_pid : int ref
val next_monitor_id : int ref
val current_pid : int option ref
val process_registry : (string, int) Hashtbl.t
val pid_to_registry_name : (int, string) Hashtbl.t
val revocation_table : (int * int, unit) Hashtbl.t
val pending_replies : (int, value) Hashtbl.t
val next_call_ref : int ref
val process_start_time : float
val uname_info : (string * string) option Lazy.t
val live_proc_tbl : (int, in_channel * out_channel * int) Hashtbl.t
val live_proc_next_id : int ref

(** {1 Declaration tables populated at load time} *)

val impl_tbl : (string * string, value) Hashtbl.t
val ctor_type_tbl : (string, string) Hashtbl.t
val record_type_tbl : (string, string) Hashtbl.t
val ffi_type_decl_tbl : (string, March_ast.Ast.type_def) Hashtbl.t
val protocol_roles_tbl : (string, string list) Hashtbl.t

(** {1 Message tap} *)

val tap_mutex : Mutex.t
val tap_queue : value Queue.t
val tap_push : value -> unit

(** {1 Logger} *)

type log_value =
  | LogStr of string
  | LogInt of int
  | LogFloat of float
  | LogBool of bool
  | LogAtom of string
  | LogNull

val logger_level : int ref
val logger_fields : (string * log_value) list ref
val logger_appenders : (string * value) list ref
val logger_module_levels : (string, int) Hashtbl.t
val log_value_to_string : log_value -> string

(** {1 Captured output}

    When [test_capture_buf] holds a buffer, [capture_write] and friends append
    to it instead of writing to the real fd. This is how the test harness and
    the browser build intercept [print]. *)

val test_capture_buf : Buffer.t option ref
val capture_write : string -> unit
val capture_writeln : string -> unit
val capture_ewriteln : string -> unit

(** {1 Ring buffers} *)

val ring_create : int -> 'a ring
val ring_push : 'a ring -> 'a -> unit
val ring_get : 'a ring -> int -> 'a option
val ring_pop_oldest : 'a ring -> 'a option

(** {1 Interpreter control-flow exceptions} *)

exception Match_failure of string
exception Assert_failure of string
exception BlockedOnReceive

(** {1 Arithmetic and comparison dispatch}

    Each takes the per-type operation and the builtin's name (for the error
    message) and returns the builtin's [value]. *)

val arith_num :
  (int -> int -> int) -> (float -> float -> float) -> string -> value

val cmp_op :
  (int -> int -> bool) ->
  (float -> float -> bool) ->
  (string -> string -> bool) ->
  (bool -> bool -> bool) ->
  string ->
  value

(** {1 Hashing and sockets} *)

val march_hash_int64 : int64 -> int64
val march_hash_string64 : string -> int64
val recv_timeout_msg : string

val tcp_wait_readable :
  Unix.file_descr -> float option -> [ `Error of string | `Ready | `Timeout ]

(** {1 Program argv override} *)

val program_argv : string list option ref
