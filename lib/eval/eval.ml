(** March tree-walking interpreter.

    Evaluates a desugared [Ast.module_] directly, without any prior type
    information.  Useful for quick prototyping, REPL experimentation, and as
    a reference semantics for the compiler back-end.

    Design notes:
    - Values are OCaml heap objects; no explicit memory management.
    - Environments are association lists; later entries shadow earlier ones.
    - Two-pass module evaluation: pass 1 installs mutable stubs so that
      mutually-recursive top-level functions can reference each other; pass 2
      fills the stubs with real closures.
    - Pattern matching raises [Match_failure] when no branch matches. *)

open March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Value type                                                          *)
(* ------------------------------------------------------------------ *)

type value =
  | VInt    of int
  | VFloat  of float
  | VString of string
  | VBool   of bool
  | VAtom   of string
  | VUnit
  | VTuple  of value list
  | VRecord of (string * value) list
  | VCon    of string * value list      (** Constructor: tag + payload *)
  | VClosure of env * string list * expr
  | VBuiltin of string * (value list -> value)
  | VPid    of int                      (** Actor process id *)
  | VTask   of int                      (** Task handle *)
  | VWorkPool                           (** Work-stealing pool capability *)
  | VCap    of int * int                (** Epoch-stamped capability: (pid, epoch) *)
  | VActorId of int                     (** Opaque actor identity (epoch-independent) *)
  | VChan   of chan_endpoint            (** Binary session-typed channel endpoint *)
  | VMChan  of mpst_endpoint            (** Multi-party session-typed channel endpoint *)
  | VForeign of string * string         (** FFI extern: (lib_name, symbol_name) *)

(** One endpoint of a binary session-typed channel.
    Each channel consists of two linked endpoints; one side's [ce_out_q]
    is the other side's [ce_in_q]. *)
and chan_endpoint = {
  ce_id      : int;           (** Globally unique channel id *)
  ce_role    : string;        (** Which side of the protocol this is *)
  ce_proto   : string;        (** Protocol name, for runtime error messages *)
  mutable ce_closed   : bool;
  ce_out_q   : value Queue.t; (** Values this endpoint puts out (other side reads) *)
  ce_in_q    : value Queue.t; (** Values this endpoint receives (other side wrote) *)
}

(** One endpoint of a multi-party session.
    For N roles there are N*(N-1) directed queues (one per ordered role pair).
    [me_out_qs] maps target_role → send queue (messages this endpoint sends to target).
    [me_in_qs]  maps source_role → recv queue (messages this endpoint receives from source).
    By construction A.me_out_qs["B"] == B.me_in_qs["A"] (same physical Queue). *)
and mpst_endpoint = {
  me_id       : int;            (** Globally unique session id *)
  me_role     : string;         (** Which role this endpoint represents *)
  me_proto    : string;         (** Protocol name, for runtime error messages *)
  mutable me_closed : bool;
  me_out_qs   : (string, value Queue.t) Hashtbl.t;  (** target_role → send queue *)
  me_in_qs    : (string, value Queue.t) Hashtbl.t;  (** source_role → recv queue *)
}

(** Association-list environment mapping names to values. *)
and env = (string * value) list

(* ------------------------------------------------------------------ *)
(* Actor runtime                                                       *)
(* ------------------------------------------------------------------ *)

type actor_inst = {
  ai_name    : string;           (** Actor type name, e.g. "Counter" *)
  ai_def     : actor_def;
  ai_env_ref : env ref;         (** Module environment at spawn time *)
  mutable ai_state    : value;
  mutable ai_alive    : bool;
  (* Phase 1: supervision infrastructure *)
  mutable ai_monitors : (int * int) list;   (** (monitor_ref, watcher_pid) pairs *)
  mutable ai_links    : int list;            (** bidirectionally linked pids *)
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
}

(** Actor definitions registered by [DActor] — reset per module eval. *)
let actor_defs_tbl : (string, actor_def * env ref) Hashtbl.t = Hashtbl.create 8

(** Live actor instances — reset per module eval. *)
let actor_registry  : (int, actor_inst) Hashtbl.t = Hashtbl.create 16

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

(** Allocates negative virtual pids to avoid collisions with real actor pids. *)
let dyn_sup_next_vpid  : int ref = ref (-1)

(** Task registry — maps task IDs to their result. *)
type task_entry = {
  te_id     : int;
  mutable te_result : value option;
  te_thunk  : value;  (** The closure to execute *)
}

let task_registry : (int, task_entry) Hashtbl.t = Hashtbl.create 16
let next_task_id : int ref = ref 0

(** Doc registry: fully-qualified name → doc string.
    Populated when [eval_decl] encounters a [DFn] with [fn_doc = Some s]. *)
let doc_registry : (string, string) Hashtbl.t = Hashtbl.create 32

(** Interface implementation table — maps (iface_name, type_name) to the method value.
    Populated when [eval_decl] processes [DImpl] nodes.
    Reset per module eval via [reset_scheduler_state]. *)
let impl_tbl : (string * string, value) Hashtbl.t = Hashtbl.create 8

(** Constructor → type name mapping.
    Maps each data constructor name (e.g. "Red") to its declaring type (e.g. "Color").
    Populated when [eval_decl] processes [DType] nodes.
    Used by [==] and interface method dispatch to look up Eq/Ord/Hash/Show impls. *)
let ctor_type_tbl : (string, string) Hashtbl.t = Hashtbl.create 16

(** Protocol → sorted role list mapping.
    Populated when [eval_decl] processes [DProtocol] nodes.
    Used by [MPST.new] to know how many endpoints to create and their names. *)
let protocol_roles_tbl : (string, string list) Hashtbl.t = Hashtbl.create 8

(** Module stack for tracking the current module path during eval.
    Updated when entering/leaving [DMod]. Top of stack = innermost module. *)
let module_stack : string list ref = ref []

let current_doc_prefix () =
  match !module_stack with
  | []    -> ""
  | parts -> String.concat "." (List.rev parts) ^ "."

(* ------------------------------------------------------------------ *)
(* Tap bus — thread-safe value inspector (Clojure tap> model)         *)
(* ------------------------------------------------------------------ *)

(** The global tap queue.  Threads push values here via [tap]; the REPL
    drains it after each expression evaluation to display tapped values. *)
let tap_mutex : Mutex.t = Mutex.create ()
let tap_queue : value Queue.t = Queue.create ()

(** Push [v] onto the tap bus.  Thread-safe: may be called from actor threads. *)
let tap_push (v : value) : unit =
  Mutex.lock tap_mutex;
  Queue.push v tap_queue;
  Mutex.unlock tap_mutex

(** Drain all pending tap values from the queue and return them in FIFO order.
    Thread-safe.  Called by the REPL after each expression evaluation. *)
let tap_drain () : value list =
  Mutex.lock tap_mutex;
  let acc = ref [] in
  while not (Queue.is_empty tap_queue) do
    acc := Queue.pop tap_queue :: !acc
  done;
  Mutex.unlock tap_mutex;
  List.rev !acc

let lookup_doc (key : string) : string option =
  Hashtbl.find_opt doc_registry key

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

(** Flag set when graceful shutdown has been requested (SIGTERM, App.stop). *)
let shutdown_requested : bool ref = ref false

(* ---- Logger global state ---- *)
(* Global log level: 0=Debug, 1=Info, 2=Warn, 3=Error.  Default: Info. *)
let logger_level : int ref = ref 1
(* Persistent key-value context attached to every log entry. *)
let logger_context : (string * string) list ref = ref []

(* ---- Test output capture ---- *)
(* When Some buf, all print/log output is redirected here instead of stdout/stderr.
   Set by run_tests around each test body; None during normal execution. *)
let test_capture_buf : Buffer.t option ref = ref None

let capture_write (s : string) : unit =
  match !test_capture_buf with
  | Some buf -> Buffer.add_string buf s
  | None -> print_string s

let capture_writeln (s : string) : unit =
  match !test_capture_buf with
  | Some buf -> Buffer.add_string buf s; Buffer.add_char buf '\n'
  | None -> print_endline s

(* Logger output goes to stderr normally; redirect to capture buf during tests. *)
let capture_ewriteln (s : string) : unit =
  match !test_capture_buf with
  | Some buf -> Buffer.add_string buf s; Buffer.add_char buf '\n'
  | None -> Printf.eprintf "%s\n%!" s

(* ---- Actor.call reply tracking ---- *)
(* Pending synchronous call replies: call_ref -> reply value. *)
let pending_replies : (int, value) Hashtbl.t = Hashtbl.create 4
let next_call_ref : int ref = ref 0

(** Ordered list of pids spawned by [spawn_from_spec], in start order.
    Shutdown iterates this in reverse (last started = first stopped). *)
let app_spawn_order : int list ref = ref []

(** Pid of the actor whose handler is currently executing.
    Set by [run_scheduler] when entering a handler; used by [self] and [receive]. *)
let current_pid : int option ref = ref None

(* ------------------------------------------------------------------ *)
(* Ring buffer                                                         *)
(* ------------------------------------------------------------------ *)

type 'a ring = {
  mutable rb_arr  : 'a option array;
  mutable rb_head : int;   (* index of next write position *)
  mutable rb_size : int;   (* number of entries stored *)
  rb_cap          : int;
}

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

(** [ring_drop_newest r n] drops the n most-recent entries (logical indices 0..n-1).
    Used by replay to discard frames newer than the cursor.
    Clamps: if n >= rb_size, clears the buffer. *)
let ring_drop_newest r n =
  if n <= 0 then ()
  else if n >= r.rb_size then (r.rb_head <- 0; r.rb_size <- 0)
  else begin
    r.rb_head <- ((r.rb_head - n) + r.rb_cap * 2) mod r.rb_cap;
    r.rb_size <- r.rb_size - n
  end

(* ------------------------------------------------------------------ *)
(* Debug trace types                                                   *)
(* ------------------------------------------------------------------ *)

type actor_inst_snapshot = {
  ais_name  : string;
  ais_state : value;
  ais_alive : bool;
}

type actor_state_snapshot = {
  ass_defs      : (string * (actor_def * env ref)) list;
  ass_instances : (int * actor_inst_snapshot) list;
  ass_next_pid  : int;
}

type trace_frame = {
  tf_expr   : expr;
  tf_env    : env;
  tf_result : value option;
  tf_exn    : string option;
  tf_actor  : actor_state_snapshot;
  tf_span   : span;
  tf_depth  : int;
}

type actor_msg_event = {
  ame_pid          : int;
  ame_actor_name   : string;
  ame_msg          : value;
  ame_state_before : value;
  ame_state_after  : value option;   (* None if handler raised *)
  ame_frame_idx    : int;            (* trace ring index at time of dispatch *)
}

type debug_ctx = {
  dc_trace         : trace_frame ring;
  mutable dc_pos   : int;       (* navigation cursor; 0 = most recent *)
  mutable dc_enabled : bool;
  mutable dc_depth : int;       (* current call depth *)
  mutable dc_on_dbg : (env -> unit) option;
  mutable dc_actor_log : actor_msg_event list;  (* per-actor message history *)
}

(** Snapshot the current actor state. Deep-copies mutable fields. *)
let snapshot_actors () : actor_state_snapshot =
  let defs = Hashtbl.fold (fun name (def, env_r) acc ->
      (name, (def, ref !env_r)) :: acc
    ) actor_defs_tbl [] in
  let instances = Hashtbl.fold (fun pid (inst : actor_inst) acc ->
      let snap = { ais_name  = inst.ai_name;
                   ais_state = inst.ai_state;
                   ais_alive = inst.ai_alive } in
      (pid, snap) :: acc
    ) actor_registry [] in
  { ass_defs = defs; ass_instances = instances; ass_next_pid = !next_pid }

(** Restore actor state from a snapshot. *)
let restore_actors (snap : actor_state_snapshot) : unit =
  Hashtbl.reset actor_defs_tbl;
  List.iter (fun (name, (def, env_r)) ->
      Hashtbl.add actor_defs_tbl name (def, env_r)
    ) snap.ass_defs;
  Hashtbl.reset actor_registry;
  List.iter (fun (pid, s) ->
      match Hashtbl.find_opt actor_defs_tbl s.ais_name with
      | None -> ()
      | Some (def, env_r) ->
        let inst = { ai_name     = s.ais_name;
                     ai_def      = def;
                     ai_env_ref  = env_r;
                     ai_state    = s.ais_state;
                     ai_alive    = s.ais_alive;
                     ai_monitors = [];
                     ai_links    = [];
                     ai_mailbox  = Queue.create ();
                     ai_supervisor = None;
                     ai_restart_count = [];
                     ai_epoch = 0;
                     ai_resources = [];
                     ai_linear_values = [] } in
        Hashtbl.add actor_registry pid inst
    ) snap.ass_instances;
  next_pid := snap.ass_next_pid

(** Module-level debug context. None = no overhead. *)
let debug_ctx : debug_ctx option ref = ref None

(* ------------------------------------------------------------------ *)
(* Exceptions                                                          *)
(* ------------------------------------------------------------------ *)

exception Match_failure of string
exception Eval_error of string

(** Raised when an [assert] expression fails during test execution.
    Carries a human-readable failure message. *)
exception Assert_failure of string

(** Raised when an actor/task's reduction budget is exhausted. *)
exception Yield

(** Global reduction context — None means reduction counting is disabled. *)
let reduction_ctx : March_scheduler.Scheduler.reduction_ctx option ref = ref None

(** Enable/disable reduction counting for the evaluator. *)
let set_reduction_counting (enabled : bool) : unit =
  if enabled then
    reduction_ctx := Some (March_scheduler.Scheduler.create_reduction_ctx ())
  else
    reduction_ctx := None

(** Reset the reduction budget (call between scheduling quanta). *)
let reset_reduction_budget () : unit =
  match !reduction_ctx with
  | Some ctx -> March_scheduler.Scheduler.reset_budget ctx
  | None -> ()

(** Check the reduction counter and raise Yield if exhausted.
    Called at every yield point: EApp, EMatch, ESend. *)
let check_reductions () : unit =
  match !reduction_ctx with
  | Some ctx ->
    if March_scheduler.Scheduler.tick ctx then
      raise Yield
  | None -> ()

let eval_error fmt = Printf.ksprintf (fun s -> raise (Eval_error s)) fmt

(* ------------------------------------------------------------------ *)
(* Pattern matching                                                    *)
(* ------------------------------------------------------------------ *)

(** Try to match [v] against [pat].
    Returns [Some bindings] on success, [None] on failure.
    Bindings are accumulated in reverse order (callers reverse or prepend). *)
let rec match_pattern (v : value) (pat : pattern) : (string * value) list option =
  match pat, v with
  | PatWild _, _ -> Some []

  | PatVar n, _ -> Some [(n.txt, v)]

  | PatLit (LitInt i, _),    VInt j    when i = j   -> Some []
  | PatLit (LitFloat f, _),  VFloat g  when f = g   -> Some []
  | PatLit (LitString s, _), VString t when s = t   -> Some []
  | PatLit (LitBool b, _),   VBool c   when b = c   -> Some []
  | PatLit (LitAtom a, _),   VAtom b   when a = b   -> Some []
  | PatLit _,                _                       -> None

  | PatCon (n, pats), VCon (tag, args) ->
    (* Strip any type qualifier from the pattern name before comparing so that
       both Result.Ok(x) and Ok(x) match VCon("Ok", …) at runtime. *)
    let bare_pat = match String.rindex_opt n.txt '.' with
      | Some i -> String.sub n.txt (i + 1) (String.length n.txt - i - 1)
      | None   -> n.txt
    in
    if bare_pat <> tag then None
    else if List.length pats <> List.length args then None
    else match_list pats args

  | PatCon _, _ -> None

  | PatAtom (a, pats, _), VAtom b when a = b && pats = [] -> Some []
  | PatAtom (a, pats, _), VCon (tag, args) when a = tag ->
    if List.length pats <> List.length args then None
    else match_list pats args
  | PatAtom _, _ -> None

  | PatTuple ([], _), VUnit -> Some []
  | PatTuple (pats, _), VTuple vs ->
    if List.length pats <> List.length vs then None
    else match_list pats vs

  | PatTuple _, _ -> None

  | PatRecord (fields, _), VRecord record_fields ->
    let bindings = List.fold_left (fun acc (fname, fpat) ->
        match acc with
        | None -> None
        | Some bs ->
          match List.assoc_opt fname.txt record_fields with
          | None -> None
          | Some fv ->
            match match_pattern fv fpat with
            | None -> None
            | Some new_bs -> Some (new_bs @ bs)
      ) (Some []) fields in
    bindings

  | PatRecord _, _ -> None

  | PatAs (inner, alias, _), _ ->
    (match match_pattern v inner with
     | None -> None
     | Some bs -> Some ((alias.txt, v) :: bs))

(** Match a list of patterns against a list of values. *)
and match_list (pats : pattern list) (vs : value list) : (string * value) list option =
  List.fold_left2 (fun acc p v ->
      match acc with
      | None -> None
      | Some bs ->
        match match_pattern v p with
        | None -> None
        | Some new_bs -> Some (new_bs @ bs)
    ) (Some []) pats vs

(* ------------------------------------------------------------------ *)
(* Built-in environment                                                *)
(* ------------------------------------------------------------------ *)

let arith_int op name = VBuiltin (name, function
    | [VInt a; VInt b] -> VInt (op a b)
    | _ -> eval_error "builtin %s: expected two ints" name)

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
  | VRecord _ -> None  (* records don't carry a type tag at runtime *)
  | _         -> None

(** Forward-reference hook for dispatch in comparison operators.
    Interface dispatch needs [apply] but [cmp_op] is defined before [apply].
    Set to the real [apply] after it is defined (see [apply_hook] pattern). *)
let iface_dispatch_hook : (value -> value list -> value) ref =
  ref (fun _fn _args -> eval_error "iface_dispatch not yet initialized")

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
         eval_error "builtin %s: incompatible operand types" name)
    | _ -> eval_error "builtin %s: incompatible operand types" name)

(** Detect whether a VCon chain is a March list (Nil / Cons(h, t)). *)
let rec is_list_value = function
  | VCon ("Nil", []) -> true
  | VCon ("Cons", [_; t]) -> is_list_value t
  | _ -> false

let rec list_elems acc = function
  | VCon ("Nil", []) -> List.rev acc
  | VCon ("Cons", [h; t]) -> list_elems (h :: acc) t
  | v -> List.rev (v :: acc)  (* improper list — shouldn't happen *)

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
      (List.map (fun (k, v) -> k ^ " = " ^ value_to_string v) fields)
    ^ " }"
  | VCon ("Nil", []) -> "[]"
  | VCon ("Cons", _) as v when is_list_value v ->
    "[" ^ String.concat ", " (List.map value_to_string (list_elems [] v)) ^ "]"
  | VCon (tag, []) -> tag
  | VCon (tag, args) ->
    tag ^ "(" ^ String.concat ", " (List.map value_to_string args) ^ ")"
  | VClosure _  -> "<fn>"
  | VBuiltin (n, _) ->
    let is_rec = String.length n >= 5 && String.sub n 0 5 = "<rec:" in
    if is_rec then "<fn>" else "<builtin:" ^ n ^ ">"
  | VPid pid -> "Pid(" ^ string_of_int pid ^ ")"
  | VTask id -> Printf.sprintf "<task:%d>" id
  | VWorkPool -> "<work_pool>"
  | VCap (pid, epoch) -> Printf.sprintf "Cap(%d, epoch=%d)" pid epoch
  | VActorId pid -> Printf.sprintf "ActorId(%d)" pid
  | VChan ce ->
    Printf.sprintf "Chan(%s#%d, %s)" ce.ce_proto ce.ce_id ce.ce_role
  | VMChan me ->
    Printf.sprintf "MChan(%s#%d, %s)" me.me_proto me.me_id me.me_role
  | VForeign (lib, sym) ->
    Printf.sprintf "<foreign:%s:%s>" lib sym

(** Pretty-print a value with indented multi-line layout when the flat
    representation exceeds [width] characters.
    Truncates collections longer than [max_items] with "... (N more)". *)
let value_to_string_pretty ?(width=80) ?(max_items=50) ?(max_depth=6) v =
  let flat = value_to_string v in
  if String.length flat <= width then flat
  else
    let indent n = String.make n ' ' in
    let truncate_list items pp_item depth =
      let n = List.length items in
      if n <= max_items then
        List.map (pp_item depth) items
      else
        let shown = List.filteri (fun i _ -> i < max_items) items in
        List.map (pp_item depth) shown
        @ [Printf.sprintf "... (%d more)" (n - max_items)]
    in
    let truncate_fields fields pp_field depth =
      let n = List.length fields in
      if n <= max_items then
        List.map (pp_field depth) fields
      else
        let shown = List.filteri (fun i _ -> i < max_items) fields in
        List.map (pp_field depth) shown
        @ [Printf.sprintf "... (%d more fields)" (n - max_items)]
    in
    let rec pp depth v =
      if depth >= max_depth then "<...>" else
      let flat_v = value_to_string v in
      if String.length flat_v <= width - depth * 2 then flat_v
      else match v with
      | VRecord fields ->
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        let strs = truncate_fields fields
          (fun d (k, fv) -> k ^ " = " ^ pp (d + 1) fv) depth in
        "{ " ^ String.concat ("\n" ^ pad ^ ", ") strs
        ^ "\n" ^ close_pad ^ "}"
      | VTuple vs ->
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        "( " ^ String.concat ("\n" ^ pad ^ ", ") (List.map (pp (depth + 1)) vs)
        ^ "\n" ^ close_pad ^ ")"
      | VCon ("Nil", []) -> "[]"
      | VCon ("Cons", _) as lv when is_list_value lv ->
        let elems = list_elems [] lv in
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        let strs = truncate_list elems (fun d e -> pp d e) (depth + 1) in
        "[ " ^ String.concat ("\n" ^ pad ^ ", ") strs
        ^ "\n" ^ close_pad ^ "]"
      | VCon (tag, args) when args <> [] ->
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        tag ^ "(\n" ^ pad
        ^ String.concat ("\n" ^ pad ^ ", ") (List.map (pp (depth + 1)) args)
        ^ "\n" ^ close_pad ^ ")"
      | _ -> flat_v
    in
    pp 0 v

(** print/println use a display form (no quotes around strings). *)
let value_display v =
  match v with
  | VString s -> s
  | _         -> value_to_string v

type actor_info = {
  ai_pid       : int;
  ai_name      : string;
  ai_alive     : bool;
  ai_state_str : string;
  (** Distinct from actor_inst.ai_state which is a [value]. *)
}

let increment_epoch pid =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst -> inst.ai_epoch <- inst.ai_epoch + 1

let list_actors () =
  Hashtbl.fold (fun pid (inst : actor_inst) acc ->
    { ai_pid       = pid;
      ai_name      = inst.ai_name;
      ai_alive     = inst.ai_alive;
      ai_state_str = value_to_string inst.ai_state }
    :: acc
  ) actor_registry []
  |> List.sort (fun a b -> compare a.ai_pid b.ai_pid)

(* ------------------------------------------------------------------ *)
(* Phase 1: Monitors, Links, and crash_actor (must precede base_env)  *)
(* ------------------------------------------------------------------ *)

let fresh_monitor_id () =
  let id = !next_monitor_id in
  next_monitor_id := id + 1;
  id

(** Forward reference for evaluating an expression — set after [eval_expr]
    is defined so that [crash_actor] can call it for supervisor restarts. *)
let eval_expr_hook : (env -> expr -> value) ref =
  ref (fun _env _expr -> eval_error "eval_expr not yet initialized")

(** Forward reference for running the scheduler — set after [run_scheduler]
    is defined so that [base_env] builtins can call it. *)
let run_scheduler_hook : (unit -> unit) ref =
  ref (fun () -> eval_error "run_scheduler not yet initialized")

(** Forward reference for [apply] — set after [apply] is defined
    so that [register_resource_ocaml] can call closures at crash time. *)
let apply_hook : (value -> value list -> value) ref =
  ref (fun _fn _args -> eval_error "apply not yet initialized")

(* ------------------------------------------------------------------ *)
(* FFI extern stub table                                               *)
(* ------------------------------------------------------------------ *)

(** Table of OCaml-side stubs for extern functions.
    Key: (lib_name, symbol_name).
    On interpreter path we don't dlopen; instead we register known
    math/libc symbols here so that `extern "c"` and `extern "m"` blocks
    work without a C runtime call. *)
let foreign_stubs : (string * string, value list -> value) Hashtbl.t =
  let t = Hashtbl.create 32 in
  let reg lib sym f = Hashtbl.replace t (lib, sym) f in
  (* libc / libm math — single-float functions *)
  let f1 name ocaml_fn =
    List.iter (fun lib -> reg lib name (function
        | [VFloat x] -> VFloat (ocaml_fn x)
        | [VInt x]   -> VFloat (ocaml_fn (float_of_int x))
        | _ -> eval_error "extern %s: expected one numeric argument" name))
      ["c"; "m"; "libm"; "libc"; "libm.so"; "libc.so"] in
  let f2 name ocaml_fn =
    List.iter (fun lib -> reg lib name (function
        | [VFloat a; VFloat b] -> VFloat (ocaml_fn a b)
        | [VInt   a; VFloat b] -> VFloat (ocaml_fn (float_of_int a) b)
        | [VFloat a; VInt   b] -> VFloat (ocaml_fn a (float_of_int b))
        | [VInt   a; VInt   b] -> VFloat (ocaml_fn (float_of_int a) (float_of_int b))
        | _ -> eval_error "extern %s: expected two numeric arguments" name))
      ["c"; "m"; "libm"; "libc"; "libm.so"; "libc.so"] in
  f1 "sqrt"  sqrt;
  f1 "cbrt"  (fun x -> Float.cbrt x);
  f1 "exp"   exp;
  f1 "exp2"  (fun x -> Float.exp2 x);
  f1 "log"   log;
  f1 "log2"  (fun x -> Float.log2 x);
  f1 "log10" log10;
  f1 "sin"   sin;
  f1 "cos"   cos;
  f1 "tan"   tan;
  f1 "asin"  asin;
  f1 "acos"  acos;
  f1 "atan"  atan;
  f1 "sinh"  sinh;
  f1 "cosh"  cosh;
  f1 "tanh"  tanh;
  f1 "fabs"  abs_float;
  f1 "ceil"  ceil;
  f1 "floor" floor;
  f1 "round" Float.round;
  f1 "trunc" (fun x -> Float.of_int (int_of_float x));
  f2 "pow"   ( ** );
  f2 "fmod"  mod_float;
  f2 "atan2" atan2;
  f2 "hypot" hypot;
  f2 "fmin"  Float.min;
  f2 "fmax"  Float.max;
  (* puts: print string + newline, return length *)
  List.iter (fun lib ->
    reg lib "puts" (function
      | [VString s] -> capture_writeln s; VInt (String.length s + 1)
      | _ -> eval_error "extern puts: expected String"))
    ["c"; "libc"; "libc.so"];
  t

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
      ai_monitors = []; ai_links = []; ai_mailbox = Queue.create ();
      ai_supervisor = Some supervisor_pid;
      ai_restart_count = []; ai_epoch = inherited_epoch;
      ai_resources = [];
      ai_linear_values = [] } in
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

(** Crash an actor: mark dead, deliver Down to monitors, propagate to links,
    and notify any supervising actor for restart. *)
