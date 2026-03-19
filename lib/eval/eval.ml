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

(** Association-list environment mapping names to values. *)
and env = (string * value) list

(* ------------------------------------------------------------------ *)
(* Actor runtime                                                       *)
(* ------------------------------------------------------------------ *)

type actor_inst = {
  ai_name    : string;           (** Actor type name, e.g. "Counter" *)
  ai_def     : actor_def;
  ai_env_ref : env ref;         (** Module environment at spawn time *)
  mutable ai_state : value;
  mutable ai_alive : bool;
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

let next_pid : int ref = ref 0

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
        let inst = { ai_name    = s.ais_name;
                     ai_def     = def;
                     ai_env_ref = env_r;
                     ai_state   = s.ais_state;
                     ai_alive   = s.ais_alive } in
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

let list_actors () =
  Hashtbl.fold (fun pid (inst : actor_inst) acc ->
    { ai_pid       = pid;
      ai_name      = inst.ai_name;
      ai_alive     = inst.ai_alive;
      ai_state_str = value_to_string inst.ai_state }
    :: acc
  ) actor_registry []
  |> List.sort (fun a b -> compare a.ai_pid b.ai_pid)

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
        | [VPid pid] ->
          (match Hashtbl.find_opt actor_registry pid with
           | Some inst -> inst.ai_alive <- false; VUnit
           | None      -> VUnit)
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
       let init_state = eval_expr !env_ref def.actor_init in
       let pid = !next_pid in
       next_pid := pid + 1;
       let inst = { ai_name = actor_name; ai_def = def; ai_env_ref = env_ref;
                    ai_state = init_state; ai_alive = true } in
       Hashtbl.add actor_registry pid inst;
       VPid pid)

  | ESend (cap_expr, msg_expr, _) ->
    check_reductions ();
    let pid_val = eval_expr env cap_expr in
    let msg_val = eval_expr env msg_expr in
    (match pid_val with
     | VPid pid ->
       (match Hashtbl.find_opt actor_registry pid with
        | None -> VCon ("None", [])
        | Some inst when not inst.ai_alive -> VCon ("None", [])
        | Some inst ->
          let (msg_tag, msg_args) = match msg_val with
            | VCon  (tag, args) -> (tag, args)
            | VAtom tag         -> (tag, [])
            | _ -> eval_error "send: message must be a constructor value, got %s"
                     (value_to_string msg_val)
          in
          (match List.find_opt (fun h -> h.ah_msg.txt = msg_tag)
                   inst.ai_def.actor_handlers with
           | None ->
             eval_error "send: actor has no handler for '%s'" msg_tag
           | Some handler ->
             if List.length handler.ah_params <> List.length msg_args then
               eval_error "send: handler '%s' expects %d args, got %d"
                 msg_tag (List.length handler.ah_params) (List.length msg_args);
             let param_bindings =
               List.map2 (fun p v -> (p.param_name.txt, v))
                 handler.ah_params msg_args
             in
             let handler_env =
               [("state", inst.ai_state)] @ param_bindings @ !(inst.ai_env_ref)
             in
             let state_before = inst.ai_state in
             let frame_idx = match !debug_ctx with
               | Some ctx -> ctx.dc_trace.rb_size - 1
               | None -> -1
             in
             let new_state =
               (try let s = eval_expr handler_env handler.ah_body in
                    (match !debug_ctx with
                     | Some ctx when ctx.dc_enabled ->
                       let evt = { ame_pid          = pid;
                                   ame_actor_name   = inst.ai_name;
                                   ame_msg          = msg_val;
                                   ame_state_before = state_before;
                                   ame_state_after  = Some s;
                                   ame_frame_idx    = frame_idx } in
                       ctx.dc_actor_log <- ctx.dc_actor_log @ [evt]
                     | _ -> ());
                    s
                with exn ->
                  (match !debug_ctx with
                   | Some ctx when ctx.dc_enabled ->
                     let evt = { ame_pid          = pid;
                                 ame_actor_name   = inst.ai_name;
                                 ame_msg          = msg_val;
                                 ame_state_before = state_before;
                                 ame_state_after  = None;
                                 ame_frame_idx    = frame_idx } in
                     ctx.dc_actor_log <- ctx.dc_actor_log @ [evt]
                   | _ -> ());
                  raise exn)
             in
             inst.ai_state <- new_state;
             VCon ("Some", [VUnit])))
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
  reduction_ctx := None;
  last_reduction_count := 0

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
        let result = apply thunk [] in
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
      let result = apply thunk [] in
      let entry = { te_id = tid; te_result = Some result; te_thunk = thunk } in
      Hashtbl.add task_registry tid entry;
      VTask tid
    | [_; _] ->
      eval_error "task_spawn_steal: first argument must be a Cap(WorkPool)"
    | _ -> eval_error "task_spawn_steal: expected 2 arguments (pool, function)"))

  ; ("task_reductions", VBuiltin ("task_reductions", function
    | [] -> VInt !last_reduction_count
    | _ -> eval_error "task_reductions: expected 0 arguments"))
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
    let mod_env = eval_decls env decls in
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

(** Run the module: evaluate it, then call [main()] if it exists. *)
let run_module (m : module_) : unit =
  let env = eval_module_env m in
  match List.assoc_opt "main" env with
  | None   -> ()  (* Library module; no main to run *)
  | Some v ->
    let _ = apply v [] in
    ()
