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
}

(** Actor definitions registered by [DActor] — reset per module eval. *)
let actor_defs_tbl : (string, actor_def * env ref) Hashtbl.t = Hashtbl.create 8

(** Live actor instances — reset per module eval. *)
let actor_registry  : (int, actor_inst) Hashtbl.t = Hashtbl.create 16

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

(** Module stack for tracking the current module path during eval.
    Updated when entering/leaving [DMod]. Top of stack = innermost module. *)
let module_stack : string list ref = ref []

let current_doc_prefix () =
  match !module_stack with
  | []    -> ""
  | parts -> String.concat "." (List.rev parts) ^ "."

let lookup_doc (key : string) : string option =
  Hashtbl.find_opt doc_registry key

let next_pid        : int ref = ref 0
let next_monitor_id : int ref = ref 0

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
                     ai_resources = [] } in
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

  | PatCon (n, pats), VCon (tag, args) when n.txt = tag ->
    if List.length pats <> List.length args then None
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

let cmp_op op_i op_f op_s op_b name = VBuiltin (name, function
    | [VInt a;    VInt b]    -> VBool (op_i a b)
    | [VFloat a;  VFloat b]  -> VBool (op_f a b)
    | [VString a; VString b] -> VBool (op_s a b)
    | [VBool a;   VBool b]   -> VBool (op_b a b)
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
  | VBuiltin (n, _) -> "<builtin:" ^ n ^ ">"
  | VPid pid -> "Pid(" ^ string_of_int pid ^ ")"
  | VTask id -> Printf.sprintf "<task:%d>" id
  | VWorkPool -> "<work_pool>"
  | VCap (pid, epoch) -> Printf.sprintf "Cap(%d, epoch=%d)" pid epoch
  | VActorId pid -> Printf.sprintf "ActorId(%d)" pid

(** Pretty-print a value with indented multi-line layout when the flat
    representation exceeds [width] characters. *)
let value_to_string_pretty ?(width=80) v =
  let flat = value_to_string v in
  if String.length flat <= width then flat
  else
    let indent n = String.make n ' ' in
    let rec pp depth v =
      let flat_v = value_to_string v in
      if String.length flat_v <= width - depth * 2 then flat_v
      else match v with
      | VRecord fields ->
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        "{ " ^ String.concat ("\n" ^ pad ^ ", ")
          (List.map (fun (k, fv) -> k ^ " = " ^ pp (depth + 1) fv) fields)
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
        "[ " ^ String.concat ("\n" ^ pad ^ ", ") (List.map (pp (depth + 1)) elems)
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

(** Spawn a fresh child actor instance (for supervisor restarts).
    Returns the new pid. *)
let spawn_child_actor (child_actor_name : string) (supervisor_pid : int) : int =
  match Hashtbl.find_opt actor_defs_tbl child_actor_name with
  | None -> eval_error "restart: unknown child actor '%s'" child_actor_name
  | Some (child_def, child_env_ref) ->
    let child_init_state = !eval_expr_hook !child_env_ref child_def.actor_init in
    let child_pid = !next_pid in
    next_pid := child_pid + 1;
    let child_inst = {
      ai_name = child_actor_name; ai_def = child_def;
      ai_env_ref = child_env_ref;
      ai_state = child_init_state; ai_alive = true;
      ai_monitors = []; ai_links = []; ai_mailbox = Queue.create ();
      ai_supervisor = Some supervisor_pid;
      ai_restart_count = []; ai_epoch = 0;
      ai_resources = [] } in
    Hashtbl.add actor_registry child_pid child_inst;
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
                 (* Spawn a new child *)
                 let new_pid = spawn_child_actor child_actor_name sup_pid in
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
         (* Respawn all children in order *)
         let new_state = match sup_inst.ai_state with
           | VRecord fields ->
             let new_fields = List.map (fun (fname, _) ->
               match List.find_opt (fun sf -> sf.sf_name.txt = fname) sup_cfg.sc_fields with
               | None -> (fname, VInt 0)
               | Some sf ->
                 let child_actor_name = match sf.sf_ty with
                   | TyCon (n, []) -> n.txt | _ -> "" in
                 if child_actor_name = "" then (fname, VInt 0)
                 else (fname, VInt (spawn_child_actor child_actor_name sup_pid))
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
           (* Respawn crashed child + rest in order *)
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
                     let new_pid = spawn_child_actor child_actor_name sup_pid in
                     List.map (fun (k, v) ->
                       if k = fname then (k, VInt new_pid) else (k, v)) acc
               ) fields to_respawn in
               VRecord updated
             | other -> other
           in
           sup_inst.ai_state <- new_state
         end
       end)