and crash_actor (pid : int) (reason : string) : unit =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst when not inst.ai_alive -> ()
  | Some inst ->
    let supervisor = inst.ai_supervisor in
    inst.ai_alive <- false;
    (* Phase 6a: run resource cleanup in reverse acquisition order.
       This runs for the actor being crashed directly.
       Linked actors are crashed by recursive calls to crash_actor below,
       so each linked actor's cleanup runs inside its own crash_actor invocation. *)
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
    (* Deliver Down(mon_ref, reason) to each watcher's mailbox *)
    List.iter (fun (mon_ref, watcher_pid) ->
      match Hashtbl.find_opt actor_registry watcher_pid with
      | Some watcher when watcher.ai_alive ->
        Queue.push (VCon ("Down", [VInt mon_ref; VString reason])) watcher.ai_mailbox
      | _ -> ()
    ) inst.ai_monitors;
    (* Propagate crash to all linked actors *)
    let links = inst.ai_links in
    inst.ai_links <- [];  (* Clear to prevent re-entrancy *)
    List.iter (fun linked_pid ->
      (* Remove back-link first to avoid infinite loop *)
      (match Hashtbl.find_opt actor_registry linked_pid with
       | Some linked_inst ->
         linked_inst.ai_links <- List.filter (fun p -> p <> pid) linked_inst.ai_links
       | None -> ());
      crash_actor linked_pid
        (Printf.sprintf "linked to %d which crashed: %s" pid reason)
    ) links;
    (* Phase 2: notify supervisor for restart *)
    (match supervisor with
     | Some sup_pid -> notify_supervisor sup_pid pid
     | None -> ())

(** Register a monitor: watcher_pid observes target_pid. Returns monitor_ref. *)
let monitor_actor ~watcher_pid ~target_pid : int =
  let mon_ref = fresh_monitor_id () in
  (match Hashtbl.find_opt actor_registry target_pid with
   | Some inst when inst.ai_alive ->
     inst.ai_monitors <- (mon_ref, watcher_pid) :: inst.ai_monitors
   | _ ->
     (* Target already dead — immediately deliver Down to watcher *)
     (match Hashtbl.find_opt actor_registry watcher_pid with
      | Some watcher when watcher.ai_alive ->
        Queue.push (VCon ("Down", [VInt mon_ref; VString "noproc"])) watcher.ai_mailbox
      | _ -> ()));
  mon_ref

(** Remove a monitor by its ref. Scans all actors. *)
let demonitor_actor (mon_ref : int) : unit =
  Hashtbl.iter (fun _ (inst : actor_inst) ->
    inst.ai_monitors <- List.filter (fun (m, _) -> m <> mon_ref) inst.ai_monitors
  ) actor_registry

(** Establish a bidirectional link between two actors. *)
let link_actors (pid_a : int) (pid_b : int) : unit =
  (match Hashtbl.find_opt actor_registry pid_a with
   | Some ia ->
     if not (List.mem pid_b ia.ai_links) then
       ia.ai_links <- pid_b :: ia.ai_links
   | None -> ());
  (match Hashtbl.find_opt actor_registry pid_b with
   | Some ib ->
     if not (List.mem pid_a ib.ai_links) then
       ib.ai_links <- pid_a :: ib.ai_links
   | None -> ())

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
(* CSV parser state                                                    *)
(* ------------------------------------------------------------------ *)

(** Opaque CSV reader state stored in a module-level table.
    The table maps integer handles to (in_channel, delimiter, mode, eof_flag). *)
type csv_mode = CsvSimple | CsvRfc4180

type csv_reader = {
  csv_ic      : in_channel;
  csv_delim   : char;
  csv_mode    : csv_mode;
  mutable csv_eof : bool;
}

let csv_table : (int, csv_reader) Hashtbl.t = Hashtbl.create 4
let next_csv_id : int ref = ref 0

(** Scan one complete CSV row from [r].
    Returns [Some fields] or [None] on EOF (before any chars were read). *)
let csv_scan_row (r : csv_reader) : string list option =
  let ic    = r.csv_ic in
  let delim = r.csv_delim in
  if r.csv_eof then None
  else
    let fields      = ref [] in
    let cur         = Buffer.create 64 in
    let row_started = ref false in
    let finished    = ref false in

    (* Emit the current buffer as a field, clear the buffer. *)
    let emit () =
      fields := Buffer.contents cur :: !fields;
      Buffer.clear cur
    in

    let next_char () = try Some (input_char ic) with End_of_file -> None in

    (match r.csv_mode with
     | CsvSimple ->
       (* No quoting: split on delimiter, newline ends the row. *)
       let rec loop () =
         if !finished then ()
         else match next_char () with
           | None ->
             r.csv_eof <- true;
             if !row_started then emit ()
           | Some c ->
             row_started := true;
             if c = delim then (emit (); loop ())
             else if c = '\n' then (emit (); finished := true)
             else if c = '\r' then begin
               (match next_char () with
                | Some '\n' | None -> ()
                | Some c2 -> Buffer.add_char cur c2);
               emit (); finished := true
             end else (Buffer.add_char cur c; loop ())
       in
       loop ()

     | CsvRfc4180 ->
       (* 4-state FSM: FieldStart → Unquoted | Quoted → QuoteInQuoted. *)
       (* State is encoded in two bools: in_quoted and after_close_quote. *)
       let in_quoted       = ref false in
       let after_close_q   = ref false in
       let rec loop () =
         if !finished then ()
         else match next_char () with
           | None ->
             r.csv_eof <- true;
             if !row_started || Buffer.length cur > 0 || !in_quoted then emit ()
           | Some c ->
             row_started := true;
             if !after_close_q then begin
               (* QuoteInQuoted state: previous char was '"' inside/after a quoted field *)
               after_close_q := false;
               if c = '"' then begin
                 (* doubled-quote escape produces a literal quote *)
                 Buffer.add_char cur '"';
                 in_quoted := true;
                 loop ()
               end else if c = delim then begin
                 emit (); loop ()
               end else if c = '\n' then begin
                 emit (); finished := true
               end else if c = '\r' then begin
                 (match next_char () with
                  | Some '\n' | None -> ()
                  | Some c2 -> Buffer.add_char cur c2);
                 emit (); finished := true
               end else begin
                 (* Malformed: char after close-quote; treat literally *)
                 Buffer.add_char cur c; loop ()
               end
             end else if !in_quoted then begin
               if c = '"' then begin
                 (* Might be end-of-field or "" escape; decide on next char *)
                 in_quoted := false;
                 after_close_q := true;
                 loop ()
               end else begin
                 Buffer.add_char cur c; loop ()
               end
             end else begin
               (* FieldStart / Unquoted *)
               if c = '"' && Buffer.length cur = 0 then begin
                 in_quoted := true; loop ()
               end else if c = delim then begin
                 emit (); loop ()
               end else if c = '\n' then begin
                 emit (); finished := true
               end else if c = '\r' then begin
                 (match next_char () with
                  | Some '\n' | None -> ()
                  | Some c2 -> Buffer.add_char cur c2);
                 emit (); finished := true
               end else begin
                 Buffer.add_char cur c; loop ()
               end
             end
       in
       loop ());

    if r.csv_eof && not !row_started && !fields = [] then None
    else Some (List.rev !fields)

(** Dispatch function for the csv_open builtin. *)
let csv_open_impl : value list -> value = function
  | [VString path; VString delim_str; VAtom mode_str] ->
    let delim = if String.length delim_str > 0 then delim_str.[0] else ',' in
    let mode  = if mode_str = "simple" then CsvSimple else CsvRfc4180 in
    (try
       let ic = open_in path in
       let id = !next_csv_id in
       incr next_csv_id;
       Hashtbl.add csv_table id
         { csv_ic = ic; csv_delim = delim; csv_mode = mode; csv_eof = false };
       VCon ("Ok", [VInt id])
     with Sys_error msg ->
       VCon ("Err", [VCon ("FileError", [VString msg])]))
  | _ -> eval_error "csv_open(path, delimiter, mode)"

(** Dispatch function for the csv_next_row builtin. *)
let csv_next_row_impl : value list -> value = function
  | [VInt id] ->
    (match Hashtbl.find_opt csv_table id with
     | None -> eval_error "csv_next_row: invalid handle %d" id
     | Some r ->
       (match csv_scan_row r with
        | None -> VCon ("CsvEof", [])
        | Some fields ->
          let lst = List.fold_right
            (fun f acc -> VCon ("Cons", [VString f; acc]))
            fields (VCon ("Nil", [])) in
          VCon ("Row", [lst])))
  | _ -> eval_error "csv_next_row(handle)"

(** Dispatch function for the csv_close builtin. *)
let csv_close_impl : value list -> value = function
  | [VInt id] ->
    (match Hashtbl.find_opt csv_table id with
     | None -> VAtom "ok"
     | Some r ->
       (try close_in r.csv_ic with _ -> ());
       Hashtbl.remove csv_table id;
       VAtom "ok")
  | _ -> eval_error "csv_close(handle)"

(* ------------------------------------------------------------------ *)
(* HTTP server helpers (interpreter mode)                             *)
(* ------------------------------------------------------------------ *)

(** Convert an OCaml string list to a March List(String) value. *)
let march_string_list xs =
  List.fold_right
    (fun s acc -> VCon ("Cons", [VString s; acc]))
    xs (VCon ("Nil", []))

(** Parse an HTTP method string to the March Method variant. *)
let http_method_of_string s =
  match String.uppercase_ascii s with
  | "GET"     -> VCon ("Get",     [])
  | "POST"    -> VCon ("Post",    [])
  | "PUT"     -> VCon ("Put",     [])
  | "PATCH"   -> VCon ("Patch",   [])
  | "DELETE"  -> VCon ("Delete",  [])
  | "HEAD"    -> VCon ("Head",    [])
  | "OPTIONS" -> VCon ("Options", [])
  | "TRACE"   -> VCon ("Trace",   [])
  | "CONNECT" -> VCon ("Connect", [])
  | _         -> VCon ("Other",   [VString s])

(** Split a URI path on "/" into non-empty segments → March List(String). *)
let split_path_info path =
  path
  |> String.split_on_char '/'
  |> List.filter (fun s -> s <> "")
  |> march_string_list

(** Read exactly one HTTP header line (up to CRLF) from a Unix socket.
    Returns the line without the trailing CR/LF. Raises End_of_file on close. *)
let http_recv_line sock =
  let buf = Buffer.create 128 in
  let one = Bytes.create 1 in
  let stop = ref false in
  while not !stop do
    let n = Unix.recv sock one 0 1 [] in
    if n = 0 then (stop := true)
    else begin
      let c = Bytes.get one 0 in
      if c = '\n' then stop := true
      else Buffer.add_char buf c
    end
  done;
  let s = Buffer.contents buf in
  (* Strip trailing CR if present *)
  if String.length s > 0 && s.[String.length s - 1] = '\r'
  then String.sub s 0 (String.length s - 1)
  else s

(** Read exactly [n] bytes from a socket into a string. *)
let http_recv_exactly sock n =
  let buf = Bytes.create n in
  let remaining = ref n in
  let off = ref 0 in
  while !remaining > 0 do
    let got = Unix.recv sock buf !off !remaining [] in
    if got = 0 then remaining := 0
    else begin off := !off + got; remaining := !remaining - got end
  done;
  Bytes.sub_string buf 0 !off

(** Parse "Name: Value" header lines into an OCaml association list. *)
let parse_header_line line =
  match String.index_opt line ':' with
  | None -> None
  | Some i ->
    let name  = String.sub line 0 i in
    let value = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
    Some (name, value)

(** Build a March Conn value from parsed request data.
    The [headers_raw] list contains (name, value) pairs. *)
let build_conn_value ~method_str ~full_path ~headers_raw ~body =
  let path, query_string =
    match String.index_opt full_path '?' with
    | Some i ->
      ( String.sub full_path 0 i,
        String.sub full_path (i + 1) (String.length full_path - i - 1) )
    | None -> (full_path, "")
  in
  let method_val  = http_method_of_string method_str in
  let path_info   = split_path_info path in
  let header_list =
    List.fold_right
      (fun (n, v) acc ->
         VCon ("Cons", [VCon ("Header", [VString n; VString v]); acc]))
      headers_raw (VCon ("Nil", []))
  in
  VCon ("Conn", [
    VInt 0;                  (* fd — not used in interpreter mode *)
    method_val;
    VString path;
    path_info;
    VString query_string;
    header_list;
    VString body;
    VInt 0;                  (* response status = 0 (not yet set) *)
    VCon ("Nil", []);        (* response headers = [] *)
    VString "";              (* response body = "" *)
    VBool false;             (* halted = false *)
    VCon ("Nil", []);        (* assigns = [] *)
    VCon ("NoUpgrade", []);  (* upgrade = NoUpgrade *)
  ])

(** Extract (status, resp_headers_value, resp_body) from a March Conn. *)
let extract_conn_response conn =
  match conn with
  | VCon ("Conn", [_fd; _meth; _path; _pi; _qs;
                   _rh; _rb;
                   VInt status; resp_headers; VString resp_body;
                   _halted; _assigns; _upgrade]) ->
    (status, resp_headers, resp_body)
  | _ -> (500, VCon ("Nil", []), "Internal Server Error")

(** Standard HTTP reason phrases. *)
let http_reason_phrase = function
  | 200 -> "OK"        | 201 -> "Created"
  | 204 -> "No Content"
  | 301 -> "Moved Permanently" | 302 -> "Found"
  | 304 -> "Not Modified"
  | 400 -> "Bad Request"       | 401 -> "Unauthorized"
  | 403 -> "Forbidden"         | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 500 -> "Internal Server Error"
  | n   -> string_of_int n

(** Serialize a March List(Header) value to HTTP header lines. *)
let rec march_headers_to_string = function
  | VCon ("Nil", []) -> ""
  | VCon ("Cons", [VCon ("Header", [VString n; VString v]); rest]) ->
    n ^ ": " ^ v ^ "\r\n" ^ march_headers_to_string rest
  | _ -> ""

(** Send all bytes in [data] to [sock], ignoring short writes. *)
let tcp_send_all sock data =
  let buf   = Bytes.of_string data in
  let total = Bytes.length buf in
  let off   = ref 0 in
  (try
     while !off < total do
       let n = Unix.send sock buf !off (total - !off) [] in
       if n = 0 then off := total
       else off := !off + n
     done
   with Unix.Unix_error _ -> ())

(* ------------------------------------------------------------------ *)
(* WebSocket helpers                                                   *)
(* ------------------------------------------------------------------ *)

(** Base64 encoding table. *)
let b64_table =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

(** Encode a raw byte string to base64. *)
let base64_encode s =
  let n = String.length s in
  let out = Buffer.create ((n / 3 + 1) * 4) in
  let i = ref 0 in
  while !i + 2 < n do
    let a = Char.code s.[!i] in
    let b = Char.code s.[!i + 1] in
    let c = Char.code s.[!i + 2] in
    Buffer.add_char out b64_table.[a lsr 2];
    Buffer.add_char out b64_table.[((a land 3) lsl 4) lor (b lsr 4)];
    Buffer.add_char out b64_table.[((b land 0xF) lsl 2) lor (c lsr 6)];
    Buffer.add_char out b64_table.[c land 0x3F];
    i := !i + 3
  done;
  (match n - !i with
   | 1 ->
     let a = Char.code s.[!i] in
     Buffer.add_char out b64_table.[a lsr 2];
     Buffer.add_char out b64_table.[(a land 3) lsl 4];
     Buffer.add_string out "=="
   | 2 ->
     let a = Char.code s.[!i] in
     let b = Char.code s.[!i + 1] in
     Buffer.add_char out b64_table.[a lsr 2];
     Buffer.add_char out b64_table.[((a land 3) lsl 4) lor (b lsr 4)];
     Buffer.add_char out b64_table.[(b land 0xF) lsl 2];
     Buffer.add_char out '='
   | _ -> ());
  Buffer.contents out

(** Compute the WebSocket accept key: SHA1(key + magic) |> base64. *)
let ws_accept_key (client_key : string) : string =
  let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" in
  let input = client_key ^ magic in
  let digest = Digestif.SHA1.(to_raw_string (digest_string input)) in
  base64_encode digest

(** Read exactly [n] bytes from a socket into a Bytes buffer at [off].
    Returns true on success, false if the connection closed early. *)
let ws_recv_exact sock (buf : bytes) off n =
  let got = ref 0 in
  let ok  = ref true in
  while !ok && !got < n do
    let r = Unix.recv sock buf (off + !got) (n - !got) [] in
    if r = 0 then ok := false
    else got := !got + r
  done;
  !ok

(** Read and parse one WebSocket frame from [sock].
    Returns a March WsFrame variant value. *)
let ws_recv_frame (sock : Unix.file_descr) : value =
  let close_gone = VCon ("Close", [VInt 1001; VString "going away"]) in
  try
    let hdr = Bytes.create 2 in
    if not (ws_recv_exact sock hdr 0 2) then close_gone
    else begin
      let b0 = Char.code (Bytes.get hdr 0) in
      let b1 = Char.code (Bytes.get hdr 1) in
      let opcode  = b0 land 0x0F in
      let masked  = (b1 lsr 7) land 1 = 1 in
      let len7    = b1 land 0x7F in
      let payload_len =
        if len7 < 126 then len7
        else if len7 = 126 then begin
          let ext = Bytes.create 2 in
          if not (ws_recv_exact sock ext 0 2) then raise Exit;
          (Char.code (Bytes.get ext 0) lsl 8) lor (Char.code (Bytes.get ext 1))
        end else begin
          let ext = Bytes.create 8 in
          if not (ws_recv_exact sock ext 0 8) then raise Exit;
          let v = ref 0 in
          for i = 0 to 7 do
            v := (!v lsl 8) lor (Char.code (Bytes.get ext i))
          done;
          !v
        end
      in
      let mask_key = Bytes.create 4 in
      if masked then
        (if not (ws_recv_exact sock mask_key 0 4) then raise Exit);
      let payload = Bytes.create payload_len in
      if payload_len > 0 then
        (if not (ws_recv_exact sock payload 0 payload_len) then raise Exit);
      if masked then
        for i = 0 to payload_len - 1 do
          let m = Char.code (Bytes.get mask_key (i mod 4)) in
          Bytes.set payload i (Char.chr ((Char.code (Bytes.get payload i)) lxor m))
        done;
      let text = Bytes.to_string payload in
      match opcode with
      | 0x1 -> VCon ("TextFrame",   [VString text])
      | 0x2 -> VCon ("BinaryFrame", [VString text])
      | 0x8 ->
        let code   = if payload_len >= 2
          then (Char.code (Bytes.get payload 0) lsl 8) lor (Char.code (Bytes.get payload 1))
          else 1000 in
        let reason = if payload_len > 2
          then String.sub (Bytes.to_string payload) 2 (payload_len - 2)
          else "" in
        VCon ("Close", [VInt code; VString reason])
      | 0x9 -> VCon ("Ping", [])
      | 0xA -> VCon ("Pong", [])
      | _   -> VCon ("Close", [VInt 1002; VString "unknown opcode"])
    end
  with _ -> close_gone

(** Write one WebSocket frame to [sock] (server→client, unmasked). *)
let ws_send_frame (sock : Unix.file_descr) (frame : value) : unit =
  try
    let (opcode, payload) = match frame with
      | VCon ("TextFrame",   [VString s]) -> (0x81, s)
      | VCon ("BinaryFrame", [VString s]) -> (0x82, s)
      | VCon ("Ping", _)                  -> (0x89, "")
      | VCon ("Pong", _)                  -> (0x8A, "")
      | VCon ("Close", [VInt code; VString reason]) ->
        let buf = Bytes.create (2 + String.length reason) in
        Bytes.set buf 0 (Char.chr ((code lsr 8) land 0xFF));
        Bytes.set buf 1 (Char.chr (code land 0xFF));
        Bytes.blit_string reason 0 buf 2 (String.length reason);
        (0x88, Bytes.to_string buf)
      | _ -> (0x88, "")
    in
    let plen = String.length payload in
    let hdr =
      if plen < 126 then begin
        let b = Bytes.create 2 in
        Bytes.set b 0 (Char.chr opcode);
        Bytes.set b 1 (Char.chr plen);
        b
      end else if plen < 65536 then begin
        let b = Bytes.create 4 in
        Bytes.set b 0 (Char.chr opcode);
        Bytes.set b 1 (Char.chr 126);
        Bytes.set b 2 (Char.chr ((plen lsr 8) land 0xFF));
        Bytes.set b 3 (Char.chr (plen land 0xFF));
        b
      end else begin
        let b = Bytes.create 10 in
        Bytes.set b 0 (Char.chr opcode);
        Bytes.set b 1 (Char.chr 127);
        for i = 0 to 7 do
          Bytes.set b (2 + i) (Char.chr ((plen lsr (56 - 8*i)) land 0xFF))
        done;
        b
      end
    in
    tcp_send_all sock (Bytes.to_string hdr);
    if plen > 0 then tcp_send_all sock payload
  with _ -> ()

(** Handle a single HTTP connection: read request → call pipeline → write response.
    [pipeline_fn] is a March value (VClosure or VBuiltin) of type Conn → Conn. *)
let handle_http_connection (sock : Unix.file_descr) (pipeline_fn : value) : unit =
  try
    (* 1. Read the request line *)
    let req_line = http_recv_line sock in
    if req_line = "" then ()
    else begin
      let (meth, full_path) =
        match String.split_on_char ' ' req_line with
        | m :: fp :: _ -> (m, fp)
        | _ -> ("GET", "/")
      in
      (* 2. Read header lines until a blank line *)
      let headers_raw = ref [] in
      let stop = ref false in
      while not !stop do
        let line = http_recv_line sock in
        if line = "" then stop := true
        else
          (match parse_header_line line with
           | Some pair -> headers_raw := pair :: !headers_raw
           | None -> ())
      done;
      let headers_raw = List.rev !headers_raw in
      (* 3. Read body if Content-Length present (case-insensitive) *)
      let content_length =
        match List.find_opt
                (fun (n, _) -> String.lowercase_ascii n = "content-length")
                headers_raw
        with
        | Some (_, s) -> int_of_string_opt (String.trim s)
        | None        -> None
      in
      let body = match content_length with
        | Some n when n > 0 -> http_recv_exactly sock n
        | _ -> ""
      in
      (* 4. Build the Conn value *)
      let conn_val = build_conn_value
          ~method_str:meth ~full_path ~headers_raw ~body in
      (* 5. Call the pipeline closure *)
      let result_conn = !apply_hook pipeline_fn [conn_val] in
      (* 6. Check for WebSocket upgrade *)
      (match result_conn with
       | VCon ("Conn", [_fd; _meth; _path; _pi; _qs;
                        _rh; _rb; _status; _rhs; _rbody;
                        _halted; _assigns;
                        VCon ("WebSocketUpgrade", [handler_fn])]) ->
         (* Find Sec-WebSocket-Key in request headers *)
         let ws_key_opt =
           List.find_opt
             (fun (n, _) -> String.lowercase_ascii n = "sec-websocket-key")
             headers_raw
         in
         (match ws_key_opt with
          | None ->
            tcp_send_all sock "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
          | Some (_, key) ->
            let accept = ws_accept_key (String.trim key) in
            let handshake =
              "HTTP/1.1 101 Switching Protocols\r\n" ^
              "Upgrade: websocket\r\n" ^
              "Connection: Upgrade\r\n" ^
              "Sec-WebSocket-Accept: " ^ accept ^ "\r\n\r\n"
            in
            tcp_send_all sock handshake;
            (* Store fd as int in WsSocket value *)
            let fd_int = (Obj.magic sock : int) in
            let ws_sock = VCon ("WsSocket", [VInt fd_int]) in
            (try ignore (!apply_hook handler_fn [ws_sock])
             with _ -> ()))
       | _ ->
         (* Normal HTTP response *)
         let (status, resp_headers, resp_body) = extract_conn_response result_conn in
         let effective_status = if status = 0 then 200 else status in
         let reason     = http_reason_phrase effective_status in
         let header_str = march_headers_to_string resp_headers in
         let response   =
           Printf.sprintf "HTTP/1.1 %d %s\r\n%sContent-Length: %d\r\n\r\n%s"
             effective_status reason
             header_str
             (String.length resp_body)
             resp_body
         in
         tcp_send_all sock response)
    end
  with _ -> ()  (* swallow connection errors *)

(* ------------------------------------------------------------------ *)
(* Session-typed channel runtime                                       *)
(* ------------------------------------------------------------------ *)

let next_chan_id : int ref = ref 0

(** Create a linked pair of channel endpoints for [proto_name].
    The two roles are [role_a] and [role_b]. Returns (endpoint_a, endpoint_b)
    where a's out_q = b's in_q and vice versa. *)
let chan_new proto_name role_a role_b =
  let id = !next_chan_id in
  incr next_chan_id;
  let q_ab = Queue.create () in  (* a sends, b receives *)
  let q_ba = Queue.create () in  (* b sends, a receives *)
  let ep_a = { ce_id = id; ce_role = role_a; ce_proto = proto_name;
               ce_closed = false; ce_out_q = q_ab; ce_in_q = q_ba } in
  let ep_b = { ce_id = id; ce_role = role_b; ce_proto = proto_name;
               ce_closed = false; ce_out_q = q_ba; ce_in_q = q_ab } in
  (ep_a, ep_b)

(** Send [v] on channel endpoint [ce]. Returns the same endpoint
    (the type system ensures linearity; here we just pass it through). *)
let chan_send ce v =
  if ce.ce_closed then
    eval_error "Chan.send: channel %s#%d is already closed" ce.ce_proto ce.ce_id;
  Queue.push v ce.ce_out_q;
  VChan ce

(** Receive from channel endpoint [ce].
    Blocks until a value is available (in the synchronous eval model,
    the sender runs first so the queue is always populated).
    Returns (value, new_endpoint_as_VTuple). *)
let chan_recv ce =
  if ce.ce_closed then
    eval_error "Chan.recv: channel %s#%d is already closed" ce.ce_proto ce.ce_id;
  if Queue.is_empty ce.ce_in_q then
    eval_error
      "Chan.recv: channel %s#%d has no pending value — \
       did you run the sender first?" ce.ce_proto ce.ce_id;
  let v = Queue.pop ce.ce_in_q in
  VTuple [v; VChan ce]

(** Close channel endpoint [ce]. The endpoint must not be in-use after this. *)
let chan_close ce =
  if ce.ce_closed then
    eval_error "Chan.close: channel %s#%d was already closed" ce.ce_proto ce.ce_id;
  ce.ce_closed <- true;
  VUnit

(* ------------------------------------------------------------------ *)
(* Multi-party session (MPST) runtime                                  *)
(* ------------------------------------------------------------------ *)

(** Create N linked MPST endpoints for [proto_name] with the given [roles]
    (sorted list of role name strings).
    For each ordered pair (A, B) of distinct roles, creates one shared Queue
    such that A.me_out_qs["B"] == B.me_in_qs["A"].
    Returns endpoints in the same order as [roles]. *)
let mpst_new proto_name roles =
  let id = !next_chan_id in
  incr next_chan_id;
  (* Pre-allocate all pairwise queues. *)
  let pair_queues : (string * string, value Queue.t) Hashtbl.t =
    Hashtbl.create (List.length roles * List.length roles)
  in
  List.iter (fun a ->
      List.iter (fun b ->
          if a <> b then
            Hashtbl.replace pair_queues (a, b) (Queue.create ())
        ) roles
    ) roles;
  (* Build one endpoint per role. *)
  List.map (fun role ->
      let out_qs = Hashtbl.create (List.length roles) in
      let in_qs  = Hashtbl.create (List.length roles) in
      List.iter (fun other ->
          if other <> role then begin
            Hashtbl.replace out_qs other (Hashtbl.find pair_queues (role, other));
            Hashtbl.replace in_qs  other (Hashtbl.find pair_queues (other, role))
          end
        ) roles;
      VMChan { me_id = id; me_role = role; me_proto = proto_name;
               me_closed = false; me_out_qs = out_qs; me_in_qs = in_qs }
    ) roles

(** Send [v] from [me] to [target_role].
    Returns the same endpoint (linearity enforced by the type system). *)
let mpst_send me target_role v =
  if me.me_closed then
    eval_error "MPST.send: session %s#%d (%s) is already closed"
      me.me_proto me.me_id me.me_role;
  (match Hashtbl.find_opt me.me_out_qs target_role with
   | None ->
     eval_error "MPST.send: role `%s` has no channel to `%s` in protocol `%s`"
       me.me_role target_role me.me_proto
   | Some q ->
     Queue.push v q;
     VMChan me)

(** Receive from [source_role] into [me].
    Returns (value, same_endpoint_as_VMChan). *)
let mpst_recv me source_role =
  if me.me_closed then
    eval_error "MPST.recv: session %s#%d (%s) is already closed"
      me.me_proto me.me_id me.me_role;
  (match Hashtbl.find_opt me.me_in_qs source_role with
   | None ->
     eval_error "MPST.recv: role `%s` has no channel from `%s` in protocol `%s`"
       me.me_role source_role me.me_proto
   | Some q ->
     if Queue.is_empty q then
       eval_error
         "MPST.recv: role `%s` expected a message from `%s` in session %s#%d \
          but the queue is empty — did you run the sender first?"
         me.me_role source_role me.me_proto me.me_id;
     let v = Queue.pop q in
     VTuple [v; VMChan me])

(** Close an MPST endpoint. *)
let mpst_close me =
  if me.me_closed then
    eval_error "MPST.close: session %s#%d (%s) was already closed"
      me.me_proto me.me_id me.me_role;
  me.me_closed <- true;
  VUnit

(* ------------------------------------------------------------------ *)
(* Base environment                                                    *)
(* ------------------------------------------------------------------ *)

let base_env : env =
  [ (* Integer arithmetic *)
    ("+",  arith_num ( + ) ( +. ) "+")
  ; ("-",  arith_num ( - ) ( -. ) "-")
  ; ("*",  arith_num ( * ) ( *. ) "*")
  ; ("/",  VBuiltin ("/", function
        | [VInt a;   VInt b]   when b <> 0 -> VInt (a / b)
        | [VFloat a; VFloat b]             -> VFloat (a /. b)
        | [VInt _;   VInt 0]               -> eval_error "division by zero"
        | _ -> eval_error "builtin /: expected two numbers"))
  ; ("%",  VBuiltin ("%", function
        | [VInt a; VInt b] when b <> 0 -> VInt (a mod b)
        | _ -> eval_error "builtin %%: expected two non-zero ints"))
    (* Float arithmetic *)
  ; ("+.", VBuiltin ("+.", function
        | [VFloat a; VFloat b] -> VFloat (a +. b)
        | _ -> eval_error "builtin +.: expected two floats"))
  ; ("-.", VBuiltin ("-.", function
        | [VFloat a; VFloat b] -> VFloat (a -. b)
        | _ -> eval_error "builtin -.: expected two floats"))
  ; ("*.", VBuiltin ("*.", function
        | [VFloat a; VFloat b] -> VFloat (a *. b)
        | _ -> eval_error "builtin *.: expected two floats"))
  ; ("/.", VBuiltin ("/.", function
        | [VFloat a; VFloat b] -> VFloat (a /. b)
        | _ -> eval_error "builtin /.: expected two floats"))
    (* Comparisons *)
  ; ("==", cmp_op ( = )  ( = )  ( = )  ( = )  "==")
  ; ("!=", cmp_op ( <> ) ( <> ) ( <> ) ( <> ) "!=")
  ; ("<",  cmp_op ( < )  ( < )  ( < )  ( < )  "<")
  ; ("<=", cmp_op ( <= ) ( <= ) ( <= ) ( <= ) "<=")
  ; (">",  cmp_op ( > )  ( > )  ( > )  ( > )  ">")
  ; (">=", cmp_op ( >= ) ( >= ) ( >= ) ( >= ) ">=")
    (* Boolean *)
  ; ("&&", VBuiltin ("&&", function
        | [VBool a; VBool b] -> VBool (a && b)
        | _ -> eval_error "builtin &&: expected two bools"))
  ; ("||", VBuiltin ("||", function
        | [VBool a; VBool b] -> VBool (a || b)
        | _ -> eval_error "builtin ||: expected two bools"))
  ; ("not", VBuiltin ("not", function
        | [VBool b] -> VBool (not b)
        | _ -> eval_error "builtin not: expected bool"))
    (* String concatenation *)
  ; ("++", VBuiltin ("++", function
        | [VString a; VString b] -> VString (a ^ b)
        | _ -> eval_error "builtin ++: expected two strings"))
    (* I/O *)
  ; ("print", VBuiltin ("print", function
        | [v] -> capture_write (value_display v); VUnit
        | vs  -> List.iter (fun v -> capture_write (value_display v)) vs; VUnit))
  ; ("println", VBuiltin ("println", function
        | [v] -> capture_writeln (value_display v); VUnit
        | vs  -> List.iter (fun v -> capture_write (value_display v)) vs;
                 capture_write "\n"; VUnit))
  ; ("print_int", VBuiltin ("print_int", function
        | [VInt n] -> capture_write (string_of_int n); VUnit
        | _ -> eval_error "print_int: expected int"))
  ; ("print_float", VBuiltin ("print_float", function
        | [VFloat f] -> capture_write (string_of_float f); VUnit
        | _ -> eval_error "print_float: expected float"))
    (* Tap bus — Clojure tap> model for non-intrusive value inspection *)
  ; ("tap", VBuiltin ("tap", function
        | [v] -> tap_push v; v
        | _ -> eval_error "tap: expected exactly one argument"))
    (* Conversions *)
  ; ("bool_to_string", VBuiltin ("bool_to_string", function
        | [VBool b] -> VString (string_of_bool b)
        | _ -> eval_error "bool_to_string: expected bool"))
  ; ("int_to_string",  VBuiltin ("int_to_string", function
        | [VInt n] -> VString (string_of_int n)
        | _ -> eval_error "int_to_string: expected int"))
  ; ("float_to_string", VBuiltin ("float_to_string", function
        | [VFloat f] -> VString (string_of_float f)
        | _ -> eval_error "float_to_string: expected float"))
  ; ("string_to_int", VBuiltin ("string_to_int", function
        | [VString s] ->
          (try VCon ("Some", [VInt (int_of_string s)])
           with Failure _ -> VCon ("None", []))
        | _ -> eval_error "string_to_int: expected string"))
  ; ("string_length", VBuiltin ("string_length", function
        | [VString s] -> VInt (String.length s)
        | _ -> eval_error "string_length: expected string"))
  ; ("string_concat", VBuiltin ("string_concat", function
        | [VString a; VString b] -> VString (a ^ b)
        | _ -> eval_error "string_concat: expected two strings"))
  ; ("read_line", VBuiltin ("read_line", function
        | [VUnit] | [] ->
          (try VString (input_line stdin)
           with End_of_file -> VString "")
        | _ -> eval_error "read_line: expected unit"))
    (* List helpers (using VCon "Cons"/"Nil") *)
  ; ("head", VBuiltin ("head", function
        | [VCon ("Cons", [h; _])] -> h
        | _ -> eval_error "head: expected non-empty list"))
  ; ("tail", VBuiltin ("tail", function
        | [VCon ("Cons", [_; t])] -> t
        | _ -> eval_error "tail: expected non-empty list"))
  ; ("is_nil", VBuiltin ("is_nil", function
        | [VCon ("Nil", [])] -> VBool true
        | [VCon ("Cons", _)] -> VBool false
        | _ -> eval_error "is_nil: expected list"))
    (* Negation *)
  ; ("negate", VBuiltin ("negate", function
        | [VInt n]   -> VInt (~- n)
        | [VFloat f] -> VFloat (~-. f)
        | _ -> eval_error "negate: expected number"))
    (* Actor builtins — operate on the global actor_registry *)
  ; ("kill", VBuiltin ("kill", function
        | [VPid pid] -> crash_actor pid "killed"; VUnit
        | _ -> eval_error "kill: expected Pid"))
  ; ("is_alive", VBuiltin ("is_alive", function
        | [VPid pid] ->
          (match Hashtbl.find_opt actor_registry pid with
           | Some inst -> VBool inst.ai_alive
           | None      -> VBool false)
        | _ -> eval_error "is_alive: expected Pid"))
  ; ("respond", VBuiltin ("respond", function
        | [_] -> VUnit   (* stub: full async impl in future *)
        | _ -> eval_error "respond: expected one argument"))
  ; ("monitor", VBuiltin ("monitor", function
        | [VPid watcher_pid; VPid target_pid] ->
          VInt (monitor_actor ~watcher_pid ~target_pid)
        | _ -> eval_error "monitor: expected (watcher_pid, target_pid)"))
  ; ("demonitor", VBuiltin ("demonitor", function
        | [VInt mon_ref] -> demonitor_actor mon_ref; VUnit
        | _ -> eval_error "demonitor: expected monitor ref"))
  ; ("link", VBuiltin ("link", function
        | [VPid a; VPid b] -> link_actors a b; VUnit
        | _ -> eval_error "link: expected two pids"))
  ; ("mailbox_size", VBuiltin ("mailbox_size", function
        | [VPid pid] ->
          (match Hashtbl.find_opt actor_registry pid with
           | Some inst -> VInt (Queue.length inst.ai_mailbox)
           | None      -> VInt 0)
        | _ -> eval_error "mailbox_size: expected pid"))
  ; ("actor_get_int", VBuiltin ("actor_get_int", function
        (* Access actor state by field index and return the Int value.
           Mirrors the compiled-mode march_actor_get_int(actor_ptr, index).
           In the compiled runtime, worker threads process messages concurrently,
           so actor_get_int sees the latest state after any recent send().
           In interpreter mode we drain the scheduler first to match that
           behaviour: pending messages are processed before the read. *)
        | [VPid pid; VInt index] ->
          !run_scheduler_hook ();
          (match Hashtbl.find_opt actor_registry pid with
           | None -> VInt 0
           | Some inst ->
             let nth_int_of_value v i =
               match v with
               | VRecord fields ->
                 (match List.nth_opt fields i with
                  | Some (_, VInt n) -> VInt n
                  | Some (_, VFloat f) -> VInt (int_of_float f)
                  | _ -> VInt 0)
               | VCon (_, args) ->
                 (match List.nth_opt args i with
                  | Some (VInt n) -> VInt n
                  | Some (VFloat f) -> VInt (int_of_float f)
                  | _ -> VInt 0)
               | VInt n when i = 0 -> VInt n
               | _ -> VInt 0
             in
             nth_int_of_value inst.ai_state index)
        | _ -> eval_error "actor_get_int: expected (Pid, Int)"))
  ; ("get_actor_field", VBuiltin ("get_actor_field", function
        (* Read a named field from an actor's current state record.
           Returns Some(value) if the actor exists and has the field,
           None otherwise. Useful for inspecting actor state from main(). *)
        | [VPid pid; VString field] ->
          (match Hashtbl.find_opt actor_registry pid with
           | Some inst ->
             (match inst.ai_state with
              | VRecord fields ->
                (match List.assoc_opt field fields with
                 | Some v -> VCon ("Some", [v])
                 | None   -> VCon ("None", []))
              | _ -> VCon ("None", []))
           | None -> VCon ("None", []))
        | _ -> eval_error "get_actor_field: expected (Pid, String)"))
  ; ("register_resource", VBuiltin ("register_resource", function
        (* Register a cleanup thunk with an actor.
           Calling convention: cleanup_thunk is (Unit -> Unit).
           In March: register_resource(pid, "name", fn _ -> cleanup_expr)
           The thunk is called at crash time in reverse acquisition order. *)
        | [VPid pid; VString name; cleanup_thunk] ->
          let cleanup () =
            let _ = !apply_hook cleanup_thunk [VUnit] in ()
          in
          register_resource_ocaml pid name cleanup;
          VUnit
        | _ -> eval_error "register_resource: expected (Pid, String, fn _ -> ...)"))
  ; ("own", VBuiltin ("own", function
        (* Register a linear value with an actor, associating its Drop impl.
           Calling convention: own(pid, value)
           Resolves Drop impl from impl_tbl using the value's type tag.
           In March: own(pid, my_handle)
           The drop fn is called at crash time in reverse acquisition order. *)
        | [VPid pid; v] ->
          (match type_tag_of v with
           | None ->
             eval_error "own: value has no Drop-resolvable type (got %s)" (value_display v)
           | Some tag ->
             (match Hashtbl.find_opt impl_tbl ("Drop", tag) with
              | None ->
                eval_error "own: no impl Drop for type '%s' — declare impl Drop(%s)" tag tag
              | Some drop_fn ->
                (match Hashtbl.find_opt actor_registry pid with
                 | None ->
                   eval_error "own: unknown actor pid %d" pid
                 | Some inst ->
                   inst.ai_linear_values <- inst.ai_linear_values @ [(v, drop_fn)];
                   VUnit)))
        | _ -> eval_error "own: expected (Pid, value)"))
  ; ("run_until_idle", VBuiltin ("run_until_idle", function
        | [] -> !run_scheduler_hook (); VUnit
        | _ -> eval_error "run_until_idle: expected 0 arguments"))
  ; ("self", VBuiltin ("self", function
        | [] ->
          (match !current_pid with
           | Some pid -> VPid pid
           | None -> eval_error "self: called outside an actor handler")
        | _ -> eval_error "self: expected 0 arguments"))
  ; ("receive", VBuiltin ("receive", function
        (* Single-threaded cooperative semantics: receive() pops the NEXT message
           from this actor's mailbox immediately. If the mailbox is empty, it errors
           rather than blocking — true blocking receive requires a multi-threaded
           scheduler (Phase 4 async). Use this only when you know a message is
           already queued (e.g., you sent the message before calling the handler). *)
        | [] ->
          (match !current_pid with
           | Some pid ->
             (match Hashtbl.find_opt actor_registry pid with
              | Some inst when not (Queue.is_empty inst.ai_mailbox) ->
                Queue.pop inst.ai_mailbox
              | _ -> eval_error "receive: mailbox is empty (async receive requires a non-empty mailbox)")
           | None -> eval_error "receive: called outside an actor handler")
        | _ -> eval_error "receive: expected 0 arguments"))
    (* Utility: convert Int to Pid (needed for supervisor state field access) *)
  ; ("pid_of_int", VBuiltin ("pid_of_int", function
        | [VInt n] -> VPid n
        | _ -> eval_error "pid_of_int: expected int"))
    (* Supervision: restart a supervised child actor.
       Accepts a Pid pointing to the child actor. Finds the supervisor,
       kills the child (if still alive), spawns a fresh instance, and
       returns the new Pid. Must be called from within a supervisor context
       (i.e. the child must have a supervisor registered). *)
  ; ("restart", VBuiltin ("restart", function
        | [VPid child_pid] ->
          (match Hashtbl.find_opt actor_registry child_pid with
           | None -> eval_error "restart: actor %d not found" child_pid
           | Some child_inst ->
             (match child_inst.ai_supervisor with
              | None -> eval_error "restart: actor %d has no supervisor" child_pid
              | Some sup_pid ->
                let child_actor_name = child_inst.ai_name in
                (* Kill the old child if still alive *)
                if child_inst.ai_alive then begin
                  child_inst.ai_supervisor <- None;  (* detach to prevent re-entry *)
                  crash_actor child_pid "restart called"
                end;
                (* Spawn fresh child, inheriting epoch *)
                let new_pid = spawn_child_actor ~crashed_pid:(Some child_pid) child_actor_name sup_pid in
                (* Update the supervisor's state to point to new pid *)
                (match Hashtbl.find_opt actor_registry sup_pid with
                 | Some sup_inst ->
                   (match sup_inst.ai_state with
                    | VRecord fields ->
                      sup_inst.ai_state <- VRecord (List.map (fun (k, v) ->
                        if v = VInt child_pid then (k, VInt new_pid) else (k, v)) fields)
                    | _ -> ())
                 | None -> ());
                VPid new_pid))
        | _ -> eval_error "restart: expected Pid"))
    (* Phase 3: epoch-based capability builtins *)
  ; ("get_cap", VBuiltin ("get_cap", function
        | [VPid pid] ->
          (match Hashtbl.find_opt actor_registry pid with
           | Some inst when inst.ai_alive ->
             (* Wrap in Some so callers can pattern-match: Some(cap) / None *)
             VCon ("Some", [VCap (pid, inst.ai_epoch)])
           | _ -> VCon ("None", []))
        | _ -> eval_error "get_cap: expected Pid"))
  ; ("send_checked", VBuiltin ("send_checked", fun args ->
        (* Validate epoch, then enqueue (Phase 4: async dispatch).
           Returns :ok if the cap is valid, :error otherwise.
           The message is delivered asynchronously — call run_until_idle()
           to process it. *)
        match args with
        | [VCap (pid, cap_epoch); msg] ->
          (match Hashtbl.find_opt actor_registry pid with
           | None -> VAtom "error"                              (* unknown actor *)
           | Some inst when not inst.ai_alive -> VAtom "error" (* actor dead *)
           | Some inst when inst.ai_epoch <> cap_epoch ->
             VAtom "error"                                      (* stale epoch *)
           | _ when Hashtbl.mem revocation_table (pid, cap_epoch) ->
             VAtom "error"                                      (* explicitly revoked *)
           | Some inst ->
             (* Valid cap: enqueue and return :ok immediately *)
             (match msg with
              | VCon _ | VAtom _ ->
                Queue.push msg inst.ai_mailbox;
                VAtom "ok"
              | _ ->
                eval_error "send_checked: message must be a constructor value, got %s"
                  (value_to_string msg)))
        | [VPid _pid; _msg] ->
          (* Legacy: bare VPid without epoch — not supported in Phase 3+ *)
          VAtom "error"
        | _ -> eval_error "send_checked: expected (Cap, msg)"))
  ; ("revoke_cap", VBuiltin ("revoke_cap", function
        (* Explicitly revoke a capability so it can no longer be used to send
           messages, even if the actor is still alive at the same epoch.
           Returns :ok always (idempotent). *)
        | [VCap (pid, epoch)] ->
          Hashtbl.replace revocation_table (pid, epoch) ();
          VAtom "ok"
        | _ -> eval_error "revoke_cap: expected Cap"))
  ; ("is_cap_valid", VBuiltin ("is_cap_valid", function
        (* Check whether a capability is currently valid (not revoked, actor alive,
           epoch matches). Returns true/false. *)
        | [VCap (pid, cap_epoch)] ->
          (match Hashtbl.find_opt actor_registry pid with
           | None -> VBool false
           | Some inst when not inst.ai_alive -> VBool false
           | Some inst when inst.ai_epoch <> cap_epoch -> VBool false
           | _ when Hashtbl.mem revocation_table (pid, cap_epoch) -> VBool false
           | _ -> VBool true)
        | _ -> eval_error "is_cap_valid: expected Cap"))
  ; ("to_string", VBuiltin ("to_string", function
        | [v] -> VString (value_display v)
        | _ -> eval_error "to_string: expected one argument"))

    (* ---- Standard interface builtins: Eq, Ord, Show, Hash ---- *)
    (* These dispatch through impl_tbl for user-defined types; fall back
       to structural/primitive operations for built-in types. *)
  ; ("eq", VBuiltin ("eq", function
        | [VInt a;    VInt b]    -> VBool (a = b)
        | [VFloat a;  VFloat b]  -> VBool (a = b)
        | [VString a; VString b] -> VBool (a = b)
        | [VBool a;   VBool b]   -> VBool (a = b)
        | [a; b] ->
          (match type_name_of_value a with
           | Some tname ->
             (match Hashtbl.find_opt impl_tbl ("Eq", tname) with
              | Some eq_fn -> !apply_hook eq_fn [a; b]
              | None       -> VBool (a = b))
           | None -> VBool (a = b))
        | _ -> eval_error "eq: expected two arguments"))
  ; ("compare", VBuiltin ("compare", function
        | [VInt a;    VInt b]    -> VInt (Int.compare a b)
        | [VFloat a;  VFloat b]  -> VInt (Float.compare a b)
        | [VString a; VString b] -> VInt (String.compare a b)
        | [VBool a;   VBool b]   -> VInt (Bool.compare a b)
        | [a; b] ->
          (match type_name_of_value a with
           | Some tname ->
             (match Hashtbl.find_opt impl_tbl ("Ord", tname) with
              | Some cmp_fn -> !apply_hook cmp_fn [a; b]
              | None        -> VInt (compare a b))
           | None -> VInt (compare a b))
        | _ -> eval_error "compare: expected two arguments"))
  ; ("show", VBuiltin ("show", function
        | [VInt n]    -> VString (string_of_int n)
        | [VFloat f]  ->
          let s = string_of_float f in
          VString (if String.contains s '.' || String.contains s 'e' then s else s ^ ".0")
        | [VBool b]   -> VString (string_of_bool b)
        | [VString s] -> VString s
        | [v] ->
          (match type_name_of_value v with
           | Some tname ->
             (match Hashtbl.find_opt impl_tbl ("Show", tname) with
              | Some show_fn -> !apply_hook show_fn [v]
              | None         -> VString (value_to_string v))
           | None -> VString (value_to_string v))
        | _ -> eval_error "show: expected one argument"))
  ; ("hash", VBuiltin ("hash", function
        | [VInt n]    -> VInt (Hashtbl.hash n)
        | [VFloat f]  -> VInt (Hashtbl.hash f)
        | [VString s] -> VInt (Hashtbl.hash s)
        | [VBool b]   -> VInt (Hashtbl.hash b)
        | [v] ->
          (match type_name_of_value v with
           | Some tname ->
             (match Hashtbl.find_opt impl_tbl ("Hash", tname) with
              | Some hash_fn -> !apply_hook hash_fn [v]
              | None         -> VInt (Hashtbl.hash v))
           | None -> VInt (Hashtbl.hash v))
        | _ -> eval_error "hash: expected one argument"))

    (* ---- Int primitives ---- *)
  ; ("int_abs", VBuiltin ("int_abs", function
        | [VInt n] -> VInt (abs n)
        | _ -> eval_error "int_abs: expected int"))
  ; ("int_pow", VBuiltin ("int_pow", function
        | [VInt base; VInt exp] ->
          if exp < 0 then eval_error "int_pow: negative exponent"
          else
            let rec go acc b e = if e = 0 then acc else go (acc * b) b (e - 1)
            in VInt (go 1 base exp)
        | _ -> eval_error "int_pow: expected two ints"))
  ; ("int_div", VBuiltin ("int_div", function
        | [VInt a; VInt b] ->
          if b = 0 then eval_error "int_div: division by zero"
          else VInt (a / b)
        | _ -> eval_error "int_div: expected two ints"))
  ; ("int_mod", VBuiltin ("int_mod", function
        | [VInt a; VInt b] ->
          if b = 0 then eval_error "int_mod: division by zero"
          else VInt (a mod b)
        | _ -> eval_error "int_mod: expected two ints"))
  ; ("int_div_euclid", VBuiltin ("int_div_euclid", function
        | [VInt a; VInt b] ->
          if b = 0 then eval_error "int_div_euclid: division by zero"
          else
            let q = a / b in
            let r = a - q * b in
            VInt (if r < 0 then (if b > 0 then q - 1 else q + 1) else q)
        | _ -> eval_error "int_div_euclid: expected two ints"))
  ; ("int_mod_euclid", VBuiltin ("int_mod_euclid", function
        | [VInt a; VInt b] ->
          if b = 0 then eval_error "int_mod_euclid: division by zero"
          else
            let r = a mod b in
            VInt (if r < 0 then r + abs b else r)
        | _ -> eval_error "int_mod_euclid: expected two ints"))
  ; ("int_to_float", VBuiltin ("int_to_float", function
        | [VInt n] -> VFloat (float_of_int n)
        | _ -> eval_error "int_to_float: expected int"))
  ; ("int_max_value", VBuiltin ("int_max_value", function
        | [] | [VUnit] -> VInt max_int
        | _ -> eval_error "int_max_value: no arguments"))
  ; ("int_min_value", VBuiltin ("int_min_value", function
        | [] | [VUnit] -> VInt min_int
        | _ -> eval_error "int_min_value: no arguments"))
    (* ---- Int bitwise primitives ---- *)
  ; ("int_and", VBuiltin ("int_and", function
        | [VInt a; VInt b] -> VInt (a land b)
        | _ -> eval_error "int_and: expected two ints"))
  ; ("int_or", VBuiltin ("int_or", function
        | [VInt a; VInt b] -> VInt (a lor b)
        | _ -> eval_error "int_or: expected two ints"))
  ; ("int_xor", VBuiltin ("int_xor", function
        | [VInt a; VInt b] -> VInt (a lxor b)
        | _ -> eval_error "int_xor: expected two ints"))
  ; ("int_not", VBuiltin ("int_not", function
        | [VInt a] -> VInt (lnot a)
        | _ -> eval_error "int_not: expected int"))
  ; ("int_shl", VBuiltin ("int_shl", function
        | [VInt a; VInt n] ->
          if n < 0 || n >= 63 then eval_error "int_shl: shift out of range"
          else VInt (a lsl n)
        | _ -> eval_error "int_shl: expected two ints"))
  ; ("int_shr", VBuiltin ("int_shr", function
        | [VInt a; VInt n] ->
          if n < 0 || n >= 63 then eval_error "int_shr: shift out of range"
          else VInt (a lsr n)
        | _ -> eval_error "int_shr: expected two ints"))
  ; ("int_popcount", VBuiltin ("int_popcount", function
        | [VInt n] ->
          (* Count set bits in 63-bit OCaml int *)
          let x = ref (if n < 0 then n lxor min_int else n) in
          let c = ref 0 in
          while !x <> 0 do
            x := !x land (!x - 1);
            incr c
          done;
          if n < 0 then VInt (!c + 1)
          else VInt !c
        | _ -> eval_error "int_popcount: expected int"))

    (* ---- Float primitives ---- *)
  ; ("float_abs", VBuiltin ("float_abs", function
        | [VFloat f] -> VFloat (abs_float f)
        | _ -> eval_error "float_abs: expected float"))
  ; ("float_floor", VBuiltin ("float_floor", function
        | [VFloat f] -> VInt (int_of_float (floor f))
        | _ -> eval_error "float_floor: expected float"))
  ; ("float_ceil", VBuiltin ("float_ceil", function
        | [VFloat f] -> VInt (int_of_float (ceil f))
        | _ -> eval_error "float_ceil: expected float"))
  ; ("float_round", VBuiltin ("float_round", function
        | [VFloat f] -> VInt (Float.to_int (Float.round f))
        | _ -> eval_error "float_round: expected float"))
  ; ("float_truncate", VBuiltin ("float_truncate", function
        | [VFloat f] -> VInt (Float.to_int f)
        | _ -> eval_error "float_truncate: expected float"))
  ; ("float_to_int", VBuiltin ("float_to_int", function
        | [VFloat f] -> VInt (Float.to_int f)
        | _ -> eval_error "float_to_int: expected float"))
  ; ("float_is_nan", VBuiltin ("float_is_nan", function
        | [VFloat f] -> VBool (Float.is_nan f)
        | _ -> eval_error "float_is_nan: expected float"))
  ; ("float_is_infinite", VBuiltin ("float_is_infinite", function
        | [VFloat f] -> VBool (Float.is_infinite f)
        | _ -> eval_error "float_is_infinite: expected float"))
  ; ("float_infinity",     VBuiltin ("float_infinity", function
        | [] | [VUnit] -> VFloat Float.infinity
        | _ -> eval_error "float_infinity: no arguments"))
  ; ("float_neg_infinity", VBuiltin ("float_neg_infinity", function
        | [] | [VUnit] -> VFloat Float.neg_infinity
        | _ -> eval_error "float_neg_infinity: no arguments"))
  ; ("float_nan", VBuiltin ("float_nan", function
        | [] | [VUnit] -> VFloat Float.nan
        | _ -> eval_error "float_nan: no arguments"))
  ; ("float_epsilon", VBuiltin ("float_epsilon", function
        | [] | [VUnit] -> VFloat epsilon_float
        | _ -> eval_error "float_epsilon: no arguments"))
  ; ("float_from_string", VBuiltin ("float_from_string", function
        | [VString s] ->
          (try VCon ("Some", [VFloat (float_of_string s)])
           with Failure _ -> VCon ("None", []))
        | _ -> eval_error "float_from_string: expected string"))
  ; ("string_to_float", VBuiltin ("string_to_float", function
        | [VString s] ->
          (try VCon ("Some", [VFloat (float_of_string s)])
           with Failure _ -> VCon ("None", []))
        | _ -> eval_error "string_to_float: expected string"))
  ; ("float_to_string", VBuiltin ("float_to_string", function
        | [VFloat f] -> VString (string_of_float f)
        | _ -> eval_error "float_to_string: expected float"))

    (* ---- Math / transcendentals ---- *)
  ; ("math_sqrt",  VBuiltin ("math_sqrt",  function
        | [VFloat f] -> VFloat (sqrt f) | _ -> eval_error "math_sqrt: expected float"))
  ; ("math_cbrt",  VBuiltin ("math_cbrt",  function
        | [VFloat f] -> VFloat (Float.cbrt f) | _ -> eval_error "math_cbrt: expected float"))
  ; ("math_pow",   VBuiltin ("math_pow",   function
        | [VFloat b; VFloat e] -> VFloat (b ** e) | _ -> eval_error "math_pow: expected two floats"))
  ; ("math_exp",   VBuiltin ("math_exp",   function
        | [VFloat f] -> VFloat (exp f) | _ -> eval_error "math_exp: expected float"))
  ; ("math_exp2",  VBuiltin ("math_exp2",  function
        | [VFloat f] -> VFloat (2.0 ** f) | _ -> eval_error "math_exp2: expected float"))
  ; ("math_log",   VBuiltin ("math_log",   function
        | [VFloat f] -> VFloat (log f) | _ -> eval_error "math_log: expected float"))
  ; ("math_log2",  VBuiltin ("math_log2",  function
        | [VFloat f] -> VFloat (log f /. log 2.0) | _ -> eval_error "math_log2: expected float"))
  ; ("math_log10", VBuiltin ("math_log10", function
        | [VFloat f] -> VFloat (log10 f) | _ -> eval_error "math_log10: expected float"))
  ; ("math_sin",   VBuiltin ("math_sin",   function
        | [VFloat f] -> VFloat (sin f) | _ -> eval_error "math_sin: expected float"))
  ; ("math_cos",   VBuiltin ("math_cos",   function
        | [VFloat f] -> VFloat (cos f) | _ -> eval_error "math_cos: expected float"))
  ; ("math_tan",   VBuiltin ("math_tan",   function
        | [VFloat f] -> VFloat (tan f) | _ -> eval_error "math_tan: expected float"))
  ; ("math_asin",  VBuiltin ("math_asin",  function
        | [VFloat f] -> VFloat (asin f) | _ -> eval_error "math_asin: expected float"))
  ; ("math_acos",  VBuiltin ("math_acos",  function
        | [VFloat f] -> VFloat (acos f) | _ -> eval_error "math_acos: expected float"))
  ; ("math_atan",  VBuiltin ("math_atan",  function
        | [VFloat f] -> VFloat (atan f) | _ -> eval_error "math_atan: expected float"))
  ; ("math_atan2", VBuiltin ("math_atan2", function
        | [VFloat y; VFloat x] -> VFloat (atan2 y x)
        | _ -> eval_error "math_atan2: expected two floats"))
  ; ("math_sinh",  VBuiltin ("math_sinh",  function
        | [VFloat f] -> VFloat (sinh f) | _ -> eval_error "math_sinh: expected float"))
  ; ("math_cosh",  VBuiltin ("math_cosh",  function
        | [VFloat f] -> VFloat (cosh f) | _ -> eval_error "math_cosh: expected float"))
  ; ("math_tanh",  VBuiltin ("math_tanh",  function
        | [VFloat f] -> VFloat (tanh f) | _ -> eval_error "math_tanh: expected float"))

    (* ---- String primitives ---- *)
  ; ("string_is_empty", VBuiltin ("string_is_empty", function
        | [VString s] -> VBool (s = "")
        | _ -> eval_error "string_is_empty: expected string"))
  ; ("string_slice", VBuiltin ("string_slice", function
        | [VString s; VInt start; VInt len] ->
          let slen = String.length s in
          let start' = max 0 (min start slen) in
          let len' = max 0 (min len (slen - start')) in
          VString (String.sub s start' len')
        | _ -> eval_error "string_slice: expected string, int, int"))
  ; ("string_contains", VBuiltin ("string_contains", function
        | [VString s; VString sub] ->
          let ls = String.length s and lsub = String.length sub in
          if lsub = 0 then VBool true
          else if ls < lsub then VBool false
          else
            let found = ref false in
            for i = 0 to ls - lsub do
              if String.sub s i lsub = sub then found := true
            done;
            VBool !found
        | _ -> eval_error "string_contains: expected two strings"))
  ; ("string_starts_with", VBuiltin ("string_starts_with", function
        | [VString s; VString prefix] ->
          let lp = String.length prefix in
          VBool (String.length s >= lp && String.sub s 0 lp = prefix)
        | _ -> eval_error "string_starts_with: expected two strings"))
  ; ("string_ends_with", VBuiltin ("string_ends_with", function
        | [VString s; VString suffix] ->
          let ls = String.length s and lsuf = String.length suffix in
          VBool (ls >= lsuf && String.sub s (ls - lsuf) lsuf = suffix)
        | _ -> eval_error "string_ends_with: expected two strings"))
  ; ("string_index_of", VBuiltin ("string_index_of", function
        | [VString s; VString sub] ->
          let ls = String.length s and lsub = String.length sub in
          if lsub = 0 then VCon ("Some", [VInt 0])
          else begin
            let result = ref None in
            (try
               for i = 0 to ls - lsub do
                 if String.sub s i lsub = sub then
                   (result := Some i; raise Exit)
               done
             with Exit -> ());
            match !result with
            | Some i -> VCon ("Some", [VInt i])
            | None   -> VCon ("None", [])
          end
        | _ -> eval_error "string_index_of: expected two strings"))
  ; ("string_replace", VBuiltin ("string_replace", function
        | [VString s; VString old_; VString new_] ->
          let lold = String.length old_ in
          if lold = 0 then VString s
          else begin
            let ls = String.length s in
            let idx = ref (-1) in
            (try
               for i = 0 to ls - lold do
                 if String.sub s i lold = old_ then
                   (idx := i; raise Exit)
               done
             with Exit -> ());
            if !idx = -1 then VString s
            else VString (String.sub s 0 !idx ^ new_ ^
                          String.sub s (!idx + lold) (ls - !idx - lold))
          end
        | _ -> eval_error "string_replace: expected three strings"))
  ; ("string_replace_all", VBuiltin ("string_replace_all", function
        | [VString s; VString old_; VString new_] ->
          if old_ = "" then VString s
          else begin
            let buf = Buffer.create (String.length s) in
            let lold = String.length old_ in
            let ls = String.length s in
            let i = ref 0 in
            while !i <= ls - lold do
              if String.sub s !i lold = old_ then begin
                Buffer.add_string buf new_;
                i := !i + lold
              end else begin
                Buffer.add_char buf s.[!i];
                incr i
              end
            done;
            while !i < ls do
              Buffer.add_char buf s.[!i];
              incr i
            done;
            VString (Buffer.contents buf)
          end
        | _ -> eval_error "string_replace_all: expected three strings"))
  ; ("string_split", VBuiltin ("string_split", function
        | [VString s; VString sep] ->
          let parts =
            if sep = "" then
              List.init (String.length s) (fun i -> String.make 1 s.[i])
            else begin
              let ls = String.length s and lsep = String.length sep in
              let result = ref [] and start = ref 0 in
              (try
                 for i = 0 to ls - lsep do
                   if String.sub s i lsep = sep then begin
                     result := String.sub s !start (i - !start) :: !result;
                     start := i + lsep
                   end
                 done
               with _ -> ());
              result := String.sub s !start (ls - !start) :: !result;
              List.rev !result
            end
          in
          List.fold_right (fun p acc -> VCon ("Cons", [VString p; acc]))
            parts (VCon ("Nil", []))
        | _ -> eval_error "string_split: expected two strings"))
  ; ("string_join", VBuiltin ("string_join", function
        | [lst; VString sep] ->
          let rec to_strings = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VString s; rest]) -> s :: to_strings rest
            | _ -> eval_error "string_join: list must contain strings"
          in
          VString (String.concat sep (to_strings lst))
        | _ -> eval_error "string_join: expected list and string separator"))
  ; ("string_trim", VBuiltin ("string_trim", function
        | [VString s] -> VString (String.trim s)
        | _ -> eval_error "string_trim: expected string"))
  ; ("string_trim_start", VBuiltin ("string_trim_start", function
        | [VString s] ->
          let i = ref 0 in
          while !i < String.length s &&
                (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\n' || s.[!i] = '\r') do
            incr i
          done;
          VString (String.sub s !i (String.length s - !i))
        | _ -> eval_error "string_trim_start: expected string"))
  ; ("string_trim_end", VBuiltin ("string_trim_end", function
        | [VString s] ->
          let i = ref (String.length s - 1) in
          while !i >= 0 &&
                (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\n' || s.[!i] = '\r') do
            decr i
          done;
          VString (String.sub s 0 (!i + 1))
        | _ -> eval_error "string_trim_end: expected string"))
  ; ("string_to_uppercase", VBuiltin ("string_to_uppercase", function
        | [VString s] -> VString (String.uppercase_ascii s)
        | _ -> eval_error "string_to_uppercase: expected string"))
  ; ("string_to_lowercase", VBuiltin ("string_to_lowercase", function
        | [VString s] -> VString (String.lowercase_ascii s)
        | _ -> eval_error "string_to_lowercase: expected string"))
  ; ("string_chars", VBuiltin ("string_chars", function
        | [VString s] ->
          let chars = List.init (String.length s) (fun i -> VString (String.make 1 s.[i])) in
          List.fold_right (fun c acc -> VCon ("Cons", [c; acc])) chars (VCon ("Nil", []))
        | _ -> eval_error "string_chars: expected string"))
  ; ("string_from_chars", VBuiltin ("string_from_chars", function
        | [lst] ->
          let buf = Buffer.create 8 in
          let rec go = function
            | VCon ("Nil", []) -> ()
            | VCon ("Cons", [VString c; rest]) -> Buffer.add_string buf c; go rest
            | _ -> eval_error "string_from_chars: list must contain single-char strings"
          in
          go lst; VString (Buffer.contents buf)
        | _ -> eval_error "string_from_chars: expected list of chars"))
  ; ("string_repeat", VBuiltin ("string_repeat", function
        | [VString s; VInt n] ->
          let buf = Buffer.create (String.length s * max 0 n) in
          for _ = 1 to n do Buffer.add_string buf s done;
          VString (Buffer.contents buf)
        | _ -> eval_error "string_repeat: expected string and int"))
  ; ("string_reverse", VBuiltin ("string_reverse", function
        | [VString s] ->
          let n = String.length s in
          VString (String.init n (fun i -> s.[n - 1 - i]))
        | _ -> eval_error "string_reverse: expected string"))
  ; ("string_pad_left", VBuiltin ("string_pad_left", function
        | [VString s; VInt width; VString fill] when String.length fill = 1 ->
          let ls = String.length s in
          if ls >= width then VString s
          else VString (String.make (width - ls) fill.[0] ^ s)
        | _ -> eval_error "string_pad_left: expected string, int, char-string"))
  ; ("string_pad_right", VBuiltin ("string_pad_right", function
        | [VString s; VInt width; VString fill] when String.length fill = 1 ->
          let ls = String.length s in
          if ls >= width then VString s
          else VString (s ^ String.make (width - ls) fill.[0])
        | _ -> eval_error "string_pad_right: expected string, int, char-string"))
  ; ("string_byte_length", VBuiltin ("string_byte_length", function
        | [VString s] -> VInt (String.length s)
        | _ -> eval_error "string_byte_length: expected string"))
  ; ("string_split_first", VBuiltin ("string_split_first", function
        (* Split on the first occurrence of [sep].
           Returns Some(head, tail) if found, None otherwise.
           Cost: O(n) scan for separator. *)
        | [VString s; VString sep] ->
          let ls = String.length s and lsep = String.length sep in
          if lsep = 0 then VCon ("None", [])
          else begin
            let rec find i =
              if i + lsep > ls then VCon ("None", [])
              else if String.sub s i lsep = sep then
                VCon ("Some", [VTuple [VString (String.sub s 0 i);
                                       VString (String.sub s (i + lsep) (ls - i - lsep))]])
              else find (i + 1)
            in find 0
          end
        | _ -> eval_error "string_split_first: expected two strings"))
  ; ("string_grapheme_count", VBuiltin ("string_grapheme_count", function
        (* Count Unicode codepoints (not grapheme clusters) in a UTF-8 string.
           For ASCII strings this equals the character count.
           Full grapheme-cluster segmentation is not available in the tree-walking
           interpreter without an external library; we count codepoints as a
           practical approximation.  Cost: O(n). *)
        | [VString s] ->
          let n = String.length s in
          let count = ref 0 in
          let i = ref 0 in
          while !i < n do
            let b = Char.code s.[!i] in
            (* UTF-8 continuation bytes are 0x80..0xBF; skip them *)
            if b land 0xC0 <> 0x80 then incr count;
            incr i
          done;
          VInt !count
        | _ -> eval_error "string_grapheme_count: expected string"))

    (* ---- Char primitives (chars represented as single-char strings) ---- *)
  ; ("char_is_alpha", VBuiltin ("char_is_alpha", function
        | [VString c] when String.length c = 1 ->
          let ch = c.[0] in VBool ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'))
        | _ -> eval_error "char_is_alpha: expected single-char string"))
  ; ("char_is_digit", VBuiltin ("char_is_digit", function
        | [VString c] when String.length c = 1 ->
          VBool (c.[0] >= '0' && c.[0] <= '9')
        | _ -> eval_error "char_is_digit: expected single-char string"))
  ; ("char_is_alphanumeric", VBuiltin ("char_is_alphanumeric", function
        | [VString c] when String.length c = 1 ->
          let ch = c.[0] in
          VBool ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9'))
        | _ -> eval_error "char_is_alphanumeric: expected single-char string"))
  ; ("char_is_whitespace", VBuiltin ("char_is_whitespace", function
        | [VString c] when String.length c = 1 ->
          VBool (c.[0] = ' ' || c.[0] = '\t' || c.[0] = '\n' || c.[0] = '\r')
        | _ -> eval_error "char_is_whitespace: expected single-char string"))
  ; ("char_is_uppercase", VBuiltin ("char_is_uppercase", function
        | [VString c] when String.length c = 1 ->
          VBool (c.[0] >= 'A' && c.[0] <= 'Z')
        | _ -> eval_error "char_is_uppercase: expected single-char string"))
  ; ("char_is_lowercase", VBuiltin ("char_is_lowercase", function
        | [VString c] when String.length c = 1 ->
          VBool (c.[0] >= 'a' && c.[0] <= 'z')
        | _ -> eval_error "char_is_lowercase: expected single-char string"))
  ; ("char_to_uppercase", VBuiltin ("char_to_uppercase", function
        | [VString c] when String.length c = 1 ->
          VString (String.make 1 (Char.uppercase_ascii c.[0]))
        | _ -> eval_error "char_to_uppercase: expected single-char string"))
  ; ("char_to_lowercase", VBuiltin ("char_to_lowercase", function
        | [VString c] when String.length c = 1 ->
          VString (String.make 1 (Char.lowercase_ascii c.[0]))
        | _ -> eval_error "char_to_lowercase: expected single-char string"))
  ; ("char_to_int", VBuiltin ("char_to_int", function
        | [VString c] when String.length c = 1 -> VInt (Char.code c.[0])
        | _ -> eval_error "char_to_int: expected single-char string"))
  ; ("char_from_int", VBuiltin ("char_from_int", function
        | [VInt n] ->
          if n >= 0 && n <= 127 then VString (String.make 1 (Char.chr n))
          else VString ""
        | _ -> eval_error "char_from_int: expected int"))

    (* ---- Comparison helpers ---- *)
  ; ("compare_int", VBuiltin ("compare_int", function
        | [VInt a; VInt b] ->
          VCon ((if a < b then "Less" else if a > b then "Greater" else "Equal"), [])
        | _ -> eval_error "compare_int: expected two ints"))
  ; ("compare_float", VBuiltin ("compare_float", function
        | [VFloat a; VFloat b] ->
          VCon ((if a < b then "Less" else if a > b then "Greater" else "Equal"), [])
        | _ -> eval_error "compare_float: expected two floats"))
  ; ("compare_string", VBuiltin ("compare_string", function
        | [VString a; VString b] ->
          let c = String.compare a b in
          VCon ((if c < 0 then "Less" else if c > 0 then "Greater" else "Equal"), [])
        | _ -> eval_error "compare_string: expected two strings"))

    (* ---- Panic / diverging functions ---- *)
  ; ("panic", VBuiltin ("panic", function
        | [VString msg] -> eval_error "panic: %s" msg
        | [v] -> eval_error "panic: %s" (value_display v)
        | _ -> eval_error "panic"))
  ; ("todo_", VBuiltin ("todo_", function
        | [VString msg] -> eval_error "todo: %s" msg
        | _ -> eval_error "todo: not yet implemented"))
  ; ("unreachable_", VBuiltin ("unreachable_", function
        | _ -> eval_error "unreachable: reached unreachable code"))
    (* ── File I/O ──────────────────────────────────────────────────── *)
  ; ("file_exists", VBuiltin ("file_exists", function
      | [VString path] -> VBool (Sys.file_exists path)
      | _ -> eval_error "file_exists(path)"))

  ; ("file_read", VBuiltin ("file_read", function
      | [VString path] ->
        (try
           let ic = open_in path in
           Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
             let n = in_channel_length ic in
             let s = Bytes.create n in
             really_input ic s 0 n;
             VCon ("Ok", [VString (Bytes.to_string s)]))
         with
         | Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
      | _ -> eval_error "file_read(path)"))

  ; ("file_write", VBuiltin ("file_write", function
      | [VString path; VString data] ->
        (try
           let oc = open_out path in
           Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
             output_string oc data;
             VCon ("Ok", [VAtom "ok"]))
         with
         | Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
      | _ -> eval_error "file_write(path, data)"))

  ; ("file_append", VBuiltin ("file_append", function
      | [VString path; VString data] ->
        (try
           let oc = open_out_gen [Open_append; Open_creat] 0o644 path in
           Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
             output_string oc data;
             VCon ("Ok", [VAtom "ok"]))
         with
         | Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
      | _ -> eval_error "file_append(path, data)"))

  ; ("file_delete", VBuiltin ("file_delete", function
      | [VString path] ->
        (try Sys.remove path; VCon ("Ok", [VAtom "ok"])
         with Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
      | _ -> eval_error "file_delete(path)"))

  ; ("file_copy", VBuiltin ("file_copy", function
      | [VString src; VString dst] ->
        (try
           let ic = open_in_bin src in
           (try
              let oc = open_out_bin dst in
              (try
                 let buf = Bytes.create 65536 in
                 let rec loop () =
                   let n = input ic buf 0 65536 in
                   if n > 0 then (output oc buf 0 n; loop ())
                 in
                 loop ();
                 close_in ic; close_out oc;
                 VCon ("Ok", [VAtom "ok"])
               with e -> close_in ic; close_out oc; raise e)
            with e -> close_in ic; raise e)
         with Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
      | _ -> eval_error "file_copy(src, dst)"))

  ; ("file_rename", VBuiltin ("file_rename", function
      | [VString src; VString dst] ->
        (try Sys.rename src dst; VCon ("Ok", [VAtom "ok"])
         with Sys_error msg -> VCon ("Err", [VCon ("IoError", [VString msg])]))
      | _ -> eval_error "file_rename(src, dst)"))

  ; ("file_stat", VBuiltin ("file_stat", function
      | [VString path] ->
        (try
           let st = Unix.stat path in
           let kind = match st.Unix.st_kind with
             | Unix.S_REG  -> VCon ("RegularFile", [])
             | Unix.S_DIR  -> VCon ("Directory", [])
             | Unix.S_LNK  -> VCon ("Symlink", [])
             | _           -> VCon ("Other", [])
           in
           (* FileStat is a positional constructor: FileStat(size, kind, modified, accessed) *)
           VCon ("Ok", [VCon ("FileStat", [
             VInt st.Unix.st_size;
             kind;
             VInt (int_of_float st.Unix.st_mtime);
             VInt (int_of_float st.Unix.st_atime);
           ])])
         with
         | Unix.Unix_error (Unix.ENOENT, _, _) ->
           VCon ("Err", [VCon ("NotFound", [VString path])])
         | Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
      | _ -> eval_error "file_stat(path)"))

  ; ("file_open", VBuiltin ("file_open", function
      | [VString path] ->
        (try
           let fd = Unix.openfile path [Unix.O_RDONLY] 0 in
           let ic = Unix.in_channel_of_descr fd in
           VCon ("Ok", [VInt (Obj.magic ic : int)])
         with
         | Unix.Unix_error (Unix.ENOENT, _, _) ->
           VCon ("Err", [VCon ("NotFound", [VString path])])
         | Unix.Unix_error (Unix.EACCES, _, _) ->
           VCon ("Err", [VCon ("Permission", [VString path])])
         | Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
      | _ -> eval_error "file_open(path)"))

  ; ("file_read_line", VBuiltin ("file_read_line", function
      | [VInt ic_int] ->
        let ic : in_channel = Obj.magic ic_int in
        (try VCon ("Some", [VString (input_line ic)])
         with End_of_file -> VCon ("None", []))
      | _ -> eval_error "file_read_line(fd)"))

  ; ("file_read_chunk", VBuiltin ("file_read_chunk", function
      | [VInt ic_int; VInt size] ->
        let ic : in_channel = Obj.magic ic_int in
        let buf = Bytes.create size in
        (try
           let n = input ic buf 0 size in
           if n = 0 then VCon ("None", [])
           else VCon ("Some", [VString (Bytes.sub_string buf 0 n)])
         with End_of_file -> VCon ("None", []))
      | _ -> eval_error "file_read_chunk(fd, size)"))

  ; ("file_close", VBuiltin ("file_close", function
      | [VInt ic_int] ->
        let ic : in_channel = Obj.magic ic_int in
        (try close_in ic with _ -> ());
        VAtom "ok"
      | _ -> eval_error "file_close(fd)"))

  (* ── Dir I/O ───────────────────────────────────────────────────── *)
  ; ("dir_exists", VBuiltin ("dir_exists", function
      | [VString path] ->
        VBool (Sys.file_exists path && Sys.is_directory path)
      | _ -> eval_error "dir_exists(path)"))

  ; ("dir_list", VBuiltin ("dir_list", function
      | [VString path] ->
        (try
           let d = Unix.opendir path in
           let entries = ref [] in
           (try
              while true do
                let e = Unix.readdir d in
                if e <> "." && e <> ".." then
                  entries := e :: !entries
              done
            with End_of_file -> ());
           Unix.closedir d;
           let sorted = List.sort String.compare !entries in
           let lst = List.fold_right
             (fun e acc -> VCon ("Cons", [VString e; acc]))
             sorted (VCon ("Nil", [])) in
           VCon ("Ok", [lst])
         with
         | Unix.Unix_error (Unix.ENOENT, _, _) ->
           VCon ("Err", [VCon ("NotFound", [VString path])])
         | Unix.Unix_error (Unix.EACCES, _, _) ->
           VCon ("Err", [VCon ("Permission", [VString path])])
         | Unix.Unix_error (Unix.ENOTDIR, _, _) ->
           VCon ("Err", [VCon ("IsDirectory", [VString path])])
         | Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
      | _ -> eval_error "dir_list(path)"))

  ; ("dir_mkdir", VBuiltin ("dir_mkdir", function
      | [VString path] ->
        (try Unix.mkdir path 0o755; VCon ("Ok", [VAtom "ok"])
         with
         | Unix.Unix_error (Unix.EEXIST, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (path ^ ": already exists")])])
         | Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
      | _ -> eval_error "dir_mkdir(path)"))

  ; ("dir_mkdir_p", VBuiltin ("dir_mkdir_p", function
      | [VString path] ->
        let parts = String.split_on_char '/' path
          |> List.filter (fun s -> s <> "") in
        let prefix = if String.length path > 0 && path.[0] = '/' then "/" else "" in
        (try
           List.fold_left (fun acc part ->
             let p = if acc = "" || acc = "/" then acc ^ part else acc ^ "/" ^ part in
             (* Ignore EEXIST: another process may have created the dir between check and mkdir *)
             (try
                if not (Sys.file_exists p) then Unix.mkdir p 0o755
              with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
             p
           ) prefix parts |> ignore;
           VCon ("Ok", [VAtom "ok"])
         with
         | Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
      | _ -> eval_error "dir_mkdir_p(path)"))

  ; ("dir_rmdir", VBuiltin ("dir_rmdir", function
      | [VString path] ->
        (try Unix.rmdir path; VCon ("Ok", [VAtom "ok"])
         with
         | Unix.Unix_error (Unix.ENOTEMPTY, _, _) ->
           VCon ("Err", [VCon ("NotEmpty", [VString path])])
         | Unix.Unix_error (Unix.ENOENT, _, _) ->
           VCon ("Err", [VCon ("NotFound", [VString path])])
         | Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
      | _ -> eval_error "dir_rmdir(path)"))

  ; ("dir_rm_rf", VBuiltin ("dir_rm_rf", function
      | [VString path] ->
        if path = "" || path = "/" then
          VCon ("Err", [VCon ("IoError", [VString "refusing to delete root"])])
        else
          let rec rm_rf p =
            match Unix.lstat p with
            | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()
            | st ->
              if st.Unix.st_kind = Unix.S_DIR then begin
                let entries = Sys.readdir p in
                Array.iter (fun e -> rm_rf (p ^ "/" ^ e)) entries;
                Unix.rmdir p
              end else
                Sys.remove p
          in
          (try rm_rf path; VCon ("Ok", [VAtom "ok"])
           with
           | Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VCon ("IoError", [VString (Unix.error_message err)])]))
      | _ -> eval_error "dir_rm_rf(path)"))

  (* ── String extras ─────────────────────────────────────────────── *)
  ; ("string_last_index_of", VBuiltin ("string_last_index_of", function
      | [VString s; VString sub] ->
        let slen = String.length s and sublen = String.length sub in
        if sublen = 0 then VCon ("Some", [VInt slen])
        else if sublen > slen then VCon ("None", [])
        else
          let result = ref None in
          for i = 0 to slen - sublen do
            if String.sub s i sublen = sub then result := Some i
          done;
          (match !result with
           | None -> VCon ("None", [])
           | Some i -> VCon ("Some", [VInt i]))
      | _ -> eval_error "string_last_index_of(s, sub)"))

    (* ---- Time builtins ---- *)
  ; ("unix_time", VBuiltin ("unix_time", function
        | [] -> VFloat (Unix.gettimeofday ())
        | [VUnit] -> VFloat (Unix.gettimeofday ())
        | _ -> eval_error "unix_time: takes no arguments"))

    (* ---- TCP socket builtins ---- *)
  ; ("tcp_connect", VBuiltin ("tcp_connect", function
        | [VString host; VInt port] ->
          (try
             let open Unix in
             let addrs = getaddrinfo host (string_of_int port)
               [AI_FAMILY PF_INET; AI_SOCKTYPE SOCK_STREAM] in
             (match addrs with
              | [] -> VCon ("Err", [VString ("cannot resolve " ^ host)])
              | ai :: _ ->
                let fd = socket ai.ai_family ai.ai_socktype ai.ai_protocol in
                (try
                   connect fd ai.ai_addr;
                   VCon ("Ok", [VInt (Obj.magic fd : int)])
                 with Unix_error (err, _, _) ->
                   close fd;
                   VCon ("Err", [VString (error_message err)])))
           with
           | Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VString (Unix.error_message err)])
           | exn ->
             VCon ("Err", [VString (Printexc.to_string exn)]))
        | _ -> eval_error "tcp_connect(host, port)"))
  ; ("tcp_send_all", VBuiltin ("tcp_send_all", function
        | [VInt fd; VString data] ->
          let sock = (Obj.magic fd : Unix.file_descr) in
          let buf = Bytes.of_string data in
          let total = Bytes.length buf in
          let rec loop off =
            if off >= total then VCon ("Ok", [VUnit])
            else
              try
                let n = Unix.send sock buf off (total - off) [] in
                loop (off + n)
              with Unix.Unix_error (err, _, _) ->
                VCon ("Err", [VString (Unix.error_message err)])
          in
          loop 0
        | _ -> eval_error "tcp_send_all(fd, data)"))
  ; ("tcp_recv_all", VBuiltin ("tcp_recv_all", function
        | [VInt fd; VInt max_bytes; VInt _timeout_ms] ->
          let sock = (Obj.magic fd : Unix.file_descr) in
          let buf = Buffer.create 4096 in
          let chunk = Bytes.create 4096 in
          let rec loop total =
            if total >= max_bytes then
              VCon ("Ok", [VString (Buffer.contents buf)])
            else
              try
                let to_read = min 4096 (max_bytes - total) in
                let n = Unix.recv sock chunk 0 to_read [] in
                if n = 0 then VCon ("Ok", [VString (Buffer.contents buf)])
                else begin
                  Buffer.add_subbytes buf chunk 0 n;
                  loop (total + n)
                end
              with Unix.Unix_error (err, _, _) ->
                VCon ("Err", [VString (Unix.error_message err)])
          in
          loop 0
        | _ -> eval_error "tcp_recv_all(fd, max_bytes, timeout_ms)"))
  ; ("tcp_close", VBuiltin ("tcp_close", function
        | [VInt fd] ->
          (try Unix.close (Obj.magic fd : Unix.file_descr) with _ -> ());
          VUnit
        | _ -> eval_error "tcp_close(fd)"))
  ; ("tcp_recv_http", VBuiltin ("tcp_recv_http", function
        | [VInt fd; VInt max_bytes] ->
          (* Read an HTTP response on a keep-alive connection:
             1. Read headers byte-by-byte until \r\n\r\n
             2. Parse Content-Length (or read until close if absent)
             3. Read exactly Content-Length bytes of body *)
          let sock = (Obj.magic fd : Unix.file_descr) in
          let hdr_buf = Buffer.create 1024 in
          let one = Bytes.create 1 in
          let found_end = ref false in
          (try
            while not !found_end do
              let n = Unix.recv sock one 0 1 [] in
              if n = 0 then (found_end := true)  (* connection closed *)
              else begin
                Buffer.add_subbytes hdr_buf one 0 1;
                let len = Buffer.length hdr_buf in
                if len >= 4 then begin
                  let s = Buffer.contents hdr_buf in
                  if s.[len-4] = '\r' && s.[len-3] = '\n'
                     && s.[len-2] = '\r' && s.[len-1] = '\n' then
                    found_end := true
                end
              end
            done
          with Unix.Unix_error (err, _, _) ->
            ignore err  (* treat as end-of-headers *));
          let headers_str = Buffer.contents hdr_buf in
          (* Parse Content-Length from headers *)
          let content_length = ref (-1) in
          let chunked = ref false in
          let lines = String.split_on_char '\n' headers_str in
          List.iter (fun line ->
            let t = String.trim (String.lowercase_ascii line) in
            if String.length t > 16
               && String.sub t 0 16 = "content-length: " then
              (try content_length :=
                 int_of_string (String.trim (String.sub t 16
                   (String.length t - 16)))
               with _ -> ())
            else if String.length t > 19
               && String.sub t 0 19 = "transfer-encoding: " then
              let v = String.trim (String.sub t 19 (String.length t - 19)) in
              if v = "chunked" then chunked := true
          ) lines;
          let body_buf = Buffer.create 4096 in
          if !chunked then begin
            (* Chunked transfer: read chunk-size\r\n, chunk-data\r\n, repeat until 0 *)
            let line_buf = Buffer.create 32 in
            let read_line () =
              Buffer.clear line_buf;
              let stop = ref false in
              (try while not !stop do
                let n = Unix.recv sock one 0 1 [] in
                if n = 0 then stop := true
                else begin
                  let c = Bytes.get one 0 in
                  Buffer.add_char line_buf c;
                  let lb = Buffer.length line_buf in
                  if lb >= 2 then begin
                    let s = Buffer.contents line_buf in
                    if s.[lb-2] = '\r' && s.[lb-1] = '\n' then
                      stop := true
                  end
                end
              done with _ -> ());
              let s = Buffer.contents line_buf in
              if String.length s >= 2
              then String.sub s 0 (String.length s - 2)
              else s
            in
            let done_ = ref false in
            while not !done_ do
              let size_line = read_line () in
              let chunk_size =
                try int_of_string ("0x" ^ String.trim size_line)
                with _ -> 0 in
              if chunk_size = 0 then
                done_ := true
              else begin
                let remaining = ref chunk_size in
                let chunk = Bytes.create (min chunk_size 8192) in
                while !remaining > 0 do
                  let to_read = min (Bytes.length chunk) !remaining in
                  let n = Unix.recv sock chunk 0 to_read [] in
                  if n = 0 then remaining := 0
                  else begin
                    Buffer.add_subbytes body_buf chunk 0 n;
                    remaining := !remaining - n
                  end
                done;
                ignore (read_line ())  (* consume trailing \r\n *)
              end
            done
          end else if !content_length >= 0 then begin
            let remaining = ref (min !content_length max_bytes) in
            let chunk = Bytes.create 4096 in
            while !remaining > 0 do
              let to_read = min 4096 !remaining in
              let n = Unix.recv sock chunk 0 to_read [] in
              if n = 0 then remaining := 0
              else begin
                Buffer.add_subbytes body_buf chunk 0 n;
                remaining := !remaining - n
              end
            done
          end else begin
            (* No Content-Length, not chunked: read until close *)
            let chunk = Bytes.create 4096 in
            let total = ref 0 in
            let stop = ref false in
            while not !stop && !total < max_bytes do
              (try
                let to_read = min 4096 (max_bytes - !total) in
                let n = Unix.recv sock chunk 0 to_read [] in
                if n = 0 then stop := true
                else begin
                  Buffer.add_subbytes body_buf chunk 0 n;
                  total := !total + n
                end
              with _ -> stop := true)
            done
          end;
          (* Return headers ++ body as a single raw string *)
          VCon ("Ok", [VString (headers_str ^ Buffer.contents body_buf)])
        | _ -> eval_error "tcp_recv_http(fd, max_bytes)"))
  ; ("tcp_recv_http_headers", VBuiltin ("tcp_recv_http_headers", function
        | [VInt fd] ->
          (* Read HTTP response headers up to \r\n\r\n.
             Returns Ok((headers_string, content_length, is_chunked)).
             content_length = -1 if not present. *)
          let sock = (Obj.magic fd : Unix.file_descr) in
          let hdr_buf = Buffer.create 1024 in
          let one = Bytes.create 1 in
          let found_end = ref false in
          (try
            while not !found_end do
              let n = Unix.recv sock one 0 1 [] in
              if n = 0 then (found_end := true)
              else begin
                Buffer.add_subbytes hdr_buf one 0 1;
                let len = Buffer.length hdr_buf in
                if len >= 4 then begin
                  let s = Buffer.contents hdr_buf in
                  if s.[len-4] = '\r' && s.[len-3] = '\n'
                     && s.[len-2] = '\r' && s.[len-1] = '\n' then
                    found_end := true
                end
              end
            done
          with Unix.Unix_error _ -> ());
          let headers_str = Buffer.contents hdr_buf in
          let content_length = ref (-1) in
          let chunked = ref false in
          List.iter (fun line ->
            let t = String.trim (String.lowercase_ascii line) in
            if String.length t > 16
               && String.sub t 0 16 = "content-length: " then
              (try content_length :=
                 int_of_string (String.trim (String.sub t 16
                   (String.length t - 16)))
               with _ -> ())
            else if String.length t > 19
               && String.sub t 0 19 = "transfer-encoding: " then
              let v = String.trim (String.sub t 19 (String.length t - 19)) in
              if v = "chunked" then chunked := true
          ) (String.split_on_char '\n' headers_str);
          VCon ("Ok", [VTuple [VString headers_str;
                               VInt !content_length;
                               VBool !chunked]])
        | _ -> eval_error "tcp_recv_http_headers(fd)"))
  ; ("tcp_recv_chunk", VBuiltin ("tcp_recv_chunk", function
        | [VInt fd; VInt max_bytes] ->
          (* Read up to max_bytes from fd. Returns Ok(string) or Ok("")
             on EOF. This is a single non-blocking-style read. *)
          let sock = (Obj.magic fd : Unix.file_descr) in
          let buf = Bytes.create (min max_bytes 8192) in
          (try
            let n = Unix.recv sock buf 0 (Bytes.length buf) [] in
            VCon ("Ok", [VString (Bytes.sub_string buf 0 n)])
          with Unix.Unix_error (err, _, _) ->
            VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "tcp_recv_chunk(fd, max_bytes)"))
  ; ("tcp_recv_chunked_frame", VBuiltin ("tcp_recv_chunked_frame", function
        | [VInt fd] ->
          (* Read one HTTP chunked transfer frame: size\r\n data\r\n.
             Returns Ok(string) for the data, Ok("") for the terminal 0-chunk. *)
          let sock = (Obj.magic fd : Unix.file_descr) in
          let one = Bytes.create 1 in
          (* Read the chunk-size line *)
          let line_buf = Buffer.create 32 in
          let stop = ref false in
          (try while not !stop do
            let n = Unix.recv sock one 0 1 [] in
            if n = 0 then stop := true
            else begin
              Buffer.add_char line_buf (Bytes.get one 0);
              let lb = Buffer.length line_buf in
              if lb >= 2 then begin
                let s = Buffer.contents line_buf in
                if s.[lb-2] = '\r' && s.[lb-1] = '\n' then
                  stop := true
              end
            end
          done with _ -> ());
          let size_str = Buffer.contents line_buf in
          let size_str = if String.length size_str >= 2
            then String.sub size_str 0 (String.length size_str - 2)
            else size_str in
          let chunk_size =
            try int_of_string ("0x" ^ String.trim size_str)
            with _ -> 0 in
          if chunk_size = 0 then
            VCon ("Ok", [VString ""])
          else begin
            let data_buf = Buffer.create chunk_size in
            let remaining = ref chunk_size in
            let tmp = Bytes.create (min chunk_size 8192) in
            (try while !remaining > 0 do
              let to_read = min (Bytes.length tmp) !remaining in
              let n = Unix.recv sock tmp 0 to_read [] in
              if n = 0 then remaining := 0
              else begin
                Buffer.add_subbytes data_buf tmp 0 n;
                remaining := !remaining - n
              end
            done with _ -> ());
            (* consume trailing \r\n *)
            (try
              ignore (Unix.recv sock one 0 1 []);
              ignore (Unix.recv sock one 0 1 [])
            with _ -> ());
            VCon ("Ok", [VString (Buffer.contents data_buf)])
          end
        | _ -> eval_error "tcp_recv_chunked_frame(fd)"))
    (* ---- HTTP serialization builtins ---- *)
  ; ("http_serialize_request", VBuiltin ("http_serialize_request", function
        | [VString meth; VString host; VString path; query_opt; header_list; VString body] ->
          let buf = Buffer.create 256 in
          let query_str = match query_opt with
            | VCon ("Some", [VString q]) -> "?" ^ q
            | _ -> ""
          in
          Buffer.add_string buf meth;
          Buffer.add_char buf ' ';
          Buffer.add_string buf path;
          Buffer.add_string buf query_str;
          Buffer.add_string buf " HTTP/1.1\r\n";
          Buffer.add_string buf "Host: ";
          Buffer.add_string buf host;
          Buffer.add_string buf "\r\n";
          let rec add_headers = function
            | VCon ("Nil", []) -> ()
            | VCon ("Cons", [VCon ("Header", [VString n; VString v]); rest]) ->
              Buffer.add_string buf n;
              Buffer.add_string buf ": ";
              Buffer.add_string buf v;
              Buffer.add_string buf "\r\n";
              add_headers rest
            | _ -> ()
          in
          add_headers header_list;
          if body <> "" then begin
            Buffer.add_string buf "Content-Length: ";
            Buffer.add_string buf (string_of_int (String.length body));
            Buffer.add_string buf "\r\n"
          end;
          Buffer.add_string buf "\r\n";
          Buffer.add_string buf body;
          VString (Buffer.contents buf)
        | _ -> eval_error "http_serialize_request(method, host, path, query_opt, headers, body)"))
  ; ("http_parse_response", VBuiltin ("http_parse_response", function
        | [VString raw] ->
          let header_end =
            let rec find i =
              if i + 3 >= String.length raw then String.length raw
              else if raw.[i] = '\r' && raw.[i+1] = '\n' && raw.[i+2] = '\r' && raw.[i+3] = '\n' then i
              else find (i + 1)
            in find 0
          in
          let header_section = String.sub raw 0 header_end in
          let body =
            if header_end + 4 <= String.length raw then
              String.sub raw (header_end + 4) (String.length raw - header_end - 4)
            else ""
          in
          let lines = String.split_on_char '\n' header_section in
          (match lines with
           | [] -> VCon ("Err", [VString "empty response"])
           | status_line :: rest ->
             let trimmed_status = String.trim status_line in
             let parts = String.split_on_char ' ' trimmed_status in
             (match parts with
              | _ :: code_str :: _ ->
                (try
                   let code = int_of_string code_str in
                   let hdrs = List.filter_map (fun line ->
                     let t = String.trim line in
                     if t = "" then None
                     else match String.index_opt t ':' with
                       | Some i ->
                         let name = String.trim (String.sub t 0 i) in
                         let value = String.trim (String.sub t (i+1) (String.length t - i - 1)) in
                         Some (name, value)
                       | None -> None
                   ) rest in
                   let header_list = List.fold_right (fun (n, v) acc ->
                     VCon ("Cons", [VCon ("Header", [VString n; VString v]); acc])
                   ) hdrs (VCon ("Nil", [])) in
                   VCon ("Ok", [VTuple [VInt code; header_list; VString body]])
                 with _ ->
                   VCon ("Err", [VString ("bad status code: " ^ code_str)]))
              | _ ->
                VCon ("Err", [VString ("bad status line: " ^ (List.hd lines))])))
        | _ -> eval_error "http_parse_response(raw_string)"))

  (* ── HTTP server (interpreter mode: pure-OCaml implementation) ──── *)
  ; ("http_server_listen", VBuiltin ("http_server_listen", function
      | [VInt port; VInt _max_conns; VInt _idle_timeout; pipeline_fn] ->
        let open Unix in
        let server_sock = socket PF_INET SOCK_STREAM 0 in
        setsockopt server_sock SO_REUSEADDR true;
        bind server_sock (ADDR_INET (inet_addr_any, port));
        listen server_sock 128;
        Printf.eprintf "march: HTTP server listening on port %d\n%!" port;
        (try
           while true do
             let (client_sock, _addr) = accept server_sock in
             (try handle_http_connection client_sock pipeline_fn
              with _ -> ());
             (try close client_sock with _ -> ())
           done
         with exn ->
           (try close server_sock with _ -> ());
           raise exn);
        VUnit
      | _ -> eval_error "http_server_listen(port, max_conns, idle_timeout, pipeline)"))

  (* ── HTTP server: fork-based N-request variant ───────────────────── *)
  (* http_server_spawn_n(port, n, max_conns, idle_timeout, pipeline_fn)
     Forks a child process that handles exactly [n] requests then exits.
     Uses a pipe to signal readiness so the parent doesn't race the client.
     Returns VInt child_pid. *)
  ; ("http_server_spawn_n", VBuiltin ("http_server_spawn_n", function
      | [VInt port; VInt n; VInt _max_conns; VInt _idle_timeout; pipeline_fn] ->
        let open Unix in
        let server_sock = socket PF_INET SOCK_STREAM 0 in
        setsockopt server_sock SO_REUSEADDR true;
        bind server_sock (ADDR_INET (inet_addr_any, port));
        listen server_sock 128;
        let (read_fd, write_fd) = pipe () in
        (match fork () with
         | 0 ->
           (* child: signal ready, handle n requests, exit *)
           (try close read_fd with _ -> ());
           (try ignore (write write_fd (Bytes.of_string "\x00") 0 1) with _ -> ());
           (try close write_fd with _ -> ());
           let handled = ref 0 in
           (try
              while !handled < n do
                let (client_sock, _addr) = accept server_sock in
                (try handle_http_connection client_sock pipeline_fn
                 with _ -> ());
                (try close client_sock with _ -> ());
                incr handled
              done
            with _ -> ());
           (try close server_sock with _ -> ());
           _exit 0
         | child_pid ->
           (* parent: wait for ready signal, close server socket, return pid *)
           (try close write_fd with _ -> ());
           (try close server_sock with _ -> ());
           let buf = Bytes.create 1 in
           (try ignore (read read_fd buf 0 1) with _ -> ());
           (try close read_fd with _ -> ());
           VInt child_pid)
      | _ -> eval_error "http_server_spawn_n(port, n, max_conns, idle_timeout, pipeline)"))

  (* http_server_wait(pid) — waitpid for the spawned server child *)
  ; ("http_server_wait", VBuiltin ("http_server_wait", function
      | [VInt pid] ->
        (try ignore (Unix.waitpid [] pid) with _ -> ());
        VUnit
      | _ -> eval_error "http_server_wait(pid)"))

  (* ── CSV parser ─────────────────────────────────────────────────── *)
  ; ("csv_open",     VBuiltin ("csv_open",     csv_open_impl))
  ; ("csv_next_row", VBuiltin ("csv_next_row", csv_next_row_impl))
  ; ("csv_close",    VBuiltin ("csv_close",    csv_close_impl))

  (* ── WebSocket builtins (interpreter mode) ───────────────────────── *)
  (* ws_recv(fd) → WsFrame *)
  ; ("ws_recv", VBuiltin ("ws_recv", function
      | [VInt fd] ->
        let sock = (Obj.magic fd : Unix.file_descr) in
        ws_recv_frame sock
      | _ -> eval_error "ws_recv(fd)"))

  (* ws_send(fd, frame) → Unit *)
  ; ("ws_send", VBuiltin ("ws_send", function
      | [VInt fd; frame] ->
        let sock = (Obj.magic fd : Unix.file_descr) in
        ws_send_frame sock frame;
        VUnit
      | _ -> eval_error "ws_send(fd, frame)"))

  (* ws_select(fd, _actor_fd, timeout_ms) → SelectResult *)
  (* Simplified: just does a recv with a timeout then returns WsData or Timeout *)
  ; ("ws_select", VBuiltin ("ws_select", function
      | [VInt fd; _actor_fd; VInt timeout_ms] ->
        let sock = (Obj.magic fd : Unix.file_descr) in
        if timeout_ms > 0 then begin
          let timeout_f = float_of_int timeout_ms /. 1000.0 in
          let (r, _, _) = Unix.select [sock] [] [] timeout_f in
          if r = [] then VCon ("Timeout", [])
          else VCon ("WsData", [ws_recv_frame sock])
        end else
          VCon ("WsData", [ws_recv_frame sock])
      | _ -> eval_error "ws_select(fd, actor_fd, timeout_ms)"))

  (* ---- Option combinators ---- *)
  ; ("Option.map", VBuiltin ("Option.map", function
        | [VCon ("Some", [v]); f] -> VCon ("Some", [!apply_hook f [v]])
        | [VCon ("None", []); _]  -> VCon ("None", [])
        | _ -> eval_error "Option.map: expected (Option, fn)"))
  ; ("Option.flat_map", VBuiltin ("Option.flat_map", function
        | [VCon ("Some", [v]); f] -> !apply_hook f [v]
        | [VCon ("None", []); _]  -> VCon ("None", [])
        | _ -> eval_error "Option.flat_map: expected (Option, fn)"))
  ; ("Option.unwrap", VBuiltin ("Option.unwrap", function
        | [VCon ("Some", [v])] -> v
        | [VCon ("None", [])]  -> eval_error "Option.unwrap: called on None"
        | _ -> eval_error "Option.unwrap: expected Option"))
  ; ("Option.unwrap_or", VBuiltin ("Option.unwrap_or", function
        | [VCon ("Some", [v]); _]       -> v
        | [VCon ("None", []); default]  -> default
        | _ -> eval_error "Option.unwrap_or: expected (Option, default)"))
  ; ("Option.is_some", VBuiltin ("Option.is_some", function
        | [VCon ("Some", [_])] -> VBool true
        | [VCon ("None", [])]  -> VBool false
        | _ -> eval_error "Option.is_some: expected Option"))
  ; ("Option.is_none", VBuiltin ("Option.is_none", function
        | [VCon ("None", [])]  -> VBool true
        | [VCon ("Some", [_])] -> VBool false
        | _ -> eval_error "Option.is_none: expected Option"))

  (* ---- Result combinators ---- *)
  ; ("Result.map", VBuiltin ("Result.map", function
        | [VCon ("Ok", [v]); f]  -> VCon ("Ok", [!apply_hook f [v]])
        | [VCon ("Err", [e]); _] -> VCon ("Err", [e])
        | _ -> eval_error "Result.map: expected (Result, fn)"))
  ; ("Result.flat_map", VBuiltin ("Result.flat_map", function
        | [VCon ("Ok", [v]); f]  -> !apply_hook f [v]
        | [VCon ("Err", [e]); _] -> VCon ("Err", [e])
        | _ -> eval_error "Result.flat_map: expected (Result, fn)"))
  ; ("Result.unwrap", VBuiltin ("Result.unwrap", function
        | [VCon ("Ok", [v])]  -> v
        | [VCon ("Err", [e])] ->
          eval_error "Result.unwrap: called on Err(%s)" (value_to_string e)
        | _ -> eval_error "Result.unwrap: expected Result"))
  ; ("Result.unwrap_or", VBuiltin ("Result.unwrap_or", function
        | [VCon ("Ok", [v]); _]        -> v
        | [VCon ("Err", []); default]  -> default
        | [VCon ("Err", [_]); default] -> default
        | _ -> eval_error "Result.unwrap_or: expected (Result, default)"))
  ; ("Result.is_ok", VBuiltin ("Result.is_ok", function
        | [VCon ("Ok", [_])]  -> VBool true
        | [VCon ("Err", [_])] -> VBool false
        | _ -> eval_error "Result.is_ok: expected Result"))
  ; ("Result.is_err", VBuiltin ("Result.is_err", function
        | [VCon ("Err", [_])] -> VBool true
        | [VCon ("Ok", [_])]  -> VBool false
        | _ -> eval_error "Result.is_err: expected Result"))
  ; ("Result.map_err", VBuiltin ("Result.map_err", function
        | [VCon ("Ok", [v]); _]  -> VCon ("Ok", [v])
        | [VCon ("Err", [e]); f] -> VCon ("Err", [!apply_hook f [e]])
        | _ -> eval_error "Result.map_err: expected (Result, fn)"))

  (* ---- List.sort / List.sort_by ---- *)
  ; ("List.sort", VBuiltin ("List.sort", function
        (* Sort an Int list using merge sort via OCaml's List.sort. *)
        | [lst] ->
          let rec to_ints = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VInt n; rest]) -> n :: to_ints rest
            | VCon ("Cons", [v; _]) ->
              eval_error "List.sort: expected Int list, got %s" (value_to_string v)
            | v -> eval_error "List.sort: not a list: %s" (value_to_string v)
          in
          let ints = to_ints lst in
          let sorted = List.sort Int.compare ints in
          List.fold_right (fun n acc -> VCon ("Cons", [VInt n; acc]))
            sorted (VCon ("Nil", []))
        | _ -> eval_error "List.sort: expected one list argument"))
  ; ("List.sort_by", VBuiltin ("List.sort_by", function
        (* Sort a list using a curried March comparison function cmp : a -> a -> Bool.
           cmp(x)(y) should return true if x should come before y.
           The function is curried so we apply in two steps. *)
        | [lst; cmp] ->
          let rec to_vals = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [h; rest]) -> h :: to_vals rest
            | v -> eval_error "List.sort_by: not a list: %s" (value_to_string v)
          in
          let vals = to_vals lst in
          (* Apply curried cmp: cmp(x)(y) — two single-arg applications *)
          let call2 f a b =
            let f1 = !apply_hook f [a] in
            !apply_hook f1 [b]
          in
          let sorted = List.stable_sort (fun x y ->
            match call2 cmp x y with
            | VBool true  -> -1   (* x before y *)
            | VBool false ->
              (match call2 cmp y x with
               | VBool true  -> 1    (* y before x *)
               | _           -> 0)   (* equal *)
            | v -> eval_error "List.sort_by: cmp must return Bool, got %s"
                     (value_to_string v)
          ) vals in
          List.fold_right (fun v acc -> VCon ("Cons", [v; acc]))
            sorted (VCon ("Nil", []))
        | _ -> eval_error "List.sort_by: expected (list, cmp_fn)"))

    (* ── String module — direct builtins accessible as String.X ────── *)
  ; ("String.chars", VBuiltin ("String.chars", function
        | [VString s] ->
          let chars = List.init (String.length s) (fun i -> VString (String.make 1 s.[i])) in
          List.fold_right (fun c acc -> VCon ("Cons", [c; acc])) chars (VCon ("Nil", []))
        | _ -> eval_error "String.chars: expected string"))
  ; ("String.pad_left", VBuiltin ("String.pad_left", function
        | [VString s; VInt width; VString fill] when String.length fill = 1 ->
          let ls = String.length s in
          if ls >= width then VString s
          else VString (String.make (width - ls) fill.[0] ^ s)
        | _ -> eval_error "String.pad_left: expected string, int, char-string"))
  ; ("String.pad_right", VBuiltin ("String.pad_right", function
        | [VString s; VInt width; VString fill] when String.length fill = 1 ->
          let ls = String.length s in
          if ls >= width then VString s
          else VString (s ^ String.make (width - ls) fill.[0])
        | _ -> eval_error "String.pad_right: expected string, int, char-string"))
  ; ("String.repeat", VBuiltin ("String.repeat", function
        | [VString s; VInt n] ->
          let buf = Buffer.create (String.length s * max 0 n) in
          for _ = 1 to n do Buffer.add_string buf s done;
          VString (Buffer.contents buf)
        | _ -> eval_error "String.repeat: expected string and int"))
  ; ("String.reverse", VBuiltin ("String.reverse", function
        | [VString s] ->
          let n = String.length s in
          VString (String.init n (fun i -> s.[n - 1 - i]))
        | _ -> eval_error "String.reverse: expected string"))
  ; ("String.split", VBuiltin ("String.split", function
        | [VString s; VString sep] ->
          let parts =
            if sep = "" then
              List.init (String.length s) (fun i -> String.make 1 s.[i])
            else begin
              let ls = String.length s and lsep = String.length sep in
              let result = ref [] and start = ref 0 in
              (try
                 for i = 0 to ls - lsep do
                   if String.sub s i lsep = sep then begin
                     result := String.sub s !start (i - !start) :: !result;
                     start := i + lsep
                   end
                 done
               with _ -> ());
              result := String.sub s !start (ls - !start) :: !result;
              List.rev !result
            end
          in
          List.fold_right (fun p acc -> VCon ("Cons", [VString p; acc]))
            parts (VCon ("Nil", []))
        | _ -> eval_error "String.split: expected two strings"))
  ; ("String.contains", VBuiltin ("String.contains", function
        | [VString s; VString sub] ->
          let ls = String.length s and lsub = String.length sub in
          if lsub = 0 then VBool true
          else if ls < lsub then VBool false
          else
            let found = ref false in
            for i = 0 to ls - lsub do
              if String.sub s i lsub = sub then found := true
            done;
            VBool !found
        | _ -> eval_error "String.contains: expected two strings"))
  ; ("String.starts_with", VBuiltin ("String.starts_with", function
        | [VString s; VString prefix] ->
          let lp = String.length prefix in
          VBool (String.length s >= lp && String.sub s 0 lp = prefix)
        | _ -> eval_error "String.starts_with: expected two strings"))
  ; ("String.ends_with", VBuiltin ("String.ends_with", function
        | [VString s; VString suffix] ->
          let ls = String.length s and lsuf = String.length suffix in
          VBool (ls >= lsuf && String.sub s (ls - lsuf) lsuf = suffix)
        | _ -> eval_error "String.ends_with: expected two strings"))
  ; ("String.trim", VBuiltin ("String.trim", function
        | [VString s] -> VString (String.trim s)
        | _ -> eval_error "String.trim: expected string"))
  ; ("String.to_upper", VBuiltin ("String.to_upper", function
        | [VString s] -> VString (String.uppercase_ascii s)
        | _ -> eval_error "String.to_upper: expected string"))
  ; ("String.to_lower", VBuiltin ("String.to_lower", function
        | [VString s] -> VString (String.lowercase_ascii s)
        | _ -> eval_error "String.to_lower: expected string"))
  ; ("String.replace", VBuiltin ("String.replace", function
        | [VString s; VString old_; VString new_] ->
          let lold = String.length old_ in
          if lold = 0 then VString s
          else begin
            let ls = String.length s in
            let idx = ref (-1) in
            (try
               for i = 0 to ls - lold do
                 if String.sub s i lold = old_ then
                   (idx := i; raise Exit)
               done
             with Exit -> ());
            if !idx = -1 then VString s
            else VString (String.sub s 0 !idx ^ new_ ^
                          String.sub s (!idx + lold) (ls - !idx - lold))
          end
        | _ -> eval_error "String.replace: expected three strings"))

  (* ── Session-typed channels ─────────────────────────────────────── *)
  (* Chan.new(proto_name) or Chan.new(proto_name, role_a, role_b)
     Returns a pair (endpoint_a, endpoint_b).
     With one arg: roles are named "A" and "B" — the typechecker already verified
     the protocol exists; we only need a connected pair at runtime. *)
  ; ("Chan.new", VBuiltin ("Chan.new", function
        | [VString proto] | [VAtom proto] | [VCon (proto, [])] ->
          let (ep_a, ep_b) = chan_new proto "A" "B" in
          VTuple [VChan ep_a; VChan ep_b]
        | [VString proto; VString role_a; VString role_b]
        | [VAtom proto; VAtom role_a; VAtom role_b] ->
          let (ep_a, ep_b) = chan_new proto role_a role_b in
          VTuple [VChan ep_a; VChan ep_b]
        | _ -> eval_error "Chan.new: expected a protocol name"))

  (* Chan.send(channel_endpoint, value) → new_channel_endpoint
     The endpoint is consumed (linear); the returned one is the continuation. *)
  ; ("Chan.send", VBuiltin ("Chan.send", function
        | [VChan ce; v] -> chan_send ce v
        | _ -> eval_error "Chan.send: expected (Chan, value)"))

  (* Chan.recv(channel_endpoint) → (value, new_channel_endpoint)
     Pops one value from the receive queue. *)
  ; ("Chan.recv", VBuiltin ("Chan.recv", function
        | [VChan ce] -> chan_recv ce
        | _ -> eval_error "Chan.recv: expected Chan"))

  (* Chan.close(channel_endpoint) → ()
     Marks the endpoint closed. Must be done when session state is End. *)
  ; ("Chan.close", VBuiltin ("Chan.close", function
        | [VChan ce] -> chan_close ce
        | _ -> eval_error "Chan.close: expected Chan"))

  (* Chan.choose(channel_endpoint, :label) → new_channel_endpoint
     Sends the chosen branch label to the other side (via chan_send), returns the channel. *)
  ; ("Chan.choose", VBuiltin ("Chan.choose", function
        | [VChan ce; (VAtom _ as v)]
        | [VChan ce; (VString _ as v)] -> chan_send ce v
        | _ -> eval_error "Chan.choose: expected (Chan, :label)"))

  (* Chan.offer(channel_endpoint) → (:label, new_channel_endpoint)
     Receives the branch label chosen by the other side (via chan_recv). *)
  ; ("Chan.offer", VBuiltin ("Chan.offer", function
        | [VChan ce] -> chan_recv ce
        | _ -> eval_error "Chan.offer: expected Chan"))

  (* ── Multi-party session (MPST) operations ──────────────────────── *)
  (* MPST.new(proto_name) → (ep_role1, ep_role2, ..., ep_roleN) sorted by role.
     The roles are inferred from the protocol name at typecheck time; at runtime
     we need the role list, which is passed as additional args by the typechecker
     desugaring via an atom list. We accept:
       MPST.new(:ThreePartyAuth, ["Client","Server","AuthDB"])
     but also a convenience form where roles are passed as additional atom args.
     Since the typechecker rewrites MPST.new(Proto) calls, we accept either form. *)
  ; ("MPST.new", VBuiltin ("MPST.new", function
        | [VString proto] | [VAtom proto] | [VCon (proto, [])] ->
          (* Look up the registered roles from [protocol_roles_tbl]. *)
          (match Hashtbl.find_opt protocol_roles_tbl proto with
           | None ->
             eval_error "MPST.new: protocol `%s` is not registered \
                         (was it declared with `protocol ... do ... end`?)" proto
           | Some roles ->
             let n = List.length roles in
             if n < 3 then
               eval_error "MPST.new: protocol `%s` has %d role(s); \
                           MPST.new requires at least 3. Use Chan.new for binary protocols."
                 proto n;
             VTuple (mpst_new proto roles))
        | _ -> eval_error "MPST.new: expected a single protocol name argument"))

  (* MPST.send(endpoint, Role, value) → new_endpoint
     Role can be a bare uppercase name (VCon "Server" []) or atom/string. *)
  ; ("MPST.send", VBuiltin ("MPST.send", function
        | [VMChan me; VAtom target; v]
        | [VMChan me; VString target; v] -> mpst_send me target v
        | [VMChan me; VCon (target, []); v] -> mpst_send me target v
        | _ -> eval_error "MPST.send: expected (MChan, Role, value)"))

  (* MPST.recv(endpoint, Source) → (value, new_endpoint) *)
  ; ("MPST.recv", VBuiltin ("MPST.recv", function
        | [VMChan me; VAtom source]
        | [VMChan me; VString source] -> mpst_recv me source
        | [VMChan me; VCon (source, [])] -> mpst_recv me source
        | _ -> eval_error "MPST.recv: expected (MChan, Role)"))

  (* MPST.close(endpoint) → () *)
  ; ("MPST.close", VBuiltin ("MPST.close", function
        | [VMChan me] -> mpst_close me
        | _ -> eval_error "MPST.close: expected MChan"))

  (* ---- Bytes builtins ---- *)
  (* Convert a raw byte value (0–255) to a single-byte String. Unlike
     char_from_int, this accepts the full 0–255 range including non-ASCII. *)
  ; ("byte_to_char", VBuiltin ("byte_to_char", function
        | [VInt n] when n >= 0 && n <= 255 -> VString (String.make 1 (Char.chr n))
        | [VInt n] -> eval_error "byte_to_char: %d out of range 0–255" n
        | _ -> eval_error "byte_to_char: expected Int"))

  (* ---- Process builtins ---- *)
  ; ("process_env", VBuiltin ("process_env", function
        | [VString name] ->
          (match Sys.getenv_opt name with
           | Some v -> VCon ("Some", [VString v])
           | None   -> VCon ("None", []))
        | _ -> eval_error "process_env: expected String"))
  ; ("process_set_env", VBuiltin ("process_set_env", function
        | [VString name; VString value] -> Unix.putenv name value; VUnit
        | _ -> eval_error "process_set_env: expected (String, String)"))
  ; ("process_cwd", VBuiltin ("process_cwd", function
        | [] -> VString (Sys.getcwd ())
        | _ -> eval_error "process_cwd: no arguments expected"))
  ; ("process_exit", VBuiltin ("process_exit", function
        | [VInt code] -> exit code
        | _ -> eval_error "process_exit: expected Int"))
  ; ("process_argv", VBuiltin ("process_argv", function
        | [] ->
          let args = Array.to_list Sys.argv in
          List.fold_right (fun s acc -> VCon ("Cons", [VString s; acc]))
            args (VCon ("Nil", []))
        | _ -> eval_error "process_argv: no arguments expected"))
  ; ("process_pid", VBuiltin ("process_pid", function
        | [] -> VInt (Unix.getpid ())
        | _ -> eval_error "process_pid: no arguments expected"))
  (* Run a command synchronously; returns Ok(ProcessResult(code, stdout, stderr))
     or Err(msg) on OS error.  Stderr is captured separately. *)
  ; ("process_spawn_sync", VBuiltin ("process_spawn_sync", function
        | [VString cmd; lst] ->
          let rec args_of_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VString s; rest]) -> s :: args_of_list rest
            | VCon ("Cons", [v; _]) ->
              eval_error "process_spawn_sync: arg must be String, got %s"
                (value_to_string v)
            | v -> eval_error "process_spawn_sync: expected list, got %s"
                     (value_to_string v)
          in
          let args_strs = args_of_list lst in
          let args_arr = Array.of_list (cmd :: args_strs) in
          (try
             let (ic, oc) = Unix.open_process_args cmd args_arr in
             close_out_noerr oc;
             let buf = Buffer.create 256 in
             (try while true do Buffer.add_channel buf ic 1 done
              with End_of_file -> ());
             let status = Unix.close_process (ic, oc) in
             let code = match status with
               | Unix.WEXITED n  -> n
               | Unix.WSIGNALED n -> -n
               | Unix.WSTOPPED  n -> -n
             in
             VCon ("Ok", [VCon ("ProcessResult",
               [VInt code; VString (Buffer.contents buf); VString ""])])
           with Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "process_spawn_sync: expected (String, List(String))"))
  (* Run a command and return its stdout as a Seq(String) of lines.
     Returns Ok(Seq) on success or Err(msg) on OS error. *)
  ; ("process_spawn_lines", VBuiltin ("process_spawn_lines", function
        | [VString cmd; lst] ->
          let rec args_of_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VString s; rest]) -> s :: args_of_list rest
            | v -> eval_error "process_spawn_lines: expected String list, got %s"
                     (value_to_string v)
          in
          let args_strs = args_of_list lst in
          let args_arr = Array.of_list (cmd :: args_strs) in
          (try
             let (ic, oc) = Unix.open_process_args cmd args_arr in
             close_out_noerr oc;
             let lines = ref [] in
             (try while true do lines := input_line ic :: !lines done
              with End_of_file -> ());
             let _ = Unix.close_process (ic, oc) in
             let ordered = List.rev !lines in
             let fold_fn = VBuiltin ("process_stream_fold", fun args ->
               match args with
               | [acc; f] ->
                 List.fold_left (fun a line ->
                   !apply_hook f [a; VString line]) acc ordered
               | _ -> eval_error "process_stream_fold: expected (acc, fn)")
             in
             VCon ("Ok", [VCon ("Seq", [fold_fn])])
           with Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "process_spawn_lines: expected (String, List(String))"))

  (* ---- Logger builtins ---- *)
  ; ("logger_set_level", VBuiltin ("logger_set_level", function
        | [VInt n] -> logger_level := n; VUnit
        | _ -> eval_error "logger_set_level: expected Int"))
  ; ("logger_get_level", VBuiltin ("logger_get_level", function
        | [] -> VInt !logger_level
        | _ -> eval_error "logger_get_level: no arguments"))
  ; ("logger_add_context", VBuiltin ("logger_add_context", function
        | [VString k; VString v] ->
          logger_context := (k, v) :: !logger_context; VUnit
        | _ -> eval_error "logger_add_context: expected (String, String)"))
  ; ("logger_clear_context", VBuiltin ("logger_clear_context", function
        | [] -> logger_context := []; VUnit
        | _ -> eval_error "logger_clear_context: no arguments"))
  ; ("logger_get_context", VBuiltin ("logger_get_context", function
        | [] ->
          List.fold_right (fun (k, v) acc ->
            VCon ("Cons", [VTuple [VString k; VString v]; acc])
          ) !logger_context (VCon ("Nil", []))
        | _ -> eval_error "logger_get_context: no arguments"))
  (* logger_write(level_str, msg, context_list, extra_list)
     Writes a log entry to stderr.  Both list args are List((String,String)) tuples. *)
  ; ("logger_write", VBuiltin ("logger_write", function
        | [VString level; VString msg; ctx_list; extra_list] ->
          let rec pairs_of = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VTuple [VString k; VString v]; rest]) ->
              (k, v) :: pairs_of rest
            | VCon ("Cons", [_; rest]) -> pairs_of rest
            | _ -> []
          in
          let all_meta = pairs_of ctx_list @ pairs_of extra_list in
          let meta_str =
            if all_meta = [] then ""
            else " {" ^ String.concat ", "
                (List.map (fun (k, v) -> k ^ "=" ^ v) all_meta) ^ "}"
          in
          capture_ewriteln (Printf.sprintf "[%s] %s%s" level msg meta_str);
          VUnit
        | _ -> eval_error "logger_write: expected (String, String, List, List)"))

  (* ---- Actor.call / Actor.cast ---- *)
  (* actor_cast: fire-and-forget async message to an actor. *)
  ; ("actor_cast", VBuiltin ("actor_cast", function
        | [VPid pid; msg] ->
          (match Hashtbl.find_opt actor_registry pid with
           | None -> VUnit
           | Some inst when not inst.ai_alive -> VUnit
           | Some inst ->
             (match msg with
              | VCon _ | VAtom _ -> Queue.push msg inst.ai_mailbox; VUnit
              | _ -> eval_error "actor_cast: message must be a constructor, got %s"
                       (value_to_string msg)))
        | _ -> eval_error "actor_cast: expected (Pid, message)"))
  (* actor_call: synchronous call — sends Call(ref, msg) and waits for a reply.
     The target handler must call actor_reply(ref, result) to unblock the caller.
     Returns Ok(result) or Err(reason). *)
  ; ("actor_call", VBuiltin ("actor_call", function
        | [VPid pid; msg; VInt _timeout_ms] ->
          let ref_id = !next_call_ref in
          next_call_ref := ref_id + 1;
          let call_msg = match msg with
            | VCon (tag, args) -> VCon ("Call", [VInt ref_id; VCon (tag, args)])
            | VAtom tag        -> VCon ("Call", [VInt ref_id; VAtom tag])
            | _ -> eval_error "actor_call: message must be a constructor, got %s"
                     (value_to_string msg)
          in
          (match Hashtbl.find_opt actor_registry pid with
           | None -> VCon ("Err", [VString "actor not found"])
           | Some inst when not inst.ai_alive ->
             VCon ("Err", [VString "actor not alive"])
           | Some inst ->
             Queue.push call_msg inst.ai_mailbox;
             !run_scheduler_hook ();
             (match Hashtbl.find_opt pending_replies ref_id with
              | Some result ->
                Hashtbl.remove pending_replies ref_id;
                VCon ("Ok", [result])
              | None ->
                VCon ("Err", [VString "no reply (timeout or unhandled Call)"])))
        | _ -> eval_error "actor_call: expected (Pid, message, Int)"))
  (* actor_reply: store a reply for a pending call.  Called from actor handlers. *)
  ; ("actor_reply", VBuiltin ("actor_reply", function
        | [VInt ref_id; result] ->
          Hashtbl.replace pending_replies ref_id result; VUnit
        | _ -> eval_error "actor_reply: expected (Int, value)"))
  ]

