(** Interpreter runtime state and value-rendering helpers shared by the
    evaluator, the builtin table, and the protocol runtimes.

    Extracted verbatim from eval.ml — no behavior change.  This module
    exists because eval.ml depends on [Eval_net] / [Eval_builtins], so
    anything those modules need may no longer live in eval.ml. *)

open March_ast.Ast
open Eval_types
open Eval_prim

(** Vault: ETS-like in-memory key-value store.
    Each table is identified by an opaque integer handle.

    Concurrency design — sharded hash map with fine-grained locking:
    ─────────────────────────────────────────────────────────────────
    A vault_table is split into [vault_num_stripes] independent shards.
    Each shard is its own Hashtbl guarded by its own Mutex.

    Key → shard mapping: Hashtbl.hash(key_string) mod vault_num_stripes

    Properties:
    • Writes to different shards are fully parallel (no shared state).
    • Writes to the same shard serialize via that shard's Mutex.
    • vault_update reads under the lock, applies [f] outside the lock
      (so [f] may safely call other vault operations without deadlocking),
      then re-acquires the lock to commit. This is "optimistic": a concurrent
      write between the read and the commit would be seen as a lost-update in
      a truly parallel setting. In the cooperative interpreter this never
      happens; in compiled multi-threaded code callers should use explicit
      serialization for true atomicity.
    • vault_size acquires each shard's lock in turn for a consistent snapshot.

    In the cooperative single-threaded interpreter the Mutexes are always
    uncontended (near-zero overhead). They provide correct behavior when
    compiled March code eventually runs on real OS threads. *)

let vault_num_stripes = 16

type vault_row = {
  vr_value  : value;
  vr_expiry : float option;  (** None = permanent; Some t = Unix expiry time *)
}

type vault_shard = {
  vs_data  : (string, vault_row) Hashtbl.t;
  vs_mutex : Mutex.t;
}

type vault_table = {
  vt_id     : int;
  vt_name   : string;
  vt_shards : vault_shard array;  (** vault_num_stripes independent shards *)
}

(** Allocate a fresh vault_table with [vault_num_stripes] empty shards. *)
let vault_make_table (id : int) (name : string) : vault_table = {
  vt_id     = id;
  vt_name   = name;
  vt_shards = Array.init vault_num_stripes (fun _ ->
    { vs_data = Hashtbl.create 16; vs_mutex = Mutex.create () });
}

let vault_registry      : (int, vault_table) Hashtbl.t = Hashtbl.create 8
let vault_name_registry : (string, int) Hashtbl.t     = Hashtbl.create 8
let vault_next_id       : int ref = ref 0

(** Detect whether a VCon chain is a March list (Nil / Cons(h, t)). *)
let rec is_list_value = function
  | VCon ("Nil", []) -> true
  | VCon ("Cons", [_; t]) -> is_list_value t
  | _ -> false