(** Notify a supervisor that a child has crashed, triggering the appropriate
    restart strategy. *)
and notify_supervisor (sup_pid : int) (crashed_pid : int) : unit =
  match Hashtbl.find_opt actor_registry sup_pid with
  | None -> ()
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
        | [v] -> print_string (value_display v); VUnit
        | vs  -> List.iter (fun v -> print_string (value_display v)) vs; VUnit))
  ; ("println", VBuiltin ("println", function
        | [v] -> print_endline (value_display v); VUnit
        | vs  -> List.iter (fun v -> print_string (value_display v)) vs;
                 print_newline (); VUnit))
  ; ("print_int", VBuiltin ("print_int", function
        | [VInt n] -> print_int n; VUnit
        | _ -> eval_error "print_int: expected int"))
  ; ("print_float", VBuiltin ("print_float", function
        | [VFloat f] -> print_float f; VUnit
        | _ -> eval_error "print_float: expected float"))
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
  ; ("to_string", VBuiltin ("to_string", function
        | [v] -> VString (value_display v)
        | _ -> eval_error "to_string: expected one argument"))

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
          if n >= 0 && n <= 127 then VCon ("Some", [VString (String.make 1 (Char.chr n))])
          else VCon ("None", [])
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
    let fn_val = eval_expr env f in
    let arg_vals = List.map (eval_expr env) args in
    apply fn_val arg_vals

  | ECon (name, args, _) ->
    let arg_vals = List.map (eval_expr env) args in
    VCon (name.txt, arg_vals)

  | ELam (params, body, _) ->
    let param_names = List.map (fun p -> p.param_name.txt) params in
    VClosure (env, param_names, body)

  | EBlock (es, _) -> eval_block env es

  | ELet (b, _) ->
    (* Standalone let (outside a block) — evaluate and ignore bindings.
       This shouldn't appear after desugaring except inside EBlock. *)
    eval_expr env b.bind_expr

  | EMatch (scrut, branches, _) ->
    check_reductions ();
    let v = eval_expr env scrut in
    eval_match env v branches

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
     | _ -> eval_error "field access on non-record value")

  | EIf (cond, then_, else_, _) ->
    (match eval_expr env cond with
     | VBool true  -> eval_expr env then_
     | VBool false -> eval_expr env else_
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
                 ai_resources = [] } in
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
                    ai_epoch = 0; ai_resources = [] } in
       Hashtbl.add actor_registry pid inst;
       VPid pid)

  | ESend (cap_expr, msg_expr, _) ->
    check_reductions ();
    let pid_val = eval_expr env cap_expr in
    let msg_val = eval_expr env msg_expr in
    (match pid_val with
     | VPid pid ->
       (match Hashtbl.find_opt actor_registry pid with
        | None -> VUnit  (* dead/unknown actor: fire-and-forget, silently drop *)
        | Some inst when not inst.ai_alive -> VUnit  (* actor was killed: drop *)
        | Some inst ->
          (* Phase 4: async — push message to mailbox, do not dispatch inline.
             Only constructor values (VCon/VAtom) are valid messages. *)
          (match msg_val with
           | VCon _ | VAtom _ ->
             Queue.push msg_val inst.ai_mailbox;
             VUnit
           | _ ->
             eval_error "send: message must be a constructor value, got %s"
               (value_to_string msg_val)))
     | _ ->
       eval_error "send: first argument must be a Pid, got %s"
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

(** Evaluate a match expression: try each branch until one matches. *)
and eval_match (env : env) (v : value) (branches : branch list) : value =
  match branches with
  | [] ->
    raise (Match_failure
             (Printf.sprintf "non-exhaustive match on value: %s"
                (value_to_string v)))
  | br :: rest ->
    (match match_pattern v br.branch_pat with
     | None -> eval_match env v rest
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
       if guard_ok
       then eval_expr env' br.branch_body
       else eval_match env v rest)

(** Tracing wrapper around [eval_expr_inner].
    When debug mode is active, records a [trace_frame] for every evaluation step.
    When [!debug_ctx] is None, this is a single pointer deref — zero overhead. *)
and eval_expr (env : env) (e : expr) : value =
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
  next_pid := 0;
  next_monitor_id := 0;
  current_pid := None;
  reduction_ctx := None;
  last_reduction_count := 0

(* NOTE: debug_ctx actor event logging is intentionally not reproduced here.
   The old ESend recorded ame_state_before/ame_state_after. When actor debug
   tracing is needed, add the same pattern inside the handler dispatch block below. *)

(** Drain all actor mailboxes cooperatively.
    Each pass iterates over all live actors; for each with a non-empty mailbox
    it pops one message, finds the matching [on Msg] handler, and runs it.
    Repeats until a full pass produces no work (all mailboxes empty). *)
let run_scheduler () =
  let changed = ref true in
  while !changed do
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
    (* Check if there's a stub already installed for this name *)
    (match List.assoc_opt def.fn_name.txt env with
     | Some (VClosure _) ->
       (* Patch the environment entry; since assoc lists are immutable we
          replace it.  For recursive stubs we rely on the stub mechanism. *)
       let closure = VClosure (env, params, clause.fc_body) in
       let env' = (def.fn_name.txt, closure)
                  :: List.remove_assoc def.fn_name.txt env in
       env'
     | _ ->
       let closure = VClosure (env, params, clause.fc_body) in
       (def.fn_name.txt, closure) :: env)

  | DLet (b, _) ->
    let v = eval_expr env b.bind_expr in
    (match match_pattern v b.bind_pat with
     | Some bs -> bs @ env
     | None    -> eval_error "top-level let binding pattern failed")

  | DType _ -> env   (* No runtime effect *)

  | DActor (name, def, _) ->
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
      | DLet (b, _) :: rest ->
        let rec pat_names a = function
          | PatVar n -> n.txt :: a
          | PatTuple (ps, _) -> List.fold_left pat_names a ps
          | PatCon (_, ps) -> List.fold_left pat_names a ps
          | _ -> a
        in
        declared_names (pat_names acc b.bind_pat) rest
      | DMod (n, _, _, _) :: rest -> declared_names (n.txt :: acc) rest
      | _ :: rest -> declared_names acc rest
    in
    let own_names = declared_names [] decls in
    let prefixed = List.filter_map (fun (k, v) ->
        if List.mem k own_names
        then Some (name.txt ^ "." ^ k, v)
        else None
      ) mod_env in
    prefixed @ env

  | DProtocol _ | DSig _ | DInterface _ | DImpl _ | DExtern _ | DUse _ | DNeeds _ -> env

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

    | DLet (b, _) :: rest ->
      let v = eval_expr env b.bind_expr in
      let env' = match match_pattern v b.bind_pat with
        | Some bs -> bs @ env
        | None    -> eval_error "top-level let pattern failed"
      in
      env_ref := env';
      make_recursive_env rest env'

    | DActor (name, def, _) :: rest ->
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

    | _ :: rest -> make_recursive_env rest env
  in

  let final_env = make_recursive_env m.mod_decls !env_ref in
  env_ref := final_env;
  final_env

(** Run the module: evaluate it, then call [main()] if it exists.
    After [main()] returns, drain all actor mailboxes via the scheduler loop.
    [main()] sets up actors and queues initial messages; the scheduler
    processes them all before the program exits. *)
let run_module (m : module_) : unit =
  let env = eval_module_env m in
  match List.assoc_opt "main" env with
  | None   -> ()
  | Some v ->
    let _ = apply v [] in
    run_scheduler ()