(* ------------------------------------------------------------------ *)
(* Evaluation                                                          *)
(* ------------------------------------------------------------------ *)

let lookup name env =
  match List.assoc_opt name env with
  | Some v -> v
  | None   -> eval_error "unbound variable: %s" name

(** Extract parameter names from a single fn_clause (after desugaring,
    all params are FPNamed or FPPat(PatVar)). *)
let clause_params (clause : fn_clause) : string list =
  List.map (function
      | FPNamed p       -> p.param_name.txt
      | FPPat (PatVar n) -> n.txt
      | FPPat _         -> eval_error "unexpected pattern param after desugaring"
    ) clause.fc_params

(** Extract span from an expression, or dummy_span if unavailable. *)
let span_of_expr (e : expr) : span =
  match e with
  | ELit (_, sp) | EApp (_, _, sp) | ECon (_, _, sp)
  | ELam (_, _, sp) | EBlock (_, sp) | ELet (_, sp)
  | EMatch (_, _, sp) | ETuple (_, sp) | ERecord (_, sp)
  | ERecordUpdate (_, _, sp) | EField (_, _, sp)
  | EIf (_, _, _, sp) | EPipe (_, _, sp) | EAnnot (_, _, sp)
  | EHole (_, sp) | EAtom (_, _, sp) | ESend (_, _, sp)
  | ESpawn (_, sp) | EDbg (_, sp) | ELetFn (_, _, _, _, sp) -> sp
  | EAssert (_, sp) -> sp
  | EVar n -> n.span
  | EResultRef _ -> dummy_span