let rec list_elems acc = function
  | VCon ("Nil", []) -> List.rev acc
  | VCon ("Cons", [h; t]) -> list_elems (h :: acc) t
  | v -> List.rev (v :: acc)  (* improper list — shouldn't happen *)

(** The user-facing display name for a [VCon]'s tag: strips any collision
    qualification (e.g. "DcA.Thing.Shared" -> "Shared") down to the bare
    ctor name a March programmer actually wrote, the same way [ECon]
    evaluation already strips an explicit `Type.Ctor` qualifier (e.g.
    `Result.Ok`) before ever constructing the value. A bare (non-colliding)
    tag has no '.' and is returned unchanged — byte-identical to before
    collision-qualified tags existed. Show/print output must never leak the
    internal qualified identity; only [==]/pattern-match/dispatch consult
    the raw (possibly-qualified) tag. *)
let display_tag (tag : string) : string =
  match String.rindex_opt tag '.' with
  | Some i -> String.sub tag (i + 1) (String.length tag - i - 1)
  | None -> tag

let rec value_to_string v =
  match v with
  | VInt n    -> string_of_int n
  | VFloat f  ->
    let s = string_of_float f in
    if String.contains s '.' || String.contains s 'e' then s
    else s ^ ".0"
  | VString s -> "\"" ^ String.escaped s ^ "\""
  | VBool b   -> string_of_bool b
  | VAtom a   -> ":" ^ a
  | VUnit     -> "()"
  | VTuple vs ->
    "(" ^ String.concat ", " (List.map value_to_string vs) ^ ")"
  | VRecord fields ->
    "{ " ^ String.concat ", "
      (List.map (fun (k, v) -> k ^ ": " ^ value_to_string v) fields)
    ^ " }"
  | VCon ("Nil", []) -> "[]"
  | VCon ("Cons", _) as v when is_list_value v ->
    "[" ^ String.concat ", " (List.map value_to_string (list_elems [] v)) ^ "]"
  | VCon (tag, []) -> display_tag tag
  | VCon (tag, args) ->
    display_tag tag ^ "(" ^ String.concat ", " (List.map value_to_string args) ^ ")"
  | VClosure _  -> "<fn>"
  | VBuiltin (n, _) ->
    let is_rec = String.length n >= 5 && String.sub n 0 5 = "<rec:" in
    if is_rec then "<fn>" else "<builtin:" ^ n ^ ">"
  | VPid pid -> "Pid(" ^ string_of_int pid ^ ")"
  | VTask id -> Printf.sprintf "<task:%d>" id
  | VCancelToken r -> Printf.sprintf "<cancel_token:%s>" (if !r then "cancelled" else "active")
  | VTimerRef t -> Printf.sprintf "<timer_ref:%s>" (if t.tt_cancelled then "cancelled" else "pending")
  | VWorkPool -> "<work_pool>"
  | VCap (pid, epoch) -> Printf.sprintf "Cap(%d, epoch=%d)" pid epoch
  | VActorId pid -> Printf.sprintf "ActorId(%d)" pid
  | VChan ce ->
    Printf.sprintf "Chan(%s#%d, %s)" ce.ce_proto ce.ce_id ce.ce_role
  | VMChan me ->
    Printf.sprintf "MChan(%s#%d, %s)" me.me_proto me.me_id me.me_role
  | VForeign (lib, sym, _, _, _) ->
    Printf.sprintf "<foreign:%s:%s>" lib sym
  | VMultiarity variants ->
    let arities = List.map (fun (a, _) -> string_of_int a) variants in
    Printf.sprintf "<fn/%s>" (String.concat "|" arities)
  | VNativeIntArr a ->
    let n = Array.length a in
    if n <= 8 then
      "NativeIntArr[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
    else
      Printf.sprintf "NativeIntArr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> string_of_int a.(i))))
  | VNativeFloatArr a ->
    let n = Array.length a in
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    if n <= 8 then
      "NativeFloatArr[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
    else
      Printf.sprintf "NativeFloatArr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> fmt a.(i))))
  | VNativeF32Arr a ->
    let n = Array.length a in
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    if n <= 8 then
      "NativeF32Arr[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
    else
      Printf.sprintf "NativeF32Arr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> fmt a.(i))))
  | VNativeI32Arr a ->
    let n = Array.length a in
    if n <= 8 then
      "NativeI32Arr[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
    else
      Printf.sprintf "NativeI32Arr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> string_of_int a.(i))))
  | VNativeU8Arr a ->
    let n = Array.length a in
    if n <= 8 then
      "NativeU8Arr[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
    else
      Printf.sprintf "NativeU8Arr(%d)[%s, ...]" n
        (String.concat ", " (List.init 4 (fun i -> string_of_int a.(i))))
  | VF32x4 a ->
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    "F32x4[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
  | VF64x2 a ->
    let fmt f = let s = string_of_float f in
                if String.contains s '.' || String.contains s 'e' then s else s ^ ".0" in
    "F64x2[" ^ String.concat ", " (Array.to_list (Array.map fmt a)) ^ "]"
  | VI32x4 a ->
    "I32x4[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
  | VI64x2 a ->
    "I64x2[" ^ String.concat ", " (Array.to_list (Array.map Int64.to_string a)) ^ "]"
  | VU8x16 a ->
    "U8x16[" ^ String.concat ", " (Array.to_list (Array.map string_of_int a)) ^ "]"
  | VTypedArray arr ->
    let elems = Array.to_list arr in
    "[|" ^ String.concat ", " (List.map value_to_string elems) ^ "|]"
  | VVaultHandle id ->
    (match Hashtbl.find_opt vault_registry id with
     | Some t -> Printf.sprintf "Vault(\"%s\"#%d)" t.vt_name id
     | None   -> Printf.sprintf "Vault(#%d)" id)
  | VRingBuf r ->
    Printf.sprintf "RingBuf(size=%d, cap=%d)" r.rb_size r.rb_cap
  | VResource _ -> "#<resource>"


(* ── Moved verbatim from eval.ml (Task 1.3) so that eval_builtins.ml
   can see them: eval.ml now depends on Eval_builtins, so the builtin
   table's helpers and the runtime state they close over may no longer
   live in eval.ml.  Order of definitions is unchanged. ── *)

type monitor_down_reason = Normal | Killed | Crash of string

type actor_inst = {
  ai_name    : string;           (** Actor type name, e.g. "Counter" *)
  ai_def     : actor_def;
  ai_env_ref : env ref;         (** Module environment at spawn time *)
  mutable ai_state    : value;
  mutable ai_alive    : bool;
  mutable ai_terminal_reason : monitor_down_reason;
  (* Phase 1: supervision infrastructure *)
  mutable ai_monitors : (int * int) list;   (** (monitor_ref, watcher_pid) pairs *)
  mutable ai_mailbox  : value Queue.t;      (** pending Down/Crashed messages *)
  (* Phase 2: supervisor support *)
  mutable ai_supervisor : int option;        (** pid of supervising actor, if any *)
  mutable ai_restart_count : (float * int) list; (** (timestamp, count) restart history *)
  (* Phase 3: epoch-based capability tracking *)
  mutable ai_epoch    : int;                 (** monotonically increasing restart epoch *)
  (* Phase 6a: OS resource cleanup *)
  mutable ai_resources : (string * (unit -> unit)) list;
  (** Named cleanup thunks acquired in order, cleaned in reverse on crash. *)
  (* Phase 6b: linear value drop handlers *)
  mutable ai_linear_values : (value * value) list;
  (** Linear values owned by this actor: (value, drop_fn) pairs in acquisition order.
      drop_fn is a March callable (VClosure or VBuiltin) : value -> value.
      Walked in reverse and called at crash time (Phase 6b). *)
  (* Task 9: bounded mailboxes — Actor.set_queue_limit surface.
     mbox_limit <= 0 means unbounded (default). mbox_policy: 0 unbounded,
     1 drop_new, 2 drop_old, 3 block (the interpreter's single-threaded
     eager scheduler cannot park a sender without deadlocking, so block is
     treated as unbounded here — see stdlib/actor.march's doc string). *)
  mutable ai_mbox_limit  : int;
  mutable ai_mbox_policy : int;
}

(** Actor definitions registered by [DActor] — reset per module eval. *)
let actor_defs_tbl : (string, actor_def * env ref) Hashtbl.t = Hashtbl.create 8

(** Live actor instances — reset per module eval. *)
let actor_registry  : (int, actor_inst) Hashtbl.t = Hashtbl.create 16

(** Pending [send_after] timers (specs/progress/2026-08-12-language-level-
    timers.md) — reset per module eval, same lifecycle as [actor_registry].
    Serviced by [timer_service_tick]. *)
let pending_timers : timer_entry list ref = ref []

(** Named registry (Task 4): name -> pid, mirroring the runtime's
    march_actor_register/unregister/whereis/registered C API. Reset per
    module eval, same lifecycle as [actor_registry]. Semantics matched to
    the C side: register fails if the name is held by a LIVE actor or if
    the registering actor is itself dead; whereis re-checks [ai_alive] at
    lookup time (a stale entry for a dead actor resolves to None) rather
    than requiring proactive cleanup on death. *)
let named_registry  : (string, int) Hashtbl.t = Hashtbl.create 16

(** Registry carry-forward stash: pid of a dying actor -> the names it held
    in [named_registry] at the moment of death. Mirrors the runtime's
    [march_actor_meta.reg_names_pending] (see
    runtime/march_runtime.c:capture_reg_names_pending), keyed by pid rather
    than hung off a meta record because the interpreter has no per-actor
    meta that outlives the instance — pids are handed out monotonically from
    [next_pid] and never reused, so a pid key is as stable as the C side's
    never-freed meta.

    Populated by [capture_reg_names_pending] and consumed exactly once by
    [spawn_child_actor] when it replaces that pid. An entry left behind
    (actor died supervised but the supervisor gave up rather than
    respawning, e.g. max_restarts exceeded) is inert: nothing reads it, and
    it dies with the table on the next module eval. *)
let reg_names_pending : (int, string list) Hashtbl.t = Hashtbl.create 8

(** Snapshot [pid]'s registered names into [reg_names_pending] so a restart
    can re-establish them on the replacement, before [crash_actor] drops
    them from [named_registry].

    Two call sites, matching the runtime's two:
      - [crash_actor], for an actor dying with [ai_supervisor] still set;
      - [one_for_all_restart] / [rest_for_one_restart], explicitly, for each
        LIVE SIBLING they are about to kill and respawn. Those two set
        [ci.ai_supervisor <- None] before crashing the sibling — solely to
        stop [crash_actor] re-entering [notify_supervisor] for it — so by
        the time [crash_actor] runs, its own supervisor gate is already
        false. Gating capture on the supervisor field ALONE therefore drops
        every batch-restarted sibling's names, even though the sibling is
        unconditionally respawned a few lines later. That exact bug shipped
        on the compiled side and was caught in review; test/native/
        actor_registry_restart_batch.march is its regression test.

    Guards an existing stash rather than overwriting it, mirroring the C
    side: no current caller can run twice for one pid, but a future one
    doing so should not lose the first snapshot. *)
let capture_reg_names_pending (pid : int) : unit =
  if not (Hashtbl.mem reg_names_pending pid) then begin
    let names =
      Hashtbl.fold (fun name owner acc -> if owner = pid then name :: acc else acc)
        named_registry []
    in
    if names <> [] then Hashtbl.replace reg_names_pending pid names
  end

(* ------------------------------------------------------------------ *)
(* Dynamic Supervisor state                                            *)
(* ------------------------------------------------------------------ *)

(** One child entry inside a dynamic supervisor. *)
type dyn_child_entry = {
  dce_pid        : int;
  dce_actor_name : string;
  dce_restart    : string;  (** "permanent" | "transient" | "temporary" *)
}

(** Runtime state for a dynamic supervisor (no static actor_def). *)
type dyn_sup_state = {
  ds_name           : string;  (** atom name, e.g. "connections" *)
  ds_strategy       : string;  (** "one_for_one" (only strategy supported now) *)
  ds_max_restarts   : int;
  ds_window_secs    : int;
  ds_vpid           : int;     (** negative virtual pid used as ai_supervisor *)
  mutable ds_children      : dyn_child_entry list;
  mutable ds_restart_count : (float * int) list;
}

(** Dynamic supervisor registry: atom name → state. Reset per module eval. *)
let dyn_sup_registry   : (string, dyn_sup_state) Hashtbl.t = Hashtbl.create 4

(** Virtual-pid → atom name mapping (for crash_actor dispatch). *)
let dyn_sup_vpid_map   : (int, string) Hashtbl.t = Hashtbl.create 4

(** Live-process registry for Process.spawn (async, non-blocking).
    Maps an opaque integer id → (in_channel, out_channel, pid). *)
let live_proc_tbl : (int, in_channel * out_channel * int) Hashtbl.t = Hashtbl.create 8

let live_proc_next_id : int ref = ref 0

(** Monotonic start time for sys_uptime_ms calculations. *)
let process_start_time : float = Unix.gettimeofday ()

(** Cached uname output for sys_os / sys_arch: (os_name, arch_name). *)
let uname_info : (string * string) option Lazy.t = lazy (
  try
    let ic = Unix.open_process_in "uname -sm 2>/dev/null" in
    let s = (try input_line ic with End_of_file -> "") in
    let _ = Unix.close_process_in ic in
    match String.split_on_char ' ' (String.trim s) with
    | [os; arch] -> Some (String.lowercase_ascii os, String.lowercase_ascii arch)
    | _ -> None
  with _ -> None)

(** True if a row is still live (not expired). *)
let vault_row_live (row : vault_row) : bool =
  match row.vr_expiry with
  | None   -> true
  | Some t -> Unix.gettimeofday () < t

(** Interface implementation table — maps (iface_name, type_name) to the method value.
    Populated when [eval_decl] processes [DImpl] nodes.
    Reset per module eval via [reset_scheduler_state]. *)
let impl_tbl : (string * string, value) Hashtbl.t = Hashtbl.create 8

(** Constructor → type name mapping.
    Maps each data constructor name (e.g. "Red") to its declaring type (e.g. "Color").
    Populated when [eval_decl] processes [DType] nodes.
    Used by [==] and interface method dispatch to look up Eq/Ord/Hash/Show impls. *)
let ctor_type_tbl : (string, string) Hashtbl.t = Hashtbl.create 16

(** Record field-set → type name mapping.
    Maps a canonical key (sorted, comma-joined field names) to the declaring type name.
    Populated when [eval_decl] processes [DType] nodes with [TDRecord].
    Used by Json derive dispatch to identify record types at runtime. *)
let record_type_tbl : (string, string) Hashtbl.t = Hashtbl.create 8

(** Type name → type definition mapping for FFI marshalling.
    Populated when [eval_decl] processes [DType] nodes.
    Used by ffi_marshal_field/unmarshal to look up record fields and ctor args. *)
let ffi_type_decl_tbl : (string, March_ast.Ast.type_def) Hashtbl.t = Hashtbl.create 16

(** Protocol → sorted role list mapping.
    Populated when [eval_decl] processes [DProtocol] nodes.
    Used by [MPST.new] to know how many endpoints to create and their names. *)
let protocol_roles_tbl : (string, string list) Hashtbl.t = Hashtbl.create 8

(** The global tap queue.  Threads push values here via [tap]; the REPL
    drains it after each expression evaluation to display tapped values. *)
let tap_mutex : Mutex.t = Mutex.create ()

let tap_queue : value Queue.t = Queue.create ()

(** Push [v] onto the tap bus.  Thread-safe: may be called from actor threads. *)
let tap_push (v : value) : unit =
  Mutex.lock tap_mutex;
  Queue.push v tap_queue;
  Mutex.unlock tap_mutex

let next_pid        : int ref = ref 0

let next_monitor_id : int ref = ref 0

(** Process registry: atom name → pid for named supervision children. *)
let process_registry : (string, int) Hashtbl.t = Hashtbl.create 8

(** Reverse map: pid → registered atom name (for re-registration on restart). *)
let pid_to_registry_name : (int, string) Hashtbl.t = Hashtbl.create 8

(** Explicit capability revocation table.
    Maps [(pid, epoch)] pairs that have been revoked via [revoke_cap].
    A cap is invalid if its (pid, epoch) is in this table OR if
    the actor's current epoch differs (implying a restart occurred). *)
let revocation_table : (int * int, unit) Hashtbl.t = Hashtbl.create 4

(* Numeric levels.  v1: 0=Debug 1=Info 2=Warn 3=Error.  v2 adds
   Trace=-1 below Debug and Fatal=4 above Error.  Default: Info. *)
let logger_level : int ref = ref 1

(* Mirrors March's `LogValue` ADT for runtime context storage. *)
type log_value =
  | LogStr of string
  | LogInt of int
  | LogFloat of float
  | LogBool of bool
  | LogAtom of string  (* atom name without leading colon *)
  | LogNull

(* Field stack: most-recent push at HEAD.  `with_scope` records depth
   on entry and truncates back to it on exit (via try_finally). *)
let logger_fields : (string * log_value) list ref = ref []

(* Appender registry: ordered list of (name, March callback).  When
   `logger_dispatch` fires a log entry, every registered appender's
   callback is invoked with the entry value.  Empty list ⇒ fall back
   to direct stderr write (preserves v1 behaviour for users who
   haven't configured appenders).

   The callback is a March function value of type `LogEntry -> Unit`.
   We invoke it via `apply_hook` (set after `apply` is defined). *)
let logger_appenders : (string * value) list ref = ref []

(* Per-module level overrides: `set_module_level("MyApp", Debug)` adds
   an entry; `level_for("MyApp")` consults this map first, then falls
   back to `logger_level`.  Module name "" is the default that applies
   when no override is registered. *)
let logger_module_levels : (string, int) Hashtbl.t = Hashtbl.create 8

(* Best-effort string representation of a LogValue for v1 shim consumers. *)
let log_value_to_string = function
  | LogStr s   -> s
  | LogInt n   -> string_of_int n
  | LogFloat f -> string_of_float f
  | LogBool b  -> if b then "true" else "false"
  | LogAtom a  -> ":" ^ a
  | LogNull    -> "null"

(* ---- Test output capture ---- *)

(* When Some buf, all print/log output is redirected here instead of stdout/stderr.
   Set by run_tests around each test body; None during normal execution. *)
let test_capture_buf : Buffer.t option ref = ref None

(* Flushed on every call, not just at exit: a long-running program (e.g. an
   HTTP server started via `forge run`, interpreted rather than compiled)
   writes print/println output through here on every request. Without an
   explicit flush, OCaml's stdout channel buffers silently until the process
   exits — logs redirected to a file or pipe (`forge run > server.log 2>&1`)
   never appear until the process is killed, even though the same program
   looks fine interactively (a terminal's own line-buffering can mask the
   channel-level buffering underneath). Mirrors capture_ewriteln below, which
   already flushes on every call for the same reason. *)
let capture_write (s : string) : unit =
  match !test_capture_buf with
  | Some buf -> Buffer.add_string buf s
  | None -> print_string s; flush stdout

let capture_writeln (s : string) : unit =
  match !test_capture_buf with
  | Some buf -> Buffer.add_string buf s; Buffer.add_char buf '\n'
  | None -> print_endline s; flush stdout

(* Logger output goes to stderr normally; redirect to capture buf during tests. *)
let capture_ewriteln (s : string) : unit =
  match !test_capture_buf with
  | Some buf -> Buffer.add_string buf s; Buffer.add_char buf '\n'
  | None -> Printf.eprintf "%s\n%!" s

(* ---- Actor.call reply tracking ---- *)

(* Pending synchronous call replies: call_ref -> reply value. *)
let pending_replies : (int, value) Hashtbl.t = Hashtbl.create 4

let next_call_ref : int ref = ref 0

(** Pid of the actor whose handler is currently executing.
    Set by [run_scheduler] when entering a handler; used by [self] and [receive]. *)
let current_pid : int option ref = ref None

(* ------------------------------------------------------------------ *)
(* Ring buffer helpers                                                 *)
(* ------------------------------------------------------------------ *)

let ring_create cap =
  { rb_arr = Array.make cap None; rb_head = 0; rb_size = 0; rb_cap = cap }

let ring_push r x =
  r.rb_arr.(r.rb_head) <- Some x;
  r.rb_head <- (r.rb_head + 1) mod r.rb_cap;
  if r.rb_size < r.rb_cap then r.rb_size <- r.rb_size + 1

(** [ring_get r i] returns entry at logical index i (0 = most recent). *)
let ring_get r i =
  if i < 0 || i >= r.rb_size then None
  else
    let idx = ((r.rb_head - 1 - i) + r.rb_cap * 2) mod r.rb_cap in
    r.rb_arr.(idx)

(** [ring_pop_oldest r] removes and returns the oldest element (FIFO head).
    Clears the slot for GC. Returns None if empty. *)
let ring_pop_oldest r =
  if r.rb_size = 0 then None
  else begin
    let idx = ((r.rb_head - r.rb_size) + r.rb_cap * 2) mod r.rb_cap in
    let v = r.rb_arr.(idx) in
    r.rb_arr.(idx) <- None;
    r.rb_size <- r.rb_size - 1;
    v
  end

(* ------------------------------------------------------------------ *)
(* Debug trace types                                                   *)
(* ------------------------------------------------------------------ *)

exception Match_failure of string

(** Raised when an [assert] expression fails during test execution.
    Carries a human-readable failure message. *)
exception Assert_failure of string

(** Raised by [receive()] when the actor's mailbox is empty.
    The scheduler catches this and re-queues the triggering message at the
    front of the mailbox so the handler can retry when a sub-message arrives. *)
exception BlockedOnReceive

(* ------------------------------------------------------------------ *)
(* March call stack for backtraces                                     *)
(* ------------------------------------------------------------------ *)

(** Decode an internal vault key string back to a March value.
    Mirrors vault_key_of_value.  Complex keys (Tuple, Ctor) are returned
    as raw VString; simple scalar keys are fully reconstructed. *)
let vault_decode_key (k : string) : value =
  let n = String.length k in
  if n >= 2 && k.[1] = ':' then
    let rest2 = String.sub k 2 (n - 2) in
    (match k.[0] with
     | 'i' -> (try VInt (int_of_string rest2) with _ -> VString k)
     | 'f' -> (try VFloat (float_of_string rest2) with _ -> VString k)
     | 'b' -> VBool (rest2 = "true")
     | 'a' -> VAtom rest2
     | 'u' -> VUnit
     | 's' ->
       (* "s:<len>:<str>" — find the colon separating length from content *)
       (match String.index_opt rest2 ':' with
        | None -> VString k
        | Some i ->
          VString (String.sub rest2 (i + 1) (String.length rest2 - i - 1)))
     | _ -> VString k)  (* Tuple/Ctor: return as raw string *)
  else VString k

(** Canonical string key for a March value used in vault tables.
    Panics if called with a non-serialisable value (function, pid, …). *)
let rec vault_key_of_value (v : value) : string =
  match v with
  | VInt n    -> Printf.sprintf "i:%d" n
  | VFloat f  -> Printf.sprintf "f:%h" f
  | VString s -> Printf.sprintf "s:%d:%s" (String.length s) s
  | VBool b   -> if b then "b:true" else "b:false"
  | VAtom a   -> Printf.sprintf "a:%s" a
  | VUnit     -> "u:"
  | VTuple vs ->
    Printf.sprintf "t:(%s)" (String.concat "," (List.map vault_key_of_value vs))
  | VCon (tag, []) -> Printf.sprintf "c:%s" tag
  | VCon (tag, args) ->
    Printf.sprintf "c:%s(%s)" tag (String.concat "," (List.map vault_key_of_value args))
  | _ ->
    eval_error "Vault: key must be a plain value (Int/String/Bool/Atom/Tuple/Ctor), got %s"
      (match v with
       | VClosure _ | VBuiltin _ -> "a function"
       | VPid _         -> "a Pid"
       | VTask _        -> "a Task"
       | VCancelToken _ -> "a CancelToken"
       | VTimerRef _    -> "a TimerRef"
       | _              -> "an unsupported value")

(** Resolve a vault handle; panics with a clear message on bad handles. *)
let vault_lookup (id : int) : vault_table =
  match Hashtbl.find_opt vault_registry id with
  | None     -> eval_error "Vault: invalid table handle %d" id
  | Some tbl -> tbl

(** Return the shard responsible for the pre-computed key string [k].
    Uses the string's structural hash masked to a non-negative value. *)
let vault_shard_for (k : string) (shards : vault_shard array) : vault_shard =
  let h = Hashtbl.hash k land 0x7FFFFFFF in
  shards.(h mod vault_num_stripes)

(* ------------------------------------------------------------------ *)
(* Pattern matching                                                    *)
(* ------------------------------------------------------------------ *)

let arith_num iop fop name = VBuiltin (name, function
    | [VInt a;   VInt b]   -> VInt   (iop a b)
    | [VFloat a; VFloat b] -> VFloat (fop a b)
    | _ -> eval_error "builtin %s: expected two numbers of the same type" name)

(** Look up the type name for a runtime value.
    Used by interface dispatch in [==], [eq], [compare], [show], [hash]. *)
let type_name_of_value = function
  | VInt _    -> Some "Int"
  | VFloat _  -> Some "Float"
  | VString _ -> Some "String"
  | VBool _   -> Some "Bool"
  | VCon (tag, _) -> Hashtbl.find_opt ctor_type_tbl tag
  | VRecord fields ->
    (* Look up record type by its field names *)
    let field_names = List.map fst fields in
    let key = String.concat "," (List.sort String.compare field_names) in
    Hashtbl.find_opt record_type_tbl key
  | _         -> None

let cmp_op op_i op_f op_s op_b name = VBuiltin (name, function
    | [VInt a;    VInt b]    -> VBool (op_i a b)
    | [VFloat a;  VFloat b]  -> VBool (op_f a b)
    | [VString a; VString b] -> VBool (op_s a b)
    | [VBool a;   VBool b]   -> VBool (op_b a b)
    | [a; b] when (name = "==" || name = "!=") ->
      (* For == and !=, look up the Eq impl if available. *)
      let eq_result = match type_name_of_value a with
        | Some tname ->
          (match Hashtbl.find_opt impl_tbl ("Eq", tname) with
           | Some eq_fn -> Some (!iface_dispatch_hook eq_fn [a; b])
           | None       -> None)
        | None -> None
      in
      (match eq_result with
       | Some (VBool b_result) ->
         VBool (if name = "!=" then not b_result else b_result)
       | _ ->
         (* No Eq impl found — fall back to structural OCaml equality *)
         VBool (if name = "==" then a = b else a <> b))
    | [a; b] when (name = "<" || name = "<=" || name = ">" || name = ">=") ->
      (* For ordering operators, look up the Ord impl if available. *)
      let cmp_result = match type_name_of_value a with
        | Some tname ->
          (match Hashtbl.find_opt impl_tbl ("Ord", tname) with
           | Some cmp_fn -> Some (!iface_dispatch_hook cmp_fn [a; b])
           | None        -> None)
        | None -> None
      in
      (match cmp_result with
       | Some (VInt n) ->
         VBool (match name with
                | "<"  -> n < 0
                | "<=" -> n <= 0
                | ">"  -> n > 0
                | ">=" -> n >= 0
                | _    -> false)
       | _ ->
         eval_error "builtin %s: no `Ord` implementation for this type" name)
    | [a; b] ->
      let type_of v = match v with
        | VInt _    -> "Int"    | VFloat _  -> "Float" | VString _ -> "String"
        | VBool _   -> "Bool"   | VAtom _   -> "Atom"  | VUnit     -> "Unit"
        | VTuple _  -> "Tuple"  | VRecord _ -> "Record"
        | VCon (t, _) -> t      | _         -> "value"
      in
      eval_error "builtin %s: cannot compare a %s with a %s — these types are not comparable"
        name (type_of a) (type_of b)
    | _ -> eval_error "builtin %s: expected two comparable values" name)

(** print/println use a display form (no quotes around strings). *)
let value_display v =
  match v with
  | VString s -> s
  | _         -> value_to_string v

let monitor_down_value = function
  | Normal -> VCon ("Normal", [])
  | Killed -> VCon ("Killed", [])
  | Crash msg -> VCon ("Crash", [VString msg])

let monitor_down_message mon_ref target_pid reason =
  VCon ("Down", [VInt mon_ref; VPid target_pid; monitor_down_value reason])

let fresh_monitor_id () =
  let id = !next_monitor_id in
  next_monitor_id := id + 1;
  id

(** Spawn a fresh child actor instance (for supervisor restarts).
    [crashed_pid] is the pid of the actor being replaced; its epoch is
    inherited and incremented so that old VCap values become stale.
    Returns the new pid. *)
let spawn_child_actor ?(crashed_pid : int option = None) (child_actor_name : string) (supervisor_pid : int) : int =
  match Hashtbl.find_opt actor_defs_tbl child_actor_name with
  | None -> eval_error "restart: unknown child actor '%s'" child_actor_name
  | Some (child_def, child_env_ref) ->
    let child_init_state = !eval_expr_hook !child_env_ref child_def.actor_init in
    let child_pid = !next_pid in
    next_pid := child_pid + 1;
    (* Inherit epoch from crashed actor + 1 for proper stale-cap detection. *)
    let inherited_epoch = match crashed_pid with
      | None -> 0
      | Some old_pid ->
        (match Hashtbl.find_opt actor_registry old_pid with
         | Some old_inst -> old_inst.ai_epoch + 1
         | None -> 1)
    in
    let child_inst = {
      ai_name = child_actor_name; ai_def = child_def;
      ai_env_ref = child_env_ref;
      ai_state = child_init_state; ai_alive = true;
      ai_terminal_reason = Normal;
      ai_monitors = []; ai_mailbox = Queue.create ();
      ai_supervisor = Some supervisor_pid;
      ai_restart_count = []; ai_epoch = inherited_epoch;
      ai_resources = [];
      ai_linear_values = [];
      ai_mbox_limit = 0; ai_mbox_policy = 0 } in
    Hashtbl.add actor_registry child_pid child_inst;
    (* Re-register in process registry if the crashed actor had a name *)
    (match crashed_pid with
     | None -> ()
     | Some old_pid ->
       (match Hashtbl.find_opt pid_to_registry_name old_pid with
        | None -> ()
        | Some name ->
          Hashtbl.remove pid_to_registry_name old_pid;
          Hashtbl.replace process_registry name child_pid;
          Hashtbl.replace pid_to_registry_name child_pid name));
    (* Carry the crashed incarnation's [named_registry] names forward onto
       the replacement (mirrors march_respawn_child's reg_names_pending
       consume). Each name is decided individually by the same "first live
       claim wins" rule [actor_register] enforces: if some OTHER live actor
       claimed that exact name during the restart window, the carried
       registration is DROPPED rather than stealing it back — that is the
       registry's normal contract, not an error, so it isn't reported. *)
    (match crashed_pid with
     | None -> ()
     | Some old_pid ->
       (match Hashtbl.find_opt reg_names_pending old_pid with
        | None -> ()
        | Some names ->
          Hashtbl.remove reg_names_pending old_pid;
          List.iter (fun name ->
            let held_by_live_other =
              match Hashtbl.find_opt named_registry name with
              | Some owner when owner <> child_pid ->
                (match Hashtbl.find_opt actor_registry owner with
                 | Some inst -> inst.ai_alive
                 | None      -> false)
              | _ -> false
            in
            if not held_by_live_other then
              Hashtbl.replace named_registry name child_pid) names));
    child_pid

(** Restart a supervisor's crashed child under one_for_one strategy.
    Finds which field in the supervisor state held the crashed pid,
    spawns a new child, and updates the supervisor's state. *)
let rec one_for_one_restart (sup_pid : int) (crashed_pid : int) : unit =
  match Hashtbl.find_opt actor_registry sup_pid with
  | None -> crash_actor sup_pid "supervisor lost"
  | Some sup_inst ->
    (match sup_inst.ai_def.actor_supervise with
     | None -> ()
     | Some sup_cfg ->
       (* Find which child field had crashed_pid *)
       let crashed_field = match sup_inst.ai_state with
         | VRecord fields ->
           List.find_opt (fun (_, v) -> v = VInt crashed_pid) fields
           |> Option.map fst
         | _ -> None
       in
       (match crashed_field with
        | None -> ()
        | Some fname ->
          (* Find the actor type for this field *)
          let child_type_opt = List.find_opt (fun sf -> sf.sf_name.txt = fname)
                                 sup_cfg.sc_fields in
          (match child_type_opt with
           | None -> ()
           | Some sf ->
             let child_actor_name = match sf.sf_ty with
               | TyCon (n, []) -> n.txt
               | _ -> ""
             in
             if child_actor_name <> "" then begin
               (* Check max_restarts window *)
               let now = Unix.gettimeofday () in
               let window = float_of_int sup_cfg.sc_window_secs in
               let recent = List.filter (fun (ts, _) -> now -. ts < window)
                              sup_inst.ai_restart_count in
               let restart_count = List.fold_left (fun acc (_, n) -> acc + n) 0 recent in
               if restart_count >= sup_cfg.sc_max_restarts then begin
                 (* Exceeded max_restarts — crash the supervisor *)
                 crash_actor sup_pid "max_restarts exceeded"
               end else begin
                 (* Update restart history *)
                 sup_inst.ai_restart_count <- recent @ [(now, 1)];
                 (* Spawn a new child, inheriting epoch from crashed actor *)
                 let new_pid = spawn_child_actor ~crashed_pid:(Some crashed_pid) child_actor_name sup_pid in
                 (* Update the supervisor's state record *)
                 (match sup_inst.ai_state with
                  | VRecord fields ->
                    sup_inst.ai_state <- VRecord (List.map (fun (k, v) ->
                      if k = fname then (k, VInt new_pid) else (k, v)) fields)
                  | _ -> ())
               end
             end)))

(** Restart under one_for_all: kill all siblings, then respawn all children. *)
and one_for_all_restart (sup_pid : int) (_crashed_pid : int) : unit =
  match Hashtbl.find_opt actor_registry sup_pid with
  | None -> ()
  | Some sup_inst ->
    (match sup_inst.ai_def.actor_supervise with
     | None -> ()
     | Some sup_cfg ->
       let now = Unix.gettimeofday () in
       let window = float_of_int sup_cfg.sc_window_secs in
       let recent = List.filter (fun (ts, _) -> now -. ts < window)
                      sup_inst.ai_restart_count in
       let restart_count = List.fold_left (fun acc (_, n) -> acc + n) 0 recent in
       if restart_count >= sup_cfg.sc_max_restarts then begin
         crash_actor sup_pid "max_restarts exceeded"
       end else begin
         sup_inst.ai_restart_count <- recent @ [(now, 1)];
         (* Kill all children that are still alive *)
         let all_child_pids = match sup_inst.ai_state with
           | VRecord fields ->
             List.filter_map (fun (_, v) -> match v with VInt p -> Some p | _ -> None) fields
           | _ -> []
         in
         List.iter (fun cpid ->
           match Hashtbl.find_opt actor_registry cpid with
           | Some ci when ci.ai_alive ->
             (* Capture BEFORE the detach below: clearing [ai_supervisor]
                makes crash_actor's own capture gate false, and this sibling
                is unconditionally respawned a few lines down. *)
             capture_reg_names_pending cpid;
             ci.ai_supervisor <- None;  (* detach before crashing to prevent re-entry *)
             crash_actor cpid "one_for_all restart"
           | _ -> ()
         ) all_child_pids;
         (* Respawn all children in order, inheriting epoch from old pids *)
         let new_state = match sup_inst.ai_state with
           | VRecord fields ->
             let new_fields = List.map (fun (fname, old_val) ->
               match List.find_opt (fun sf -> sf.sf_name.txt = fname) sup_cfg.sc_fields with
               | None -> (fname, VInt 0)
               | Some sf ->
                 let child_actor_name = match sf.sf_ty with
                   | TyCon (n, []) -> n.txt | _ -> "" in
                 if child_actor_name = "" then (fname, VInt 0)
                 else
                   let old_pid = match old_val with VInt p -> Some p | _ -> None in
                   (fname, VInt (spawn_child_actor ~crashed_pid:old_pid child_actor_name sup_pid))
             ) fields in
             VRecord new_fields
           | other -> other
         in
         sup_inst.ai_state <- new_state
       end)

(** Restart under rest_for_one: kill children ordered after the crashed one,
    then respawn only those. *)
and rest_for_one_restart (sup_pid : int) (crashed_pid : int) : unit =
  match Hashtbl.find_opt actor_registry sup_pid with
  | None -> ()
  | Some sup_inst ->
    (match sup_inst.ai_def.actor_supervise with
     | None -> ()
     | Some sup_cfg ->
       let now = Unix.gettimeofday () in
       let window = float_of_int sup_cfg.sc_window_secs in
       let recent = List.filter (fun (ts, _) -> now -. ts < window)
                      sup_inst.ai_restart_count in
       let restart_count = List.fold_left (fun acc (_, n) -> acc + n) 0 recent in
       if restart_count >= sup_cfg.sc_max_restarts then begin
         crash_actor sup_pid "max_restarts exceeded"
       end else begin
         sup_inst.ai_restart_count <- recent @ [(now, 1)];
         (* Find the index of the crashed child in declaration order *)
         let order = List.map (fun n -> n.txt) sup_cfg.sc_order in
         let crashed_fname = match sup_inst.ai_state with
           | VRecord fields ->
             (match List.find_opt (fun (_, v) -> v = VInt crashed_pid) fields with
              | Some (k, _) -> k | None -> "")
           | _ -> ""
         in
         let crashed_idx =
           let rec find_idx i = function
             | [] -> -1
             | x :: _ when x = crashed_fname -> i
             | _ :: rest -> find_idx (i + 1) rest
           in find_idx 0 order
         in
         if crashed_idx >= 0 then begin
           (* Kill siblings that come after the crashed child *)
           let rest_names = List.filteri (fun i _ -> i > crashed_idx) order in
           List.iter (fun fname ->
             let cpid = match sup_inst.ai_state with
               | VRecord fields ->
                 (match List.assoc_opt fname fields with Some (VInt p) -> p | _ -> -1)
               | _ -> -1
             in
             if cpid >= 0 then
               (match Hashtbl.find_opt actor_registry cpid with
                | Some ci when ci.ai_alive ->
                  (* Same reason as one_for_all_restart's identical call:
                     capture before the detach, or this sibling's names are
                     lost even though it is respawned below. *)
                  capture_reg_names_pending cpid;
                  ci.ai_supervisor <- None;
                  crash_actor cpid "rest_for_one restart"
                | _ -> ())
           ) rest_names;
           (* Respawn crashed child + rest in order, inheriting epoch from old pids *)
           let to_respawn = List.filteri (fun i _ -> i >= crashed_idx) order in
           let new_state = match sup_inst.ai_state with
             | VRecord fields ->
               let updated = List.fold_left (fun acc fname ->
                 match List.find_opt (fun sf -> sf.sf_name.txt = fname) sup_cfg.sc_fields with
                 | None -> acc
                 | Some sf ->
                   let child_actor_name = match sf.sf_ty with
                     | TyCon (n, []) -> n.txt | _ -> "" in
                   if child_actor_name = "" then acc
                   else
                     let old_pid = match List.assoc_opt fname acc with
                       | Some (VInt p) -> Some p | _ -> None in
                     let new_pid = spawn_child_actor ~crashed_pid:old_pid child_actor_name sup_pid in
                     List.map (fun (k, v) ->
                       if k = fname then (k, VInt new_pid) else (k, v)) acc
               ) fields to_respawn in
               VRecord updated
             | other -> other
           in
           sup_inst.ai_state <- new_state
         end
       end)

(** Notify a dynamic supervisor that one of its children crashed. *)
and notify_dyn_supervisor (sup_name : string) (crashed_pid : int) : unit =
  match Hashtbl.find_opt dyn_sup_registry sup_name with
  | None -> ()
  | Some ds ->
    (match List.find_opt (fun e -> e.dce_pid = crashed_pid) ds.ds_children with
     | None -> ()
     | Some entry ->
       (* Remove from the list regardless of restart policy *)
       ds.ds_children <- List.filter (fun e -> e.dce_pid <> crashed_pid) ds.ds_children;
       if entry.dce_restart = "temporary" then ()
       else begin
         (* Permanent or transient: attempt restart within budget *)
         let now = Unix.gettimeofday () in
         let window = float_of_int ds.ds_window_secs in
         let recent = List.filter (fun (ts, _) -> now -. ts < window)
                        ds.ds_restart_count in
         let restart_count = List.fold_left (fun acc (_, n) -> acc + n) 0 recent in
         if restart_count < ds.ds_max_restarts then begin
           ds.ds_restart_count <- recent @ [(now, 1)];
           let new_pid = spawn_child_actor ~crashed_pid:(Some crashed_pid)
                           entry.dce_actor_name ds.ds_vpid in
           ds.ds_children <- { entry with dce_pid = new_pid } :: ds.ds_children
         end
       end)

(** Notify a supervisor that a child has crashed, triggering the appropriate
    restart strategy. *)
and notify_supervisor (sup_pid : int) (crashed_pid : int) : unit =
  match Hashtbl.find_opt actor_registry sup_pid with
  | None ->
    (* Check if this is a dynamic supervisor virtual pid *)
    (match Hashtbl.find_opt dyn_sup_vpid_map sup_pid with
     | Some sup_name -> notify_dyn_supervisor sup_name crashed_pid
     | None -> ())
  | Some sup_inst ->
    (match sup_inst.ai_def.actor_supervise with
     | None -> ()
     | Some sup_cfg ->
       (match sup_cfg.sc_strategy with
        | OneForOne  -> one_for_one_restart sup_pid crashed_pid
        | OneForAll  -> one_for_all_restart sup_pid crashed_pid
        | RestForOne -> rest_for_one_restart sup_pid crashed_pid))

(** Crash an actor: mark dead, deliver Down to monitors,
    and notify any supervising actor for restart. *)
and crash_actor_with_reason (pid : int) (_reason : string)
    (down_reason : monitor_down_reason) : unit =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst when not inst.ai_alive -> ()
  | Some inst ->
    let supervisor = inst.ai_supervisor in
    inst.ai_terminal_reason <- down_reason;
    inst.ai_alive <- false;
    (* Phase 6a: run resource cleanup in reverse acquisition order. *)
    List.iter (fun (_, cleanup) ->
      try cleanup ()
      with exn ->
        Printf.eprintf "warn: resource cleanup failed for actor %d: %s\n"
          pid (Printexc.to_string exn)
    ) (List.rev inst.ai_resources);
    inst.ai_resources <- [];  (* clear so cleanup doesn't re-run on double-crash *)
    (* Phase 6b: call Drop impl on each owned linear value, in reverse acquisition order.
       drop_fn is a March callable (VClosure or VBuiltin): value -> value.
       Errors are caught and logged so one failing drop cannot block others. *)
    List.iter (fun (v, drop_fn) ->
      try
        let _ = !apply_hook drop_fn [v] in ()
      with exn ->
        Printf.eprintf "warn: Drop handler failed for actor %d: %s\n"
          pid (Printexc.to_string exn)
    ) (List.rev inst.ai_linear_values);
    inst.ai_linear_values <- [];  (* clear to prevent re-run on double-crash *)
    (* Task 5: retire this actor's registered names from [named_registry]
       BEFORE any Down notification is delivered below (mirrors the
       runtime's do_actor_death -> registry_retire_actor placement, and the
       same reasoning: a watcher woken by a Down that immediately calls
       Actor.whereis/Actor.registered must not see the name still mapped to
       this dead pid). Compare-and-drop by pid, not by name alone, so a name
       already reassigned to a different live pid (stale-overwrite) is left
       untouched.

       Task 6 parity: snapshot the names FIRST if this actor is supervised,
       so a restart can re-establish them on the replacement. Unsupervised
       actors' names are simply dropped, as before. Siblings killed by
       one_for_all / rest_for_one have already had their [ai_supervisor]
       cleared by the time they get here, which is why those two strategies
       call [capture_reg_names_pending] themselves before clearing it. *)
    if supervisor <> None then capture_reg_names_pending pid;
    let dead_names =
      Hashtbl.fold
        (fun name owner acc -> if owner = pid then name :: acc else acc)
        named_registry []
    in
    List.iter (Hashtbl.remove named_registry) dead_names;
    (* Deliver Down(mon_ref, reason) to each watcher's mailbox *)
    List.iter (fun (mon_ref, watcher_pid) ->
      match Hashtbl.find_opt actor_registry watcher_pid with
      | Some watcher when watcher.ai_alive ->
        Queue.push (monitor_down_message mon_ref pid down_reason) watcher.ai_mailbox
      | _ -> ()
    ) inst.ai_monitors;
    (* Phase 2: notify supervisor for restart *)
    (match supervisor with
     | Some sup_pid -> notify_supervisor sup_pid pid
     | None -> ())

and crash_actor (pid : int) (reason : string) : unit =
  crash_actor_with_reason pid reason (Crash reason)

(** Task 9: interpreter-side counter for messages dropped by bounded-mailbox
    overflow policies. Mirrors the compiled runtime's
    MARCH_STAT_MSGS_DROPPED / march_stat_counters[4], surfaced to March via
    sched_stat(4) / Scheduler.dropped_messages(). *)
let dropped_messages_count = ref 0

(** Task 9: enqueue [msg] onto [inst]'s mailbox, honoring its bounded-mailbox
    policy (set via actor_set_mailbox_limit / Actor.set_queue_limit).
    - limit <= 0 (default): unbounded, always enqueue.
    - policy 3 (block): the interpreter's single-threaded eager scheduler
      cannot park a sender without deadlocking, so block is treated as
      unbounded here (documented divergence — see stdlib/actor.march).
    - policy 1 (drop_new): reject the incoming message when at capacity.
    - policy 2 (drop_old): evict the oldest queued message to make room.
    - unrecognized policy: falls back to unbounded (defensive default). *)
let mailbox_enqueue (inst : actor_inst) (msg : value) : unit =
  let limit = inst.ai_mbox_limit in
  if limit <= 0 then
    Queue.push msg inst.ai_mailbox
  else
    match inst.ai_mbox_policy with
    | 3 -> Queue.push msg inst.ai_mailbox (* block: unbounded in the interpreter *)
    | 1 ->
      if Queue.length inst.ai_mailbox < limit then
        Queue.push msg inst.ai_mailbox
      else
        incr dropped_messages_count (* drop_new: reject the incoming message *)
    | 2 ->
      if Queue.length inst.ai_mailbox >= limit && not (Queue.is_empty inst.ai_mailbox) then begin
        ignore (Queue.pop inst.ai_mailbox);
        incr dropped_messages_count
      end;
      Queue.push msg inst.ai_mailbox (* drop_old: evict oldest, then enqueue *)
    | _ -> Queue.push msg inst.ai_mailbox

(** Register a monitor: watcher_pid observes target_pid. Returns monitor_ref. *)
let monitor_actor ~watcher_pid ~target_pid : int =
  let mon_ref = fresh_monitor_id () in
  (match Hashtbl.find_opt actor_registry target_pid with
   | Some inst when inst.ai_alive ->
     inst.ai_monitors <- (mon_ref, watcher_pid) :: inst.ai_monitors
   | target ->
     (* Target already dead — immediately deliver Down to watcher *)
     let reason = match target with
       | Some inst -> inst.ai_terminal_reason
       | None -> Normal
     in
     (match Hashtbl.find_opt actor_registry watcher_pid with
      | Some watcher when watcher.ai_alive ->
        Queue.push (monitor_down_message mon_ref target_pid reason) watcher.ai_mailbox
      | _ -> ()));
  mon_ref

(** Remove a monitor by its ref. Scans all actors. *)
let demonitor_actor (mon_ref : int) : unit =
  Hashtbl.iter (fun _ (inst : actor_inst) ->
    inst.ai_monitors <- List.filter (fun (m, _) -> m <> mon_ref) inst.ai_monitors
  ) actor_registry

(** Register an OS resource with an actor.
    [cleanup] is called in reverse acquisition order when the actor crashes.
    Safe to call on a dead or unknown actor (no-op). *)
let register_resource_ocaml (pid : int) (name : string) (cleanup : unit -> unit) : unit =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst ->
    inst.ai_resources <- inst.ai_resources @ [(name, cleanup)]

(** [type_tag_of v] returns the type name string for value [v], used to look up
    Drop implementations in [impl_tbl].
    - Primitives map to their canonical type name.
    - Constructor values map to their constructor tag (works for single-constructor
      newtypes like [type FileHandle = FileHandle(Int)]).
    - Returns [None] for values without a registered impl (VPid, VClosure, etc.). *)
let type_tag_of (v : value) : string option =
  match v with
  | VInt _    -> Some "Int"
  | VFloat _  -> Some "Float"
  | VString _ -> Some "String"
  | VBool _   -> Some "Bool"
  | VUnit     -> Some "Unit"
  | VCon (tag, _) -> Some tag
  | _ -> None

(* ------------------------------------------------------------------ *)
(* Show dispatch helper                                                *)
(* ------------------------------------------------------------------ *)

(** Call the Show impl for [v] if one is registered, else fall back to
    value_to_string.  Used by to_string and println builtins so they
    respect user-defined impl Show even when the prelude is not loaded. *)
(* ── Portable hash primitives ─────────────────────────────────────────────
   Bit-for-bit reimplementations of the compiled runtime's hash functions
   (march_hash_int / march_hash_string, runtime/march_runtime.c) so the
   polymorphic `hash()` builtin agrees across backends. Both mask to 62 bits
   (non-negative, <= 2^62-1 = OCaml max_int) so the result fits the
   interpreter's 63-bit native-int Value exactly. See runtime/march_runtime.c
   MARCH_HASH_MASK for the invariant. *)
let march_hash_mask = 0x3FFFFFFFFFFFFFFFL

(* splitmix64 finalizer, matching march_hash_int. *)
let march_hash_int64 (x : int64) : int64 =
  let open Int64 in
  let v = logxor x (shift_right_logical x 30) in
  let v = mul v 0xbf58476d1ce4e5b9L in
  let v = logxor v (shift_right_logical v 27) in
  let v = mul v 0x94d049bb133111ebL in
  let v = logxor v (shift_right_logical v 31) in
  logand v march_hash_mask

(* FNV-1a 64-bit over the UTF-8 bytes, matching march_hash_string. *)
let march_hash_string64 (s : string) : int64 =
  let open Int64 in
  let h = ref 0xcbf29ce484222325L in       (* 14695981039346656037 *)
  String.iter (fun c ->
      h := logxor !h (of_int (Char.code c));
      h := mul !h 0x100000001b3L            (* 1099511628211 *)
    ) s;
  logand !h march_hash_mask

let rec show_dispatch (v : value) : string =
  match v with
  | VInt n    -> string_of_int n
  | VFloat f  ->
    let s = string_of_float f in
    if String.contains s '.' || String.contains s 'e' then s else s ^ ".0"
  | VBool b   -> string_of_bool b
  | VString s -> s
  | VAtom a   -> ":" ^ a
  | VTuple vs ->
    (* Tuples format through [show] recursively — a nested string is DISPLAYED
       (unquoted), matching each element's own `show` and the compiled tuple
       Show impls (`Show$Tuple<N>`, prelude).  Without this, tuples fell to the
       repr-form [value_to_string], which QUOTES nested strings, diverging from
       compiled output — the interpreter was internally inconsistent too
       (Option/List go through their unquoted Show impls, only tuples quoted).
       [value_to_string] itself is unchanged (it is the repr form, pinned by
       test_value_to_string). *)
    "(" ^ String.concat ", " (List.map show_dispatch vs) ^ ")"
  | _ ->
    (match type_name_of_value v with
     | Some tname ->
       (match Hashtbl.find_opt impl_tbl ("Show", tname) with
        | Some show_fn ->
          (match !apply_hook show_fn [v] with
           | VString s -> s
           | other     -> value_to_string other)
        | None -> value_to_string v)
     | None -> value_to_string v)

(* ------------------------------------------------------------------ *)
(* Base environment                                                    *)
(* ------------------------------------------------------------------ *)

(* ── Socket read deadlines ──────────────────────────────────────────────
   [recv_timeout_msg] is a contract shared with runtime/march_http.c
   (MARCH_RECV_TIMEOUT_MSG) and stdlib/socket.march, which matches this exact
   string to build Socket.RecvTimeout.  All three must agree, or a timeout
   silently degrades into a generic RecvFailed in one execution mode only. *)
let recv_timeout_msg = "recv: timed out"

(* Wait until [sock] is readable or [deadline] (absolute, Unix.gettimeofday
   scale) passes.  [None] means block indefinitely. *)
let tcp_wait_readable (sock : Unix.file_descr) (deadline : float option)
    : [ `Ready | `Timeout | `Error of string ] =
  match deadline with
  | None -> `Ready
  | Some t ->
    let remaining = t -. Unix.gettimeofday () in
    if remaining <= 0. then `Timeout
    else
      (try
         match Unix.select [sock] [] [] remaining with
         | [], _, _ -> `Timeout
         | _ -> `Ready
       with
       | Unix.Unix_error (Unix.EINTR, _, _) -> `Ready  (* re-poll on the next recv *)
       | Unix.Unix_error (err, _, _) -> `Error (Unix.error_message err))

(** argv the running March program should see, when the driver supplies one.

    [None] — the default, and what a bare `march f.march` still does — means
    [process_argv] falls back to the compiler process's own [Sys.argv].
    `march f.march --args a b` sets [Some ["f.march"; "a"; "b"]] so a script run
    by `forge run f.march -- a b` sees its own arguments, matching what the same
    program sees compiled and executed directly.

    It lives here rather than in eval.ml beside [ffi_shim_so] because
    [Eval_builtins] must read it, and [Eval_builtins] only opens the modules
    earlier in the include chain.  eval.ml's [include Eval_runtime] re-exports
    it, so bin/main.ml still reaches it as [March_eval.Eval.program_argv]. *)
let program_argv : string list option ref = ref None