(** Evaluate a block: return the value of the last expression.
    [ELet] bindings extend the environment for subsequent expressions. *)
let rec eval_block (env : env) (es : expr list) : value =
  match es with
  | []      -> VUnit
  | [e]     -> eval_expr env e
  | ELet (b, _) :: rest ->
    let v = eval_expr env b.bind_expr in
    let bindings = match match_pattern v b.bind_pat with
      | Some bs -> bs
      | None    -> raise (Match_failure
                            (Printf.sprintf "let binding pattern failed"))
    in
    eval_block (bindings @ env) rest
  (* Local named recursive function: fn go(params) do body end *)
  | ELetFn (name, params, _, body, _) :: rest ->
    let param_names = List.map (fun p -> p.param_name.txt) params in
    (* Use the env_ref trick so the function can call itself recursively. *)
    let env_ref = ref env in
    let rec_v = VBuiltin ("<rec:" ^ name.txt ^ ">", fun args ->
      let call_env = !env_ref in
      apply (VClosure (call_env, param_names, body)) args) in
    let env' = (name.txt, rec_v) :: env in
    env_ref := env';
    eval_block env' rest
  | e :: rest ->
    let _ = eval_expr env e in
    eval_block env rest

(** Apply a callable value to a list of argument values. *)
and apply_inner (fn_val : value) (args : value list) : value =
  match fn_val with
  | VClosure (closure_env, params, body) ->
    if List.length params <> List.length args then
      eval_error "arity mismatch: expected %d args, got %d"
        (List.length params) (List.length args);
    let env' = List.combine params args @ closure_env in
    eval_expr env' body

  | VBuiltin (_, f) -> f args

  | VForeign (lib, sym) ->
    (match Hashtbl.find_opt foreign_stubs (lib, sym) with
     | Some f -> f args
     | None ->
       eval_error "extern %s:%s — no OCaml stub registered for this symbol \
                   (add it to the foreign_stubs table in eval.ml)" lib sym)

  | _ -> eval_error "applied non-function value: %s" (value_to_string fn_val)

(** Depth-tracking wrapper around [apply_inner]. *)
and apply (fn_val : value) (args : value list) : value =
  (match !debug_ctx with
   | Some ctx -> ctx.dc_depth <- ctx.dc_depth + 1
   | None -> ());
  let result =
    (try `Ok (apply_inner fn_val args)
     with exn -> `Err exn)
  in
  (match !debug_ctx with
   | Some ctx -> ctx.dc_depth <- max 0 (ctx.dc_depth - 1)
   | None -> ());
  match result with
  | `Ok v    -> v
  | `Err exn -> raise exn

(** Main expression evaluator (inner, no tracing). *)
and eval_expr_inner (env : env) (e : expr) : value =
  match e with
  | ELit (LitInt n, _)    -> VInt n
  | ELit (LitFloat f, _)  -> VFloat f
  | ELit (LitString s, _) -> VString s
  | ELit (LitBool b, _)   -> VBool b
  | ELit (LitAtom a, _)   -> VAtom a

  | EVar n -> lookup n.txt env

  | EHole (name, _) ->
    let label = match name with Some n -> "?" ^ n.txt | None -> "?" in
    eval_error "typed hole `%s` reached the evaluator — the type checker should have caught this" label

  | EApp (f, args, _) ->
    check_reductions ();
    (if !March_coverage.Coverage.coverage_enabled then begin
      let name = match f with
        | EVar n -> n.txt
        | EField (_, field, _) -> field.txt
        | _ -> "<anon>"
      in
      March_coverage.Coverage.record_fn_call name
    end);
    let fn_val = eval_expr env f in
    let arg_vals = List.map (eval_expr env) args in
    apply fn_val arg_vals

  | ECon (name, args, _) ->
    let arg_vals = List.map (eval_expr env) args in
    (* Strip any type qualifier from the constructor tag so that
       Result.Ok and Ok both produce VCon("Ok", …) at runtime. *)
    let tag = match String.rindex_opt name.txt '.' with
      | Some i -> String.sub name.txt (i + 1) (String.length name.txt - i - 1)
      | None   -> name.txt
    in
    VCon (tag, arg_vals)

  | ELam (params, body, _) ->
    let param_names = List.map (fun p -> p.param_name.txt) params in
    VClosure (env, param_names, body)

  | EBlock (es, _) -> eval_block env es

  | ELet (b, _) ->
    (* Standalone let (outside a block) — evaluate and ignore bindings.
       This shouldn't appear after desugaring except inside EBlock. *)
    eval_expr env b.bind_expr

  | EMatch (scrut, branches, sp) ->
    check_reductions ();
    let v = eval_expr env scrut in
    eval_match env sp v branches

  | ETuple ([], _) -> VUnit
  | ETuple (es, _) ->
    VTuple (List.map (eval_expr env) es)

  | ERecord (fields, _) ->
    VRecord (List.map (fun (n, ex) -> (n.txt, eval_expr env ex)) fields)

  | ERecordUpdate (base, updates, _) ->
    let base_val = eval_expr env base in
    (match base_val with
     | VRecord fields ->
       let updated = List.map (fun (n, ex) -> (n.txt, eval_expr env ex)) updates in
       (* Merge: updated fields override existing ones *)
       let new_fields = List.map (fun (k, v) ->
           match List.assoc_opt k updated with
           | Some v' -> (k, v')
           | None    -> (k, v)
         ) fields in
       (* Add any fields in updated that weren't in the original *)
       let extra = List.filter (fun (k, _) ->
           not (List.mem_assoc k fields)) updated in
       VRecord (new_fields @ extra)
     | _ -> eval_error "record update on non-record value")

  | EField (ex, field, _) ->
    (* First try to resolve as a module path (handles A.B.c chained access) *)
    let rec module_path_str = function
      | ECon (n, [], _) -> Some n.txt
      | EField (e2, f, _) ->
        (match module_path_str e2 with
         | Some prefix -> Some (prefix ^ "." ^ f.txt)
         | None -> None)
      | _ -> None
    in
    let qualified_lookup =
      match module_path_str ex with
      | Some prefix ->
        let key = prefix ^ "." ^ field.txt in
        List.assoc_opt key env
      | None -> None
    in
    (match qualified_lookup with
     | Some v -> v
     | None ->
    (match eval_expr env ex with
     | VRecord fields ->
       (match List.assoc_opt field.txt fields with
        | Some v -> v
        | None   -> eval_error "record has no field '%s'" field.txt)
     | VCon (mod_name, []) ->
       (* Module member access: Mod.member — look up "Mod.member" in env *)
       let key = mod_name ^ "." ^ field.txt in
       (match List.assoc_opt key env with
        | Some v -> v
        | None   -> eval_error "no member '%s' in module '%s'" field.txt mod_name)
     | _ -> eval_error "field access on non-record value"))

  | EIf (cond, then_, else_, sp) ->
    (match eval_expr env cond with
     | VBool true  ->
       (if !March_coverage.Coverage.coverage_enabled then
         March_coverage.Coverage.record_branch sp true);
       eval_expr env then_
     | VBool false ->
       (if !March_coverage.Coverage.coverage_enabled then
         March_coverage.Coverage.record_branch sp false);
       eval_expr env else_
     | _           -> eval_error "if condition must be a boolean")

  | EPipe _ ->
    eval_error "pipe expression reached evaluator (should be desugared)"

  | EResultRef _ ->
    raise (Eval_error "EResultRef reached evaluator — substitution missing")

  | EDbg (None, _) ->
    (* Unconditional breakpoint: pause and open debug REPL. *)
    (match !debug_ctx with
     | Some ctx when ctx.dc_enabled ->
       (match ctx.dc_on_dbg with
        | Some f -> f env
        | None   -> ())
     | _ -> ());
    VUnit

  | EDbg (Some inner, sp) ->
    let v = eval_expr env inner in
    (match !debug_ctx with
     | Some ctx when ctx.dc_enabled ->
       (match v with
        | VBool b ->
          (* Conditional breakpoint: pause only when true. *)
          if b then (match ctx.dc_on_dbg with Some f -> f env | None -> ())
        | _ ->
          (* Value trace: print to stderr and return the value. *)
          Printf.eprintf "[dbg] %s:%d:%d = %s\n%!"
            sp.March_ast.Ast.file sp.March_ast.Ast.start_line
            sp.March_ast.Ast.start_col (value_to_string v))
     | _ -> ());
    v

  | EAnnot (ex, _, _) -> eval_expr env ex

  | EAtom (a, [], _) -> VAtom a
  | EAtom (a, args, _) ->
    let arg_vals = List.map (eval_expr env) args in
    VCon (a, arg_vals)

  | ESpawn (actor_expr, _) ->
    let actor_name = match actor_expr with
      | EVar n           -> n.txt
      | ECon (n, [], _)  -> n.txt
      | _ -> eval_error "spawn: expected actor name (got complex expression)"
    in
    (match Hashtbl.find_opt actor_defs_tbl actor_name with
     | None -> eval_error "spawn: unknown actor '%s'" actor_name
     | Some (def, env_ref) ->
       let pid = !next_pid in
       next_pid := pid + 1;
       (* Phase 2: if this actor is a supervisor, spawn children first and
          inject their pids into the init state. *)
       let init_state = match def.actor_supervise with
         | None ->
           eval_expr !env_ref def.actor_init
         | Some sup_cfg ->
           (* Spawn each child and collect (field_name -> pid) *)
           let child_pids = List.map (fun sf ->
             let child_actor_name = match sf.sf_ty with
               | TyCon (n, []) -> n.txt
               | _ -> eval_error "supervise: child type must be a simple actor name"
             in
             match Hashtbl.find_opt actor_defs_tbl child_actor_name with
             | None -> eval_error "spawn supervisor: unknown child actor '%s'" child_actor_name
             | Some (child_def, child_env_ref) ->
               let child_init_state = eval_expr !child_env_ref child_def.actor_init in
               let child_pid = !next_pid in
               next_pid := child_pid + 1;
               let child_inst = {
                 ai_name = child_actor_name; ai_def = child_def;
                 ai_env_ref = child_env_ref;
                 ai_state = child_init_state; ai_alive = true;
                 ai_monitors = []; ai_links = []; ai_mailbox = Queue.create ();
                 ai_supervisor = Some pid;
                 ai_restart_count = []; ai_epoch = 0;
                 ai_resources = [];
                 ai_linear_values = [] } in
               Hashtbl.add actor_registry child_pid child_inst;
               (sf.sf_name.txt, child_pid)
           ) sup_cfg.sc_fields in
           (* Build init state: start from declared init, then overlay child pids *)
           let base_state = eval_expr !env_ref def.actor_init in
           (match base_state with
            | VRecord fields ->
              (* Replace fields that correspond to child actors with their pids *)
              let updated = List.map (fun (fname, fval) ->
                match List.assoc_opt fname child_pids with
                | Some cpid -> (fname, VInt cpid)
                | None -> (fname, fval)
              ) fields in
              (* Also add any child pids not in the record *)
              let extras = List.filter_map (fun (fname, cpid) ->
                if List.assoc_opt fname fields = None
                then Some (fname, VInt cpid)
                else None
              ) child_pids in
              VRecord (updated @ extras)
            | _ ->
              (* Non-record state: just use the init as-is *)
              base_state)
       in
       let inst = { ai_name     = actor_name; ai_def = def; ai_env_ref = env_ref;
                    ai_state    = init_state; ai_alive = true;
                    ai_monitors = []; ai_links = []; ai_mailbox = Queue.create ();
                    ai_supervisor = None; ai_restart_count = [];
                    ai_epoch = 0; ai_resources = [];
                    ai_linear_values = [] } in
       Hashtbl.add actor_registry pid inst;
       VPid pid)

  | ESend (cap_expr, msg_expr, _) ->
    check_reductions ();
    let pid_val = eval_expr env cap_expr in
    let msg_val = eval_expr env msg_expr in
    (match pid_val with
     | VPid pid ->
       (match Hashtbl.find_opt actor_registry pid with
        | None -> VCon ("None", [])  (* dead/unknown actor: fire-and-forget, silently drop *)
        | Some inst when not inst.ai_alive -> VCon ("None", [])  (* actor was killed: drop *)
        | Some inst ->
          (* Phase 4: async — push message to mailbox, do not dispatch inline.
             Only constructor values (VCon/VAtom) are valid messages. *)
          (match msg_val with
           | VCon _ | VAtom _ ->
             Queue.push msg_val inst.ai_mailbox;
             VCon ("Some", [VUnit])
           | _ ->
             eval_error "send: message must be a constructor value, got %s"
               (value_to_string msg_val)))
     | VCap (pid, cap_epoch) ->
       (* Capability-based send: validate epoch and revocation before enqueuing. *)
       (match Hashtbl.find_opt actor_registry pid with
        | None -> VCon ("None", [])
        | Some inst when not inst.ai_alive -> VCon ("None", [])
        | Some inst when inst.ai_epoch <> cap_epoch ->
          eval_error "send: capability epoch mismatch — cap has epoch %d, actor is at epoch %d"
            cap_epoch inst.ai_epoch
        | _ when Hashtbl.mem revocation_table (pid, cap_epoch) ->
          eval_error "send: capability (pid=%d, epoch=%d) has been revoked" pid cap_epoch
        | Some inst ->
          (match msg_val with
           | VCon _ | VAtom _ ->
             Queue.push msg_val inst.ai_mailbox;
             VCon ("Some", [VUnit])
           | _ ->
             eval_error "send: message must be a constructor value, got %s"
               (value_to_string msg_val)))
     | _ ->
       eval_error "send: first argument must be a Pid or Cap, got %s"
         (value_to_string pid_val))

  | ELetFn (name, params, _, body, _) ->
    (* ELetFn as a standalone expression: return the closure (for e.g. last expr in block) *)
    let param_names = List.map (fun p -> p.param_name.txt) params in
    let env_ref = ref env in
    let rec_v = VBuiltin ("<rec:" ^ name.txt ^ ">", fun args ->
      let call_env = !env_ref in
      apply (VClosure (call_env, param_names, body)) args) in
    let env' = (name.txt, rec_v) :: env in
    env_ref := env';
    rec_v

  | EAssert (inner, _) ->
    (* Compiler-assisted assertion rewriting:
       If the inner expression is a binary comparison (==, !=, <, >, <=, >=),
       we evaluate both sides separately so we can show their values on failure.
       Otherwise, we just evaluate the expression and check if it's true. *)
    let comparison_ops = ["=="; "!="; "<"; ">"; "<="; ">="] in
    (match inner with
     | EApp (EVar op_name, [lhs; rhs], _) when List.mem op_name.txt comparison_ops ->
       let lv = eval_expr env lhs in
       let rv = eval_expr env rhs in
       let op_fn = lookup op_name.txt env in
       (match apply op_fn [lv; rv] with
        | VBool true -> VUnit
        | VBool false ->
          raise (Assert_failure (Printf.sprintf
            "assert %s %s %s\n    left:  %s\n    right: %s"
            (value_to_string lv) op_name.txt (value_to_string rv)
            (value_to_string lv) (value_to_string rv)))
        | _ -> raise (Assert_failure "assert: comparison did not return Bool"))
     | _ ->
       (match eval_expr env inner with
        | VBool true  -> VUnit
        | VBool false ->
          raise (Assert_failure "assert: condition was false")
        | v ->
          raise (Assert_failure (Printf.sprintf "assert: expected Bool, got %s"
            (value_to_string v)))))

(** Evaluate a match expression: try each branch until one matches.
    [match_span] is the span of the [EMatch] node, used for coverage arm tracking. *)
and eval_match (env : env) (match_span : span) (v : value) (branches : branch list) : value =
  let rec go arm_idx = function
    | [] ->
      raise (Match_failure
               (Printf.sprintf "non-exhaustive match on value: %s"
                  (value_to_string v)))
    | br :: rest ->
      (match match_pattern v br.branch_pat with
       | None -> go (arm_idx + 1) rest
       | Some bindings ->
         let env' = bindings @ env in
         (* Check guard if present *)
         let guard_ok = match br.branch_guard with
           | None   -> true
           | Some g ->
             (match eval_expr env' g with
              | VBool b -> b
              | _       -> eval_error "guard must evaluate to a boolean")
         in
         if guard_ok then begin
           (if !March_coverage.Coverage.coverage_enabled then
             March_coverage.Coverage.record_arm match_span arm_idx);
           eval_expr env' br.branch_body
         end else go (arm_idx + 1) rest)
  in
  go 0 branches

(** Tracing wrapper around [eval_expr_inner].
    When debug mode is active, records a [trace_frame] for every evaluation step.
    When [!debug_ctx] is None, this is a single pointer deref — zero overhead.
    Coverage recording is gated by [March_coverage.Coverage.coverage_enabled]. *)
and eval_expr (env : env) (e : expr) : value =
  (if !March_coverage.Coverage.coverage_enabled then
    March_coverage.Coverage.record_expr (span_of_expr e));
  match !debug_ctx with
  | None | Some { dc_enabled = false; _ } ->
    eval_expr_inner env e
  | Some ctx ->
    let outcome =
      try `Ok (eval_expr_inner env e)
      with exn -> `Err exn
    in
    let (result_v, exn_s) = match outcome with
      | `Ok v  -> (Some v, None)
      | `Err e -> (None, Some (Printexc.to_string e))
    in
    let frame = { tf_expr   = e;
                  tf_env    = env;
                  tf_result = result_v;
                  tf_exn    = exn_s;
                  tf_actor  = snapshot_actors ();
                  tf_span   = span_of_expr e;
                  tf_depth  = ctx.dc_depth } in
    ring_push ctx.dc_trace frame;
    (match outcome with
     | `Ok v   -> v
     | `Err exn -> raise exn)

(* ------------------------------------------------------------------ *)
(* Phase 2/3: Initialize eval_expr_hook for supervisor restarts       *)
(* ------------------------------------------------------------------ *)

let () = eval_expr_hook := eval_expr
let () = apply_hook := apply
let () = iface_dispatch_hook := apply

(* ------------------------------------------------------------------ *)
(* Task builtins                                                       *)
(* These are defined after [apply] so they can call it directly.      *)
(* ------------------------------------------------------------------ *)

(** The number of reductions consumed during the most recent call to
    [eval_with_reduction_tracking]. *)
let last_reduction_count : int ref = ref 0

(** Reset all scheduler/task state. Call between test runs. *)
let reset_scheduler_state () : unit =
  Hashtbl.clear task_registry;
  next_task_id := 0;
  Hashtbl.clear actor_registry;
  Hashtbl.clear actor_defs_tbl;
  Hashtbl.reset impl_tbl;
  Hashtbl.reset ctor_type_tbl;
  Hashtbl.reset protocol_roles_tbl;
  next_pid := 0;
  next_monitor_id := 0;
  current_pid := None;
  reduction_ctx := None;
  last_reduction_count := 0;
  Hashtbl.clear process_registry;
  Hashtbl.clear pid_to_registry_name;
  Hashtbl.clear dyn_sup_registry;
  Hashtbl.clear dyn_sup_vpid_map;
  dyn_sup_next_vpid := (-1);
  app_spawn_order := [];
  shutdown_requested := false;
  Hashtbl.clear revocation_table;
  Hashtbl.clear pending_replies;
  next_call_ref := 0;
  logger_level := 1;
  logger_context := []

(* NOTE: debug_ctx actor event logging is intentionally not reproduced here.
   The old ESend recorded ame_state_before/ame_state_after. When actor debug
   tracing is needed, add the same pattern inside the handler dispatch block below. *)

(** Drain all actor mailboxes cooperatively.
    Each pass iterates over all live actors; for each with a non-empty mailbox
    it pops one message, finds the matching [on Msg] handler, and runs it.
    Repeats until a full pass produces no work (all mailboxes empty). *)
let run_scheduler () =
  let changed = ref true in
  while !changed && not !shutdown_requested do
    changed := false;
    (* Snapshot current pids to avoid issues with new actors spawned mid-pass *)
    let pids = Hashtbl.fold (fun pid _ acc -> pid :: acc) actor_registry [] in
    List.iter (fun pid ->
      match Hashtbl.find_opt actor_registry pid with
      | None -> ()
      | Some inst when not inst.ai_alive -> ()
      | Some inst when Queue.is_empty inst.ai_mailbox -> ()
      | Some inst ->
        let msg = Queue.pop inst.ai_mailbox in
        let (msg_tag, msg_args) = match msg with
          | VCon (tag, args) -> (tag, args)
          | VAtom tag        -> (tag, [])
          | _ ->
            Printf.eprintf "run_scheduler: dropping malformed message from actor %d: %s\n"
              pid (value_to_string msg);
            ("__drop__", [])
        in
        if msg_tag <> "__drop__" then
          (match List.find_opt (fun h -> h.ah_msg.txt = msg_tag)
                   inst.ai_def.actor_handlers with
           | None ->
             (* No handler for this message tag: silently drop *)
             ()
           | Some handler ->
             if List.length handler.ah_params <> List.length msg_args then
               Printf.eprintf "run_scheduler: handler '%s' arity mismatch for actor %d\n%!"
                 msg_tag pid
               (* Arity mismatch: message consumed but actor not crashed.
                  The message is lost and the actor continues with unchanged state.
                  This is intentional: a mismatch is a programming error, but crashing
                  the actor would mask the original bug. *)
             else begin
               changed := true;   (* only mark changed when handler actually runs *)
               let prev_pid = !current_pid in
               current_pid := Some pid;
               let param_bindings =
                 List.map2 (fun p v -> (p.param_name.txt, v))
                   handler.ah_params msg_args
               in
               let handler_env =
                 [("state", inst.ai_state)] @ param_bindings @ !(inst.ai_env_ref)
               in
               (match !eval_expr_hook handler_env handler.ah_body with
                | new_state ->
                  inst.ai_state <- new_state
                | exception exn ->
                  (* Handler raised an exception: crash the actor *)
                  crash_actor pid (Printexc.to_string exn));
               current_pid := prev_pid
             end)
    ) pids
  done

let () = run_scheduler_hook := run_scheduler

(* ------------------------------------------------------------------ *)
(* App / Supervisor machinery                                          *)
(* ------------------------------------------------------------------ *)

(** Task builtins: spawn, await, await_unwrap, yield.
    Placed after [apply] because [task_spawn] calls [apply] to eagerly
    execute the thunk (Phase 1: single-threaded cooperative scheduler). *)
let task_builtins : env =
  [ ("task_spawn", VBuiltin ("task_spawn", function
      | [thunk] ->
        let tid = !next_task_id in
        next_task_id := tid + 1;
        (* Phase 1: eagerly evaluate the thunk.
           Phase 2 will enqueue on the run queue instead. *)
        (* Thunks are (Int -> a) — pass dummy 0 arg. *)
        let result = apply thunk [VInt 0] in
        let entry = { te_id = tid; te_result = Some result; te_thunk = thunk } in
        Hashtbl.add task_registry tid entry;
        VTask tid
      | _ -> eval_error "task_spawn: expected 1 argument (a function)"))

  ; ("task_await", VBuiltin ("task_await", function
      | [VTask tid] ->
        (match Hashtbl.find_opt task_registry tid with
         | Some entry ->
           (match entry.te_result with
            | Some v -> VCon ("Ok", [v])
            | None -> VCon ("Err", [VString "task not completed"]))
         | None -> VCon ("Err", [VString (Printf.sprintf "unknown task %d" tid)]))
      | _ -> eval_error "task_await: expected 1 argument (a Task)"))

  ; ("task_await_unwrap", VBuiltin ("task_await_unwrap", function
      | [VTask tid] ->
        (match Hashtbl.find_opt task_registry tid with
         | Some entry ->
           (match entry.te_result with
            | Some v -> v
            | None -> eval_error "task_await!: task %d not completed" tid)
         | None -> eval_error "task_await!: unknown task %d" tid)
      | _ -> eval_error "task_await!: expected 1 argument (a Task)"))

  ; ("task_yield", VBuiltin ("task_yield", function
      | [] ->
        (* Voluntary yield — exhaust the budget so check_reductions raises Yield.
           When reduction counting is disabled this is a no-op. *)
        (match !reduction_ctx with
         | Some ctx ->
           ctx.March_scheduler.Scheduler.remaining <- 0;
           ignore (March_scheduler.Scheduler.tick ctx)
         | None -> ());
        VUnit
      | _ -> eval_error "task_yield: expected 0 arguments"))

  ; ("task_spawn_steal", VBuiltin ("task_spawn_steal", function
    | [VWorkPool; thunk] ->
      (* Cap(WorkPool) validated — spawn on the stealing pool.
         In Phase 1 (single-threaded), this is equivalent to task_spawn
         but validates the capability requirement. *)
      let tid = !next_task_id in
      next_task_id := tid + 1;
      (* Thunks are (Int -> a) — pass dummy 0 arg. *)
      let result = apply thunk [VInt 0] in
      let entry = { te_id = tid; te_result = Some result; te_thunk = thunk } in
      Hashtbl.add task_registry tid entry;
      VTask tid
    | [_; _] ->
      eval_error "task_spawn_steal: first argument must be a Cap(WorkPool)"
    | _ -> eval_error "task_spawn_steal: expected 2 arguments (pool, function)"))

  ; ("task_reductions", VBuiltin ("task_reductions", function
    | [] -> VInt !last_reduction_count
    | _ -> eval_error "task_reductions: expected 0 arguments"))

  ; ("get_work_pool", VWorkPool)
  (* Capability builtins — at runtime caps are opaque unit sentinels *)
  ; ("root_cap",   VUnit)
  ; ("cap_narrow", VBuiltin ("cap_narrow", function
    | [_cap] -> VUnit   (* attenuation is a compile-time check; runtime is a no-op *)
    | _ -> eval_error "cap_narrow: expected 1 argument"))

  (* Phase 5: task_spawn_link — spawn a task linked to an actor pid.
     If the linked actor crashes, the task is cancelled (or vice versa). *)
  (* App/Supervisor builtins *)
  ; ("worker", VBuiltin ("worker", function
      | [VCon (name, [])] ->
        VRecord [("actor", VString name); ("restart", VAtom "permanent")]
      | [VString name] ->
        VRecord [("actor", VString name); ("restart", VAtom "permanent")]
      (* Two-arg form: worker(Name, :restart_policy) or worker(Name, :registered_name).
         Restart policies (:permanent, :temporary, :transient) set the restart field.
         Any other atom is treated as a registered process name. *)
      | [VCon (name, []); VAtom arg] ->
        (match arg with
         | "permanent" | "temporary" | "transient" ->
           VRecord [("actor", VString name); ("restart", VAtom arg)]
         | atom_name ->
           VRecord [("actor", VString name); ("restart", VAtom "permanent");
                    ("name", VAtom atom_name)])
      | [VString name; VAtom arg] ->
        (match arg with
         | "permanent" | "temporary" | "transient" ->
           VRecord [("actor", VString name); ("restart", VAtom arg)]
         | atom_name ->
           VRecord [("actor", VString name); ("restart", VAtom "permanent");
                    ("name", VAtom atom_name)])
      (* Three-arg form: worker(Name, :policy, {name: :my_svc}) *)
      | [VCon (name, []); VAtom policy; VRecord opts] ->
        let base = [("actor", VString name); ("restart", VAtom policy)] in
        let with_name = match List.assoc_opt "name" opts with
          | Some (VAtom n) -> ("name", VAtom n) :: base
          | _ -> base in
        VRecord with_name
      | [VString name; VAtom policy; VRecord opts] ->
        let base = [("actor", VString name); ("restart", VAtom policy)] in
        let with_name = match List.assoc_opt "name" opts with
          | Some (VAtom n) -> ("name", VAtom n) :: base
          | _ -> base in
        VRecord with_name
      | _ -> eval_error "worker: expected an actor name, or (name, :policy), or (name, :policy, opts)"))

  ; ("Supervisor.spec", VBuiltin ("Supervisor.spec", function
      | [strategy; children] ->
        VRecord [("strategy", strategy); ("children", children)]
      | _ -> eval_error "Supervisor.spec: expected (strategy, children)"))

  ; ("App.stop", VBuiltin ("App.stop", function
      | [] | [VUnit] ->
        shutdown_requested := true;
        VUnit
      | _ -> eval_error "App.stop: expected no arguments"))


  (* Process registry: whereis returns Option(Pid); whereis_bang crashes if missing *)
  ; ("whereis", VBuiltin ("whereis", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VCon ("Some", [VPid pid])
         | _ -> VCon ("None", []))
      | _ -> eval_error "whereis: expected atom argument"))

  ; ("App.whereis", VBuiltin ("App.whereis", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VCon ("Some", [VPid pid])
         | _ -> VCon ("None", []))
      | _ -> eval_error "App.whereis: expected atom argument"))

  ; ("whereis_bang", VBuiltin ("whereis_bang", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VPid pid
         | _ -> eval_error "whereis!: no alive process named :%s" name)
      | _ -> eval_error "whereis_bang: expected atom argument"))

  ; ("App.whereis_bang", VBuiltin ("App.whereis_bang", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VPid pid
         | _ -> eval_error "whereis!: no alive process named :%s" name)
      | _ -> eval_error "App.whereis_bang: expected atom argument"))

  (* Dynamic supervisor: dynamic_supervisor(:name, :strategy) *)
  ; ("dynamic_supervisor", VBuiltin ("dynamic_supervisor", function
      | [VAtom name; strategy] ->
        let strat_str = match strategy with
          | VAtom s -> s | VCon (s, []) -> String.lowercase_ascii s | _ -> "one_for_one" in
        let vpid = !dyn_sup_next_vpid in
        dyn_sup_next_vpid := vpid - 1;
        let ds = { ds_name = name; ds_strategy = strat_str;
                   ds_max_restarts = 10; ds_window_secs = 60;
                   ds_vpid = vpid;
                   ds_children = []; ds_restart_count = [] } in
        Hashtbl.replace dyn_sup_registry name ds;
        Hashtbl.replace dyn_sup_vpid_map vpid name;
        VRecord [("type", VString "dynamic_supervisor"); ("name", VAtom name); ("vpid", VInt vpid)]
      | [VAtom name; strategy; VRecord opts] ->
        let strat_str = match strategy with
          | VAtom s -> s | VCon (s, []) -> String.lowercase_ascii s | _ -> "one_for_one" in
        let max_r = match List.assoc_opt "max_restarts" opts with
          | Some (VInt n) -> n | _ -> 10 in
        let window = match List.assoc_opt "within" opts with
          | Some (VInt n) -> n | _ -> 60 in
        let vpid = !dyn_sup_next_vpid in
        dyn_sup_next_vpid := vpid - 1;
        let ds = { ds_name = name; ds_strategy = strat_str;
                   ds_max_restarts = max_r; ds_window_secs = window;
                   ds_vpid = vpid;
                   ds_children = []; ds_restart_count = [] } in
        Hashtbl.replace dyn_sup_registry name ds;
        Hashtbl.replace dyn_sup_vpid_map vpid name;
        VRecord [("type", VString "dynamic_supervisor"); ("name", VAtom name); ("vpid", VInt vpid)]
      | _ -> eval_error "dynamic_supervisor: expected (name, strategy) or (name, strategy, opts)"))

  (* Supervisor.start_child(:sup_name, child_spec) : Result(Pid, String) *)
  ; ("Supervisor.start_child", VBuiltin ("Supervisor.start_child", function
      | [VAtom sup_name; VRecord spec_fields] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VCon ("Err", [VString ("no dynamic supervisor named :" ^ sup_name)])
         | Some ds ->
           let actor_name = match List.assoc_opt "actor" spec_fields with
             | Some (VString s) -> s
             | _ -> "" in
           let restart_pol = match List.assoc_opt "restart" spec_fields with
             | Some (VAtom s) -> s | _ -> "permanent" in
           if actor_name = "" then
             VCon ("Err", [VString "start_child: spec missing actor field"])
           else begin
             let new_pid = spawn_child_actor actor_name ds.ds_vpid in
             let entry = { dce_pid = new_pid; dce_actor_name = actor_name;
                           dce_restart = restart_pol } in
             ds.ds_children <- entry :: ds.ds_children;
             VCon ("Ok", [VInt new_pid])
           end)
      | _ -> eval_error "Supervisor.start_child: expected (atom, child_spec)"))

  (* Supervisor.stop_child(:sup_name, pid) : Result(Unit, String) *)
  ; ("Supervisor.stop_child", VBuiltin ("Supervisor.stop_child", function
      | [VAtom sup_name; VInt pid] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VCon ("Err", [VString ("no dynamic supervisor named :" ^ sup_name)])
         | Some ds ->
           (match List.find_opt (fun e -> e.dce_pid = pid) ds.ds_children with
            | None -> VCon ("Err", [VString "stop_child: pid not found"])
            | Some entry ->
              (* Detach from supervisor first to prevent restart *)
              (match Hashtbl.find_opt actor_registry entry.dce_pid with
               | Some inst -> inst.ai_supervisor <- None
               | None -> ());
              ds.ds_children <- List.filter (fun e -> e.dce_pid <> pid) ds.ds_children;
              crash_actor pid "stop_child";
              VCon ("Ok", [VUnit])))
      | _ -> eval_error "Supervisor.stop_child: expected (atom, pid)"))

  (* Supervisor.which_children(:sup_name) : List({pid, actor, restart}) *)
  ; ("Supervisor.which_children", VBuiltin ("Supervisor.which_children", function
      | [VAtom sup_name] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VCon ("Nil", [])
         | Some ds ->
           let make_rec e =
             VRecord [("pid",    VInt e.dce_pid);
                      ("actor",  VString e.dce_actor_name);
                      ("restart", VAtom e.dce_restart)] in
           List.fold_right
             (fun e acc -> VCon ("Cons", [make_rec e; acc]))
             ds.ds_children (VCon ("Nil", [])))
      | _ -> eval_error "Supervisor.which_children: expected (atom)"))

  (* Supervisor.count_children(:sup_name) : {active: Int, specs: Int} *)
  ; ("Supervisor.count_children", VBuiltin ("Supervisor.count_children", function
      | [VAtom sup_name] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VRecord [("active", VInt 0); ("specs", VInt 0)]
         | Some ds ->
           let total = List.length ds.ds_children in
           let active = List.length (List.filter (fun e ->
             match Hashtbl.find_opt actor_registry e.dce_pid with
             | Some inst -> inst.ai_alive | None -> false) ds.ds_children) in
           VRecord [("active", VInt active); ("specs", VInt total)])
      | _ -> eval_error "Supervisor.count_children: expected (atom)"))

  ; ("task_spawn_link", VBuiltin ("task_spawn_link", function
    | [thunk; VPid linked_pid] ->
      let tid = !next_task_id in
      next_task_id := tid + 1;
      (* Check if linked actor is still alive before running *)
      let linked_alive = match Hashtbl.find_opt actor_registry linked_pid with
        | Some inst -> inst.ai_alive
        | None -> false
      in
      if not linked_alive then begin
        (* Linked actor already dead — task fails immediately *)
        let entry = { te_id = tid; te_result = Some (VCon ("Err", [VString "linked actor dead"]));
                      te_thunk = thunk } in
        Hashtbl.add task_registry tid entry;
        VTask tid
      end else begin
        (* Eagerly execute the thunk (Phase 1: single-threaded) *)
        let result =
          (try
             let v = apply thunk [VInt 0] in
             v
           with exn ->
             (* Task raised an exception: crash the linked actor *)
             (match Hashtbl.find_opt actor_registry linked_pid with
              | Some inst when inst.ai_alive ->
                crash_actor linked_pid
                  (Printf.sprintf "linked task raised: %s" (Printexc.to_string exn))
              | _ -> ());
             raise exn)
        in
        let entry = { te_id = tid; te_result = Some result; te_thunk = thunk } in
        Hashtbl.add task_registry tid entry;
        VTask tid
      end
    | _ -> eval_error "task_spawn_link: expected (thunk, Pid)"))
  ]

(** Run [thunk] (a zero-argument closure) while counting reductions.
    Returns [(result, reductions_consumed)].  The count is also stored in
    [last_reduction_count] so that the [task_reductions] builtin can read it. *)
let eval_with_reduction_tracking (thunk : value) : value * int =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  reduction_ctx := Some ctx;
  let result = apply thunk [] in
  let consumed = March_scheduler.Scheduler.max_reductions - ctx.March_scheduler.Scheduler.remaining in
  reduction_ctx := None;
  last_reduction_count := consumed;
  (result, consumed)

(* ------------------------------------------------------------------ *)
(* App / Supervisor machinery                                          *)
(* ------------------------------------------------------------------ *)

(** Convert a March list value (VCon Cons/Nil) to an OCaml list of values. *)
let rec march_list_to_list = function
  | VCon ("Nil", []) -> []
  | VCon ("Cons", [h; t]) -> h :: march_list_to_list t
  | v -> eval_error "march_list_to_list: expected list, got %s" (value_to_string v)

(** Send [Shutdown()] to [pid], run one scheduler pass to execute the handler
    if defined, then force-kill the actor regardless. *)
let shutdown_actor_pid (pid : int) : unit =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst when not inst.ai_alive -> ()
  | Some inst ->
    (* Enqueue Shutdown() message *)
    Queue.push (VCon ("Shutdown", [])) inst.ai_mailbox;
    (* Process one message from this actor's mailbox (the Shutdown we just queued) *)
    if not (Queue.is_empty inst.ai_mailbox) then begin
      let msg = Queue.pop inst.ai_mailbox in
      let (msg_tag, msg_args) = match msg with
        | VCon (tag, args) -> (tag, args)
        | VAtom tag        -> (tag, [])
        | _                -> ("__drop__", [])
      in
      if msg_tag <> "__drop__" then begin
        match List.find_opt (fun h -> h.ah_msg.txt = msg_tag)
                inst.ai_def.actor_handlers with
        | None -> ()  (* No Shutdown handler: fall through to force-kill *)
        | Some handler ->
          if List.length handler.ah_params = List.length msg_args then begin
            let prev_pid = !current_pid in
            current_pid := Some pid;
            let param_bindings =
              List.map2 (fun p v -> (p.param_name.txt, v))
                handler.ah_params msg_args
            in
            let handler_env =
              [("state", inst.ai_state)] @ param_bindings @ !(inst.ai_env_ref)
            in
            (match !eval_expr_hook handler_env handler.ah_body with
             | new_state -> inst.ai_state <- new_state
             | exception _ -> ());
            current_pid := prev_pid
          end
      end
    end;
    (* Force-kill the actor *)
    (match Hashtbl.find_opt actor_registry pid with
     | Some inst2 -> inst2.ai_alive <- false
     | None -> ())

(** Graceful shutdown: stop all app-level children in reverse spawn order. *)
let graceful_shutdown () : unit =
  let pids_rev = List.rev !app_spawn_order in
  List.iter shutdown_actor_pid pids_rev;
  app_spawn_order := []

(** Spawn all children described in a supervisor spec record.
    Spec shape: { strategy = :one_for_one, children = [ChildSpec, ...] }
    ChildSpec shape: { actor = "Name", restart = :permanent }
    Records spawn order in [app_spawn_order]. *)
let spawn_from_spec (spec : value) : unit =
  match spec with
  | VRecord fields ->
    let children_val = match List.assoc_opt "children" fields with
      | Some v -> v
      | None -> eval_error "spawn_from_spec: spec missing 'children' field"
    in
    let children = march_list_to_list children_val in
    List.iter (fun child ->
      match child with
      | VRecord child_fields ->
        (* Dynamic supervisor specs are pre-registered; skip spawning an actor for them *)
        (match List.assoc_opt "type" child_fields with
         | Some (VString "dynamic_supervisor") -> ()
         | _ ->
           let actor_name = match List.assoc_opt "actor" child_fields with
             | Some (VString s) -> s
             | Some other -> eval_error "spawn_from_spec: actor field should be a string, got %s"
                               (value_to_string other)
             | None -> eval_error "spawn_from_spec: child spec missing 'actor' field"
           in
           (match Hashtbl.find_opt actor_defs_tbl actor_name with
            | None -> eval_error "spawn_from_spec: unknown actor '%s'" actor_name
            | Some (def, env_ref) ->
              let pid = !next_pid in
              next_pid := pid + 1;
              let init_state = eval_expr !env_ref def.actor_init in
              let inst = {
                ai_name = actor_name; ai_def = def; ai_env_ref = env_ref;
                ai_state = init_state; ai_alive = true;
                ai_monitors = []; ai_links = []; ai_mailbox = Queue.create ();
                ai_supervisor = None; ai_restart_count = []; ai_epoch = 0;
                ai_resources = []; ai_linear_values = [] } in
              Hashtbl.add actor_registry pid inst;
              app_spawn_order := !app_spawn_order @ [pid];
              (* Register named children in the process registry *)
              (match List.assoc_opt "name" child_fields with
               | Some (VAtom atom_name) ->
                 Hashtbl.replace process_registry atom_name pid;
                 Hashtbl.replace pid_to_registry_name pid atom_name
               | _ -> ())))
      | other -> eval_error "spawn_from_spec: expected child spec record, got %s"
                   (value_to_string other)
    ) children
  | other -> eval_error "spawn_from_spec: expected supervisor spec record, got %s"
               (value_to_string other)

(* ------------------------------------------------------------------ *)
(* Module evaluation                                                   *)
(* ------------------------------------------------------------------ *)

(** A mutable stub: lets us install a forward reference for a name and
    later fill it with the real closure. *)
type stub = { mutable sv : value }

(** Evaluate a single declaration, extending [env].
    Returns the updated environment. *)
let rec eval_decl (env : env) (d : decl) : env =
  match d with
  | DFn (def, _) ->
    (* Register doc string if present *)
    (match def.fn_doc with
     | Some s -> Hashtbl.replace doc_registry (current_doc_prefix () ^ def.fn_name.txt) s
     | None   -> ());
    let clause = match def.fn_clauses with
      | [c] -> c
      | _   -> eval_error "fn %s: expected exactly one clause after desugaring"
                  def.fn_name.txt
    in
    let params = clause_params clause in
    (* Use a mutable env ref so the closure can call itself recursively.
       When [rec_closure] is invoked, [env_ref] already contains the
       function's own name, making self-recursion work in the REPL. *)
    let env_ref = ref env in
    let rec_closure = VBuiltin ("<rec:" ^ def.fn_name.txt ^ ">",
                                fun args ->
                                  let call_env = !env_ref in
                                  let fn_v = VClosure (call_env, params, clause.fc_body) in
                                  apply fn_v args) in
    let env' = (def.fn_name.txt, rec_closure)
               :: List.remove_assoc def.fn_name.txt env in
    env_ref := env';
    env'

  | DLet (_, b, _) ->
    let v = eval_expr env b.bind_expr in
    (match match_pattern v b.bind_pat with
     | Some bs -> bs @ env
     | None    -> eval_error "top-level let binding pattern failed")

  | DType (_, name, _, td, _) ->
    (* Populate ctor_type_tbl so dispatch can find the type from a constructor value. *)
    (match td with
     | TDVariant variants ->
       List.iter (fun (v : variant) ->
           Hashtbl.replace ctor_type_tbl v.var_name.txt name.txt
         ) variants
     | _ -> ());
    env

  | DActor (_, name, def, _) ->
    (* Register actor definition so spawn() can find it later *)
    let env_ref = ref env in
    Hashtbl.replace actor_defs_tbl name.txt (def, env_ref);
    env

  | DMod (name, _, decls, _) ->
    (* Evaluate nested module; bindings are prefixed with "ModName." *)
    module_stack := name.txt :: !module_stack;
    (* Two-pass evaluation for inner decls so recursive/mutual fns work *)
    let inner_ref = ref env in
    List.iter (function
      | DFn (def, _) ->
        let stub = VBuiltin ("<stub:" ^ def.fn_name.txt ^ ">",
                             fun _ -> eval_error "stub %s called before initialisation"
                                 def.fn_name.txt) in
        inner_ref := (def.fn_name.txt, stub) :: !inner_ref
      | _ -> ()
    ) decls;
    let rec eval_mod_decls ds e =
      match ds with
      | [] -> e
      | DFn (def, _) :: rest ->
        (match def.fn_doc with
         | Some s -> Hashtbl.replace doc_registry (current_doc_prefix () ^ def.fn_name.txt) s
         | None   -> ());
        let clause = match def.fn_clauses with
          | [c] -> c
          | _   -> eval_error "fn %s: expected one clause after desugaring"
                       def.fn_name.txt
        in
        let params = clause_params clause in
        let rec_closure = VBuiltin ("<rec:" ^ def.fn_name.txt ^ ">",
                                    fun args ->
                                      let call_env = !inner_ref in
                                      let fn_v = VClosure (call_env, params, clause.fc_body) in
                                      apply fn_v args) in
        let e' = (def.fn_name.txt, rec_closure)
                   :: List.remove_assoc def.fn_name.txt e in
        inner_ref := e';
        eval_mod_decls rest e'
      | d :: rest ->
        let e' = eval_decl e d in
        inner_ref := e';
        eval_mod_decls rest e'
    in
    let mod_env = eval_mod_decls decls !inner_ref in
    module_stack := List.tl !module_stack;
    (* Collect names actually defined by this module's declarations
       (DFn, DLet top bindings, nested DMod names).  We only expose
       these under the qualified prefix, not inherited outer bindings. *)
    let rec declared_names acc = function
      | [] -> acc
      | DFn (def, _) :: rest -> declared_names (def.fn_name.txt :: acc) rest
      | DLet (_, b, _) :: rest ->
        let rec pat_names a = function
          | PatVar n -> n.txt :: a
          | PatTuple (ps, _) -> List.fold_left pat_names a ps
          | PatCon (_, ps) -> List.fold_left pat_names a ps
          | _ -> a
        in
        declared_names (pat_names acc b.bind_pat) rest
      | DMod (n, _, _, _) :: rest -> declared_names (n.txt :: acc) rest
      | DExtern (edef, _) :: rest ->
        let names = List.map (fun (ef : extern_fn) -> ef.ef_name.txt) edef.ext_fns in
        declared_names (names @ acc) rest
      | _ :: rest -> declared_names acc rest
    in
    let own_names = declared_names [] decls in
    (* Also export keys like "B.f" when "B" is a declared sub-module *)
    let is_own_key k =
      List.exists (fun n ->
        k = n ||
        (String.length k > String.length n + 1 &&
         String.sub k 0 (String.length n + 1) = n ^ ".")
      ) own_names
    in
    let prefixed = List.filter_map (fun (k, v) ->
        if is_own_key k
        then Some (name.txt ^ "." ^ k, v)
        else None
      ) mod_env in
    prefixed @ env

  | DImpl (idef, sp) ->
    (* Evaluate each impl method so they become callable at runtime.
       Default methods injected by the desugar pass have fc_params=[] and a
       lambda body; evaluate the body directly and bind the resulting value.
       Phase 6b: also populate impl_tbl so the `own` builtin can resolve drop fns. *)
    let type_name = match idef.impl_ty with
      | TyCon (n, _) -> n.txt
      | TyVar n      -> n.txt
      | _            -> ""
    in
    List.fold_left (fun env (mname, fn_def) ->
        let new_env = match fn_def.fn_clauses with
          | [{ fc_params = []; fc_body; _ }] ->
            let v = eval_expr env fc_body in
            (mname.txt, v) :: env
          | _ ->
            eval_decl env (DFn (fn_def, sp))
        in
        (* Phase 6b: register in impl_tbl for own() resolution *)
        if type_name <> "" then begin
          match List.assoc_opt mname.txt new_env with
          | Some fn_val ->
            Hashtbl.replace impl_tbl (idef.impl_iface.txt, type_name) fn_val
          | None -> ()
        end;
        new_env
      ) env idef.impl_methods

  | DProtocol (name, pdef, _sp) ->
    (* Register the protocol roles so MPST.new can create the right endpoints. *)
    let rec collect_roles acc = function
      | [] -> acc
      | ProtoMsg (s, r, _) :: rest ->
        collect_roles (s.txt :: r.txt :: acc) rest
      | ProtoLoop steps :: rest ->
        collect_roles (collect_roles acc steps) rest
      | ProtoChoice (ch, branches) :: rest ->
        let branch_roles = List.concat_map (fun (_, steps) ->
            collect_roles [] steps) branches in
        collect_roles (ch.txt :: branch_roles @ acc) rest
    in
    let roles = List.sort_uniq String.compare
        (collect_roles [] pdef.proto_steps) in
    Hashtbl.replace protocol_roles_tbl name.txt roles;
    env

  | DSig _ | DInterface _ | DNeeds _ -> env

  | DExtern (edef, _sp) ->
    (* Bind each extern function name to a VForeign stub. *)
    List.fold_left (fun env' (ef : extern_fn) ->
      let stub = VForeign (edef.ext_lib_name, ef.ef_name.txt) in
      (ef.ef_name.txt, stub) :: env'
    ) env edef.ext_fns

  | DDeriving _ ->
    (* DDeriving is expanded to DImpl blocks by the desugar pass; skip here. *)
    env

  | DApp _ ->
    (* DApp is desugared to DFn(__app_init__) before eval; reaching here is a bug. *)
    env

  | DTest _ | DSetup _ | DSetupAll _ | DDescribe _ ->
    (* DTest/DSetup/DSetupAll/DDescribe are not run during normal module eval.
       They are collected and run by [run_tests]. *)
    env

  | DUse (ud, _) ->
    let prefix = String.concat "." (List.map (fun (n : name) -> n.txt) ud.use_path) ^ "." in
    (match ud.use_sel with
     | UseSingle -> env
     | UseAll ->
       let plen = String.length prefix in
       let additions = List.filter_map (fun (k, v) ->
           if String.length k > plen && String.sub k 0 plen = prefix then
             Some (String.sub k plen (String.length k - plen), v)
           else None) env in
       additions @ env
     | UseNames names ->
       List.fold_left (fun env n ->
           match List.assoc_opt (prefix ^ n.txt) env with
           | Some v -> (n.txt, v) :: env
           | None -> env) env names
     | UseExcept excluded ->
       let excl_set = List.map (fun (n : name) -> n.txt) excluded in
       let plen = String.length prefix in
       let additions = List.filter_map (fun (k, v) ->
           if String.length k > plen && String.sub k 0 plen = prefix then
             let short = String.sub k plen (String.length k - plen) in
             if List.mem short excl_set then None
             else Some (short, v)
           else None) env in
       additions @ env)

  | DAlias (ad, _) ->
    let orig_prefix = String.concat "." (List.map (fun (n : name) -> n.txt) ad.alias_path) ^ "." in
    let short_name = ad.alias_name.txt in
    let short_prefix = short_name ^ "." in
    let plen = String.length orig_prefix in
    let additions = List.filter_map (fun (k, v) ->
        if String.length k > plen && String.sub k 0 plen = orig_prefix then
          Some (short_prefix ^ String.sub k plen (String.length k - plen), v)
        else None) env in
    additions @ env

and eval_decls (env : env) (decls : decl list) : env =
  List.fold_left eval_decl env decls

(** Two-pass module evaluation.

    Pass 1: For every top-level [DFn], install a stub closure in the
            environment.  This lets mutually-recursive functions refer
            to each other by name.

    Pass 2: Re-evaluate each [DFn] so that its closure captures the
            fully-populated environment (including all stubs). *)
let eval_module_env (m : module_) : env =
  (* Reset global actor and task state for this module run *)
  Hashtbl.clear actor_defs_tbl;
  Hashtbl.clear actor_registry;
  next_pid := 0;
  Hashtbl.clear task_registry;
  next_task_id := 0;
  Hashtbl.clear dyn_sup_registry;
  Hashtbl.clear dyn_sup_vpid_map;
  dyn_sup_next_vpid := (-1);

  (* Pass 1: stubs.  We use a ref cell shared across all stubs so that
     closures created in pass 2 can see the final environment. *)
  let env_ref : env ref = ref (task_builtins @ base_env) in

  (* Install a placeholder for every top-level fn *)
  let install_stub = function
    | DFn (def, _) ->
      (* Placeholder that will be overwritten in pass 2 *)
      let stub = VBuiltin ("<stub:" ^ def.fn_name.txt ^ ">",
                           fun _ -> eval_error "stub %s called before initialisation"
                               def.fn_name.txt) in
      env_ref := (def.fn_name.txt, stub) :: !env_ref
    | _ -> ()
  in
  List.iter install_stub m.mod_decls;

  (* Pass 2: evaluate declarations in order, building up real closures.
     Each closure closes over [env_ref], which by the time any function
     is *called* will hold the full environment. *)
  let rec make_recursive_env decls env =
    match decls with
    | [] -> env
    | DFn (def, _) :: rest ->
      (match def.fn_doc with
       | Some s -> Hashtbl.replace doc_registry (current_doc_prefix () ^ def.fn_name.txt) s
       | None   -> ());
      let clause = match def.fn_clauses with
        | [c] -> c
        | _   -> eval_error "fn %s: expected one clause after desugaring"
                     def.fn_name.txt
      in
      let params = clause_params clause in
      (* The closure environment is the ref itself; we use a trick:
         build a closure that looks up in [env_ref] at call time. *)
      let rec_closure = VBuiltin ("<rec:" ^ def.fn_name.txt ^ ">",
                                  fun args ->
                                    let call_env = !env_ref in
                                    let fn_v = VClosure (call_env, params, clause.fc_body) in
                                    apply fn_v args) in
      let env' = (def.fn_name.txt, rec_closure)
                 :: List.remove_assoc def.fn_name.txt env in
      env_ref := env';
      make_recursive_env rest env'

    | DLet (_, b, _) :: rest ->
      let v = eval_expr env b.bind_expr in
      let env' = match match_pattern v b.bind_pat with
        | Some bs -> bs @ env
        | None    -> eval_error "top-level let pattern failed"
      in
      env_ref := env';
      make_recursive_env rest env'

    | DActor (_, name, def, _) :: rest ->
      (* Register actor with the shared env_ref so handlers can call module fns *)
      Hashtbl.replace actor_defs_tbl name.txt (def, env_ref);
      make_recursive_env rest env

    | DMod _ as d :: rest ->
      (* Evaluate nested module via eval_decl (which handles module_stack push/pop
         and exposes prefixed bindings). Docs inside nested modules are registered
         as a side effect of eval_decl → eval_decls → eval_decl(DFn). *)
      let env' = eval_decl env d in
      env_ref := env';
      make_recursive_env rest env'

    | DImpl (idef, sp) :: rest ->
      (* Bind each impl method (including injected defaults) as a function.
         Zero-param clauses hold a lambda body; eval directly to bind the value.
         Phase 6b: also populate impl_tbl so the `own` builtin can resolve drop fns. *)
      let type_name = match idef.impl_ty with
        | TyCon (n, _) -> n.txt
        | TyVar n      -> n.txt
        | _            -> ""
      in
      let env' = List.fold_left (fun acc_env (mname, fn_def) ->
          let new_acc = match fn_def.fn_clauses with
            | [{ fc_params = []; fc_body; _ }] ->
              let v = eval_expr acc_env fc_body in
              (mname.txt, v) :: acc_env
            | _ ->
              eval_decl acc_env (DFn (fn_def, sp))
          in
          (* Phase 6b: register in impl_tbl for own() resolution *)
          if type_name <> "" then begin
            match List.assoc_opt mname.txt new_acc with
            | Some fn_val ->
              Hashtbl.replace impl_tbl (idef.impl_iface.txt, type_name) fn_val
            | None -> ()
          end;
          new_acc
        ) env idef.impl_methods in
      env_ref := env';
      make_recursive_env rest env'

    | (DUse _ | DAlias _) as d :: rest ->
      let env' = eval_decl env d in
      env_ref := env';
      make_recursive_env rest env'

    | DType (_, name, _, td, _) :: rest ->
      (* Populate ctor_type_tbl for dispatch *)
      (match td with
       | TDVariant variants ->
         List.iter (fun (v : variant) ->
             Hashtbl.replace ctor_type_tbl v.var_name.txt name.txt
           ) variants
       | _ -> ());
      make_recursive_env rest env

    | DProtocol _ as d :: rest ->
      ignore (eval_decl env d);
      make_recursive_env rest env

    | DExtern _ as d :: rest ->
      let env' = eval_decl env d in
      env_ref := env';
      make_recursive_env rest env'

    | _ :: rest -> make_recursive_env rest env
  in

  let final_env = make_recursive_env m.mod_decls !env_ref in
  env_ref := final_env;
  final_env

(** Call an optional hook stored as [Some(fn)] / [None] in a VCon. *)
let call_hook_opt (v_opt : value option) : unit =
  match v_opt with
  | Some (VCon ("Some", [hook_fn])) -> ignore (apply hook_fn [])
  | _ -> ()

(** Run the module: evaluate it, then call [main()] or drive the [app] lifecycle.
    - [main()] path: call main, drain the scheduler, exit.
    - [app] path: evaluate __app_init__ → { spec, on_start, on_stop },
      spawn supervision tree, call on_start, run scheduler until shutdown,
      call graceful_shutdown, call on_stop, exit. *)
let run_module (m : module_) : unit =
  (* Reset global app state for fresh run *)
  app_spawn_order   := [];
  shutdown_requested := false;
  let env = eval_module_env m in
  (* Install SIGTERM/SIGINT handlers for graceful shutdown *)
  let handle_signal (_ : int) = shutdown_requested := true in
  Sys.set_signal Sys.sigterm (Sys.Signal_handle handle_signal);
  Sys.set_signal Sys.sigint  (Sys.Signal_handle handle_signal);
  match List.assoc_opt "__app_init__" env with
  | Some init_fn ->
    (* App entry point: evaluate app body to get { spec, on_start, on_stop } *)
    let app_record = apply init_fn [] in
    let spec = match app_record with
      | VRecord fields ->
        (match List.assoc_opt "spec" fields with
         | Some v -> v
         | None -> app_record)
      | _ -> app_record
    in
    let on_start_opt = match app_record with
      | VRecord fields -> List.assoc_opt "on_start" fields
      | _ -> None
    in
    let on_stop_opt = match app_record with
      | VRecord fields -> List.assoc_opt "on_stop" fields
      | _ -> None
    in
    (* 1. Spawn supervision tree *)
    spawn_from_spec spec;
    (* 2. Call on_start hook (after tree is up) *)
    call_hook_opt on_start_opt;
    (* 3. Run scheduler until drained or shutdown requested *)
    run_scheduler ();
    (* 4. Graceful shutdown: reverse-order Shutdown() to each child *)
    if not (List.is_empty !app_spawn_order) then
      graceful_shutdown ();
    (* 5. Call on_stop hook (after tree is down) *)
    call_hook_opt on_stop_opt
  | None ->
    match List.assoc_opt "main" env with
    | None   -> ()
    | Some v ->
      let _ = apply v [] in
      run_scheduler ()

(* ------------------------------------------------------------------ *)
(* Test runner                                                         *)
(* ------------------------------------------------------------------ *)

(** Result of running a single test. *)
type test_result =
  | TestPass
  | TestFail of string  (** failure message *)
  | TestError of string (** unexpected exception *)

(** Collect all [DTest], [DSetup], and [DSetupAll] nodes from the module,
    flattening [DDescribe] groups (prefixing test names with describe label). *)
let collect_test_decls (m : module_) :
    expr option * expr option * (string * expr) list =
  let setup_ref     = ref None in
  let setup_all_ref = ref None in
  let tests         = ref [] in
  let rec collect_decl prefix d =
    match d with
    | DTest (tdef, _) ->
      let full_name = if prefix = "" then tdef.test_name
                      else prefix ^ " " ^ tdef.test_name in
      tests := (full_name, tdef.test_body) :: !tests
    | DDescribe (name, decls, _) ->
      let new_prefix = if prefix = "" then name else prefix ^ " " ^ name in
      List.iter (collect_decl new_prefix) decls
    | DSetup (body, _)    -> setup_ref     := Some body
    | DSetupAll (body, _) -> setup_all_ref := Some body
    | _ -> ()
  in
  List.iter (collect_decl "") m.mod_decls;
  (!setup_all_ref, !setup_ref, List.rev !tests)

(** Run the test suite in [m] with the given options.
    Returns [(total, n_failed, failures)] so the caller can emit a summary.
    [~verbose] — emit each test name instead of dots.
    [~quiet]   — suppress all output; just return counts and failure list.
    [~filter]  — only run tests whose name contains this substring.

    Output:
      - Dot mode (default):  prints one `.` per pass, `F` per fail, then "Finished" line.
      - Verbose mode:        prints `✓ name` / `✗ name  (msg)`, then "Finished" line.
      - Quiet mode:          no output at all; caller handles reporting.

    Exit-code contract: the caller is responsible for exiting 1 if failures > 0.
    [~capture_io] — when true, suppress print/log output during each test and
    include it in the failure message if the test fails.  Opt-in via @capture_io
    in the test source. *)
let run_tests ?(verbose=false) ?(quiet=false) ?(dot_stream=false) ?(filter="") ?(capture_io=false) (m : module_) : int * int * (string * string) list =
  (* Build the module environment (registers all fns, lets, etc.) *)
  let env = eval_module_env m in
  let (setup_all_opt, setup_opt, tests) = collect_test_decls m in
  (* Apply filter *)
  let tests = if filter = "" then tests
              else List.filter (fun (name, _) ->
                     let lname = String.lowercase_ascii name in
                     let lpat  = String.lowercase_ascii filter in
                     let n = String.length lname and p = String.length lpat in
                     let rec check i =
                       if i + p > n then false
                       else if String.sub lname i p = lpat then true
                       else check (i + 1)
                     in check 0
                   ) tests in
  (* Run setup_all once *)
  (match setup_all_opt with
   | Some body -> (try let _ = eval_expr env body in ()
                   with exn ->
                     Printf.eprintf "setup_all failed: %s\n%!" (Printexc.to_string exn))
   | None -> ());
  let total = List.length tests in
  let failures = ref [] in
  if not verbose && not quiet then Printf.printf "%!" else ();
  List.iter (fun (name, body) ->
    (* Run per-test setup *)
    (match setup_opt with
     | Some s -> (try let _ = eval_expr env s in ()
                  with exn ->
                    Printf.eprintf "setup failed for \"%s\": %s\n%!" name (Printexc.to_string exn))
     | None -> ());
    (* When capture_io is enabled, redirect print/log into a per-test buffer. *)
    let cap_buf = if capture_io then Some (Buffer.create 128) else None in
    (match cap_buf with Some b -> test_capture_buf := Some b | None -> ());
    let result =
      try
        let _ = eval_expr env body in
        TestPass
      with
      | Assert_failure msg -> TestFail msg
      | Eval_error msg     -> TestError msg
      | Match_failure msg  -> TestError ("match failure: " ^ msg)
      | exn                -> TestError (Printexc.to_string exn)
    in
    test_capture_buf := None;
    let captured = match cap_buf with
      | Some b -> Buffer.contents b
      | None -> ""
    in
    (* Append captured output to failure message when non-empty. *)
    let with_output msg =
      if captured = "" then msg
      else msg ^ "\n\n--- captured output ---\n" ^ String.trim captured
    in
    if quiet then begin
      (* Collect failures silently *)
      (match result with
       | TestPass -> ()
       | TestFail msg -> failures := (name, with_output msg) :: !failures
       | TestError msg -> failures := (name, with_output ("error: " ^ msg)) :: !failures)
    end else if verbose then begin
      match result with
      | TestPass ->
        Printf.printf "  ✓ %s\n%!" name
      | TestFail msg ->
        let full = with_output msg in
        Printf.printf "  ✗ %s\n    %s\n%!" name
          (String.concat "\n    " (String.split_on_char '\n' full));
        failures := (name, full) :: !failures
      | TestError msg ->
        let full = with_output ("error: " ^ msg) in
        Printf.printf "  ✗ %s\n    %s\n%!" name
          (String.concat "\n    " (String.split_on_char '\n' full));
        failures := (name, full) :: !failures
    end else begin
      (match result with
       | TestPass ->
         if dot_stream then Printf.printf "\027[32m.\027[0m%!"
         else Printf.printf ".%!"
       | TestFail msg ->
         if dot_stream then Printf.printf "\027[31mF\027[0m%!"
         else Printf.printf "F%!";
         failures := (name, with_output msg) :: !failures
       | TestError msg ->
         if dot_stream then Printf.printf "\027[31mE\027[0m%!"
         else Printf.printf "E%!";
         failures := (name, with_output ("error: " ^ msg)) :: !failures)
    end
  ) tests;
  let n_failed = List.length !failures in
  if not quiet && not dot_stream then begin
    if not verbose then Printf.printf "\n%!";
    (* Print failure details in dot mode *)
    if not verbose && !failures <> [] then begin
      Printf.printf "\n%d failure(s):\n\n" (List.length !failures);
      List.iter (fun (name, msg) ->
        Printf.printf "FAIL: \"%s\"\n  %s\n\n" name
          (String.concat "\n  " (String.split_on_char '\n' msg))
      ) (List.rev !failures)
    end;
    Printf.printf "Finished: %d test%s, %d failure%s\n%!"
      total (if total = 1 then "" else "s")
      n_failed (if n_failed = 1 then "" else "s")
  end;
  (total, n_failed, List.rev !failures)

(* ------------------------------------------------------------------ *)
(* Doctest runner                                                      *)
(* ------------------------------------------------------------------ *)

(** Run all doctests extracted from [fn_doc] fields in the module.

    [parse_expr] converts a source string to an AST [expr].  It is injected
    by the caller so that [march_eval] does not need to depend on [march_parser].

    Returns [(total, n_failed, failures)] with the same contract as [run_tests].
    Output format mirrors [run_tests]:
      Verbose   — "  ✓ doctest Option.is_some (1)"
      Dot mode  — one '.' per pass, 'F' per fail, 'E' per error
      Quiet     — no output; caller handles reporting. *)
let run_doctests ?(verbose=false) ?(quiet=false) ?(filter="")
    ~(parse_expr : string -> expr)
    (m : module_) : int * int * (string * string) list =
  (* Build the module environment *)
  let env = eval_module_env m in
  (* Collect (qualified_fn_name, doc_string) pairs, walking nested mods *)
  let rec collect_docs prefix decls =
    List.concat_map (fun decl ->
      match decl with
      | DFn (def, _) ->
        (match def.fn_doc with
         | None -> []
         | Some doc ->
           let qname = if prefix = "" then def.fn_name.txt
                       else prefix ^ "." ^ def.fn_name.txt in
           [(qname, doc)])
      | DMod (mname, _, inner, _) ->
        let new_prefix = if prefix = "" then mname.txt
                         else prefix ^ "." ^ mname.txt in
        collect_docs new_prefix inner
      | _ -> [])
    decls
  in
  let fn_docs = collect_docs "" m.mod_decls in
  (* Expand docs into (test_name, example) list *)
  let tests : (string * March_doctest.Doctest.example) list =
    List.concat_map (fun (fname, doc) ->
      let examples = March_doctest.Doctest.extract doc in
      List.mapi (fun i ex ->
        let name = Printf.sprintf "doctest %s (%d)" fname (i + 1) in
        (name, ex)
      ) examples
    ) fn_docs
  in
  (* Filter *)
  let tests =
    if filter = "" then tests
    else List.filter (fun (name, _) ->
           let lname = String.lowercase_ascii name in
           let lpat  = String.lowercase_ascii filter in
           let n = String.length lname and p = String.length lpat in
           let rec check i =
             if i + p > n then false
             else if String.sub lname i p = lpat then true
             else check (i + 1)
           in check 0
         ) tests
  in
  let total    = List.length tests in
  let failures = ref [] in
  List.iter (fun (name, ex) ->
    let result =
      (try
         let expr   = parse_expr ex.March_doctest.Doctest.ex_source in
         let v      = eval_expr env expr in
         let actual = value_to_string v in
         (match ex.March_doctest.Doctest.ex_expected with
          | March_doctest.Doctest.ExpectOutput expected ->
            if actual = expected then TestPass
            else TestFail (Printf.sprintf "expected: %s\n  got:      %s" expected actual)
          | March_doctest.Doctest.ExpectPanic expected ->
            TestFail (Printf.sprintf "expected panic %S\n  but got: %s" expected actual)
          | March_doctest.Doctest.ExpectNothing ->
            TestPass)
       with
       | Eval_error msg ->
         (match ex.March_doctest.Doctest.ex_expected with
          | March_doctest.Doctest.ExpectPanic expected ->
            (* Panic messages are raised as "panic: <msg>"; strip the prefix *)
            let panic_tag = "panic: " in
            let actual_msg =
              if String.length msg > String.length panic_tag &&
                 String.sub msg 0 (String.length panic_tag) = panic_tag
              then String.sub msg (String.length panic_tag)
                     (String.length msg - String.length panic_tag)
              else msg
            in
            if actual_msg = expected then TestPass
            else TestFail (Printf.sprintf "expected panic %S\n  got panic: %s" expected actual_msg)
          | _ ->
            TestError msg)
       | exn ->
         TestError (Printexc.to_string exn))
    in
    if quiet then begin
      match result with
      | TestPass -> ()
      | TestFail msg -> failures := (name, msg) :: !failures
      | TestError msg -> failures := (name, "error: " ^ msg) :: !failures
    end else if verbose then begin
      match result with
      | TestPass ->
        Printf.printf "  ✓ %s\n%!" name
      | TestFail msg ->
        Printf.printf "  ✗ %s\n    %s\n%!" name
          (String.concat "\n    " (String.split_on_char '\n' msg));
        failures := (name, msg) :: !failures
      | TestError msg ->
        Printf.printf "  ✗ %s (error: %s)\n%!" name msg;
        failures := (name, "error: " ^ msg) :: !failures
    end else begin
      match result with
      | TestPass  -> Printf.printf "\027[32m.\027[0m%!"
      | TestFail msg ->
        Printf.printf "\027[31mF\027[0m%!";
        failures := (name, msg) :: !failures
      | TestError msg ->
        Printf.printf "\027[31mE\027[0m%!";
        failures := (name, "error: " ^ msg) :: !failures
    end
  ) tests;
  let n_failed = List.length !failures in
  if not quiet then begin
    if not verbose then Printf.printf "\n%!";
    if not verbose && !failures <> [] then begin
      Printf.printf "\n%d failure(s):\n\n" (List.length !failures);
      List.iter (fun (name, msg) ->
        Printf.printf "FAIL: \"%s\"\n  %s\n\n" name
          (String.concat "\n  " (String.split_on_char '\n' msg))
      ) (List.rev !failures)
    end;
    Printf.printf "Finished: %d doctest%s, %d failure%s\n%!"
      total (if total = 1 then "" else "s")
      n_failed (if n_failed = 1 then "" else "s")
  end;
  (total, n_failed, List.rev !failures)
