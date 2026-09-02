(** [base_env] — the delta-rule builtin table (core-march.md §4.4).

    Extracted verbatim from eval.ml — no behavior change.  This module is a
    LEAF with respect to the evaluator: it calls no evaluator function
    directly.  Where a builtin must re-enter evaluation it goes through the
    [Eval_prim] hook refs ([eval_expr_hook], [apply_hook], [run_scheduler_hook],
    [iface_dispatch_hook]) that eval.ml installs at startup — the same
    indirection that existed before this extraction.

    Shared runtime state (actor registry, type tables, vault, logging) lives in
    [Eval_runtime]; this module and [Eval] both depend on it. *)

open March_ast.Ast
open Eval_types
open Eval_prim
open Eval_runtime
open Eval_simd
open Eval_session
open Eval_net

let base_env : env =
  (* δ-rules — core-march.md §4.4. These bindings ARE the primitive operators;
     surface `a + b` etc. is ordinary application (EApp) of the VBuiltin bound
     here, dispatched via E-App-Prim (§4.2) — there is no separate arithmetic
     evaluation path. *)
  [ (* Integer arithmetic *)
    ("+",  arith_num ( + ) ( +. ) "+")   (* δ-Add-I / δ-Add-F — §4.4 *)
  ; ("-",  arith_num ( - ) ( -. ) "-")   (* δ-Sub-I / δ-Sub-F — §4.4 *)
  ; ("*",  arith_num ( * ) ( *. ) "*")   (* δ-Mul-I / δ-Mul-F — §4.4 *)
  ; ("/",  VBuiltin ("/", function       (* δ-Div-I / δ-Div-F / δ-Div-0 / δ-Div-0F — §4.4 *)
        | [VInt a;   VInt b]   when b <> 0   -> VInt (a / b)
        | [VFloat a; VFloat b] when b <> 0.0 -> VFloat (a /. b)
        | [VInt _;   VInt 0]                 -> eval_error "division by zero"
        (* Float division by zero: unlike integer sdiv, OCaml/IEEE 754 silently
           returns infinity rather than raising an exception, so we must catch it
           explicitly.  Same guard applies to the /. operator below. *)
        | [VFloat _; VFloat 0.0]             -> eval_error "division by zero"
        | _ -> eval_error "builtin /: expected two numbers"))
  ; ("%",  VBuiltin ("%", function       (* δ-Mod-I / δ-Mod-0 — §4.4 *)
        | [VInt a; VInt b] when b <> 0 -> VInt (a mod b)
        | [VInt _; VInt 0]             -> eval_error "modulo by zero"
        | _ -> eval_error "builtin %%: expected two integers"))
    (* Float arithmetic *)
  ; ("+.", VBuiltin ("+.", fun args -> match args with
        | [VFloat a; VFloat b] -> VFloat (a +. b)
        | [VInt _; _] | [_; VInt _] ->
          eval_error "+.: arguments must be Float, not Int — use `+` for Int or `int_to_float` to convert"
        | _ -> eval_error "+.: expected two Floats, got %s"
            (String.concat " and " (List.map value_to_string args))))
  ; ("-.", VBuiltin ("-.", fun args -> match args with
        | [VFloat a; VFloat b] -> VFloat (a -. b)
        | [VInt _; _] | [_; VInt _] ->
          eval_error "-.: arguments must be Float, not Int — use `-` for Int or `int_to_float` to convert"
        | _ -> eval_error "-.: expected two Floats, got %s"
            (String.concat " and " (List.map value_to_string args))))
  ; ("*.", VBuiltin ("*.", fun args -> match args with
        | [VFloat a; VFloat b] -> VFloat (a *. b)
        | [VInt _; _] | [_; VInt _] ->
          eval_error "*.: arguments must be Float, not Int — use `*` for Int or `int_to_float` to convert"
        | _ -> eval_error "*.: expected two Floats, got %s"
            (String.concat " and " (List.map value_to_string args))))
  ; ("/.", VBuiltin ("/.", fun args -> match args with
        | [VFloat a; VFloat b] when b <> 0.0 -> VFloat (a /. b)
        | [VFloat _; VFloat 0.0]             -> eval_error "division by zero"
        | [VInt _; _] | [_; VInt _] ->
          eval_error "/.: arguments must be Float, not Int — use `/` for Int or `int_to_float` to convert"
        | _ -> eval_error "/.: expected two Floats, got %s"
            (String.concat " and " (List.map value_to_string args))))
    (* Comparisons — δ-Eq-* / δ-Neq-* / δ-Lt-* / δ-Le-* / δ-Gt-* / δ-Ge-* — §4.4 *)
  ; ("==", cmp_op ( = )  ( = )  ( = )  ( = )  "==")
  ; ("!=", cmp_op ( <> ) ( <> ) ( <> ) ( <> ) "!=")
  ; ("<",  cmp_op ( < )  ( < )  ( < )  ( < )  "<")
  ; ("<=", cmp_op ( <= ) ( <= ) ( <= ) ( <= ) "<=")
  ; (">",  cmp_op ( > )  ( > )  ( > )  ( > )  ">")
  ; (">=", cmp_op ( >= ) ( >= ) ( >= ) ( >= ) ">=")
    (* Boolean — δ-rules — §4.4 *)
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
        | [v] -> capture_writeln (show_dispatch v); VUnit
        | vs  -> List.iter (fun v -> capture_write (show_dispatch v)) vs;
                 capture_write "\n"; VUnit))
    (* print_line: see typecheck.ml.  Interpreted output is one OCaml channel
       with no vectored-write split, so this is just `print` plus a newline —
       what matters is that the NAME exists on both backends. *)
  ; ("print_line", VBuiltin ("print_line", function
        | [v] -> capture_writeln (value_display v); VUnit
        | _ -> eval_error "print_line: expected one string"))
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
    (* Property-testing primitive: run a zero-arg thunk, catch any runtime
       failure (assert, panic, match failure, division by zero, out-of-bounds,
       etc.) and reflect it as Result(a, String).  Used by stdlib/check.march
       to drive property tests without needing user-level try/catch. *)
  ; ("__try_call", VBuiltin ("__try_call", function
        | [thunk] ->
          (* The thunk is a 1-arg lambda whose argument is ignored — this
             is a workaround for a typechecker issue with `() -> a` types
             in argument position. We pass VBool true, which the March-side
             lambda `fn _ -> body` discards. *)
          (try VCon ("Ok", [!apply_hook thunk [VBool true]])
           with
           | BlockedOnReceive    -> raise BlockedOnReceive
           | Assert_failure msg -> VCon ("Err", [VString msg])
           | Match_failure msg  -> VCon ("Err", [VString ("match failure: " ^ msg)])
           | Eval_error msg     -> VCon ("Err", [VString msg])
           | Failure msg        -> VCon ("Err", [VString msg])
           | Division_by_zero   -> VCon ("Err", [VString "division by zero"])
           | Stack_overflow     -> VCon ("Err", [VString "stack overflow"])
           | Invalid_argument m -> VCon ("Err", [VString ("invalid argument: " ^ m)])
           | exn                -> VCon ("Err", [VString (Printexc.to_string exn)]))
        | _ -> eval_error "__try_call: expected one thunk argument"))
    (* Value-carrying try — same semantics as __try_call but the Ok payload is
       the thunk's actual (possibly heap) result rather than a Bool.  The
       interpreter already wraps an arbitrary value, so the body is identical;
       the two differ only in the native runtime + typechecker signature. *)
  ; ("__try_call_val", VBuiltin ("__try_call_val", function
        | [thunk] ->
          (try VCon ("Ok", [!apply_hook thunk [VBool true]])
           with
           | BlockedOnReceive    -> raise BlockedOnReceive
           | Assert_failure msg -> VCon ("Err", [VString msg])
           | Match_failure msg  -> VCon ("Err", [VString ("match failure: " ^ msg)])
           | Eval_error msg     -> VCon ("Err", [VString msg])
           | Failure msg        -> VCon ("Err", [VString msg])
           | Division_by_zero   -> VCon ("Err", [VString "division by zero"])
           | Stack_overflow     -> VCon ("Err", [VString "stack overflow"])
           | Invalid_argument m -> VCon ("Err", [VString ("invalid argument: " ^ m)])
           | exn                -> VCon ("Err", [VString (Printexc.to_string exn)]))
        | _ -> eval_error "__try_call_val: expected one thunk argument"))
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
    (* io_read_line: alias for read_line, avoids name conflict inside IO module *)
  ; ("io_read_line", VBuiltin ("io_read_line", function
        | [VUnit] | [] ->
          (try VString (input_line stdin)
           with End_of_file -> VString "")
        | _ -> eval_error "io_read_line: expected unit"))
  ; ("read_byte", VBuiltin ("read_byte", function
        | [VUnit] | [] ->
          (try VInt (Char.code (input_char stdin))
           with End_of_file -> VInt (-1))
        | _ -> eval_error "read_byte: expected unit"))
    (* io_read_byte: alias for read_byte, avoids name conflict inside IO module *)
  ; ("io_read_byte", VBuiltin ("io_read_byte", function
        | [VUnit] | [] ->
          (try VInt (Char.code (input_char stdin))
           with End_of_file -> VInt (-1))
        | _ -> eval_error "io_read_byte: expected unit"))
    (* print_stderr: write string to stderr without newline *)
  ; ("print_stderr", VBuiltin ("print_stderr", function
        | [VString s] -> Printf.eprintf "%s%!" s; VUnit
        | [v] -> Printf.eprintf "%s%!" (value_display v); VUnit
        | _ -> eval_error "print_stderr: expected String"))
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
        | [VPid pid] -> crash_actor_with_reason pid "killed" Killed; VUnit
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
    (* Named registry (Task 4) — interpreter parity with
       march_actor_register/unregister/whereis/registered. [named_registry]
       maps name -> pid, mirroring the runtime's forward Vault table. *)
  ; ("actor_register", VBuiltin ("actor_register", function
        | [VPid pid; VString name] ->
          let live pid' = match Hashtbl.find_opt actor_registry pid' with
            | Some inst -> inst.ai_alive
            | None      -> false
          in
          if not (live pid) then VBool false
          else
            (match Hashtbl.find_opt named_registry name with
             | Some existing when live existing -> VBool false  (* held by a live actor *)
             | _ -> Hashtbl.replace named_registry name pid; VBool true)
        | _ -> eval_error "actor_register: expected (Pid, String)"))
  ; ("actor_unregister", VBuiltin ("actor_unregister", function
        | [VString name] ->
          if Hashtbl.mem named_registry name then begin
            Hashtbl.remove named_registry name; VBool true
          end else VBool false
        | _ -> eval_error "actor_unregister: expected String"))
  ; ("actor_whereis", VBuiltin ("actor_whereis", function
        | [VString name] ->
          (match Hashtbl.find_opt named_registry name with
           | Some pid ->
             (match Hashtbl.find_opt actor_registry pid with
              | Some inst when inst.ai_alive -> VCon ("Some", [VPid pid])
              | _ -> VCon ("None", []))
           | None -> VCon ("None", []))
        | _ -> eval_error "actor_whereis: expected String"))
  ; ("actor_registered", VBuiltin ("actor_registered", function
        | [] ->
          Hashtbl.fold (fun name _pid acc -> VString name :: acc) named_registry []
          |> List.fold_left (fun acc v -> VCon ("Cons", [v; acc])) (VCon ("Nil", []))
        | _ -> eval_error "actor_registered: expected unit"))
  ; ("mailbox_size", VBuiltin ("mailbox_size", function
        | [VPid pid] ->
          (match Hashtbl.find_opt actor_registry pid with
           | Some inst -> VInt (Queue.length inst.ai_mailbox)
           | None      -> VInt 0)
        | _ -> eval_error "mailbox_size: expected pid"))
  ; ("sched_stat", VBuiltin ("sched_stat", function
        (* No C scheduler in the interpreter; report what's meaningful:
           0 = live actors, 1 = total actors ever spawned, 4 = messages
           dropped by bounded-mailbox overflow policies (Task 9). Everything
           else (runq depth, recycled stacks, timer heap) has no interpreted
           analogue, so it reads 0 like an unknown index. *)
        | [VInt 0] -> VInt (Hashtbl.length actor_registry)
        | [VInt 1] -> VInt !next_pid
        | [VInt 4] -> VInt !dropped_messages_count
        | [VInt _] -> VInt 0
        | _ -> eval_error "sched_stat: expected Int"))
  ; ("actor_set_mailbox_limit", VBuiltin ("actor_set_mailbox_limit", function
        (* Task 9: bind a mailbox capacity + overflow policy to an actor.
           policy: 0 unbounded, 1 drop_new, 2 drop_old, 3 block (treated as
           unbounded in the interpreter — see mailbox_enqueue above). *)
        | [VPid pid; VInt limit; VInt policy] ->
          (match Hashtbl.find_opt actor_registry pid with
           | Some inst ->
             inst.ai_mbox_limit <- limit;
             inst.ai_mbox_policy <- policy
           | None -> ());
          VUnit
        | _ -> eval_error "actor_set_mailbox_limit: expected (Pid, Int, Int)"))
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
        (* Cooperative blocking receive: pop the NEXT message from this actor's
           mailbox.  If the mailbox is empty, raise [BlockedOnReceive] so the
           scheduler can re-queue the triggering message and retry on the next
           pass once a sub-message has been delivered. *)
        | [] ->
          (match !current_pid with
           | Some pid ->
             (match Hashtbl.find_opt actor_registry pid with
              | Some inst when not (Queue.is_empty inst.ai_mailbox) ->
                Queue.pop inst.ai_mailbox
              | Some _ ->
                raise BlockedOnReceive
              | None -> eval_error "receive: actor %d not found" pid)
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
                mailbox_enqueue inst msg;
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
        | [v] -> VString (show_dispatch v)
        | _ -> eval_error "to_string: expected one argument"))

    (* ---- Record introspection builtins ---- *)

    (* record_keys: returns a list of field name strings from a record value.
       %{a: 1, b: 2} => ["a", "b"]  (sorted by field name — matches the
       native record layout, which stores fields sorted by name) *)
  ; ("record_keys", VBuiltin ("record_keys", function
        | [VRecord fields] ->
          let sorted = List.sort (fun (a, _) (b, _) -> compare a b) fields in
          List.fold_right (fun (k, _) acc ->
            VCon ("Cons", [VString k; acc])
          ) sorted (VCon ("Nil", []))
        | [_] -> eval_error "record_keys: expected a record"
        | _ -> eval_error "record_keys: expected one argument"))

    (* record_values: returns a list of values from a record.
       %{a: 1, b: 2} => [1, 2]  (sorted by field name — see record_keys) *)
  ; ("record_values", VBuiltin ("record_values", function
        | [VRecord fields] ->
          let sorted = List.sort (fun (a, _) (b, _) -> compare a b) fields in
          List.fold_right (fun (_, v) acc ->
            VCon ("Cons", [v; acc])
          ) sorted (VCon ("Nil", []))
        | [_] -> eval_error "record_values: expected a record"
        | _ -> eval_error "record_values: expected one argument"))

    (* record_entries: returns a list of (key, value) pairs from a record.
       %{a: 1, b: 2} => [("a", 1), ("b", 2)]  (sorted by field name — see
       record_keys) *)
  ; ("record_entries", VBuiltin ("record_entries", function
        | [VRecord fields] ->
          let sorted = List.sort (fun (a, _) (b, _) -> compare a b) fields in
          List.fold_right (fun (k, v) acc ->
            VCon ("Cons", [VTuple [VString k; v]; acc])
          ) sorted (VCon ("Nil", []))
        | [_] -> eval_error "record_entries: expected a record"
        | _ -> eval_error "record_entries: expected one argument"))

    (* record_get: returns Some(value) if field exists, None otherwise.
       record_get(%{a: 1, b: 2}, "a") => Some(1)
       record_get(%{a: 1}, "z") => None *)
  ; ("record_get", VBuiltin ("record_get", function
        | [VRecord fields; VString key] ->
          (match List.assoc_opt key fields with
           | Some v -> VCon ("Some", [v])
           | None   -> VCon ("None", []))
        | [_; _] -> eval_error "record_get: expected (record, string)"
        | _ -> eval_error "record_get: expected two arguments"))

    (* record_put: returns a new record with the field set (or added).
       record_put(%{a: 1}, "b", 2) => %{a: 1, b: 2}
       record_put(%{a: 1}, "a", 9) => %{a: 9} *)
  ; ("record_put", VBuiltin ("record_put", function
        | [VRecord fields; VString key; value] ->
          let rec update = function
            | [] -> [(key, value)]
            | (k, _) :: rest when k = key -> (key, value) :: rest
            | pair :: rest -> pair :: update rest
          in
          VRecord (update fields)
        | [_; _; _] -> eval_error "record_put: expected (record, string, value)"
        | _ -> eval_error "record_put: expected three arguments"))

    (* record_has_key: returns true if the record has the given field.
       record_has_key(%{a: 1}, "a") => true
       record_has_key(%{a: 1}, "z") => false *)
  ; ("record_has_key", VBuiltin ("record_has_key", function
        | [VRecord fields; VString key] ->
          VBool (List.exists (fun (k, _) -> k = key) fields)
        | [_; _] -> eval_error "record_has_key: expected (record, string)"
        | _ -> eval_error "record_has_key: expected two arguments"))

    (* record_from_list: builds a record from a list of (string, value) pairs.
       record_from_list([("a", 1), ("b", 2)]) => %{a: 1, b: 2} *)
  ; ("record_from_list", VBuiltin ("record_from_list", function
        | [lst] ->
          let rec to_pairs = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VTuple [VString k; v]; rest]) ->
              (k, v) :: to_pairs rest
            | _ -> eval_error "record_from_list: expected list of (string, value) pairs"
          in
          VRecord (to_pairs lst)
        | _ -> eval_error "record_from_list: expected one argument"))

    (* ---- HTML template builtins ---- *)

    (* html_escape_str: OCaml-level HTML entity escaping for the auto-escape builtin. *)
  (* Contextual escaper: the interpreter's half of html_escape_ctx. The
     escapers themselves live in March_ctxesc.Escape so the interpreter and the
     C runtime cannot drift apart -- an interpreter that escapes differently
     from compiled code is precisely how the ~H ADT misread stayed hidden (see
     specs/progress/2026-08-05-h-sigil-adt-misread.md). *)
  ; ("html_escape_ctx", VBuiltin ("html_escape_ctx",
      let rec iolist_flatten v =
        match v with
        | VCon ("Empty", []) -> ""
        | VCon ("Str", [VString s]) -> s
        | VCon ("Segments", [lst]) ->
          let rec concat_list l =
            match l with
            | VCon ("Nil", []) -> ""
            | VCon ("Cons", [h; t]) -> iolist_flatten h ^ concat_list t
            | _ -> ""
          in
          concat_list lst
        | _ -> ""
      in
      function
      | [VInt id; v] ->
        let is_html_ctx = id = 0 in
        (match v with
         (* Already-safe HTML, and the context is HTML: insert verbatim.
            Anywhere else it is a context mismatch, so it gets flattened and
            then escaped for wherever it actually landed. *)
         (* Context-indexed trust: each Trusted* type names the one context
            its string may be inserted into verbatim. `Safe` is the legacy
            context-free form, treated as HTML trust. Mirrors the table in
            lib/tir/llvm_emit.ml -- the compiled backend resolves this
            statically, the interpreter at runtime, and they must agree. *)
         | VCon (("Safe" | "TrustedHtml"), [VString s]) when id = 0 -> VString s
         | VCon ("TrustedAttr", [VString s]) when id = 1 -> VString s
         | VCon ("TrustedUrl", [VString s]) when id = 2 || id = 3 -> VString s
         | VCon ("TrustedCss", [VString s]) when id = 4 || id = 7 -> VString s
         (* Both JS escapers: 5 inside a string literal, 9 at an expression
            position. They differ in POSITION within one language, like the
            url and css pairs above, and expression position is the only place
            trusted JS is worth inserting at all. *)
         | VCon ("TrustedJs", [VString s]) when id = 5 || id = 9 -> VString s
         (* Trusted, but not for THIS context -- escape it like anything else. *)
         | VCon (("Safe" | "TrustedHtml" | "TrustedAttr" | "TrustedUrl"
                 | "TrustedCss" | "TrustedJs"), [VString s]) ->
           VString (March_ctxesc.Escape.apply_id id s)
         | (VCon ("Empty", []) | VCon ("Str", _) | VCon ("Segments", _))
           when is_html_ctx -> VString (iolist_flatten v)
         | VCon ("Empty", []) | VCon ("Str", _) | VCon ("Segments", _) ->
           VString (March_ctxesc.Escape.apply_id id (iolist_flatten v))
         | VString s -> VString (March_ctxesc.Escape.apply_id id s)
         | v -> VString (March_ctxesc.Escape.apply_id id (value_display v)))
      | _ -> eval_error "html_escape_ctx: expected (Int, value)"))
  ; ("html_auto_escape", VBuiltin ("html_auto_escape",
      let html_escape_str s =
        (* Replace & first to avoid double-escaping *)
        let replace_all ~sub ~by s =
          let buf = Buffer.create (String.length s) in
          let lsub = String.length sub in
          let ls = String.length s in
          let i = ref 0 in
          while !i <= ls - lsub do
            if String.sub s !i lsub = sub then begin
              Buffer.add_string buf by;
              i := !i + lsub
            end else begin
              Buffer.add_char buf s.[!i];
              i := !i + 1
            end
          done;
          while !i < ls do
            Buffer.add_char buf s.[!i];
            i := !i + 1
          done;
          Buffer.contents buf
        in
        let s = replace_all ~sub:"&" ~by:"&amp;" s in
        let s = replace_all ~sub:"<" ~by:"&lt;" s in
        let s = replace_all ~sub:">" ~by:"&gt;" s in
        let s = replace_all ~sub:"\"" ~by:"&quot;" s in
        let s = replace_all ~sub:"'" ~by:"&#39;" s in
        s
      in
      (* Flatten an IOList value to a string without HTML escaping.
         Used for IOList fragments that are already safe HTML. *)
      let rec iolist_flatten v =
        match v with
        | VCon ("Empty", []) -> ""
        | VCon ("Str", [VString s]) -> s
        | VCon ("Segments", [lst]) ->
          let rec concat_list l =
            match l with
            | VCon ("Nil", []) -> ""
            | VCon ("Cons", [h; t]) -> iolist_flatten h ^ concat_list t
            | _ -> ""
          in
          concat_list lst
        | _ -> ""
      in
      function
      (* Html.Safe(s) — already safe, return as-is *)
      | [VCon ("Safe", [VString s])] -> VString s
      (* IOList variants — already rendered HTML, flatten without escaping *)
      | [VCon ("Empty", []) as v] -> VString (iolist_flatten v)
      | [VCon ("Str", _) as v]    -> VString (iolist_flatten v)
      | [VCon ("Segments", _) as v] -> VString (iolist_flatten v)
      (* Plain string — escape HTML entities *)
      | [VString s] -> VString (html_escape_str s)
      (* Anything else — convert to string and escape *)
      | [v] -> VString (html_escape_str (value_display v))
      | _ -> eval_error "html_auto_escape: expected one argument"))

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
        | [v] -> VString (show_dispatch v)
        | _ -> eval_error "show: expected one argument"))
  ; ("hash", VBuiltin ("hash", function
        (* Cross-backend hash() equality: reimplement the compiled runtime's
           algorithms (march_hash_int/float/string, runtime/march_runtime.c)
           bit-for-bit in Int64, with the same 62-bit mask so the result is
           representable in the interpreter's 63-bit native-int Value. Was
           OCaml's Hashtbl.hash, which shared zero bits with the compiled
           hash by design. *)
        | [VInt n]    -> VInt (Int64.to_int (march_hash_int64 (Int64.of_int n)))
        | [VFloat f]  -> VInt (Int64.to_int (march_hash_int64 (Int64.bits_of_float f)))
        | [VString s] -> VInt (Int64.to_int (march_hash_string64 s))
        | [VBool b]   -> VInt (if b then 1 else 0)
        | [v] ->
          (match type_name_of_value v with
           | Some tname ->
             (match Hashtbl.find_opt impl_tbl ("Hash", tname) with
              | Some hash_fn -> !apply_hook hash_fn [v]
              | None         -> VInt (Hashtbl.hash v))
           | None -> VInt (Hashtbl.hash v))
        | _ -> eval_error "hash: expected one argument"))

    (* ---- Json derive dispatch builtins ---- *)
    (* These dispatch to_json/from_json through impl_tbl for user-defined
       variant types.  For record types, the DImpl eval binds to_json/from_json
       directly in the env, so the env-bound version is used as fallback. *)
  ; ("to_json", VBuiltin ("to_json", function
        | [v] ->
          (match type_name_of_value v with
           | Some tname ->
             (match Hashtbl.find_opt impl_tbl ("JsonTo", tname) with
              | Some to_fn -> !apply_hook to_fn [v]
              | None       -> eval_error "to_json: no Json derive for type %s" tname)
           | None -> eval_error "to_json: cannot determine type of value")
        | _ -> eval_error "to_json: expected one argument"))
  ; ("from_json", VBuiltin ("from_json", function
        | [v] ->
          (* Dispatch from_json by inspecting the JsonValue structure.
             For variant-encoded JSON: look at the "tag" field to find the
             constructor, then look up the type via ctor_type_tbl.
             For record-encoded JSON: look at the field names and match
             via record_type_tbl. *)
          let try_variant_dispatch () =
            (* JSON objects with a "tag" field: look up the tag string
               in ctor_type_tbl to find the type, then dispatch *)
            match v with
            | VCon ("Object", [pairs_list]) ->
              (* Walk the association list to find ("tag", Str(ctor_name)) *)
              let rec find_tag = function
                | VCon ("Nil", []) -> None
                | VCon ("Cons", [VTuple [VString "tag"; VCon ("Str", [VString tag])]; _rest]) ->
                  Some tag
                | VCon ("Cons", [_; rest_list]) -> find_tag rest_list
                | _ -> None
              in
              (match find_tag pairs_list with
               | Some tag ->
                 (match Hashtbl.find_opt ctor_type_tbl tag with
                  | Some tname ->
                    (match Hashtbl.find_opt impl_tbl ("JsonFrom", tname) with
                     | Some from_fn -> Some (!apply_hook from_fn [v])
                     | None -> None)
                  | None -> None)
               | None -> None)
            | _ -> None
          in
          let try_record_dispatch () =
            (* JSON objects without a "tag" but with known field set *)
            match v with
            | VCon ("Object", [pairs_list]) ->
              let rec collect_keys acc = function
                | VCon ("Nil", []) -> Some acc
                | VCon ("Cons", [VTuple [VString k; _]; rest]) ->
                  collect_keys (k :: acc) rest
                | _ -> None
              in
              (match collect_keys [] pairs_list with
               | Some keys ->
                 let sorted = List.sort String.compare keys in
                 let key = String.concat "," sorted in
                 (match Hashtbl.find_opt record_type_tbl key with
                  | Some tname ->
                    (match Hashtbl.find_opt impl_tbl ("JsonFrom", tname) with
                     | Some from_fn -> Some (!apply_hook from_fn [v])
                     | None -> None)
                  | None -> None)
               | None -> None)
            | _ -> None
          in
          (match try_variant_dispatch () with
           | Some result -> result
           | None ->
             (match try_record_dispatch () with
              | Some result -> result
              | None ->
                eval_error "from_json: cannot determine target type from JSON value"))
        | _ -> eval_error "from_json: expected one argument"))

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
  (* Offset-aware search.  Clamping must mirror march_string_index_of_from in
     runtime/march_runtime.c exactly — negative start to 0, start past the end
     to None, empty needle matching AT the clamped start — or interpreted and
     compiled runs disagree and the divergence surfaces far from here. *)
  ; ("string_index_of_from", VBuiltin ("string_index_of_from", function
        | [VString s; VString sub; VInt start] ->
          let ls = String.length s and lsub = String.length sub in
          let start = if start < 0 then 0 else start in
          if start > ls then VCon ("None", [])
          else if lsub = 0 then VCon ("Some", [VInt start])
          else if lsub > ls - start then VCon ("None", [])
          else begin
            let result = ref None in
            (try
               for i = start to ls - lsub do
                 if String.sub s i lsub = sub then
                   (result := Some i; raise Exit)
               done
             with Exit -> ());
            match !result with
            | Some i -> VCon ("Some", [VInt i])
            | None   -> VCon ("None", [])
          end
        | _ -> eval_error "string_index_of_from: expected (String, String, Int)"))
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
  ; ("string_concat3", VBuiltin ("string_concat3", function
        | [VString a; VString b; VString c] -> VString (a ^ b ^ c)
        | _ -> eval_error "string_concat3: expected three strings"))
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
  ; ("string_to_codepoints", VBuiltin ("string_to_codepoints", function
        | [VString s] ->
          let codepoints = ref [] in
          let len = String.length s in
          let i = ref 0 in
          while !i < len do
            let byte = Char.code s.[!i] in
            if byte < 0x80 then begin
              (* 1-byte: 0xxxxxxx *)
              codepoints := VInt byte :: !codepoints;
              incr i
            end else if byte < 0xE0 then begin
              (* 2-byte: 110xxxxx 10xxxxxx *)
              if !i + 1 < len then begin
                let byte2 = Char.code s.[!i + 1] in
                let cp = ((byte - 0xC0) lsl 6) lor (byte2 - 0x80) in
                codepoints := VInt cp :: !codepoints;
                i := !i + 2
              end else begin
                codepoints := VInt byte :: !codepoints;
                incr i
              end
            end else if byte < 0xF0 then begin
              (* 3-byte: 1110xxxx 10xxxxxx 10xxxxxx *)
              if !i + 2 < len then begin
                let byte2 = Char.code s.[!i + 1] in
                let byte3 = Char.code s.[!i + 2] in
                let cp = ((byte - 0xE0) lsl 12) lor ((byte2 - 0x80) lsl 6) lor (byte3 - 0x80) in
                codepoints := VInt cp :: !codepoints;
                i := !i + 3
              end else begin
                codepoints := VInt byte :: !codepoints;
                incr i
              end
            end else begin
              (* 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx *)
              if !i + 3 < len then begin
                let byte2 = Char.code s.[!i + 1] in
                let byte3 = Char.code s.[!i + 2] in
                let byte4 = Char.code s.[!i + 3] in
                let cp = ((byte - 0xF0) lsl 18) lor ((byte2 - 0x80) lsl 12) lor
                         ((byte3 - 0x80) lsl 6) lor (byte4 - 0x80) in
                codepoints := VInt cp :: !codepoints;
                i := !i + 4
              end else begin
                codepoints := VInt byte :: !codepoints;
                incr i
              end
            end
          done;
          (* Build list in order (reversed because we built with cons) *)
          List.fold_right (fun cp acc -> VCon ("Cons", [cp; acc])) (List.rev !codepoints) (VCon ("Nil", []))
        | _ -> eval_error "string_to_codepoints: expected string"))
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
  (* Byte-indexed random access.  Clamping must mirror march_string_byte_at in
     runtime/march_runtime.c exactly — out of range (negative or >= len) is -1,
     never a trap — or interpreted and compiled runs disagree. *)
  ; ("string_byte_at", VBuiltin ("string_byte_at", function
        | [VString s; VInt i] ->
          if i < 0 || i >= String.length s then VInt (-1)
          else VInt (Char.code s.[i])
        | _ -> eval_error "string_byte_at: expected (String, Int)"))
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

    (* ---- IOList.hash — FNV-1a hash for ETag generation ---- *)
    (* Walks the IOList tree hashing each Str segment's bytes without
       first flattening to a single string.  Returns a lowercase hex string.
       FNV-1a 64-bit: offset_basis = 14695981039346656037, prime = 1099511628211. *)
  ; ("iolist_hash_fnv1a", VBuiltin ("iolist_hash_fnv1a",
      let fnv_prime    = Int64.of_string "1099511628211" in
      let fnv_offset   = Int64.of_string "-3750763034362895579" (* 14695981039346656037 as int64 *) in
      let hash_bytes h s =
        let len = String.length s in
        let h = ref h in
        for i = 0 to len - 1 do
          let b = Int64.of_int (Char.code s.[i]) in
          h := Int64.mul (Int64.logxor !h b) fnv_prime
        done;
        !h
      in
      let rec hash_iolist h v =
        match v with
        | VCon ("Empty", [])         -> h
        | VCon ("Str", [VString s])  -> hash_bytes h s
        | VCon ("Segments", [lst])   ->
          let rec hash_list h l =
            match l with
            | VCon ("Nil", [])       -> h
            | VCon ("Cons", [hd; tl]) -> hash_list (hash_iolist h hd) tl
            | _                      -> h
          in
          hash_list h lst
        | _                          -> h
      in
      let to_hex h =
        (* 16 hex chars for 64-bit hash *)
        Printf.sprintf "%016Lx" h
      in
      function
      | [v] ->
        let h = hash_iolist fnv_offset v in
        VString (to_hex h)
      | _ -> eval_error "iolist_hash_fnv1a: expected one argument"))

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
  (* Byte constructor, NOT a code-point constructor: the result is the single
     byte [n land 0xFF], which is exactly what march_char_from_int does in the
     C runtime ((char)(n & 0xFF)).  This used to clamp to ASCII and return the
     EMPTY string above 127, so every caller handing it a real byte -- URI
     percent-decode, the msgpack byte walk, Http header decoding -- was correct
     compiled and silently corrupt interpreted, with no error to notice.  The
     masking (rather than a range check) is deliberate and load-bearing for
     parity: the runtime wraps, so 256 must yield byte 0 here too, not raise. *)
  ; ("char_from_int", VBuiltin ("char_from_int", function
        | [VInt n] -> VString (String.make 1 (Char.chr (n land 0xFF)))
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
  ; ("panic_", VBuiltin ("panic_", function
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
         | Unix.Unix_error (e, _, _) -> VCon ("Err", [file_error_of_unix path e])
         | Sys_error msg            -> VCon ("Err", [file_error_of_sys path msg]))
      | _ -> eval_error "file_read(path)"))

  ; ("file_write", VBuiltin ("file_write", function
      | [VString path; VString data] ->
        (try
           let oc = open_out path in
           Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
             output_string oc data;
             VCon ("Ok", [VAtom "ok"]))
         with
         | Unix.Unix_error (e, _, _) -> VCon ("Err", [file_error_of_unix path e])
         | Sys_error msg            -> VCon ("Err", [file_error_of_sys path msg]))
      | _ -> eval_error "file_write(path, data)"))

  ; ("file_append", VBuiltin ("file_append", function
      | [VString path; VString data] ->
        (try
           let oc = open_out_gen [Open_append; Open_creat] 0o644 path in
           Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
             output_string oc data;
             VCon ("Ok", [VAtom "ok"]))
         with
         | Unix.Unix_error (e, _, _) -> VCon ("Err", [file_error_of_unix path e])
         | Sys_error msg            -> VCon ("Err", [file_error_of_sys path msg]))
      | _ -> eval_error "file_append(path, data)"))

  ; ("file_delete", VBuiltin ("file_delete", function
      | [VString path] ->
        (try Sys.remove path; VCon ("Ok", [VAtom "ok"])
         with
         | Unix.Unix_error (e, _, _) -> VCon ("Err", [file_error_of_unix path e])
         | Sys_error msg            -> VCon ("Err", [file_error_of_sys path msg]))
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
             | _           -> VCon ("OtherKind", [])
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

    (* ── Structured cleanup ──────────────────────────────────────────
       try_finally(action, cleanup) runs action() and then cleanup(),
       re-raising any exception thrown by action *after* cleanup has
       run.  March code does not have its own try/finally construct,
       so this primitive is how stdlib wrappers (e.g., File.with_lines)
       guarantee resource release even when a callback panics. *)
  ; ("try_finally", VBuiltin ("try_finally", function
      | [action_fn; cleanup_fn] ->
        let run_cleanup () =
          try ignore (!apply_hook cleanup_fn [VUnit]) with _ -> ()
        in
        (match !apply_hook action_fn [VUnit] with
         | exception e -> run_cleanup (); raise e
         | result -> run_cleanup (); result)
      | _ -> eval_error "try_finally(action: (_) -> a, cleanup: (_) -> _): a"))

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

    (* ---- peak_rss_bytes(): process self-inspection ----
       OCaml has no getrusage binding, so the interpreter approximates with
       Gc.quick_stat()'s top_heap_words converted to bytes. This measures the
       OCaml *interpreter's* heap, not the compiled process's resident set —
       the two are not comparable in magnitude or units. Only ORDERING
       (a later call >= an earlier one, modulo GC compaction) is guaranteed
       to agree with the compiled `march_peak_rss_bytes` path; do not expect
       or assert equal raw numbers between interpreted and compiled runs. *)
  ; ("peak_rss_bytes", VBuiltin ("peak_rss_bytes", function
        | [] | [VUnit] ->
          let stat = Gc.quick_stat () in
          VInt (stat.Gc.top_heap_words * (Sys.word_size / 8))
        | _ -> eval_error "peak_rss_bytes: takes no arguments"))

    (* ---- live_allocs(): net count of live March heap objects ----
       In a COMPILED program this reads march_live_allocs() — the runtime's
       always-on alloc/free-on-rc-zero counter — and is exact.  The tree-walker
       has no such objects at all: interpreted values are OCaml values managed
       by the OCaml GC, and no march_alloc ever runs.  There is no meaningful
       approximation, so this returns a constant 0 rather than inventing a
       number that could be mistaken for a real measurement.
       CONSEQUENCE, and it is deliberate: a leak guard built on live_allocs is
       only falsifiable in the COMPILED path.  test/native's leak probes print
       it to STDERR and let the dune threshold rule read it from the compiled
       binary's captured stderr, keeping STDOUT (which IS diffed against an
       interpreter-produced .expected) free of it.  Do not assert on this
       value from an interpreted test. *)
  ; ("live_allocs", VBuiltin ("live_allocs", function
        | [] | [VUnit] -> VInt 0
        | _ -> eval_error "live_allocs: takes no arguments"))

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
        | [VInt fd; VInt max_bytes; VInt timeout_ms] ->
          let sock = (Obj.magic fd : Unix.file_descr) in
          let buf = Buffer.create 4096 in
          let chunk = Bytes.create 4096 in
          (* A TOTAL deadline for the whole read, matching march_tcp_recv_all:
             a peer dribbling one byte per interval must not be able to hold
             the caller forever by resetting a per-call timer. *)
          let deadline =
            if timeout_ms > 0 then Some (Unix.gettimeofday () +. float_of_int timeout_ms /. 1000.)
            else None
          in
          let rec loop total =
            if total >= max_bytes then
              VCon ("Ok", [VString (Buffer.contents buf)])
            else
              match tcp_wait_readable sock deadline with
              | `Timeout -> VCon ("Err", [VString recv_timeout_msg])
              | `Error e -> VCon ("Err", [VString e])
              | `Ready ->
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
  ; ("tcp_listen", VBuiltin ("tcp_listen", function
        | [VInt port] ->
          (try
             let open Unix in
             let sock = socket PF_INET SOCK_STREAM 0 in
             setsockopt sock SO_REUSEADDR true;
             bind sock (ADDR_INET (inet_addr_any, port));
             listen sock 1024;
             VCon ("Ok", [VInt (Obj.magic sock : int)])
           with Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "tcp_listen(port)"))
  ; ("tcp_accept", VBuiltin ("tcp_accept", function
        | [VInt listen_fd] ->
          (try
             let open Unix in
             let sock = (Obj.magic listen_fd : file_descr) in
             let (client_fd, _addr) = accept sock in
             VCon ("Ok", [VInt (Obj.magic client_fd : int)])
           with Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "tcp_accept(listen_fd)"))
  ; ("tcp_local_port", VBuiltin ("tcp_local_port", function
        | [VInt fd] ->
          (try
             let open Unix in
             let sock = (Obj.magic fd : file_descr) in
             (match getsockname sock with
              | ADDR_INET (_, port) -> VCon ("Ok", [VInt port])
              | ADDR_UNIX _ ->
                VCon ("Err", [VString "tcp_local_port: not an INET socket"]))
           with Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "tcp_local_port(fd)"))
  (* tcp_peer_addr(fd) → String: numeric IP of the connected peer.
     Returns "" when the fd is not a connected INET socket.  IPv4-mapped
     IPv6 addresses (::ffff:1.2.3.4) are normalized to plain IPv4. *)
  ; ("tcp_peer_addr", VBuiltin ("tcp_peer_addr", function
        | [VInt fd] ->
          (try
             match Unix.getpeername (Obj.magic fd : Unix.file_descr) with
             | Unix.ADDR_INET (addr, _) ->
               let ip = Unix.string_of_inet_addr addr in
               let mapped_prefix = "::ffff:" in
               let plen = String.length mapped_prefix in
               let ip =
                 if String.length ip > plen
                    && String.sub ip 0 plen = mapped_prefix
                    && String.contains ip '.'
                 then String.sub ip plen (String.length ip - plen)
                 else ip
               in
               VString ip
             | Unix.ADDR_UNIX _ -> VString ""
           with _ -> VString "")
        | _ -> eval_error "tcp_peer_addr(fd)"))
  ; ("dns_resolve", VBuiltin ("dns_resolve", function
        | [VString host] ->
          (try
             let open Unix in
             let addrs = getaddrinfo host "" [AI_FAMILY PF_INET] in
             let ip_strings = List.filter_map (fun ai ->
               match ai.ai_addr with
               | ADDR_INET (addr, _) -> Some (string_of_inet_addr addr)
               | _ -> None) addrs in
             if ip_strings = [] then
               VCon ("Err", [VString ("cannot resolve " ^ host)])
             else
               let ip_list = List.fold_right (fun s acc ->
                 VCon ("Cons", [VString s; acc])) ip_strings (VCon ("Nil", [])) in
               VCon ("Ok", [ip_list])
           with
           | Unix.Unix_error (err, _, _) ->
             VCon ("Err", [VString (Unix.error_message err)])
           | exn ->
             VCon ("Err", [VString (Printexc.to_string exn)]))
        | _ -> eval_error "dns_resolve(host: String): Result(List(String), String)"))
    (* ---- Low-level binary TCP receive ---- *)
  ; ("tcp_recv_exact", VBuiltin ("tcp_recv_exact", function
        | [VInt fd; VInt n] ->
          let sock = (Obj.magic fd : Unix.file_descr) in
          let buf = Bytes.create n in
          let rec loop off =
            if off >= n then
              (* Bytes is Bytes(String): the received buffer IS the payload. *)
              VCon ("Ok", [VCon ("Bytes", [VString (Bytes.to_string buf)])])
            else
              (try
                 let got = Unix.recv sock buf off (n - off) [] in
                 if got = 0 then VCon ("Err", [VString "connection closed"])
                 else loop (off + got)
               with Unix.Unix_error (err, _, _) ->
                 VCon ("Err", [VString (Unix.error_message err)]))
          in
          loop 0
        | _ -> eval_error "tcp_recv_exact(fd, n)"))
    (* ---- MD5 hash (hex string output) ---- *)
  ; ("md5", VBuiltin ("md5", function
        | [VString s] ->
          VString (Digestif.MD5.(to_hex (digest_string s)))
        | _ -> eval_error "md5(s: String): String"))
    (* ---- SHA-256 hash (hex string output) ---- *)
  ; ("sha256", VBuiltin ("sha256", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VString (Digestif.SHA256.(to_hex (digest_string s)))
           | Error e -> eval_error "sha256: %s" e)
        | _ -> eval_error "sha256(s: String | Bytes): String"))
    (* ---- SHA-512 hash (hex string output) ---- *)
  ; ("sha512", VBuiltin ("sha512", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VString (Digestif.SHA512.(to_hex (digest_string s)))
           | Error e -> eval_error "sha512: %s" e)
        | _ -> eval_error "sha512(s: String | Bytes): String"))
    (* ---- SHA-1 hash (hex string output, used for UUID v5) ---- *)
  ; ("sha1", VBuiltin ("sha1", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VString (Digestif.SHA1.(to_hex (digest_string s)))
           | Error e -> eval_error "sha1: %s" e)
        | _ -> eval_error "sha1(s: String | Bytes): String"))
    (* ---- SHA-1 raw bytes (used for UUID v5 byte manipulation) ---- *)
  ; ("sha1_bytes", VBuiltin ("sha1_bytes", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> march_bytes_of_string (Digestif.SHA1.(to_raw_string (digest_string s)))
           | Error e -> eval_error "sha1_bytes: %s" e)
        | _ -> eval_error "sha1_bytes(s: String | Bytes): Bytes"))
    (* ---- HMAC-SHA-256: returns Ok(Bytes) ---- *)
  ; ("hmac_sha256", VBuiltin ("hmac_sha256", function
        | [key_v; msg_v] ->
          (match march_val_to_raw key_v, march_val_to_raw msg_v with
           | Ok key, Ok msg ->
             let raw = Digestif.SHA256.(to_raw_string (hmac_string ~key msg)) in
             VCon ("Ok", [march_bytes_of_string raw])
           | Error e, _ | _, Error e -> eval_error "hmac_sha256: %s" e)
        | _ -> eval_error "hmac_sha256(key: String | Bytes, msg: String | Bytes): Ok(Bytes)"))
    (* ---- stdlib_hmac_sha256: alias for hmac_sha256, avoids name shadowing
       when a module defines its own fn hmac_sha256 wrapper ---- *)
  ; ("stdlib_hmac_sha256", VBuiltin ("stdlib_hmac_sha256", function
        | [key_v; msg_v] ->
          (match march_val_to_raw key_v, march_val_to_raw msg_v with
           | Ok key, Ok msg ->
             let raw = Digestif.SHA256.(to_raw_string (hmac_string ~key msg)) in
             VCon ("Ok", [march_bytes_of_string raw])
           | Error e, _ | _, Error e -> eval_error "stdlib_hmac_sha256: %s" e)
        | _ -> eval_error "stdlib_hmac_sha256(key: String | Bytes, msg: String | Bytes): Ok(Bytes)"))
    (* ---- HMAC-SHA-256 over Bytes: returns bare Bytes (no Result wrapper).
       Needed by HKDF-style constructions that chain MACs: the pseudorandom
       key must round-trip as raw bytes, never through a UTF-8 String. ---- *)
  ; ("hmac_sha256_bytes", VBuiltin ("hmac_sha256_bytes", function
        | [key_v; msg_v] ->
          (match march_val_to_raw key_v, march_val_to_raw msg_v with
           | Ok key, Ok msg ->
             march_bytes_of_string (Digestif.SHA256.(to_raw_string (hmac_string ~key msg)))
           | Error e, _ | _, Error e -> eval_error "hmac_sha256_bytes: %s" e)
        | _ -> eval_error "hmac_sha256_bytes(key: Bytes, msg: Bytes): Bytes"))
    (* ---- PBKDF2-HMAC-SHA256: returns Ok(Bytes) ---- *)
  ; ("pbkdf2_sha256", VBuiltin ("pbkdf2_sha256", function
        | [pwd_v; salt_v; VInt iters; VInt dklen] ->
          (match march_val_to_raw pwd_v, march_val_to_raw salt_v with
           | Ok password, Ok salt ->
             let raw = pbkdf2_hmac_sha256 ~password ~salt ~iterations:iters ~dklen in
             VCon ("Ok", [march_bytes_of_string raw])
           | Error e, _ | _, Error e -> eval_error "pbkdf2_sha256: %s" e)
        | _ -> eval_error "pbkdf2_sha256(password: String, salt: String | Bytes, iterations: Int, dklen: Int): Ok(Bytes)"))
    (* ---- Base64 encode: Bytes -> String ---- *)
  ; ("base64_encode", VBuiltin ("base64_encode", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VString (base64_encode s)
           | Error e -> eval_error "base64_encode: %s" e)
        | _ -> eval_error "base64_encode(s: Bytes): String"))
    (* ---- Base64 decode: String -> Ok(Bytes) | Err(String) ---- *)
  ; ("base64_decode", VBuiltin ("base64_decode", function
        | [VString s] ->
          (match base64_decode s with
           | Ok raw -> VCon ("Ok", [march_bytes_of_string raw])
           | Error e -> VCon ("Err", [VString e]))
        | _ -> eval_error "base64_decode(s: String): Ok(Bytes) | Err(String)"))
    (* ---- random_bytes(n): generate n cryptographically random bytes
       by reading from the OS CSPRNG (/dev/urandom on Unix).  This is
       the source the Crypto module documents as suitable for keys,
       nonces, salts, and tokens — it MUST NOT be the Random.int PRNG
       (which is fast but predictable). *)
  ; ("random_bytes", VBuiltin ("random_bytes", function
        | [VInt n] ->
          if n < 0 then eval_error "random_bytes: negative length %d" n
          else
            let buf = Bytes.create n in
            (if n > 0 then
              try
                let ic = open_in_bin "/dev/urandom" in
                Fun.protect ~finally:(fun () -> close_in_noerr ic)
                  (fun () -> really_input ic buf 0 n)
              with Sys_error msg ->
                eval_error "random_bytes: cannot read /dev/urandom: %s" msg);
            march_bytes_of_string (Bytes.to_string buf)
        | _ -> eval_error "random_bytes(n: Int): Bytes"))
    (* ---- Bytes <-> NativeU8Arr bridge: an O(n) copy each way (the two
       layouts cannot be aliased — see runtime/march_extras.c). High bytes
       (0x80-0xFF) must land as 128-255, i.e. zero-extended, never negative. *)
  ; ("bytes_to_u8_arr", VBuiltin ("bytes_to_u8_arr", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VNativeU8Arr (Array.init (String.length s)
                       (fun i -> Char.code s.[i]))
           | Error e -> eval_error "bytes_to_u8_arr: %s" e)
        | _ -> eval_error "bytes_to_u8_arr(b: Bytes): NativeU8Arr"))
  ; ("u8_arr_to_bytes", VBuiltin ("u8_arr_to_bytes", function
        | [VNativeU8Arr a] ->
          let buf = Bytes.create (Array.length a) in
          Array.iteri (fun i v -> Bytes.set buf i (Char.chr (v land 0xff))) a;
          march_bytes_of_string (Bytes.to_string buf)
        | _ -> eval_error "u8_arr_to_bytes(a: NativeU8Arr): Bytes"))
    (* ---- stdlib_* aliases: allow Crypto module to call builtins without shadowing ---- *)
  ; ("stdlib_sha256", VBuiltin ("stdlib_sha256", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VString (Digestif.SHA256.(to_hex (digest_string s)))
           | Error e -> eval_error "stdlib_sha256: %s" e)
        | _ -> eval_error "stdlib_sha256(s: String | Bytes): String"))
  ; ("stdlib_sha512", VBuiltin ("stdlib_sha512", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VString (Digestif.SHA512.(to_hex (digest_string s)))
           | Error e -> eval_error "stdlib_sha512: %s" e)
        | _ -> eval_error "stdlib_sha512(s: String | Bytes): String"))
  ; ("stdlib_random_bytes", VBuiltin ("stdlib_random_bytes", function
        | [VInt n] ->
          if n < 0 then eval_error "stdlib_random_bytes: negative length %d" n
          else
            let buf = Bytes.create n in
            (if n > 0 then
              try
                let ic = open_in_bin "/dev/urandom" in
                Fun.protect ~finally:(fun () -> close_in_noerr ic)
                  (fun () -> really_input ic buf 0 n)
              with Sys_error msg ->
                eval_error "stdlib_random_bytes: cannot read /dev/urandom: %s" msg);
            march_bytes_of_string (Bytes.to_string buf)
        | _ -> eval_error "stdlib_random_bytes(n: Int): Bytes"))
  ; ("stdlib_base64_encode", VBuiltin ("stdlib_base64_encode", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s -> VString (base64_encode s)
           | Error e -> eval_error "stdlib_base64_encode: %s" e)
        | _ -> eval_error "stdlib_base64_encode(s: Bytes): String"))
  ; ("stdlib_base64_decode", VBuiltin ("stdlib_base64_decode", function
        | [VString s] ->
          (match base64_decode s with
           | Ok raw -> VCon ("Ok", [march_bytes_of_string raw])
           | Error e -> VCon ("Err", [VString e]))
        | _ -> eval_error "stdlib_base64_decode(s: String): Ok(Bytes) | Err(String)"))
    (* ── Compression builtins ─────────────────────────────────────────────── *
     * Each C stub raises Failure(msg) on error, returns string on success.
     * We catch Failure and convert to Ok(Bytes) | Err(String) for March.
     * ──────────────────────────────────────────────────────────────────── *)
  ; ("stdlib_gzip_encode", VBuiltin ("stdlib_gzip_encode", function
        | [v; VInt lvl] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_gzip_encode s lvl)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_gzip_encode: %s" e)
        | _ -> eval_error "stdlib_gzip_encode(data: Bytes, level: Int): Ok(Bytes) | Err(String)"))
  ; ("stdlib_gzip_decode", VBuiltin ("stdlib_gzip_decode", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_gzip_decode s)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_gzip_decode: %s" e)
        | _ -> eval_error "stdlib_gzip_decode(data: Bytes): Ok(Bytes) | Err(String)"))
  ; ("stdlib_deflate_encode", VBuiltin ("stdlib_deflate_encode", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_deflate_encode s)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_deflate_encode: %s" e)
        | _ -> eval_error "stdlib_deflate_encode(data: Bytes): Ok(Bytes) | Err(String)"))
  ; ("stdlib_deflate_decode", VBuiltin ("stdlib_deflate_decode", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_deflate_decode s)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_deflate_decode: %s" e)
        | _ -> eval_error "stdlib_deflate_decode(data: Bytes): Ok(Bytes) | Err(String)"))
  ; ("stdlib_zstd_encode", VBuiltin ("stdlib_zstd_encode", function
        | [v; VInt lvl] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_zstd_encode s lvl)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_zstd_encode: %s" e)
        | _ -> eval_error "stdlib_zstd_encode(data: Bytes, level: Int): Ok(Bytes) | Err(String)"))
  ; ("stdlib_zstd_decode", VBuiltin ("stdlib_zstd_decode", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_zstd_decode s)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_zstd_decode: %s" e)
        | _ -> eval_error "stdlib_zstd_decode(data: Bytes): Ok(Bytes) | Err(String)"))
  ; ("stdlib_brotli_encode", VBuiltin ("stdlib_brotli_encode", function
        | [v; VInt mode; VInt quality] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_brotli_encode s mode quality)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_brotli_encode: %s" e)
        | _ -> eval_error "stdlib_brotli_encode(data: Bytes, mode: Int, quality: Int): Ok(Bytes) | Err(String)"))
  ; ("stdlib_brotli_decode", VBuiltin ("stdlib_brotli_decode", function
        | [v] ->
          (match march_val_to_raw v with
           | Ok s ->
             (try VCon ("Ok", [march_bytes_of_string (caml_march_brotli_decode s)])
              with Failure msg -> VCon ("Err", [VString msg]))
           | Error e -> eval_error "stdlib_brotli_decode: %s" e)
        | _ -> eval_error "stdlib_brotli_decode(data: Bytes): Ok(Bytes) | Err(String)"))
    (* ---- uuid_v4(): generate a random UUID v4 string ---- *)
  ; ("uuid_v4", VBuiltin ("uuid_v4", function
        | [] ->
          let buf = Bytes.create 16 in
          (try
            let ic = open_in_bin "/dev/urandom" in
            Fun.protect ~finally:(fun () -> close_in_noerr ic)
              (fun () -> really_input ic buf 0 16)
          with Sys_error msg ->
            eval_error "uuid_v4: cannot read /dev/urandom: %s" msg);
          (* Set version 4: high nibble of byte 6 = 0x4 *)
          Bytes.set buf 6 (Char.chr ((Char.code (Bytes.get buf 6) land 0x0f) lor 0x40));
          (* Set variant bits: top 2 bits of byte 8 = 0b10 *)
          Bytes.set buf 8 (Char.chr ((Char.code (Bytes.get buf 8) land 0x3f) lor 0x80));
          let hex b = Printf.sprintf "%02x" (Char.code b) in
          let s = String.concat "" (List.init 16 (fun i -> hex (Bytes.get buf i))) in
          (* xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx *)
          VString (String.sub s 0 8 ^ "-" ^ String.sub s 8 4 ^ "-"
                   ^ String.sub s 12 4 ^ "-" ^ String.sub s 16 4 ^ "-"
                   ^ String.sub s 20 12)
        | _ -> eval_error "uuid_v4: no arguments expected"))

    (* ---- uuid_v7(): generate a time-ordered UUID v7 string (RFC 9562) ----
       Layout (128 bits total):
         bits   0–47  : unix_ts_ms          (48 bits, big-endian)
         bits  48–51  : version = 0b0111     (4 bits)
         bits  52–63  : rand_a              (12 bits)
         bits  64–65  : variant = 0b10      (2 bits)
         bits  66–127 : rand_b              (62 bits)
       Random bytes come from /dev/urandom (matches random_bytes/v4 policy
       pending a future switch of uuid_v4 to CSPRNG).  Uses the current
       system time in milliseconds via Unix.gettimeofday (). *)
  ; ("uuid_v7", VBuiltin ("uuid_v7", function
        | args when args = [] || args = [VUnit] ->
          let ms =
            (* 48 bits is plenty: 2^48 ms ≈ 8925 years past epoch *)
            Int64.of_float (Unix.gettimeofday () *. 1000.0)
          in
          let ts_byte i =
            (* Big-endian: byte 0 is the most significant byte of ms *)
            let shift = (5 - i) * 8 in
            Int64.to_int
              (Int64.logand (Int64.shift_right_logical ms shift) 0xFFL)
          in
          let buf = Bytes.create 16 in
          (* Timestamp bytes 0..5 *)
          for i = 0 to 5 do Bytes.set buf i (Char.chr (ts_byte i)) done;
          (* Fill bytes 6..15 with CSPRNG *)
          (try
            let ic = open_in_bin "/dev/urandom" in
            Fun.protect ~finally:(fun () -> close_in_noerr ic)
              (fun () -> really_input ic buf 6 10)
          with Sys_error msg ->
            eval_error "uuid_v7: cannot read /dev/urandom: %s" msg);
          (* Set version 7: high nibble of byte 6 = 0x7 *)
          Bytes.set buf 6
            (Char.chr ((Char.code (Bytes.get buf 6) land 0x0f) lor 0x70));
          (* Set variant bits: top 2 bits of byte 8 = 0b10 *)
          Bytes.set buf 8
            (Char.chr ((Char.code (Bytes.get buf 8) land 0x3f) lor 0x80));
          let hex b = Printf.sprintf "%02x" (Char.code b) in
          let s = String.concat "" (List.init 16 (fun i -> hex (Bytes.get buf i))) in
          VString (String.sub s 0 8 ^ "-" ^ String.sub s 8 4 ^ "-"
                   ^ String.sub s 12 4 ^ "-" ^ String.sub s 16 4 ^ "-"
                   ^ String.sub s 20 12)
        | _ -> eval_error "uuid_v7: no arguments expected"))

    (* ---- uuid_v7_at(unix_ms: Int): UUID v7 at a specific timestamp ----
       Useful for backfilling old records with time-sorted UUIDs, and for
       deterministic tests that want to pin the timestamp portion. *)
  ; ("uuid_v7_at", VBuiltin ("uuid_v7_at", function
        | [VInt unix_ms] ->
          if unix_ms < 0 then
            eval_error "uuid_v7_at: negative timestamp %d" unix_ms
          else begin
            let ms = Int64.of_int unix_ms in
            let ts_byte i =
              let shift = (5 - i) * 8 in
              Int64.to_int
                (Int64.logand (Int64.shift_right_logical ms shift) 0xFFL)
            in
            let buf = Bytes.create 16 in
            for i = 0 to 5 do Bytes.set buf i (Char.chr (ts_byte i)) done;
            (try
              let ic = open_in_bin "/dev/urandom" in
              Fun.protect ~finally:(fun () -> close_in_noerr ic)
                (fun () -> really_input ic buf 6 10)
            with Sys_error msg ->
              eval_error "uuid_v7_at: cannot read /dev/urandom: %s" msg);
            Bytes.set buf 6
              (Char.chr ((Char.code (Bytes.get buf 6) land 0x0f) lor 0x70));
            Bytes.set buf 8
              (Char.chr ((Char.code (Bytes.get buf 8) land 0x3f) lor 0x80));
            let hex b = Printf.sprintf "%02x" (Char.code b) in
            let s = String.concat "" (List.init 16 (fun i -> hex (Bytes.get buf i))) in
            VString (String.sub s 0 8 ^ "-" ^ String.sub s 8 4 ^ "-"
                     ^ String.sub s 12 4 ^ "-" ^ String.sub s 16 4 ^ "-"
                     ^ String.sub s 20 12)
          end
        | _ -> eval_error "uuid_v7_at(unix_ms: Int): UUID v7 at a fixed ms timestamp"))

    (* ---- unix_time_ms(): Int milliseconds since Unix epoch ---- *)
  ; ("unix_time_ms", VBuiltin ("unix_time_ms", function
        | args when args = [] || args = [VUnit] ->
          VInt (int_of_float (Unix.gettimeofday () *. 1000.0))
        | _ -> eval_error "unix_time_ms: takes no arguments"))
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
          with
          | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
            (* An SO_RCVTIMEO deadline expired: the same fact
               tcp_recv_chunk_timeout reports, so it gets the same sentinel. *)
            VCon ("Err", [VString recv_timeout_msg])
          | Unix.Unix_error (err, _, _) ->
            VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "tcp_recv_chunk(fd, max_bytes)"))
  ; ("tcp_recv_chunk_timeout", VBuiltin ("tcp_recv_chunk_timeout", function
        | [VInt fd; VInt max_bytes; VInt timeout_ms] ->
          (* Read up to max_bytes, waiting at most timeout_ms for the peer to
             send anything.  Mirrors march_tcp_recv_chunk_timeout, INCLUDING the
             recv_timeout_msg spelling — stdlib/socket.march matches that string
             to build RecvTimeout, and it must mean the same thing compiled and
             interpreted. *)
          let sock = (Obj.magic fd : Unix.file_descr) in
          let deadline =
            if timeout_ms > 0 then Some (Unix.gettimeofday () +. float_of_int timeout_ms /. 1000.)
            else None
          in
          (match tcp_wait_readable sock deadline with
           | `Timeout -> VCon ("Err", [VString recv_timeout_msg])
           | `Error e -> VCon ("Err", [VString e])
           | `Ready ->
             let buf = Bytes.create (min max_bytes 8192) in
             (try
               let n = Unix.recv sock buf 0 (Bytes.length buf) [] in
               VCon ("Ok", [VString (Bytes.sub_string buf 0 n)])
             with Unix.Unix_error (err, _, _) ->
               VCon ("Err", [VString (Unix.error_message err)])))
        | _ -> eval_error "tcp_recv_chunk_timeout(fd, max_bytes, timeout_ms)"))
  ; ("tcp_set_recv_timeout", VBuiltin ("tcp_set_recv_timeout", function
        | [VInt fd; VInt timeout_ms] ->
          (* SO_RCVTIMEO: a persistent property of the fd, so later reads fail
             instead of hanging.  timeout_ms <= 0 clears it (POSIX: a zero
             timeval blocks forever). *)
          let sock = (Obj.magic fd : Unix.file_descr) in
          let secs = if timeout_ms > 0 then float_of_int timeout_ms /. 1000. else 0. in
          (try
            Unix.setsockopt_float sock Unix.SO_RCVTIMEO secs;
            VCon ("Ok", [VUnit])
          with Unix.Unix_error (err, _, _) ->
            VCon ("Err", [VString ("setsockopt(SO_RCVTIMEO): " ^ Unix.error_message err)]))
        | _ -> eval_error "tcp_set_recv_timeout(fd, timeout_ms)"))
  ; ("tcp_recv_timeout", VBuiltin ("tcp_recv_timeout", function
        | [VInt fd; VInt max_bytes; VInt timeout_ms] ->
          (* As tcp_recv_chunk_timeout, but an expired deadline is Ok(None)
             rather than an Err carrying a sentinel string.  Shares
             tcp_wait_readable so both spellings agree on what "expired" means,
             interpreted and compiled. *)
          let sock = (Obj.magic fd : Unix.file_descr) in
          let deadline =
            if timeout_ms > 0 then Some (Unix.gettimeofday () +. float_of_int timeout_ms /. 1000.)
            else None
          in
          (match tcp_wait_readable sock deadline with
           | `Timeout -> VCon ("Ok", [VCon ("None", [])])
           | `Error e -> VCon ("Err", [VString e])
           | `Ready ->
             let buf = Bytes.create (min max_bytes 8192) in
             (try
               let n = Unix.recv sock buf 0 (Bytes.length buf) [] in
               VCon ("Ok", [VCon ("Some", [VString (Bytes.sub_string buf 0 n)])])
             with Unix.Unix_error (err, _, _) ->
               VCon ("Err", [VString (Unix.error_message err)])))
        | _ -> eval_error "tcp_recv_timeout(fd, max_bytes, timeout_ms)"))
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

  ; ("http_fetch", VBuiltin ("http_fetch", function
        | [VString meth; VString url; VString header_block; VString body] ->
          (match !http_fetch_hook with
           | None ->
             eval_error "http_fetch unavailable: native builds use the socket transport"
           | Some f ->
             (match f meth url header_block body with
              | Ok raw    -> VCon ("Ok", [VString raw])
              | Error msg -> VCon ("Err", [VString msg])))
        | _ -> eval_error "http_fetch(method, url, header_block, body)"))
  ; ("http_fetch_available", VBuiltin ("http_fetch_available", function
        | [] | [VUnit] ->
          VBool (match !http_fetch_hook with Some _ -> true | None -> false)
        | _ -> eval_error "http_fetch_available()"))

  (* ── HTTP server (interpreter mode: pure-OCaml implementation) ──── *)
  (* Single-threaded, non-blocking, multiplexed event loop — see
     [run_http_event_loop] above.  select()s across the listen socket AND
     every open client connection each iteration (1s timeout so the loop
     can check [shutdown_requested] between iterations, letting Ctrl+C /
     SIGTERM exit cleanly).  No connection's recv/send can ever block
     progress on any other connection: a slow/idle client (e.g. a
     WebSocket client that connects but delays sending its upgrade
     request) simply sits in HCReadingRequest without being served, while
     every other connection continues to make progress.  Mirrors the C
     runtime's g_http_shutdown pattern for shutdown handling. *)
  ; ("http_server_listen", VBuiltin ("http_server_listen", function
      | [VInt port; VInt _max_conns; VInt _idle_timeout; pipeline_fn] ->
        let open Unix in
        let server_sock = socket PF_INET SOCK_STREAM 0 in
        setsockopt server_sock SO_REUSEADDR true;
        bind server_sock (ADDR_INET (inet_addr_any, port));
        listen server_sock 128;
        Printf.eprintf "march: HTTP server listening on port %d\n%!" port;
        (try run_http_event_loop server_sock pipeline_fn
         with
         (* EINTR from accept/select that slipped past inner handlers —
            treat as a clean shutdown rather than re-raising as a fatal error *)
         | Unix_error (EINTR, _, _) ->
           Printf.eprintf "march: Shutting down...\n%!";
           (try close server_sock with _ -> ());
           exit 0
         | exn ->
           (try close server_sock with _ -> ());
           raise exn);
        (try close server_sock with _ -> ());
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

  (* ---- TLS builtins ----
   *
   * In the interpreter these are stubs that return dummy handles so that
   * unit tests for the March Tls module can exercise the wrapping logic
   * without requiring an OpenSSL-linked OCaml runtime.
   * Real TLS runs via march_tls.c in the compiled native binary.
   *)

  (* tls_client_ctx(ca_file, alpn_list, min_ver, verify_peer) → Ok(Int)|Err(String) *)
  ; ("tls_client_ctx", VBuiltin ("tls_client_ctx", function
        | [_ca; _alpn; _ver; _vp] ->
          (* Return a stub handle of 1; tests verify wrapping, not real TLS *)
          VCon ("Ok", [VInt 1])
        | _ -> eval_error "tls_client_ctx(ca_file, alpn_list, min_ver, verify_peer)"))

  (* tls_server_ctx(cert, key, ca, alpn, min_ver) → Ok(Int)|Err(String) *)
  ; ("tls_server_ctx", VBuiltin ("tls_server_ctx", function
        | [VString cert; _key; _ca; _alpn; _ver] ->
          if cert = "" then
            VCon ("Err", [VString "server_ctx: cert_file is required"])
          else
            VCon ("Ok", [VInt 2])
        | _ -> eval_error "tls_server_ctx(cert, key, ca, alpn, min_ver)"))

  (* tls_connect(fd, ctx_handle, hostname) → Ok(Int)|Err(String) *)
  ; ("tls_connect", VBuiltin ("tls_connect", function
        | [VInt _fd; VInt _ctx; VString _host] ->
          VCon ("Ok", [VInt 3])
        | _ -> eval_error "tls_connect(fd, ctx_handle, hostname)"))

  (* tls_accept(fd, ctx_handle) → Ok(Int)|Err(String) *)
  ; ("tls_accept", VBuiltin ("tls_accept", function
        | [VInt _fd; VInt _ctx] ->
          VCon ("Ok", [VInt 4])
        | _ -> eval_error "tls_accept(fd, ctx_handle)"))

  (* tls_read(ssl_handle, max_bytes) → Ok(String)|Err(String) *)
  ; ("tls_read", VBuiltin ("tls_read", function
        | [VInt _ssl; VInt _max] ->
          VCon ("Ok", [VString ""])
        | _ -> eval_error "tls_read(ssl_handle, max_bytes)"))

  (* tls_read_timeout(ssl_handle, max_bytes, timeout_ms)
       → Ok(Option(String))|Err(String).  There is no real TLS in the
       interpreter, so this mirrors the tls_read stub above. *)
  ; ("tls_read_timeout", VBuiltin ("tls_read_timeout", function
        | [VInt _ssl; VInt _max; VInt _timeout] ->
          VCon ("Ok", [VCon ("Some", [VString ""])])
        | _ -> eval_error "tls_read_timeout(ssl_handle, max_bytes, timeout_ms)"))

  (* tls_write(ssl_handle, data) → Ok(Int)|Err(String) *)
  ; ("tls_write", VBuiltin ("tls_write", function
        | [VInt _ssl; VString data] ->
          VCon ("Ok", [VInt (String.length data)])
        | _ -> eval_error "tls_write(ssl_handle, data)"))

  (* tls_close(ssl_handle) → Unit *)
  ; ("tls_close", VBuiltin ("tls_close", function
        | [VInt _ssl] -> VUnit
        | _ -> eval_error "tls_close(ssl_handle)"))

  (* tls_ctx_free(ctx_handle) → Unit *)
  ; ("tls_ctx_free", VBuiltin ("tls_ctx_free", function
        | [VInt _ctx] -> VUnit
        | _ -> eval_error "tls_ctx_free(ctx_handle)"))

  (* tls_negotiated_alpn(ssl_handle) → Option(String) *)
  ; ("tls_negotiated_alpn", VBuiltin ("tls_negotiated_alpn", function
        | [VInt _ssl] -> VCon ("None", [])
        | _ -> eval_error "tls_negotiated_alpn(ssl_handle)"))

  (* tls_peer_cn(ssl_handle) → Option(String) *)
  ; ("tls_peer_cn", VBuiltin ("tls_peer_cn", function
        | [VInt _ssl] -> VCon ("None", [])
        | _ -> eval_error "tls_peer_cn(ssl_handle)"))

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
  ; ("string_from_codepoint", VBuiltin ("string_from_codepoint", function
        | [VInt cp] ->
          (* Validate codepoint: 0x0 to 0x10FFFF, reject surrogates (0xD800-0xDFFF) *)
          if cp < 0 || cp > 0x10FFFF then
            VCon ("None", [])
          else if cp >= 0xD800 && cp <= 0xDFFF then
            VCon ("None", [])  (* Reject surrogate pairs *)
          else
            (* Encode as UTF-8 *)
            let buf = Buffer.create 4 in
            if cp <= 0x7F then
              (* 1-byte: 0xxxxxxx *)
              Buffer.add_char buf (Char.chr cp)
            else if cp <= 0x7FF then begin
              (* 2-byte: 110xxxxx 10xxxxxx *)
              let b1 = 0xC0 lor (cp lsr 6) in
              let b2 = 0x80 lor (cp land 0x3F) in
              Buffer.add_char buf (Char.chr b1);
              Buffer.add_char buf (Char.chr b2)
            end else if cp <= 0xFFFF then begin
              (* 3-byte: 1110xxxx 10xxxxxx 10xxxxxx *)
              let b1 = 0xE0 lor (cp lsr 12) in
              let b2 = 0x80 lor ((cp lsr 6) land 0x3F) in
              let b3 = 0x80 lor (cp land 0x3F) in
              Buffer.add_char buf (Char.chr b1);
              Buffer.add_char buf (Char.chr b2);
              Buffer.add_char buf (Char.chr b3)
            end else begin
              (* 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx *)
              let b1 = 0xF0 lor (cp lsr 18) in
              let b2 = 0x80 lor ((cp lsr 12) land 0x3F) in
              let b3 = 0x80 lor ((cp lsr 6) land 0x3F) in
              let b4 = 0x80 lor (cp land 0x3F) in
              Buffer.add_char buf (Char.chr b1);
              Buffer.add_char buf (Char.chr b2);
              Buffer.add_char buf (Char.chr b3);
              Buffer.add_char buf (Char.chr b4)
            end;
            VCon ("Some", [VString (Buffer.contents buf)])
        | _ -> eval_error "string_from_codepoint: expected int"))

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
  (* Convert a raw byte value (0–255) to a single-byte String.  Same payload
     as char_from_int (they share march_char_from_int once compiled); the
     difference is the out-of-range contract, which is deliberate.  This one
     names a byte, so a value outside 0–255 is a caller bug and is reported;
     char_from_int wraps, because the C runtime wraps. *)
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
          let args = match !program_argv with
            | Some argv -> argv
            | None -> Array.to_list Sys.argv
          in
          List.fold_right (fun s acc -> VCon ("Cons", [VString s; acc]))
            args (VCon ("Nil", []))
        | _ -> eval_error "process_argv: no arguments expected"))
  ; ("process_pid", VBuiltin ("process_pid", function
        | [] -> VInt (Unix.getpid ())
        | _ -> eval_error "process_pid: no arguments expected"))
  (* ── System / runtime introspection builtins ────────────────────────── *)
  ; ("sys_uptime_ms", VBuiltin ("sys_uptime_ms", function
        | [] | [VUnit] ->
          let ms = int_of_float ((Unix.gettimeofday () -. process_start_time) *. 1000.0) in
          VInt ms
        | _ -> eval_error "sys_uptime_ms: no arguments expected"))
  ; ("sys_heap_bytes", VBuiltin ("sys_heap_bytes", function
        | [] | [VUnit] ->
          let s = Gc.stat () in
          VInt (s.Gc.live_words * (Sys.word_size / 8))
        | _ -> eval_error "sys_heap_bytes: no arguments expected"))
  ; ("sys_word_size", VBuiltin ("sys_word_size", function
        | [] | [VUnit] -> VInt Sys.word_size
        | _ -> eval_error "sys_word_size: no arguments expected"))
  ; ("sys_minor_gcs", VBuiltin ("sys_minor_gcs", function
        | [] | [VUnit] ->
          let s = Gc.stat () in VInt s.Gc.minor_collections
        | _ -> eval_error "sys_minor_gcs: no arguments expected"))
  ; ("sys_major_gcs", VBuiltin ("sys_major_gcs", function
        | [] | [VUnit] ->
          let s = Gc.stat () in VInt s.Gc.major_collections
        | _ -> eval_error "sys_major_gcs: no arguments expected"))
  ; ("sys_actor_count", VBuiltin ("sys_actor_count", function
        | [] | [VUnit] -> VInt (Hashtbl.length actor_registry)
        | _ -> eval_error "sys_actor_count: no arguments expected"))
  ; ("sys_cpu_count", VBuiltin ("sys_cpu_count", function
        | [] | [VUnit] -> VInt (Domain.recommended_domain_count ())
        | _ -> eval_error "sys_cpu_count: no arguments expected"))
    (* Interpreter best-effort: read /proc on Linux, 0 elsewhere (native
       compiled mode uses the real cross-platform C in march_extras.c). *)
  ; ("sys_cpu_load_milli", VBuiltin ("sys_cpu_load_milli", function
        | [] | [VUnit] ->
          let v = try
            let ic = open_in "/proc/loadavg" in
            let line = input_line ic in close_in ic;
            (match String.split_on_char ' ' line with
             | first :: _ -> int_of_float (float_of_string first *. 1000.0)
             | [] -> 0)
          with _ -> 0 in
          VInt v
        | _ -> eval_error "sys_cpu_load_milli: no arguments expected"))
  ; ("sys_mem_total_bytes", VBuiltin ("sys_mem_total_bytes", function
        | [] | [VUnit] ->
          let read_meminfo_kb field =
            try
              let prefix = field ^ ":" in
              let plen = String.length prefix in
              let ic = open_in "/proc/meminfo" in
              let rec scan () =
                match input_line ic with
                | line ->
                  if String.length line >= plen && String.sub line 0 plen = prefix then begin
                    close_in ic;
                    let rest = String.sub line plen (String.length line - plen) in
                    (try Scanf.sscanf rest " %d" (fun kb -> kb) with _ -> 0)
                  end else scan ()
                | exception End_of_file -> close_in ic; 0
              in scan ()
            with _ -> 0
          in
          VInt (read_meminfo_kb "MemTotal" * 1024)
        | _ -> eval_error "sys_mem_total_bytes: no arguments expected"))
  ; ("sys_mem_available_bytes", VBuiltin ("sys_mem_available_bytes", function
        | [] | [VUnit] ->
          let read_meminfo_kb field =
            try
              let prefix = field ^ ":" in
              let plen = String.length prefix in
              let ic = open_in "/proc/meminfo" in
              let rec scan () =
                match input_line ic with
                | line ->
                  if String.length line >= plen && String.sub line 0 plen = prefix then begin
                    close_in ic;
                    let rest = String.sub line plen (String.length line - plen) in
                    (try Scanf.sscanf rest " %d" (fun kb -> kb) with _ -> 0)
                  end else scan ()
                | exception End_of_file -> close_in ic; 0
              in scan ()
            with _ -> 0
          in
          VInt (read_meminfo_kb "MemAvailable" * 1024)
        | _ -> eval_error "sys_mem_available_bytes: no arguments expected"))
  ; ("sys_os", VBuiltin ("sys_os", function
        | [] | [VUnit] ->
          let atom = match Sys.os_type with
            | "Win32" | "Cygwin" -> "windows"
            | _ ->
              (match Lazy.force uname_info with
               | Some ("darwin", _) -> "macos"
               | Some ("linux",  _) -> "linux"
               | Some (os, _)       -> os
               | None               -> "unknown")
          in
          VCon (atom, [])
        | _ -> eval_error "sys_os: no arguments expected"))
  ; ("sys_arch", VBuiltin ("sys_arch", function
        | [] | [VUnit] ->
          let atom = match Lazy.force uname_info with
            | Some (_, "x86_64")                     -> "x86_64"
            | Some (_, "aarch64") | Some (_, "arm64") -> "aarch64"
            | Some (_, "i386")   | Some (_, "i686")   -> "x86"
            | Some (_, arch) when arch <> ""          -> arch
            | _                                       -> "unknown"
          in
          VCon (atom, [])
        | _ -> eval_error "sys_arch: no arguments expected"))
  ; ("march_version", VBuiltin ("march_version", function
        | [] | [VUnit] -> VString "0.1.0"
        | _ -> eval_error "march_version: no arguments expected"))
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

  (* Spawn a process asynchronously (non-blocking).
     Returns Ok(LiveProcess(pid, stream_id)) or Err(String). *)
  ; ("process_spawn_async", VBuiltin ("process_spawn_async", function
        | [VString cmd; lst] ->
          let rec args_of_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VString s; rest]) -> s :: args_of_list rest
            | v -> eval_error "process_spawn_async: expected String list, got %s"
                     (value_to_string v)
          in
          let args_strs = args_of_list lst in
          let args_arr  = Array.of_list (cmd :: args_strs) in
          (try
            let (stdin_r,  stdin_w)  = Unix.pipe () in
            let (stdout_r, stdout_w) = Unix.pipe () in
            let (stderr_r, stderr_w) = Unix.pipe () in
            let pid = Unix.create_process cmd args_arr stdin_r stdout_w stderr_w in
            Unix.close stdin_r;
            Unix.close stdout_w;
            Unix.close stderr_w;
            Unix.close stderr_r;
            let ic = Unix.in_channel_of_descr stdout_r in
            let oc = Unix.out_channel_of_descr stdin_w in
            let id = !live_proc_next_id in
            incr live_proc_next_id;
            Hashtbl.add live_proc_tbl id (ic, oc, pid);
            VCon ("Ok", [VCon ("LiveProcess", [VInt pid; VInt id])])
          with Unix.Unix_error (err, _, _) ->
            VCon ("Err", [VString (Unix.error_message err)]))
        | _ -> eval_error "process_spawn_async: expected (String, List(String))"))

  (* Read one line from a LiveProcess's stdout.
     Returns Some(line) or None on EOF. *)
  ; ("process_read_line", VBuiltin ("process_read_line", function
        | [VCon ("LiveProcess", [VInt _pid; VInt id])] ->
          (match Hashtbl.find_opt live_proc_tbl id with
           | None -> VCon ("None", [])
           | Some (ic, _, _) ->
             (try VCon ("Some", [VString (input_line ic)])
              with End_of_file -> VCon ("None", [])))
        | _ -> eval_error "process_read_line: expected LiveProcess"))

  (* Write raw bytes to the process's stdin. *)
  ; ("process_write", VBuiltin ("process_write", function
        | [VCon ("LiveProcess", [VInt _pid; VInt id]); VString data] ->
          (match Hashtbl.find_opt live_proc_tbl id with
           | None -> VUnit
           | Some (_, oc, _) ->
             output_string oc data;
             flush oc;
             VUnit)
        | _ -> eval_error "process_write: expected (LiveProcess, String)"))

  (* Send SIGTERM to the process. *)
  ; ("process_kill_proc", VBuiltin ("process_kill_proc", function
        | [VCon ("LiveProcess", [VInt pid; VInt _id])] ->
          (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
          VUnit
        | _ -> eval_error "process_kill_proc: expected LiveProcess"))

  (* Wait for the process to finish; close the channel. Returns exit code. *)
  ; ("process_wait_proc", VBuiltin ("process_wait_proc", function
        | [VCon ("LiveProcess", [VInt pid; VInt id])] ->
          (match Hashtbl.find_opt live_proc_tbl id with
           | Some (ic, oc, _) ->
             (try close_in_noerr ic with _ -> ());
             (try close_out_noerr oc with _ -> ());
             Hashtbl.remove live_proc_tbl id
           | None -> ());
          (try
            let (_, status) = Unix.waitpid [] pid in
            match status with
            | Unix.WEXITED  n -> VInt n
            | Unix.WSIGNALED n -> VInt (- n)
            | Unix.WSTOPPED  n -> VInt (- n)
          with Unix.Unix_error _ -> VInt (-1))
        | _ -> eval_error "process_wait_proc: expected LiveProcess"))

  (* ---- Logger builtins ----
     v1 (legacy): logger_add_context, logger_clear_context,
     logger_get_context — operate on the same field stack but coerce
     values to/from String for backward compat.
     v2: logger_add_field, logger_get_fields, logger_pop_to_depth,
     logger_field_count work in terms of the LogValue ADT. *)
  ; ("logger_set_level", VBuiltin ("logger_set_level", function
        | [VInt n] -> logger_level := n; VUnit
        | _ -> eval_error "logger_set_level: expected Int"))
  ; ("logger_get_level", VBuiltin ("logger_get_level", function
        | [] -> VInt !logger_level
        | _ -> eval_error "logger_get_level: no arguments"))

  (* v1 shim: pushes a LogStr field. *)
  ; ("logger_add_context", VBuiltin ("logger_add_context", function
        | [VString k; VString v] ->
          logger_fields := (k, LogStr v) :: !logger_fields; VUnit
        | _ -> eval_error "logger_add_context: expected (String, String)"))
  ; ("logger_clear_context", VBuiltin ("logger_clear_context", function
        | [] -> logger_fields := []; VUnit
        | _ -> eval_error "logger_clear_context: no arguments"))
  (* v1 shim: returns String values; non-String LogValues are stringified. *)
  ; ("logger_get_context", VBuiltin ("logger_get_context", function
        | [] ->
          List.fold_right (fun (k, v) acc ->
            VCon ("Cons", [VTuple [VString k; VString (log_value_to_string v)]; acc])
          ) !logger_fields (VCon ("Nil", []))
        | _ -> eval_error "logger_get_context: no arguments"))

  (* v2: structured field stack manipulation.
     Field values are encoded as the March `LogValue` ADT. *)
  ; ("logger_add_field", VBuiltin ("logger_add_field", function
        | [VString k; v] ->
          let lv = match v with
            | VCon ("LStr",   [VString s]) -> LogStr s
            | VCon ("LInt",   [VInt n])    -> LogInt n
            | VCon ("LFloat", [VFloat f])  -> LogFloat f
            | VCon ("LBool",  [VBool b])   -> LogBool b
            | VCon ("LAtom",  [VAtom a])   -> LogAtom a
            | VCon ("LNull",  [])          -> LogNull
            (* Defensive: if a v1 caller hands us a bare String, wrap it. *)
            | VString s                    -> LogStr s
            | VInt n                       -> LogInt n
            | VFloat f                     -> LogFloat f
            | VBool b                      -> LogBool b
            | _ -> LogStr (value_to_string v)
          in
          logger_fields := (k, lv) :: !logger_fields; VUnit
        | _ -> eval_error "logger_add_field(key: String, value: LogValue)"))
  ; ("logger_field_count", VBuiltin ("logger_field_count", function
        | [] -> VInt (List.length !logger_fields)
        | _ -> eval_error "logger_field_count: no arguments"))
  (* Truncate field stack so its length is exactly `depth`.  Used by
     `with_scope` to roll back on exit / panic. *)
  ; ("logger_pop_to_depth", VBuiltin ("logger_pop_to_depth", function
        | [VInt depth] ->
          let cur = !logger_fields in
          let cur_len = List.length cur in
          if depth >= cur_len then VUnit
          else begin
            let rec drop n lst =
              if n <= 0 then lst
              else match lst with
                | [] -> []
                | _ :: t -> drop (n - 1) t
            in
            logger_fields := drop (cur_len - depth) cur; VUnit
          end
        | _ -> eval_error "logger_pop_to_depth: expected Int"))
  (* Returns the field stack as a List(LogField).  Each LogField wraps
     (key, LogValue).  Encoded so March pattern-matches on the same
     constructors users write. *)
  ; ("logger_get_fields", VBuiltin ("logger_get_fields", function
        | [] ->
          let log_value_to_march = function
            | LogStr s   -> VCon ("LStr",   [VString s])
            | LogInt n   -> VCon ("LInt",   [VInt n])
            | LogFloat f -> VCon ("LFloat", [VFloat f])
            | LogBool b  -> VCon ("LBool",  [VBool b])
            | LogAtom a  -> VCon ("LAtom",  [VAtom a])
            | LogNull    -> VCon ("LNull",  [])
          in
          List.fold_right (fun (k, v) acc ->
            VCon ("Cons",
                  [VCon ("LogField", [VString k; log_value_to_march v]); acc])
          ) !logger_fields (VCon ("Nil", []))
        | _ -> eval_error "logger_get_fields: no arguments"))

  (* logger_write(level_str, msg, context_list, extra_list)
     v1 entry point.  Both list args are List((String,String)) tuples.
     For v2, prefer the appender pipeline (logger_dispatch — see below). *)
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

  (* ── Logger v2 appender registry + dispatch ─────────────────────────
     Appenders are March callbacks of type `LogEntry -> Unit`.  We
     store them as opaque `value`s and invoke them via apply_hook.
     Multiple appenders fire in registration order. *)
  ; ("logger_register_appender", VBuiltin ("logger_register_appender", function
        | [VString name; cb] ->
          (* Replace any existing entry with the same name (idempotent). *)
          logger_appenders :=
            (name, cb) ::
            (List.filter (fun (n, _) -> n <> name) !logger_appenders);
          VUnit
        | _ -> eval_error "logger_register_appender(name: String, cb: LogEntry -> Unit)"))
  ; ("logger_remove_appender", VBuiltin ("logger_remove_appender", function
        | [VString name] ->
          logger_appenders :=
            List.filter (fun (n, _) -> n <> name) !logger_appenders;
          VUnit
        | _ -> eval_error "logger_remove_appender(name: String)"))
  ; ("logger_clear_appenders", VBuiltin ("logger_clear_appenders", function
        | [] -> logger_appenders := []; VUnit
        | _ -> eval_error "logger_clear_appenders: no arguments"))
  ; ("logger_appender_names", VBuiltin ("logger_appender_names", function
        | [] ->
          List.fold_right (fun (n, _) acc ->
            VCon ("Cons", [VString n; acc])
          ) !logger_appenders (VCon ("Nil", []))
        | _ -> eval_error "logger_appender_names: no arguments"))
  (* logger_dispatch(level_str, msg, source, fields)
     Builds a `LogEntry` value and fans it out to every registered
     appender in turn.  When no appenders are registered (empty
     registry), falls back to the v1 stderr text format so the logger
     remains useful out of the box. *)
  ; ("logger_dispatch", VBuiltin ("logger_dispatch", function
        | [VString level_s; VString msg; VString source; fields_list] ->
          (* Map the all-caps level string back to the March Level
             constructor: "DEBUG" -> Debug, "INFO" -> Info, etc.
             Anything unrecognised becomes Info to keep formatters
             happy (level filtering already happened upstream). *)
          let level_to_march s =
            let ctor = match s with
              | "DEBUG" -> "Debug"
              | "INFO"  -> "Info"
              | "WARN"  -> "Warn"
              | "ERROR" -> "Error"
              | _       -> "Info"
            in
            VCon (ctor, [])
          in
          let now_ms = int_of_float (Unix.gettimeofday () *. 1000.0) in
          let entry =
            VCon ("LogEntry",
                  [level_to_march level_s;
                   VString msg;
                   VInt now_ms;
                   VString source;
                   fields_list])
          in
          if !logger_appenders = [] then begin
            (* v1 fallback: render fields as "k=v" pairs. *)
            let rec field_strs = function
              | VCon ("Nil", []) -> []
              | VCon ("Cons",
                      [VCon ("LogField",
                             [VString k; v]); rest]) ->
                let vstr = match v with
                  | VCon ("LStr",   [VString s]) -> s
                  | VCon ("LInt",   [VInt n])    -> string_of_int n
                  | VCon ("LFloat", [VFloat f])  -> string_of_float f
                  | VCon ("LBool",  [VBool b])   -> if b then "true" else "false"
                  | VCon ("LAtom",  [VAtom a])   -> ":" ^ a
                  | VCon ("LNull",  [])          -> "null"
                  | _                             -> value_to_string v
                in
                (k ^ "=" ^ vstr) :: field_strs rest
              | VCon ("Cons", [_; rest]) -> field_strs rest
              | _ -> []
            in
            let parts = field_strs fields_list in
            let suffix =
              if parts = [] then ""
              else " {" ^ String.concat ", " parts ^ "}"
            in
            capture_ewriteln (Printf.sprintf "[%s] %s%s" level_s msg suffix);
            VUnit
          end else begin
            List.iter (fun (n, cb) ->
              try ignore (!apply_hook cb [entry])
              with exn ->
                Printf.eprintf "[logger] appender %S failed: %s\n%!"
                  n (Printexc.to_string exn)
            ) !logger_appenders;
            VUnit
          end
        | _ -> eval_error "logger_dispatch(level: String, msg: String, source: String, fields: List(LogField))"))

  (* Per-module level overrides. *)
  ; ("logger_set_module_level", VBuiltin ("logger_set_module_level", function
        | [VString m; VInt n] ->
          Hashtbl.replace logger_module_levels m n; VUnit
        | _ -> eval_error "logger_set_module_level(module: String, level: Int)"))
  ; ("logger_clear_module_level", VBuiltin ("logger_clear_module_level", function
        | [VString m] ->
          Hashtbl.remove logger_module_levels m; VUnit
        | _ -> eval_error "logger_clear_module_level(module: String)"))
  ; ("logger_module_level", VBuiltin ("logger_module_level", function
        | [VString m] ->
          (match Hashtbl.find_opt logger_module_levels m with
           | Some n -> VInt n
           | None   -> VInt !logger_level)
        | _ -> eval_error "logger_module_level(module: String): Int"))

  (* ── Vault builtins ──────────────────────────────────────────────────────
     Vault is an ETS-like per-node in-memory KV store backed by a sharded
     concurrent hash map.  Each vault_table has vault_num_stripes = 16
     independent (Hashtbl + Mutex) shards.  Key → shard mapping is by hash,
     so writes to different keys in different shards run in parallel.

     vault_update applies [f] outside the shard lock to prevent deadlocks
     when [f] itself calls vault operations.  This makes update "optimistic":
     truly atomic compound operations require external serialisation in a
     multi-threaded compiled runtime. *)

  ; ("vault_new", VBuiltin ("vault_new", function
      | [VString name] ->
        let id = !vault_next_id in
        incr vault_next_id;
        let tbl = vault_make_table id name in
        Hashtbl.replace vault_registry id tbl;
        (* Register name → id so any actor can look it up by name. *)
        Hashtbl.replace vault_name_registry name id;
        (* If called inside an actor, register a cleanup thunk so the table and
           its name entry are removed when the owning actor crashes or exits.
           At top-level (current_pid = None) both live until program exit. *)
        (match !current_pid with
         | Some pid ->
           let cleanup () =
             Hashtbl.remove vault_registry id;
             Hashtbl.remove vault_name_registry name
           in
           register_resource_ocaml pid (Printf.sprintf "vault:%s" name) cleanup
         | None -> ());
        VVaultHandle id
      | _ -> eval_error "vault_new: expected String (table name)"))

  ; ("vault_whereis", VBuiltin ("vault_whereis", function
      | [VString name] ->
        (match Hashtbl.find_opt vault_name_registry name with
         | None    -> VCon ("None", [])
         | Some id -> VCon ("Some", [VVaultHandle id]))
      | _ -> eval_error "vault_whereis: expected String (table name)"))

  ; ("vault_set", VBuiltin ("vault_set", function
      | [VVaultHandle id; key; v] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        Mutex.lock shard.vs_mutex;
        Hashtbl.replace shard.vs_data k { vr_value = v; vr_expiry = None };
        Mutex.unlock shard.vs_mutex;
        VUnit
      | _ -> eval_error "vault_set: expected (VaultTable, key, value)"))

  ; ("vault_set_ttl", VBuiltin ("vault_set_ttl", function
      | [VVaultHandle id; key; v; VInt ttl_secs] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        let expiry = Unix.gettimeofday () +. float_of_int ttl_secs in
        Mutex.lock shard.vs_mutex;
        Hashtbl.replace shard.vs_data k { vr_value = v; vr_expiry = Some expiry };
        Mutex.unlock shard.vs_mutex;
        VUnit
      | _ -> eval_error "vault_set_ttl: expected (VaultTable, key, value, Int)"))

  (* Atomic insert-if-absent: the read, the absence check, and the write all
     happen under one shard lock, so concurrent callers racing on the same key
     cannot both succeed — exactly one gets [true]. ttl_secs <= 0 means no
     expiry. Use as a lock / idempotency claim. *)
  ; ("vault_put_new", VBuiltin ("vault_put_new", function
      | [VVaultHandle id; key; v; VInt ttl_secs] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        let expiry =
          if ttl_secs <= 0 then None
          else Some (Unix.gettimeofday () +. float_of_int ttl_secs) in
        Mutex.lock shard.vs_mutex;
        let inserted =
          match Hashtbl.find_opt shard.vs_data k with
          | Some row when vault_row_live row -> false
          | _ ->
            Hashtbl.replace shard.vs_data k { vr_value = v; vr_expiry = expiry };
            true
        in
        Mutex.unlock shard.vs_mutex;
        VBool inserted
      | _ -> eval_error "vault_put_new: expected (VaultTable, key, value, Int)"))

  (* Atomic integer increment: read-add-write under one shard lock, returning
     the new value. A missing or non-integer entry is treated as 0. Any
     existing TTL is preserved. Concurrent increments do not lose updates. *)
  ; ("vault_incr", VBuiltin ("vault_incr", function
      | [VVaultHandle id; key; VInt delta] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        Mutex.lock shard.vs_mutex;
        let (cur, expiry) =
          match Hashtbl.find_opt shard.vs_data k with
          | Some row when vault_row_live row ->
            ((match row.vr_value with VInt n -> n | _ -> 0), row.vr_expiry)
          | _ -> (0, None)
        in
        let nv = cur + delta in
        Hashtbl.replace shard.vs_data k { vr_value = VInt nv; vr_expiry = expiry };
        Mutex.unlock shard.vs_mutex;
        VInt nv
      | _ -> eval_error "vault_incr: expected (VaultTable, key, Int)"))

  (* Atomic bounded list push: append [value] to the list stored at [key]
     (newest at the tail) and keep only the last [max] elements, all under one
     shard lock. A missing or non-list entry starts from the empty list; max <= 0
     keeps everything. Any existing TTL is preserved. Closes the
     get -> append -> set race for ring buffers / inboxes. *)
  ; ("vault_push_capped", VBuiltin ("vault_push_capped", function
      | [VVaultHandle id; key; value; VInt max_n] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        Mutex.lock shard.vs_mutex;
        let (cur, expiry) =
          match Hashtbl.find_opt shard.vs_data k with
          | Some row when vault_row_live row -> (list_elems [] row.vr_value, row.vr_expiry)
          | _ -> ([], None)
        in
        let appended = cur @ [value] in
        let len = List.length appended in
        let capped =
          if max_n > 0 && len > max_n
          then List.filteri (fun i _ -> i >= len - max_n) appended
          else appended
        in
        let new_list =
          List.fold_right (fun x acc -> VCon ("Cons", [x; acc])) capped (VCon ("Nil", [])) in
        Hashtbl.replace shard.vs_data k { vr_value = new_list; vr_expiry = expiry };
        Mutex.unlock shard.vs_mutex;
        VUnit
      | _ -> eval_error "vault_push_capped: expected (VaultTable, key, value, Int)"))

  ; ("vault_get", VBuiltin ("vault_get", function
      | [VVaultHandle id; key] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        Mutex.lock shard.vs_mutex;
        let result =
          match Hashtbl.find_opt shard.vs_data k with
          | None -> VCon ("None", [])
          | Some row when not (vault_row_live row) ->
            Hashtbl.remove shard.vs_data k;
            VCon ("None", [])
          | Some row -> VCon ("Some", [row.vr_value])
        in
        Mutex.unlock shard.vs_mutex;
        result
      | _ -> eval_error "vault_get: expected (VaultTable, key)"))

  ; ("vault_drop", VBuiltin ("vault_drop", function
      | [VVaultHandle id; key] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        Mutex.lock shard.vs_mutex;
        Hashtbl.remove shard.vs_data k;
        Mutex.unlock shard.vs_mutex;
        VUnit
      | _ -> eval_error "vault_drop: expected (VaultTable, key)"))

  ; ("vault_update", VBuiltin ("vault_update", function
      | [VVaultHandle id; key; f] ->
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        (* Phase 1: read current value under lock *)
        Mutex.lock shard.vs_mutex;
        let row_opt =
          match Hashtbl.find_opt shard.vs_data k with
          | None -> None
          | Some row when not (vault_row_live row) ->
            Hashtbl.remove shard.vs_data k; None
          | Some row -> Some row
        in
        Mutex.unlock shard.vs_mutex;
        (* Phase 2: apply f OUTSIDE the lock — safe even if f calls vault ops *)
        (match row_opt with
         | None -> VUnit
         | Some row ->
           let new_val = !apply_hook f [row.vr_value] in
           (* Phase 3: commit result under lock *)
           Mutex.lock shard.vs_mutex;
           (match Hashtbl.find_opt shard.vs_data k with
            | Some r when vault_row_live r ->
              Hashtbl.replace shard.vs_data k { r with vr_value = new_val }
            | _ -> ());  (* key deleted/expired during computation — skip *)
           Mutex.unlock shard.vs_mutex;
           VUnit)
      | _ -> eval_error "vault_update: expected (VaultTable, key, fn)"))

  ; ("vault_size", VBuiltin ("vault_size", function
      | [VVaultHandle id] ->
        let tbl = vault_lookup id in
        (* Lock each shard in turn — prune expired entries while counting *)
        let count = Array.fold_left (fun acc shard ->
          Mutex.lock shard.vs_mutex;
          let n = Hashtbl.fold (fun k row c ->
            if vault_row_live row then c + 1
            else (Hashtbl.remove shard.vs_data k; c)
          ) shard.vs_data 0 in
          Mutex.unlock shard.vs_mutex;
          acc + n
        ) 0 tbl.vt_shards in
        VInt count
      | _ -> eval_error "vault_size: expected VaultTable"))

  (* vault_keys: return all live keys as a March List(String). *)
  ; ("vault_keys", VBuiltin ("vault_keys", function
      | [VVaultHandle id] ->
        let tbl = vault_lookup id in
        let keys = Array.fold_left (fun acc shard ->
          Mutex.lock shard.vs_mutex;
          let ks = Hashtbl.fold (fun k row acc ->
            if vault_row_live row then k :: acc
            else (Hashtbl.remove shard.vs_data k; acc)
          ) shard.vs_data [] in
          Mutex.unlock shard.vs_mutex;
          ks @ acc
        ) [] tbl.vt_shards in
        (* Build March linked list: Cons(k, Cons(k2, ... Nil)) *)
        List.fold_right (fun k acc ->
          VCon ("Cons", [vault_decode_key k; acc])
        ) keys (VCon ("Nil", []))
      | _ -> eval_error "vault_keys: expected VaultTable"))

  (* String-namespace vault helpers: accept a String namespace name and
     auto-create/find the vault by that name.  Useful for the pattern:
       ptype MyStore = { ns : String }
       Vault.ns_set(self.ns, key, value) *)
  ; ("vault_ns_set", VBuiltin ("vault_ns_set", function
      | [VString name; key; v] ->
        let id = match Hashtbl.find_opt vault_name_registry name with
          | Some id -> id
          | None ->
            let id = !vault_next_id in
            incr vault_next_id;
            let tbl = vault_make_table id name in
            Hashtbl.replace vault_registry id tbl;
            Hashtbl.replace vault_name_registry name id;
            id
        in
        let tbl = vault_lookup id in
        let k = vault_key_of_value key in
        let shard = vault_shard_for k tbl.vt_shards in
        Mutex.lock shard.vs_mutex;
        Hashtbl.replace shard.vs_data k { vr_value = v; vr_expiry = None };
        Mutex.unlock shard.vs_mutex;
        VUnit
      | _ -> eval_error "vault_ns_set: expected (String, key, value)"))

  ; ("vault_ns_get", VBuiltin ("vault_ns_get", function
      | [VString name; key] ->
        (match Hashtbl.find_opt vault_name_registry name with
         | None -> VCon ("None", [])
         | Some id ->
           let tbl = vault_lookup id in
           let k = vault_key_of_value key in
           let shard = vault_shard_for k tbl.vt_shards in
           Mutex.lock shard.vs_mutex;
           let result =
             match Hashtbl.find_opt shard.vs_data k with
             | None -> VCon ("None", [])
             | Some row when not (vault_row_live row) ->
               Hashtbl.remove shard.vs_data k;
               VCon ("None", [])
             | Some row -> VCon ("Some", [row.vr_value])
           in
           Mutex.unlock shard.vs_mutex;
           result)
      | _ -> eval_error "vault_ns_get: expected (String, key)"))

  ; ("vault_ns_drop", VBuiltin ("vault_ns_drop", function
      | [VString name; key] ->
        (match Hashtbl.find_opt vault_name_registry name with
         | None -> VUnit
         | Some id ->
           let tbl = vault_lookup id in
           let k = vault_key_of_value key in
           let shard = vault_shard_for k tbl.vt_shards in
           Mutex.lock shard.vs_mutex;
           Hashtbl.remove shard.vs_data k;
           Mutex.unlock shard.vs_mutex;
           VUnit)
      | _ -> eval_error "vault_ns_drop: expected (String, key)"))

  (* ---- Actor.call / Actor.cast ---- *)
  (* actor_cast: fire-and-forget async message to an actor. *)
  ; ("actor_cast", VBuiltin ("actor_cast", function
        | [VPid pid; msg] ->
          (match Hashtbl.find_opt actor_registry pid with
           | None -> VUnit
           | Some inst when not inst.ai_alive -> VUnit
           | Some inst ->
             (match msg with
              | VCon _ | VAtom _ -> mailbox_enqueue inst msg; VUnit
              | _ -> eval_error "actor_cast: message must be a constructor, got %s"
                       (value_to_string msg)))
        | _ -> eval_error "actor_cast: expected (Pid, message)"))
  (* actor_call: synchronous call, CANONICAL (compiled) protocol — the message
     is a zero-arg sentinel constructor whose TAG selects the receiving
     handler, and the runtime injects the caller (here: the reply ref) as
     that handler's single argument.  The handler answers with
     actor_reply(reply_to, result) / Actor.reply.  Mirrors the compiled
     runtime's march_actor_call exactly (specs/lang/actors.md "Synchronous
     Request-Reply"; the maintainer decision documents the compiled form as
     canonical — the interpreter previously wrapped the call as a 2-arg
     Call(ref, msg) needing an `on Call(ref, msg)` handler, so NO single
     example worked in both backends).  Routing:
       1. A handler NAMED like the sentinel wins (same-name sentinel types).
       2. Otherwise the sentinel's constructor INDEX within its own declared
          type selects the actor's handler at that index — the compiled
          tag-routing.  With the documented `type GetReq = GetReq` single-ctor
          sentinel this is index 0 = the actor's FIRST handler.
     Returns Ok(result) or Err(reason). *)
  ; ("actor_call", VBuiltin ("actor_call", function
        | [VPid pid; msg; VInt _timeout_ms] ->
          let ref_id = !next_call_ref in
          next_call_ref := ref_id + 1;
          let sentinel_tag = match msg with
            | VCon (tag, _) -> tag
            | VAtom tag     -> tag
            | _ -> eval_error "actor_call: message must be a constructor, got %s"
                     (value_to_string msg)
          in
          (match Hashtbl.find_opt actor_registry pid with
           | None -> VCon ("Err", [VString "actor not found"])
           | Some inst when not inst.ai_alive ->
             VCon ("Err", [VString "actor not alive"])
           | Some inst ->
             let handlers = inst.ai_def.actor_handlers in
             let handler_name =
               if List.exists (fun h -> h.ah_msg.txt = sentinel_tag) handlers
               then Some sentinel_tag
               else
                 (* Tag-index routing: the sentinel's ctor index within its own
                    declared type picks the handler at that index. *)
                 (match Hashtbl.find_opt ctor_type_tbl sentinel_tag with
                  | Some tyname ->
                    (match Hashtbl.find_opt ffi_type_decl_tbl tyname with
                     | Some (March_ast.Ast.TDVariant variants) ->
                       let rec idx i = function
                         | [] -> None
                         | (v : March_ast.Ast.variant) :: rest ->
                           if v.var_name.txt = sentinel_tag then Some i
                           else idx (i + 1) rest
                       in
                       (match idx 0 variants with
                        | Some i ->
                          (match List.nth_opt handlers i with
                           | Some h -> Some h.ah_msg.txt
                           | None -> None)
                        | None -> None)
                     | _ -> None)
                  | None -> None)
             in
             (match handler_name with
              | None ->
                VCon ("Err", [VString "no reply (timeout or unhandled Call)"])
              | Some hname ->
                mailbox_enqueue inst (VCon (hname, [VInt ref_id]));
                !run_scheduler_hook ();
                (match Hashtbl.find_opt pending_replies ref_id with
                 | Some result ->
                   Hashtbl.remove pending_replies ref_id;
                   VCon ("Ok", [result])
                 | None ->
                   VCon ("Err", [VString "no reply (timeout or unhandled Call)"]))))
        | _ -> eval_error "actor_call: expected (Pid, message, Int)"))
  (* actor_reply: store a reply for a pending call.  Called from actor handlers. *)
  ; ("actor_reply", VBuiltin ("actor_reply", function
        | [VInt ref_id; result] ->
          Hashtbl.replace pending_replies ref_id result; VUnit
        | _ -> eval_error "actor_reply: expected (Int, value)"))
  (* actor_send_after/actor_cancel_timer (specs/progress/2026-08-12-language-
     level-timers.md). Real wall-clock scheduling: the entry sits in
     [pending_timers] until [timer_service_tick] (called once per
     [run_scheduler] pass, i.e. from run_until_idle) observes
     [Unix.gettimeofday] has reached [tt_fire_at]. No pid-liveness check at
     schedule time — mirrors actor_cast/march_send: a dead or never-spawned
     target simply drops the message when the timer fires (checked in
     timer_service_tick, not here). Named with the "actor_" prefix (not
     bare) so the Actor.send_after/Actor.cancel_timer wrappers in
     stdlib/actor.march can reuse the friendly names without recursing into
     themselves — see typecheck.ml's identical naming-rationale comment. *)
  ; ("actor_send_after", VBuiltin ("actor_send_after", function
        | [VPid pid; msg; VInt delay_ms] ->
          let fire_at = Unix.gettimeofday () *. 1000. +. float_of_int (max 0 delay_ms) in
          let entry = { tt_fire_at = fire_at; tt_target = pid; tt_msg = msg;
                        tt_cancelled = false } in
          pending_timers := entry :: !pending_timers;
          VTimerRef entry
        | _ -> eval_error "actor_send_after: expected (Pid, message, Int)"))
  ; ("actor_cancel_timer", VBuiltin ("actor_cancel_timer", function
        | [VTimerRef entry] -> entry.tt_cancelled <- true; VUnit
        | _ -> eval_error "actor_cancel_timer: expected a TimerRef"))

  (* ── NativeArray builtins ────────────────────────────────────────────────
     Flat OCaml int/float arrays with tight-loop implementations of common
     numeric operations (sum, map, fold).  These are the fast interpreter
     path for P10 — while the March Array module uses a 32-way trie that
     cannot be vectorized, NativeArray maps directly to OCaml's native
     array type which compiles to cache-friendly sequential memory access.

     Int variants *)
  ; ("native_int_arr_make", VBuiltin ("native_int_arr_make", function
        | [VInt n; VInt init] ->
          if n < 0 then eval_error "native_int_arr_make: negative size %d" n;
          VNativeIntArr (Array.make n init)
        | _ -> eval_error "native_int_arr_make: expected (Int, Int)"))
  ; ("native_int_arr_length", VBuiltin ("native_int_arr_length", function
        | [VNativeIntArr a] -> VInt (Array.length a)
        | _ -> eval_error "native_int_arr_length: expected NativeIntArr"))
  ; ("native_int_arr_get", VBuiltin ("native_int_arr_get", function
        | [VNativeIntArr a; VInt i] ->
          if i < 0 || i >= Array.length a then
            eval_error "native_int_arr_get: index %d out of bounds (len=%d)" i (Array.length a);
          VInt a.(i)
        | _ -> eval_error "native_int_arr_get: expected (NativeIntArr, Int)"))
  ; ("native_int_arr_set", VBuiltin ("native_int_arr_set", function
        | [VNativeIntArr a; VInt i; VInt v] ->
          let n = Array.length a in
          if i < 0 || i >= n then
            eval_error "native_int_arr_set: index %d out of bounds (len=%d)" i n;
          let a' = Array.copy a in
          a'.(i) <- v;
          VNativeIntArr a'
        | _ -> eval_error "native_int_arr_set: expected (NativeIntArr, Int, Int)"))
  ; ("native_int_arr_sum", VBuiltin ("native_int_arr_sum", function
        | [VNativeIntArr a] ->
          let s = ref 0 in
          for i = 0 to Array.length a - 1 do s := !s + a.(i) done;
          VInt !s
        | _ -> eval_error "native_int_arr_sum: expected NativeIntArr"))
  ; ("native_int_arr_min", VBuiltin ("native_int_arr_min", function
        | [VNativeIntArr a] ->
          let m = ref a.(0) in
          for i = 1 to Array.length a - 1 do if a.(i) < !m then m := a.(i) done;
          VInt !m
        | _ -> eval_error "native_int_arr_min: expected NativeIntArr"))
  ; ("native_int_arr_max", VBuiltin ("native_int_arr_max", function
        | [VNativeIntArr a] ->
          let m = ref a.(0) in
          for i = 1 to Array.length a - 1 do if a.(i) > !m then m := a.(i) done;
          VInt !m
        | _ -> eval_error "native_int_arr_max: expected NativeIntArr"))
  ; ("native_int_arr_sumsq_dev", VBuiltin ("native_int_arr_sumsq_dev", function
        | [VNativeIntArr a; VFloat mean] ->
          let s = ref 0.0 in
          for i = 0 to Array.length a - 1 do
            let d = float_of_int a.(i) -. mean in
            s := !s +. d *. d
          done;
          VFloat !s
        | _ -> eval_error "native_int_arr_sumsq_dev: expected (NativeIntArr, Float)"))
  ; ("native_int_arr_map", VBuiltin ("native_int_arr_map", function
        | [VNativeIntArr a; f] ->
          let n = Array.length a in
          let b = Array.make n 0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VInt a.(i)] with
             | VInt v -> b.(i) <- v
             | v -> eval_error "native_int_arr_map: function returned non-Int: %s"
                      (value_to_string v))
          done;
          VNativeIntArr b
        | _ -> eval_error "native_int_arr_map: expected (NativeIntArr, fn)"))
  ; ("native_int_arr_map2", VBuiltin ("native_int_arr_map2", function
        | [VNativeIntArr a; VNativeIntArr b; f] ->
          let n = Array.length a in
          if Array.length b <> n then
            eval_error "native_int_arr_map2: array length mismatch (%d vs %d)" n (Array.length b);
          let out = Array.make n 0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VInt a.(i); VInt b.(i)] with
             | VInt v -> out.(i) <- v
             | v -> eval_error "native_int_arr_map2: function returned non-Int: %s"
                      (value_to_string v))
          done;
          VNativeIntArr out
        | _ -> eval_error "native_int_arr_map2: expected (NativeIntArr, NativeIntArr, fn)"))
  ; ("native_int_arr_to_float_arr", VBuiltin ("native_int_arr_to_float_arr", function
        | [VNativeIntArr a] -> VNativeFloatArr (Array.map float_of_int a)
        | _ -> eval_error "native_int_arr_to_float_arr: expected NativeIntArr"))
  ; ("native_int_arr_fold", VBuiltin ("native_int_arr_fold", function
        | [acc0; VNativeIntArr a; f] ->
          let acc = ref acc0 in
          for i = 0 to Array.length a - 1 do
            acc := !apply_hook f [!acc; VInt a.(i)]
          done;
          !acc
        | _ -> eval_error "native_int_arr_fold: expected (init, NativeIntArr, fn)"))
  ; ("native_int_arr_from_list", VBuiltin ("native_int_arr_from_list", function
        | [lst] ->
          let rec to_ocaml_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VInt h; t]) -> h :: to_ocaml_list t
            | v -> eval_error "native_int_arr_from_list: expected List(Int), got %s"
                     (value_to_string v)
          in
          VNativeIntArr (Array.of_list (to_ocaml_list lst))
        | _ -> eval_error "native_int_arr_from_list: expected List(Int)"))
  ; ("native_int_arr_to_list", VBuiltin ("native_int_arr_to_list", function
        | [VNativeIntArr a] ->
          Array.fold_right (fun x acc -> VCon ("Cons", [VInt x; acc]))
            a (VCon ("Nil", []))
        | _ -> eval_error "native_int_arr_to_list: expected NativeIntArr"))

  (* Float variants *)
  ; ("native_float_arr_make", VBuiltin ("native_float_arr_make", function
        | [VInt n; VFloat init] ->
          if n < 0 then eval_error "native_float_arr_make: negative size %d" n;
          VNativeFloatArr (Array.make n init)
        | _ -> eval_error "native_float_arr_make: expected (Int, Float)"))
  ; ("native_float_arr_length", VBuiltin ("native_float_arr_length", function
        | [VNativeFloatArr a] -> VInt (Array.length a)
        | _ -> eval_error "native_float_arr_length: expected NativeFloatArr"))
  ; ("native_float_arr_get", VBuiltin ("native_float_arr_get", function
        | [VNativeFloatArr a; VInt i] ->
          if i < 0 || i >= Array.length a then
            eval_error "native_float_arr_get: index %d out of bounds (len=%d)" i (Array.length a);
          VFloat a.(i)
        | _ -> eval_error "native_float_arr_get: expected (NativeFloatArr, Int)"))
  ; ("native_float_arr_set", VBuiltin ("native_float_arr_set", function
        | [VNativeFloatArr a; VInt i; VFloat v] ->
          let n = Array.length a in
          if i < 0 || i >= n then
            eval_error "native_float_arr_set: index %d out of bounds (len=%d)" i n;
          let a' = Array.copy a in
          a'.(i) <- v;
          VNativeFloatArr a'
        | _ -> eval_error "native_float_arr_set: expected (NativeFloatArr, Int, Float)"))
  ; ("native_float_arr_sum", VBuiltin ("native_float_arr_sum", function
        | [VNativeFloatArr a] ->
          let s = ref 0.0 in
          for i = 0 to Array.length a - 1 do s := !s +. a.(i) done;
          VFloat !s
        | _ -> eval_error "native_float_arr_sum: expected NativeFloatArr"))
  ; ("native_float_arr_min", VBuiltin ("native_float_arr_min", function
        | [VNativeFloatArr a] ->
          let m = ref a.(0) in
          for i = 1 to Array.length a - 1 do if a.(i) < !m then m := a.(i) done;
          VFloat !m
        | _ -> eval_error "native_float_arr_min: expected NativeFloatArr"))
  ; ("native_float_arr_max", VBuiltin ("native_float_arr_max", function
        | [VNativeFloatArr a] ->
          let m = ref a.(0) in
          for i = 1 to Array.length a - 1 do if a.(i) > !m then m := a.(i) done;
          VFloat !m
        | _ -> eval_error "native_float_arr_max: expected NativeFloatArr"))
  ; ("native_float_arr_sumsq_dev", VBuiltin ("native_float_arr_sumsq_dev", function
        | [VNativeFloatArr a; VFloat mean] ->
          let s = ref 0.0 in
          for i = 0 to Array.length a - 1 do
            let d = a.(i) -. mean in
            s := !s +. d *. d
          done;
          VFloat !s
        | _ -> eval_error "native_float_arr_sumsq_dev: expected (NativeFloatArr, Float)"))
  ; ("native_float_arr_map", VBuiltin ("native_float_arr_map", function
        | [VNativeFloatArr a; f] ->
          let n = Array.length a in
          let b = Array.make n 0.0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VFloat a.(i)] with
             | VFloat v -> b.(i) <- v
             | v -> eval_error "native_float_arr_map: function returned non-Float: %s"
                      (value_to_string v))
          done;
          VNativeFloatArr b
        | _ -> eval_error "native_float_arr_map: expected (NativeFloatArr, fn)"))
  ; ("native_float_arr_map2", VBuiltin ("native_float_arr_map2", function
        | [VNativeFloatArr a; VNativeFloatArr b; f] ->
          let n = Array.length a in
          if Array.length b <> n then
            eval_error "native_float_arr_map2: array length mismatch (%d vs %d)" n (Array.length b);
          let out = Array.make n 0.0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VFloat a.(i); VFloat b.(i)] with
             | VFloat v -> out.(i) <- v
             | v -> eval_error "native_float_arr_map2: function returned non-Float: %s"
                      (value_to_string v))
          done;
          VNativeFloatArr out
        | _ -> eval_error "native_float_arr_map2: expected (NativeFloatArr, NativeFloatArr, fn)"))
  ; ("native_float_arr_fold", VBuiltin ("native_float_arr_fold", function
        | [acc0; VNativeFloatArr a; f] ->
          let acc = ref acc0 in
          for i = 0 to Array.length a - 1 do
            acc := !apply_hook f [!acc; VFloat a.(i)]
          done;
          !acc
        | _ -> eval_error "native_float_arr_fold: expected (init, NativeFloatArr, fn)"))
  (* native_int_arr_filter_mask(arr, bool_typed_arr) → keep elements where mask is true *)
  ; ("native_int_arr_filter_mask", VBuiltin ("native_int_arr_filter_mask", function
        | [VNativeIntArr arr; VTypedArray mask] ->
          let n = Array.length arr in
          if n <> Array.length mask then
            eval_error "native_int_arr_filter_mask: array length %d != mask length %d" n (Array.length mask);
          let kept = ref [] in
          for i = n - 1 downto 0 do
            if mask.(i) = VBool true then kept := arr.(i) :: !kept
          done;
          VNativeIntArr (Array.of_list !kept)
        | _ -> eval_error "native_int_arr_filter_mask: expected (NativeIntArr, TypedArray(Bool))"))
  (* native_float_arr_filter_mask(arr, bool_typed_arr) → keep elements where mask is true *)
  ; ("native_float_arr_filter_mask", VBuiltin ("native_float_arr_filter_mask", function
        | [VNativeFloatArr arr; VTypedArray mask] ->
          let n = Array.length arr in
          if n <> Array.length mask then
            eval_error "native_float_arr_filter_mask: array length %d != mask length %d" n (Array.length mask);
          let kept = ref [] in
          for i = n - 1 downto 0 do
            if mask.(i) = VBool true then kept := arr.(i) :: !kept
          done;
          VNativeFloatArr (Array.of_list !kept)
        | _ -> eval_error "native_float_arr_filter_mask: expected (NativeFloatArr, TypedArray(Bool))"))
  ; ("native_float_arr_from_list", VBuiltin ("native_float_arr_from_list", function
        | [lst] ->
          let rec to_ocaml_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VFloat h; t]) -> h :: to_ocaml_list t
            | v -> eval_error "native_float_arr_from_list: expected List(Float), got %s"
                     (value_to_string v)
          in
          VNativeFloatArr (Array.of_list (to_ocaml_list lst))
        | _ -> eval_error "native_float_arr_from_list: expected List(Float)"))
  ; ("native_float_arr_to_list", VBuiltin ("native_float_arr_to_list", function
        | [VNativeFloatArr a] ->
          Array.fold_right (fun x acc -> VCon ("Cons", [VFloat x; acc]))
            a (VCon ("Nil", []))
        | _ -> eval_error "native_float_arr_to_list: expected NativeFloatArr"))

  (* ── Narrow-width NativeArray families — f32 / i32 / u8 (P10 narrow types).
     Boundary rule: integer stores wrap mod 2^w two's-complement; float
     stores round to nearest-even binary32; loads widen exactly (element
     representation is already the widened form, so get/to_list/sum read
     back plain — no widening work needed).  Never trap. *)
  (* f32 *)
  ; ("native_f32_arr_make", VBuiltin ("native_f32_arr_make", function
        | [VInt n; VFloat init] ->
          if n < 0 then eval_error "native_f32_arr_make: negative size %d" n;
          VNativeF32Arr (Array.make n (f32_round init))
        | _ -> eval_error "native_f32_arr_make: expected (Int, Float)"))
  ; ("native_f32_arr_length", VBuiltin ("native_f32_arr_length", function
        | [VNativeF32Arr a] -> VInt (Array.length a)
        | _ -> eval_error "native_f32_arr_length: expected NativeF32Arr"))
  ; ("native_f32_arr_get", VBuiltin ("native_f32_arr_get", function
        | [VNativeF32Arr a; VInt i] ->
          if i < 0 || i >= Array.length a then
            eval_error "native_f32_arr_get: index %d out of bounds (len=%d)" i (Array.length a);
          VFloat a.(i)
        | _ -> eval_error "native_f32_arr_get: expected (NativeF32Arr, Int)"))
  ; ("native_f32_arr_set", VBuiltin ("native_f32_arr_set", function
        | [VNativeF32Arr a; VInt i; VFloat v] ->
          let n = Array.length a in
          if i < 0 || i >= n then
            eval_error "native_f32_arr_set: index %d out of bounds (len=%d)" i n;
          let a' = Array.copy a in
          a'.(i) <- f32_round v;
          VNativeF32Arr a'
        | _ -> eval_error "native_f32_arr_set: expected (NativeF32Arr, Int, Float)"))
  ; ("native_f32_arr_sum", VBuiltin ("native_f32_arr_sum", function
        | [VNativeF32Arr a] -> VFloat (Array.fold_left (+.) 0.0 a)
        | _ -> eval_error "native_f32_arr_sum: expected NativeF32Arr"))
  ; ("native_f32_arr_map", VBuiltin ("native_f32_arr_map", function
        | [VNativeF32Arr a; f] ->
          let n = Array.length a in
          let b = Array.make n 0.0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VFloat a.(i)] with
             | VFloat v -> b.(i) <- f32_round v
             | v -> eval_error "native_f32_arr_map: function returned non-Float: %s"
                      (value_to_string v))
          done;
          VNativeF32Arr b
        | _ -> eval_error "native_f32_arr_map: expected (NativeF32Arr, fn)"))
  ; ("native_f32_arr_map2", VBuiltin ("native_f32_arr_map2", function
        | [VNativeF32Arr a; VNativeF32Arr b; f] ->
          let n = Array.length a in
          if Array.length b <> n then
            eval_error "native_f32_arr_map2: array length mismatch (%d vs %d)" n (Array.length b);
          let out = Array.make n 0.0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VFloat a.(i); VFloat b.(i)] with
             | VFloat v -> out.(i) <- f32_round v
             | v -> eval_error "native_f32_arr_map2: function returned non-Float: %s"
                      (value_to_string v))
          done;
          VNativeF32Arr out
        | _ -> eval_error "native_f32_arr_map2: expected (NativeF32Arr, NativeF32Arr, fn)"))
  ; ("native_f32_arr_fold", VBuiltin ("native_f32_arr_fold", function
        | [acc0; VNativeF32Arr a; f] ->
          let acc = ref acc0 in
          for i = 0 to Array.length a - 1 do
            acc := !apply_hook f [!acc; VFloat a.(i)]
          done;
          !acc
        | _ -> eval_error "native_f32_arr_fold: expected (init, NativeF32Arr, fn)"))
  ; ("native_f32_arr_from_list", VBuiltin ("native_f32_arr_from_list", function
        | [lst] ->
          let rec to_ocaml_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VFloat h; t]) -> h :: to_ocaml_list t
            | v -> eval_error "native_f32_arr_from_list: expected List(Float), got %s"
                     (value_to_string v)
          in
          VNativeF32Arr (Array.of_list (List.map f32_round (to_ocaml_list lst)))
        | _ -> eval_error "native_f32_arr_from_list: expected List(Float)"))
  ; ("native_f32_arr_to_list", VBuiltin ("native_f32_arr_to_list", function
        | [VNativeF32Arr a] ->
          Array.fold_right (fun x acc -> VCon ("Cons", [VFloat x; acc]))
            a (VCon ("Nil", []))
        | _ -> eval_error "native_f32_arr_to_list: expected NativeF32Arr"))

  (* i32 *)
  ; ("native_i32_arr_make", VBuiltin ("native_i32_arr_make", function
        | [VInt n; VInt init] ->
          if n < 0 then eval_error "native_i32_arr_make: negative size %d" n;
          VNativeI32Arr (Array.make n (i32_wrap init))
        | _ -> eval_error "native_i32_arr_make: expected (Int, Int)"))
  ; ("native_i32_arr_length", VBuiltin ("native_i32_arr_length", function
        | [VNativeI32Arr a] -> VInt (Array.length a)
        | _ -> eval_error "native_i32_arr_length: expected NativeI32Arr"))
  ; ("native_i32_arr_get", VBuiltin ("native_i32_arr_get", function
        | [VNativeI32Arr a; VInt i] ->
          if i < 0 || i >= Array.length a then
            eval_error "native_i32_arr_get: index %d out of bounds (len=%d)" i (Array.length a);
          VInt a.(i)
        | _ -> eval_error "native_i32_arr_get: expected (NativeI32Arr, Int)"))
  ; ("native_i32_arr_set", VBuiltin ("native_i32_arr_set", function
        | [VNativeI32Arr a; VInt i; VInt v] ->
          let n = Array.length a in
          if i < 0 || i >= n then
            eval_error "native_i32_arr_set: index %d out of bounds (len=%d)" i n;
          let a' = Array.copy a in
          a'.(i) <- i32_wrap v;
          VNativeI32Arr a'
        | _ -> eval_error "native_i32_arr_set: expected (NativeI32Arr, Int, Int)"))
  ; ("native_i32_arr_sum", VBuiltin ("native_i32_arr_sum", function
        | [VNativeI32Arr a] -> VInt (Array.fold_left (+) 0 a)
        | _ -> eval_error "native_i32_arr_sum: expected NativeI32Arr"))
  ; ("native_i32_arr_map", VBuiltin ("native_i32_arr_map", function
        | [VNativeI32Arr a; f] ->
          let n = Array.length a in
          let b = Array.make n 0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VInt a.(i)] with
             | VInt v -> b.(i) <- i32_wrap v
             | v -> eval_error "native_i32_arr_map: function returned non-Int: %s"
                      (value_to_string v))
          done;
          VNativeI32Arr b
        | _ -> eval_error "native_i32_arr_map: expected (NativeI32Arr, fn)"))
  ; ("native_i32_arr_map2", VBuiltin ("native_i32_arr_map2", function
        | [VNativeI32Arr a; VNativeI32Arr b; f] ->
          let n = Array.length a in
          if Array.length b <> n then
            eval_error "native_i32_arr_map2: array length mismatch (%d vs %d)" n (Array.length b);
          let out = Array.make n 0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VInt a.(i); VInt b.(i)] with
             | VInt v -> out.(i) <- i32_wrap v
             | v -> eval_error "native_i32_arr_map2: function returned non-Int: %s"
                      (value_to_string v))
          done;
          VNativeI32Arr out
        | _ -> eval_error "native_i32_arr_map2: expected (NativeI32Arr, NativeI32Arr, fn)"))
  ; ("native_i32_arr_fold", VBuiltin ("native_i32_arr_fold", function
        | [acc0; VNativeI32Arr a; f] ->
          let acc = ref acc0 in
          for i = 0 to Array.length a - 1 do
            acc := !apply_hook f [!acc; VInt a.(i)]
          done;
          !acc
        | _ -> eval_error "native_i32_arr_fold: expected (init, NativeI32Arr, fn)"))
  ; ("native_i32_arr_from_list", VBuiltin ("native_i32_arr_from_list", function
        | [lst] ->
          let rec to_ocaml_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VInt h; t]) -> h :: to_ocaml_list t
            | v -> eval_error "native_i32_arr_from_list: expected List(Int), got %s"
                     (value_to_string v)
          in
          VNativeI32Arr (Array.of_list (List.map i32_wrap (to_ocaml_list lst)))
        | _ -> eval_error "native_i32_arr_from_list: expected List(Int)"))
  ; ("native_i32_arr_to_list", VBuiltin ("native_i32_arr_to_list", function
        | [VNativeI32Arr a] ->
          Array.fold_right (fun x acc -> VCon ("Cons", [VInt x; acc]))
            a (VCon ("Nil", []))
        | _ -> eval_error "native_i32_arr_to_list: expected NativeI32Arr"))

  (* u8 *)
  ; ("native_u8_arr_make", VBuiltin ("native_u8_arr_make", function
        | [VInt n; VInt init] ->
          if n < 0 then eval_error "native_u8_arr_make: negative size %d" n;
          VNativeU8Arr (Array.make n (u8_wrap init))
        | _ -> eval_error "native_u8_arr_make: expected (Int, Int)"))
  ; ("native_u8_arr_length", VBuiltin ("native_u8_arr_length", function
        | [VNativeU8Arr a] -> VInt (Array.length a)
        | _ -> eval_error "native_u8_arr_length: expected NativeU8Arr"))
  ; ("native_u8_arr_get", VBuiltin ("native_u8_arr_get", function
        | [VNativeU8Arr a; VInt i] ->
          if i < 0 || i >= Array.length a then
            eval_error "native_u8_arr_get: index %d out of bounds (len=%d)" i (Array.length a);
          VInt a.(i)
        | _ -> eval_error "native_u8_arr_get: expected (NativeU8Arr, Int)"))
  ; ("native_u8_arr_set", VBuiltin ("native_u8_arr_set", function
        | [VNativeU8Arr a; VInt i; VInt v] ->
          let n = Array.length a in
          if i < 0 || i >= n then
            eval_error "native_u8_arr_set: index %d out of bounds (len=%d)" i n;
          let a' = Array.copy a in
          a'.(i) <- u8_wrap v;
          VNativeU8Arr a'
        | _ -> eval_error "native_u8_arr_set: expected (NativeU8Arr, Int, Int)"))
  ; ("native_u8_arr_sum", VBuiltin ("native_u8_arr_sum", function
        | [VNativeU8Arr a] -> VInt (Array.fold_left (+) 0 a)
        | _ -> eval_error "native_u8_arr_sum: expected NativeU8Arr"))
  ; ("native_u8_arr_map", VBuiltin ("native_u8_arr_map", function
        | [VNativeU8Arr a; f] ->
          let n = Array.length a in
          let b = Array.make n 0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VInt a.(i)] with
             | VInt v -> b.(i) <- u8_wrap v
             | v -> eval_error "native_u8_arr_map: function returned non-Int: %s"
                      (value_to_string v))
          done;
          VNativeU8Arr b
        | _ -> eval_error "native_u8_arr_map: expected (NativeU8Arr, fn)"))
  ; ("native_u8_arr_map2", VBuiltin ("native_u8_arr_map2", function
        | [VNativeU8Arr a; VNativeU8Arr b; f] ->
          let n = Array.length a in
          if Array.length b <> n then
            eval_error "native_u8_arr_map2: array length mismatch (%d vs %d)" n (Array.length b);
          let out = Array.make n 0 in
          for i = 0 to n - 1 do
            (match !apply_hook f [VInt a.(i); VInt b.(i)] with
             | VInt v -> out.(i) <- u8_wrap v
             | v -> eval_error "native_u8_arr_map2: function returned non-Int: %s"
                      (value_to_string v))
          done;
          VNativeU8Arr out
        | _ -> eval_error "native_u8_arr_map2: expected (NativeU8Arr, NativeU8Arr, fn)"))
  ; ("native_u8_arr_fold", VBuiltin ("native_u8_arr_fold", function
        | [acc0; VNativeU8Arr a; f] ->
          let acc = ref acc0 in
          for i = 0 to Array.length a - 1 do
            acc := !apply_hook f [!acc; VInt a.(i)]
          done;
          !acc
        | _ -> eval_error "native_u8_arr_fold: expected (init, NativeU8Arr, fn)"))
  ; ("native_u8_arr_from_list", VBuiltin ("native_u8_arr_from_list", function
        | [lst] ->
          let rec to_ocaml_list = function
            | VCon ("Nil", []) -> []
            | VCon ("Cons", [VInt h; t]) -> h :: to_ocaml_list t
            | v -> eval_error "native_u8_arr_from_list: expected List(Int), got %s"
                     (value_to_string v)
          in
          VNativeU8Arr (Array.of_list (List.map u8_wrap (to_ocaml_list lst)))
        | _ -> eval_error "native_u8_arr_from_list: expected List(Int)"))
  ; ("native_u8_arr_to_list", VBuiltin ("native_u8_arr_to_list", function
        | [VNativeU8Arr a] ->
          Array.fold_right (fun x acc -> VCon ("Cons", [VInt x; acc]))
            a (VCon ("Nil", []))
        | _ -> eval_error "native_u8_arr_to_list: expected NativeU8Arr"))

  (* Conversions — Array.map one-liners; destination narrowing applied,
     widening directions copy verbatim. *)
  ; ("native_float_to_f32_arr", VBuiltin ("native_float_to_f32_arr", function
        | [VNativeFloatArr a] -> VNativeF32Arr (Array.map f32_round a)
        | _ -> eval_error "native_float_to_f32_arr: expected NativeFloatArr"))
  ; ("native_f32_to_float_arr", VBuiltin ("native_f32_to_float_arr", function
        | [VNativeF32Arr a] -> VNativeFloatArr (Array.copy a)
        | _ -> eval_error "native_f32_to_float_arr: expected NativeF32Arr"))
  ; ("native_int_to_i32_arr", VBuiltin ("native_int_to_i32_arr", function
        | [VNativeIntArr a] -> VNativeI32Arr (Array.map i32_wrap a)
        | _ -> eval_error "native_int_to_i32_arr: expected NativeIntArr"))
  ; ("native_i32_to_int_arr", VBuiltin ("native_i32_to_int_arr", function
        | [VNativeI32Arr a] -> VNativeIntArr (Array.copy a)
        | _ -> eval_error "native_i32_to_int_arr: expected NativeI32Arr"))
  ; ("native_int_to_u8_arr", VBuiltin ("native_int_to_u8_arr", function
        | [VNativeIntArr a] -> VNativeU8Arr (Array.map u8_wrap a)
        | _ -> eval_error "native_int_to_u8_arr: expected NativeIntArr"))
  ; ("native_u8_to_int_arr", VBuiltin ("native_u8_to_int_arr", function
        | [VNativeU8Arr a] -> VNativeIntArr (Array.copy a)
        | _ -> eval_error "native_u8_to_int_arr: expected NativeU8Arr"))
  ; ("native_i32_to_f32_arr", VBuiltin ("native_i32_to_f32_arr", function
        | [VNativeI32Arr a] -> VNativeF32Arr (Array.map (fun v -> f32_round (float_of_int v)) a)
        | _ -> eval_error "native_i32_to_f32_arr: expected NativeI32Arr"))
  ; ("native_u8_to_f32_arr", VBuiltin ("native_u8_to_f32_arr", function
        | [VNativeU8Arr a] -> VNativeF32Arr (Array.map (fun v -> f32_round (float_of_int v)) a)
        | _ -> eval_error "native_u8_to_f32_arr: expected NativeU8Arr"))

  (* ── Simd — explicit 128-bit SIMD vector types (F32x4/F64x2/I32x4/I64x2/U8x16).
     127 builtins per the op grid in
     docs/superpowers/plans/2026-08-10-simd-vector-types.md (Global
     Constraints). Interpreter-path only here; compiled (LLVM) support is a
     later task. ── *)

  (* ── F32x4 ── *)
  ; ("simd_f32x4_splat", VBuiltin ("simd_f32x4_splat", function
        | [VFloat v] -> VF32x4 (Array.make 4 (f32_round v))
        | _ -> eval_error "simd_f32x4_splat: bad arguments"))
  ; ("simd_f32x4_make", VBuiltin ("simd_f32x4_make", function
        | [VFloat v0; VFloat v1; VFloat v2; VFloat v3] -> VF32x4 [| f32_round v0; f32_round v1; f32_round v2; f32_round v3 |]
        | _ -> eval_error "simd_f32x4_make: bad arguments"))
  ; ("simd_f32x4_extract", VBuiltin ("simd_f32x4_extract", function
        | [VF32x4 a; VInt i] ->
          if i < 0 || i >= 4 then
            eval_error "simd_f32x4_extract: lane %d out of range (0..3)" i;
          VFloat a.(i)
        | _ -> eval_error "simd_f32x4_extract: bad arguments"))
  ; ("simd_f32x4_replace", VBuiltin ("simd_f32x4_replace", function
        | [VF32x4 a; VInt i; VFloat x] ->
          if i < 0 || i >= 4 then
            eval_error "simd_f32x4_replace: lane %d out of range (0..3)" i;
          let a' = Array.copy a in
          a'.(i) <- f32_round x;
          VF32x4 a'
        | _ -> eval_error "simd_f32x4_replace: bad arguments"))
  ; ("simd_f32x4_load", VBuiltin ("simd_f32x4_load", function
        | [VNativeF32Arr arr; VInt i] ->
          simd_bounds_check "simd_f32x4_load" i 4 (Array.length arr);
          VF32x4 (Array.sub arr i 4)
        | _ -> eval_error "simd_f32x4_load: bad arguments"))
  ; ("simd_f32x4_store", VBuiltin ("simd_f32x4_store", function
        | [VNativeF32Arr arr; VInt i; VF32x4 v] ->
          simd_bounds_check "simd_f32x4_store" i 4 (Array.length arr);
          let arr' = Array.copy arr in
          Array.blit v 0 arr' i 4;
          VNativeF32Arr arr'
        | _ -> eval_error "simd_f32x4_store: bad arguments"))
  ; ("simd_f32x4_eq", VBuiltin ("simd_f32x4_eq", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> if a.(i) = b.(i) then simd_f32_allones else simd_f32_zero))
        | _ -> eval_error "simd_f32x4_eq: bad arguments"))
  ; ("simd_f32x4_lt", VBuiltin ("simd_f32x4_lt", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> if a.(i) < b.(i) then simd_f32_allones else simd_f32_zero))
        | _ -> eval_error "simd_f32x4_lt: bad arguments"))
  ; ("simd_f32x4_gt", VBuiltin ("simd_f32x4_gt", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> if a.(i) > b.(i) then simd_f32_allones else simd_f32_zero))
        | _ -> eval_error "simd_f32x4_gt: bad arguments"))
  ; ("simd_f32x4_and", VBuiltin ("simd_f32x4_and", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> simd_f32_and a.(i) b.(i)))
        | _ -> eval_error "simd_f32x4_and: bad arguments"))
  ; ("simd_f32x4_or", VBuiltin ("simd_f32x4_or", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> simd_f32_or a.(i) b.(i)))
        | _ -> eval_error "simd_f32x4_or: bad arguments"))
  ; ("simd_f32x4_xor", VBuiltin ("simd_f32x4_xor", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> simd_f32_xor a.(i) b.(i)))
        | _ -> eval_error "simd_f32x4_xor: bad arguments"))
  ; ("simd_f32x4_not", VBuiltin ("simd_f32x4_not", function
        | [VF32x4 a] -> VF32x4 (Array.map simd_f32_not a)
        | _ -> eval_error "simd_f32x4_not: bad arguments"))
  ; ("simd_f32x4_select", VBuiltin ("simd_f32x4_select", function
        | [VF32x4 m; VF32x4 a; VF32x4 b] ->
          VF32x4 (simd_select simd_f32_is_highbit m a b)
        | _ -> eval_error "simd_f32x4_select: bad arguments"))
  ; ("simd_f32x4_any", VBuiltin ("simd_f32x4_any", function
        | [VF32x4 a] -> VBool (simd_any simd_f32_is_highbit a)
        | _ -> eval_error "simd_f32x4_any: bad arguments"))
  ; ("simd_f32x4_all", VBuiltin ("simd_f32x4_all", function
        | [VF32x4 a] -> VBool (simd_all simd_f32_is_highbit a)
        | _ -> eval_error "simd_f32x4_all: bad arguments"))
  ; ("simd_f32x4_first_set", VBuiltin ("simd_f32x4_first_set", function
        | [VF32x4 a] -> VInt (simd_first_set simd_f32_is_highbit a)
        | _ -> eval_error "simd_f32x4_first_set: bad arguments"))
  ; ("simd_f32x4_add", VBuiltin ("simd_f32x4_add", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> f32_round (a.(i) +. b.(i))))
        | _ -> eval_error "simd_f32x4_add: bad arguments"))
  ; ("simd_f32x4_sub", VBuiltin ("simd_f32x4_sub", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> f32_round (a.(i) -. b.(i))))
        | _ -> eval_error "simd_f32x4_sub: bad arguments"))
  ; ("simd_f32x4_mul", VBuiltin ("simd_f32x4_mul", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> f32_round (a.(i) *. b.(i))))
        | _ -> eval_error "simd_f32x4_mul: bad arguments"))
  ; ("simd_f32x4_div", VBuiltin ("simd_f32x4_div", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> f32_round (a.(i) /. b.(i))))
        | _ -> eval_error "simd_f32x4_div: bad arguments"))
  ; ("simd_f32x4_min", VBuiltin ("simd_f32x4_min", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> f32_round (simd_minnum_f a.(i) b.(i))))
        | _ -> eval_error "simd_f32x4_min: bad arguments"))
  ; ("simd_f32x4_max", VBuiltin ("simd_f32x4_max", function
        | [VF32x4 a; VF32x4 b] ->
          VF32x4 (Array.init 4 (fun i -> f32_round (simd_maxnum_f a.(i) b.(i))))
        | _ -> eval_error "simd_f32x4_max: bad arguments"))
  (* f32x4 fma runs the SAME operation as the compiled path by construction:
     [fma32_single_round] is a single-rounded binary32 fused multiply-add
     (round-to-odd emulation; see its definition above), bit-identical to
     llvm_emit.ml's llvm.fma.v4f32. The old formula here,
     [f32_round (Float.fma a b c)], was binary64-fused then narrowed -- two
     roundings -- and diverged in the last ulp (~1 random triple in 20M);
     test t15 in test/test_stdlib_suite.ml pins the boundary triples and
     test/native/simd_fma_fuzz.march is the compiled-vs-interpreted fuzz.
     f64x2 below needs no emulation (Float.fma IS binary64-fused). *)
  ; ("simd_f32x4_fma", VBuiltin ("simd_f32x4_fma", function
        | [VF32x4 a; VF32x4 b; VF32x4 c] ->
          VF32x4 (Array.init 4 (fun i -> fma32_single_round a.(i) b.(i) c.(i)))
        | _ -> eval_error "simd_f32x4_fma: bad arguments"))
  ; ("simd_f32x4_sqrt", VBuiltin ("simd_f32x4_sqrt", function
        | [VF32x4 a] -> VF32x4 (Array.map (fun x -> f32_round (sqrt x)) a)
        | _ -> eval_error "simd_f32x4_sqrt: bad arguments"))
  ; ("simd_f32x4_sum", VBuiltin ("simd_f32x4_sum", function
        | [VF32x4 a] -> VFloat (Array.fold_left (+.) 0.0 a)
        | _ -> eval_error "simd_f32x4_sum: bad arguments"))
  ; ("simd_f32x4_hmin", VBuiltin ("simd_f32x4_hmin", function
        | [VF32x4 a] -> VFloat (simd_hfold simd_minnum_f a)
        | _ -> eval_error "simd_f32x4_hmin: bad arguments"))
  ; ("simd_f32x4_hmax", VBuiltin ("simd_f32x4_hmax", function
        | [VF32x4 a] -> VFloat (simd_hfold simd_maxnum_f a)
        | _ -> eval_error "simd_f32x4_hmax: bad arguments"))

  (* ── F64x2 ── *)
  ; ("simd_f64x2_splat", VBuiltin ("simd_f64x2_splat", function
        | [VFloat v] -> VF64x2 (Array.make 2 v)
        | _ -> eval_error "simd_f64x2_splat: bad arguments"))
  ; ("simd_f64x2_make", VBuiltin ("simd_f64x2_make", function
        | [VFloat v0; VFloat v1] -> VF64x2 [| v0; v1 |]
        | _ -> eval_error "simd_f64x2_make: bad arguments"))
  ; ("simd_f64x2_extract", VBuiltin ("simd_f64x2_extract", function
        | [VF64x2 a; VInt i] ->
          if i < 0 || i >= 2 then
            eval_error "simd_f64x2_extract: lane %d out of range (0..1)" i;
          VFloat a.(i)
        | _ -> eval_error "simd_f64x2_extract: bad arguments"))
  ; ("simd_f64x2_replace", VBuiltin ("simd_f64x2_replace", function
        | [VF64x2 a; VInt i; VFloat x] ->
          if i < 0 || i >= 2 then
            eval_error "simd_f64x2_replace: lane %d out of range (0..1)" i;
          let a' = Array.copy a in
          a'.(i) <- x;
          VF64x2 a'
        | _ -> eval_error "simd_f64x2_replace: bad arguments"))
  ; ("simd_f64x2_load", VBuiltin ("simd_f64x2_load", function
        | [VNativeFloatArr arr; VInt i] ->
          simd_bounds_check "simd_f64x2_load" i 2 (Array.length arr);
          VF64x2 (Array.sub arr i 2)
        | _ -> eval_error "simd_f64x2_load: bad arguments"))
  ; ("simd_f64x2_store", VBuiltin ("simd_f64x2_store", function
        | [VNativeFloatArr arr; VInt i; VF64x2 v] ->
          simd_bounds_check "simd_f64x2_store" i 2 (Array.length arr);
          let arr' = Array.copy arr in
          Array.blit v 0 arr' i 2;
          VNativeFloatArr arr'
        | _ -> eval_error "simd_f64x2_store: bad arguments"))
  ; ("simd_f64x2_eq", VBuiltin ("simd_f64x2_eq", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> if a.(i) = b.(i) then simd_f64_allones else simd_f64_zero))
        | _ -> eval_error "simd_f64x2_eq: bad arguments"))
  ; ("simd_f64x2_lt", VBuiltin ("simd_f64x2_lt", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> if a.(i) < b.(i) then simd_f64_allones else simd_f64_zero))
        | _ -> eval_error "simd_f64x2_lt: bad arguments"))
  ; ("simd_f64x2_gt", VBuiltin ("simd_f64x2_gt", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> if a.(i) > b.(i) then simd_f64_allones else simd_f64_zero))
        | _ -> eval_error "simd_f64x2_gt: bad arguments"))
  ; ("simd_f64x2_and", VBuiltin ("simd_f64x2_and", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> simd_f64_and a.(i) b.(i)))
        | _ -> eval_error "simd_f64x2_and: bad arguments"))
  ; ("simd_f64x2_or", VBuiltin ("simd_f64x2_or", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> simd_f64_or a.(i) b.(i)))
        | _ -> eval_error "simd_f64x2_or: bad arguments"))
  ; ("simd_f64x2_xor", VBuiltin ("simd_f64x2_xor", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> simd_f64_xor a.(i) b.(i)))
        | _ -> eval_error "simd_f64x2_xor: bad arguments"))
  ; ("simd_f64x2_not", VBuiltin ("simd_f64x2_not", function
        | [VF64x2 a] -> VF64x2 (Array.map simd_f64_not a)
        | _ -> eval_error "simd_f64x2_not: bad arguments"))
  ; ("simd_f64x2_select", VBuiltin ("simd_f64x2_select", function
        | [VF64x2 m; VF64x2 a; VF64x2 b] ->
          VF64x2 (simd_select simd_f64_is_highbit m a b)
        | _ -> eval_error "simd_f64x2_select: bad arguments"))
  ; ("simd_f64x2_any", VBuiltin ("simd_f64x2_any", function
        | [VF64x2 a] -> VBool (simd_any simd_f64_is_highbit a)
        | _ -> eval_error "simd_f64x2_any: bad arguments"))
  ; ("simd_f64x2_all", VBuiltin ("simd_f64x2_all", function
        | [VF64x2 a] -> VBool (simd_all simd_f64_is_highbit a)
        | _ -> eval_error "simd_f64x2_all: bad arguments"))
  ; ("simd_f64x2_first_set", VBuiltin ("simd_f64x2_first_set", function
        | [VF64x2 a] -> VInt (simd_first_set simd_f64_is_highbit a)
        | _ -> eval_error "simd_f64x2_first_set: bad arguments"))
  ; ("simd_f64x2_add", VBuiltin ("simd_f64x2_add", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> a.(i) +. b.(i)))
        | _ -> eval_error "simd_f64x2_add: bad arguments"))
  ; ("simd_f64x2_sub", VBuiltin ("simd_f64x2_sub", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> a.(i) -. b.(i)))
        | _ -> eval_error "simd_f64x2_sub: bad arguments"))
  ; ("simd_f64x2_mul", VBuiltin ("simd_f64x2_mul", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> a.(i) *. b.(i)))
        | _ -> eval_error "simd_f64x2_mul: bad arguments"))
  ; ("simd_f64x2_div", VBuiltin ("simd_f64x2_div", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> a.(i) /. b.(i)))
        | _ -> eval_error "simd_f64x2_div: bad arguments"))
  ; ("simd_f64x2_min", VBuiltin ("simd_f64x2_min", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> simd_minnum_f a.(i) b.(i)))
        | _ -> eval_error "simd_f64x2_min: bad arguments"))
  ; ("simd_f64x2_max", VBuiltin ("simd_f64x2_max", function
        | [VF64x2 a; VF64x2 b] ->
          VF64x2 (Array.init 2 (fun i -> simd_maxnum_f a.(i) b.(i)))
        | _ -> eval_error "simd_f64x2_max: bad arguments"))
  ; ("simd_f64x2_fma", VBuiltin ("simd_f64x2_fma", function
        | [VF64x2 a; VF64x2 b; VF64x2 c] ->
          VF64x2 (Array.init 2 (fun i -> Float.fma a.(i) b.(i) c.(i)))
        | _ -> eval_error "simd_f64x2_fma: bad arguments"))
  ; ("simd_f64x2_sqrt", VBuiltin ("simd_f64x2_sqrt", function
        | [VF64x2 a] -> VF64x2 (Array.map (fun x -> sqrt x) a)
        | _ -> eval_error "simd_f64x2_sqrt: bad arguments"))
  ; ("simd_f64x2_sum", VBuiltin ("simd_f64x2_sum", function
        | [VF64x2 a] -> VFloat (Array.fold_left (+.) 0.0 a)
        | _ -> eval_error "simd_f64x2_sum: bad arguments"))
  ; ("simd_f64x2_hmin", VBuiltin ("simd_f64x2_hmin", function
        | [VF64x2 a] -> VFloat (simd_hfold simd_minnum_f a)
        | _ -> eval_error "simd_f64x2_hmin: bad arguments"))
  ; ("simd_f64x2_hmax", VBuiltin ("simd_f64x2_hmax", function
        | [VF64x2 a] -> VFloat (simd_hfold simd_maxnum_f a)
        | _ -> eval_error "simd_f64x2_hmax: bad arguments"))

  (* ── I32x4 ── *)
  ; ("simd_i32x4_splat", VBuiltin ("simd_i32x4_splat", function
        | [VInt v] -> VI32x4 (Array.make 4 (i32_wrap v))
        | _ -> eval_error "simd_i32x4_splat: bad arguments"))
  ; ("simd_i32x4_make", VBuiltin ("simd_i32x4_make", function
        | [VInt v0; VInt v1; VInt v2; VInt v3] -> VI32x4 [| i32_wrap v0; i32_wrap v1; i32_wrap v2; i32_wrap v3 |]
        | _ -> eval_error "simd_i32x4_make: bad arguments"))
  ; ("simd_i32x4_extract", VBuiltin ("simd_i32x4_extract", function
        | [VI32x4 a; VInt i] ->
          if i < 0 || i >= 4 then
            eval_error "simd_i32x4_extract: lane %d out of range (0..3)" i;
          VInt a.(i)
        | _ -> eval_error "simd_i32x4_extract: bad arguments"))
  ; ("simd_i32x4_replace", VBuiltin ("simd_i32x4_replace", function
        | [VI32x4 a; VInt i; VInt x] ->
          if i < 0 || i >= 4 then
            eval_error "simd_i32x4_replace: lane %d out of range (0..3)" i;
          let a' = Array.copy a in
          a'.(i) <- i32_wrap x;
          VI32x4 a'
        | _ -> eval_error "simd_i32x4_replace: bad arguments"))
  ; ("simd_i32x4_load", VBuiltin ("simd_i32x4_load", function
        | [VNativeI32Arr arr; VInt i] ->
          simd_bounds_check "simd_i32x4_load" i 4 (Array.length arr);
          VI32x4 (Array.sub arr i 4)
        | _ -> eval_error "simd_i32x4_load: bad arguments"))
  ; ("simd_i32x4_store", VBuiltin ("simd_i32x4_store", function
        | [VNativeI32Arr arr; VInt i; VI32x4 v] ->
          simd_bounds_check "simd_i32x4_store" i 4 (Array.length arr);
          let arr' = Array.copy arr in
          Array.blit v 0 arr' i 4;
          VNativeI32Arr arr'
        | _ -> eval_error "simd_i32x4_store: bad arguments"))
  ; ("simd_i32x4_eq", VBuiltin ("simd_i32x4_eq", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> if a.(i) = b.(i) then -1 else 0))
        | _ -> eval_error "simd_i32x4_eq: bad arguments"))
  ; ("simd_i32x4_lt", VBuiltin ("simd_i32x4_lt", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> if a.(i) < b.(i) then -1 else 0))
        | _ -> eval_error "simd_i32x4_lt: bad arguments"))
  ; ("simd_i32x4_gt", VBuiltin ("simd_i32x4_gt", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> if a.(i) > b.(i) then -1 else 0))
        | _ -> eval_error "simd_i32x4_gt: bad arguments"))
  ; ("simd_i32x4_and", VBuiltin ("simd_i32x4_and", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> i32_wrap (a.(i) land b.(i))))
        | _ -> eval_error "simd_i32x4_and: bad arguments"))
  ; ("simd_i32x4_or", VBuiltin ("simd_i32x4_or", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> i32_wrap (a.(i) lor b.(i))))
        | _ -> eval_error "simd_i32x4_or: bad arguments"))
  ; ("simd_i32x4_xor", VBuiltin ("simd_i32x4_xor", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> i32_wrap (a.(i) lxor b.(i))))
        | _ -> eval_error "simd_i32x4_xor: bad arguments"))
  ; ("simd_i32x4_not", VBuiltin ("simd_i32x4_not", function
        | [VI32x4 a] -> VI32x4 (Array.map (fun x -> i32_wrap (lnot x)) a)
        | _ -> eval_error "simd_i32x4_not: bad arguments"))
  ; ("simd_i32x4_select", VBuiltin ("simd_i32x4_select", function
        | [VI32x4 m; VI32x4 a; VI32x4 b] ->
          VI32x4 (simd_select simd_i32_is_highbit m a b)
        | _ -> eval_error "simd_i32x4_select: bad arguments"))
  ; ("simd_i32x4_any", VBuiltin ("simd_i32x4_any", function
        | [VI32x4 a] -> VBool (simd_any simd_i32_is_highbit a)
        | _ -> eval_error "simd_i32x4_any: bad arguments"))
  ; ("simd_i32x4_all", VBuiltin ("simd_i32x4_all", function
        | [VI32x4 a] -> VBool (simd_all simd_i32_is_highbit a)
        | _ -> eval_error "simd_i32x4_all: bad arguments"))
  ; ("simd_i32x4_first_set", VBuiltin ("simd_i32x4_first_set", function
        | [VI32x4 a] -> VInt (simd_first_set simd_i32_is_highbit a)
        | _ -> eval_error "simd_i32x4_first_set: bad arguments"))
  ; ("simd_i32x4_add", VBuiltin ("simd_i32x4_add", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> i32_wrap (a.(i) + b.(i))))
        | _ -> eval_error "simd_i32x4_add: bad arguments"))
  ; ("simd_i32x4_sub", VBuiltin ("simd_i32x4_sub", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> i32_wrap (a.(i) - b.(i))))
        | _ -> eval_error "simd_i32x4_sub: bad arguments"))
  ; ("simd_i32x4_mul", VBuiltin ("simd_i32x4_mul", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> i32_wrap (a.(i) * b.(i))))
        | _ -> eval_error "simd_i32x4_mul: bad arguments"))
  ; ("simd_i32x4_min", VBuiltin ("simd_i32x4_min", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> Stdlib.min a.(i) b.(i)))
        | _ -> eval_error "simd_i32x4_min: bad arguments"))
  ; ("simd_i32x4_max", VBuiltin ("simd_i32x4_max", function
        | [VI32x4 a; VI32x4 b] ->
          VI32x4 (Array.init 4 (fun i -> Stdlib.max a.(i) b.(i)))
        | _ -> eval_error "simd_i32x4_max: bad arguments"))
  ; ("simd_i32x4_shl", VBuiltin ("simd_i32x4_shl", function
        | [VI32x4 a; VInt n] ->
          let cnt = n land 31 in
          VI32x4 (Array.map (fun x -> i32_wrap (x lsl cnt)) a)
        | _ -> eval_error "simd_i32x4_shl: bad arguments"))
  ; ("simd_i32x4_shr", VBuiltin ("simd_i32x4_shr", function
        | [VI32x4 a; VInt n] ->
          let cnt = n land 31 in
          VI32x4 (Array.map (fun x -> i32_wrap (x asr cnt)) a)
        | _ -> eval_error "simd_i32x4_shr: bad arguments"))
  ; ("simd_i32x4_sum", VBuiltin ("simd_i32x4_sum", function
        | [VI32x4 a] -> VInt (Array.fold_left (+) 0 a)
        | _ -> eval_error "simd_i32x4_sum: bad arguments"))
  ; ("simd_i32x4_hmin", VBuiltin ("simd_i32x4_hmin", function
        | [VI32x4 a] -> VInt (simd_hfold Stdlib.min a)
        | _ -> eval_error "simd_i32x4_hmin: bad arguments"))
  ; ("simd_i32x4_hmax", VBuiltin ("simd_i32x4_hmax", function
        | [VI32x4 a] -> VInt (simd_hfold Stdlib.max a)
        | _ -> eval_error "simd_i32x4_hmax: bad arguments"))

  (* ── I64x2 ── *)
  ; ("simd_i64x2_splat", VBuiltin ("simd_i64x2_splat", function
        | [VInt v] -> VI64x2 (Array.make 2 (Int64.of_int v))
        | _ -> eval_error "simd_i64x2_splat: bad arguments"))
  ; ("simd_i64x2_make", VBuiltin ("simd_i64x2_make", function
        | [VInt v0; VInt v1] -> VI64x2 [| Int64.of_int v0; Int64.of_int v1 |]
        | _ -> eval_error "simd_i64x2_make: bad arguments"))
  ; ("simd_i64x2_extract", VBuiltin ("simd_i64x2_extract", function
        | [VI64x2 a; VInt i] ->
          if i < 0 || i >= 2 then
            eval_error "simd_i64x2_extract: lane %d out of range (0..1)" i;
          VInt (Int64.to_int a.(i))
        | _ -> eval_error "simd_i64x2_extract: bad arguments"))
  ; ("simd_i64x2_replace", VBuiltin ("simd_i64x2_replace", function
        | [VI64x2 a; VInt i; VInt x] ->
          if i < 0 || i >= 2 then
            eval_error "simd_i64x2_replace: lane %d out of range (0..1)" i;
          let a' = Array.copy a in
          a'.(i) <- Int64.of_int x;
          VI64x2 a'
        | _ -> eval_error "simd_i64x2_replace: bad arguments"))
  ; ("simd_i64x2_load", VBuiltin ("simd_i64x2_load", function
        | [VNativeIntArr arr; VInt i] ->
          simd_bounds_check "simd_i64x2_load" i 2 (Array.length arr);
          VI64x2 (Array.init 2 (fun k -> Int64.of_int arr.(i + k)))
        | _ -> eval_error "simd_i64x2_load: bad arguments"))
  ; ("simd_i64x2_store", VBuiltin ("simd_i64x2_store", function
        | [VNativeIntArr arr; VInt i; VI64x2 v] ->
          simd_bounds_check "simd_i64x2_store" i 2 (Array.length arr);
          let arr' = Array.copy arr in
          for k = 0 to 2 - 1 do arr'.(i + k) <- Int64.to_int v.(k) done;
          VNativeIntArr arr'
        | _ -> eval_error "simd_i64x2_store: bad arguments"))
  ; ("simd_i64x2_eq", VBuiltin ("simd_i64x2_eq", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> if Int64.equal a.(i) b.(i) then -1L else 0L))
        | _ -> eval_error "simd_i64x2_eq: bad arguments"))
  ; ("simd_i64x2_lt", VBuiltin ("simd_i64x2_lt", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> if Int64.compare a.(i) b.(i) < 0 then -1L else 0L))
        | _ -> eval_error "simd_i64x2_lt: bad arguments"))
  ; ("simd_i64x2_gt", VBuiltin ("simd_i64x2_gt", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> if Int64.compare a.(i) b.(i) > 0 then -1L else 0L))
        | _ -> eval_error "simd_i64x2_gt: bad arguments"))
  ; ("simd_i64x2_and", VBuiltin ("simd_i64x2_and", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> Int64.logand a.(i) b.(i)))
        | _ -> eval_error "simd_i64x2_and: bad arguments"))
  ; ("simd_i64x2_or", VBuiltin ("simd_i64x2_or", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> Int64.logor a.(i) b.(i)))
        | _ -> eval_error "simd_i64x2_or: bad arguments"))
  ; ("simd_i64x2_xor", VBuiltin ("simd_i64x2_xor", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> Int64.logxor a.(i) b.(i)))
        | _ -> eval_error "simd_i64x2_xor: bad arguments"))
  ; ("simd_i64x2_not", VBuiltin ("simd_i64x2_not", function
        | [VI64x2 a] -> VI64x2 (Array.map Int64.lognot a)
        | _ -> eval_error "simd_i64x2_not: bad arguments"))
  ; ("simd_i64x2_select", VBuiltin ("simd_i64x2_select", function
        | [VI64x2 m; VI64x2 a; VI64x2 b] ->
          VI64x2 (simd_select simd_i64_is_highbit m a b)
        | _ -> eval_error "simd_i64x2_select: bad arguments"))
  ; ("simd_i64x2_any", VBuiltin ("simd_i64x2_any", function
        | [VI64x2 a] -> VBool (simd_any simd_i64_is_highbit a)
        | _ -> eval_error "simd_i64x2_any: bad arguments"))
  ; ("simd_i64x2_all", VBuiltin ("simd_i64x2_all", function
        | [VI64x2 a] -> VBool (simd_all simd_i64_is_highbit a)
        | _ -> eval_error "simd_i64x2_all: bad arguments"))
  ; ("simd_i64x2_first_set", VBuiltin ("simd_i64x2_first_set", function
        | [VI64x2 a] -> VInt (simd_first_set simd_i64_is_highbit a)
        | _ -> eval_error "simd_i64x2_first_set: bad arguments"))
  ; ("simd_i64x2_add", VBuiltin ("simd_i64x2_add", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> Int64.add a.(i) b.(i)))
        | _ -> eval_error "simd_i64x2_add: bad arguments"))
  ; ("simd_i64x2_sub", VBuiltin ("simd_i64x2_sub", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> Int64.sub a.(i) b.(i)))
        | _ -> eval_error "simd_i64x2_sub: bad arguments"))
  ; ("simd_i64x2_mul", VBuiltin ("simd_i64x2_mul", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> Int64.mul a.(i) b.(i)))
        | _ -> eval_error "simd_i64x2_mul: bad arguments"))
  ; ("simd_i64x2_min", VBuiltin ("simd_i64x2_min", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> if Int64.compare a.(i) b.(i) <= 0 then a.(i) else b.(i)))
        | _ -> eval_error "simd_i64x2_min: bad arguments"))
  ; ("simd_i64x2_max", VBuiltin ("simd_i64x2_max", function
        | [VI64x2 a; VI64x2 b] ->
          VI64x2 (Array.init 2 (fun i -> if Int64.compare a.(i) b.(i) >= 0 then a.(i) else b.(i)))
        | _ -> eval_error "simd_i64x2_max: bad arguments"))
  ; ("simd_i64x2_shl", VBuiltin ("simd_i64x2_shl", function
        | [VI64x2 a; VInt n] ->
          let cnt = n land 63 in
          VI64x2 (Array.map (fun x -> Int64.shift_left x cnt) a)
        | _ -> eval_error "simd_i64x2_shl: bad arguments"))
  ; ("simd_i64x2_shr", VBuiltin ("simd_i64x2_shr", function
        | [VI64x2 a; VInt n] ->
          let cnt = n land 63 in
          VI64x2 (Array.map (fun x -> Int64.shift_right x cnt) a)
        | _ -> eval_error "simd_i64x2_shr: bad arguments"))
  ; ("simd_i64x2_sum", VBuiltin ("simd_i64x2_sum", function
        | [VI64x2 a] -> VInt (Int64.to_int (Array.fold_left Int64.add 0L a))
        | _ -> eval_error "simd_i64x2_sum: bad arguments"))
  ; ("simd_i64x2_hmin", VBuiltin ("simd_i64x2_hmin", function
        | [VI64x2 a] -> VInt (Int64.to_int (simd_hfold (fun x y -> if Int64.compare x y <= 0 then x else y) a))
        | _ -> eval_error "simd_i64x2_hmin: bad arguments"))
  ; ("simd_i64x2_hmax", VBuiltin ("simd_i64x2_hmax", function
        | [VI64x2 a] -> VInt (Int64.to_int (simd_hfold (fun x y -> if Int64.compare x y >= 0 then x else y) a))
        | _ -> eval_error "simd_i64x2_hmax: bad arguments"))

  (* ── U8x16 ── *)
  ; ("simd_u8x16_splat", VBuiltin ("simd_u8x16_splat", function
        | [VInt v] -> VU8x16 (Array.make 16 (u8_wrap v))
        | _ -> eval_error "simd_u8x16_splat: bad arguments"))
  ; ("simd_u8x16_make", VBuiltin ("simd_u8x16_make", function
        | [VInt v0; VInt v1; VInt v2; VInt v3; VInt v4; VInt v5; VInt v6; VInt v7; VInt v8; VInt v9; VInt v10; VInt v11; VInt v12; VInt v13; VInt v14; VInt v15] -> VU8x16 [| u8_wrap v0; u8_wrap v1; u8_wrap v2; u8_wrap v3; u8_wrap v4; u8_wrap v5; u8_wrap v6; u8_wrap v7; u8_wrap v8; u8_wrap v9; u8_wrap v10; u8_wrap v11; u8_wrap v12; u8_wrap v13; u8_wrap v14; u8_wrap v15 |]
        | _ -> eval_error "simd_u8x16_make: bad arguments"))
  ; ("simd_u8x16_extract", VBuiltin ("simd_u8x16_extract", function
        | [VU8x16 a; VInt i] ->
          if i < 0 || i >= 16 then
            eval_error "simd_u8x16_extract: lane %d out of range (0..15)" i;
          VInt a.(i)
        | _ -> eval_error "simd_u8x16_extract: bad arguments"))
  ; ("simd_u8x16_replace", VBuiltin ("simd_u8x16_replace", function
        | [VU8x16 a; VInt i; VInt x] ->
          if i < 0 || i >= 16 then
            eval_error "simd_u8x16_replace: lane %d out of range (0..15)" i;
          let a' = Array.copy a in
          a'.(i) <- u8_wrap x;
          VU8x16 a'
        | _ -> eval_error "simd_u8x16_replace: bad arguments"))
  ; ("simd_u8x16_load", VBuiltin ("simd_u8x16_load", function
        | [VNativeU8Arr arr; VInt i] ->
          simd_bounds_check "simd_u8x16_load" i 16 (Array.length arr);
          VU8x16 (Array.sub arr i 16)
        | _ -> eval_error "simd_u8x16_load: bad arguments"))
  ; ("simd_u8x16_store", VBuiltin ("simd_u8x16_store", function
        | [VNativeU8Arr arr; VInt i; VU8x16 v] ->
          simd_bounds_check "simd_u8x16_store" i 16 (Array.length arr);
          let arr' = Array.copy arr in
          Array.blit v 0 arr' i 16;
          VNativeU8Arr arr'
        | _ -> eval_error "simd_u8x16_store: bad arguments"))
  ; ("simd_u8x16_eq", VBuiltin ("simd_u8x16_eq", function
        | [VU8x16 a; VU8x16 b] ->
          VU8x16 (Array.init 16 (fun i -> if a.(i) = b.(i) then 255 else 0))
        | _ -> eval_error "simd_u8x16_eq: bad arguments"))
  ; ("simd_u8x16_lt", VBuiltin ("simd_u8x16_lt", function
        | [VU8x16 a; VU8x16 b] ->
          VU8x16 (Array.init 16 (fun i -> if a.(i) < b.(i) then 255 else 0))
        | _ -> eval_error "simd_u8x16_lt: bad arguments"))
  ; ("simd_u8x16_gt", VBuiltin ("simd_u8x16_gt", function
        | [VU8x16 a; VU8x16 b] ->
          VU8x16 (Array.init 16 (fun i -> if a.(i) > b.(i) then 255 else 0))
        | _ -> eval_error "simd_u8x16_gt: bad arguments"))
  ; ("simd_u8x16_and", VBuiltin ("simd_u8x16_and", function
        | [VU8x16 a; VU8x16 b] ->
          VU8x16 (Array.init 16 (fun i -> u8_wrap (a.(i) land b.(i))))
        | _ -> eval_error "simd_u8x16_and: bad arguments"))
  ; ("simd_u8x16_or", VBuiltin ("simd_u8x16_or", function
        | [VU8x16 a; VU8x16 b] ->
          VU8x16 (Array.init 16 (fun i -> u8_wrap (a.(i) lor b.(i))))
        | _ -> eval_error "simd_u8x16_or: bad arguments"))
  ; ("simd_u8x16_xor", VBuiltin ("simd_u8x16_xor", function
        | [VU8x16 a; VU8x16 b] ->
          VU8x16 (Array.init 16 (fun i -> u8_wrap (a.(i) lxor b.(i))))
        | _ -> eval_error "simd_u8x16_xor: bad arguments"))
  ; ("simd_u8x16_not", VBuiltin ("simd_u8x16_not", function
        | [VU8x16 a] -> VU8x16 (Array.map (fun x -> u8_wrap (lnot x)) a)
        | _ -> eval_error "simd_u8x16_not: bad arguments"))
  ; ("simd_u8x16_select", VBuiltin ("simd_u8x16_select", function
        | [VU8x16 m; VU8x16 a; VU8x16 b] ->
          VU8x16 (simd_select simd_u8_is_highbit m a b)
        | _ -> eval_error "simd_u8x16_select: bad arguments"))
  ; ("simd_u8x16_any", VBuiltin ("simd_u8x16_any", function
        | [VU8x16 a] -> VBool (simd_any simd_u8_is_highbit a)
        | _ -> eval_error "simd_u8x16_any: bad arguments"))
  ; ("simd_u8x16_all", VBuiltin ("simd_u8x16_all", function
        | [VU8x16 a] -> VBool (simd_all simd_u8_is_highbit a)
        | _ -> eval_error "simd_u8x16_all: bad arguments"))
  ; ("simd_u8x16_first_set", VBuiltin ("simd_u8x16_first_set", function
        | [VU8x16 a] -> VInt (simd_first_set simd_u8_is_highbit a)
        | _ -> eval_error "simd_u8x16_first_set: bad arguments"))

  (* ── TypedArray builtins — contiguous native arrays for columnar DataFrame storage ── *)
  (* typed_array_create(length, default) → TypedArray filled with default value *)
  ; ("typed_array_create", VBuiltin ("typed_array_create", function
        | [VInt n; default] when n >= 0 -> VTypedArray (Array.make n default)
        | [VInt _; _] -> eval_error "typed_array_create: length must be non-negative"
        | _ -> eval_error "typed_array_create: expected (Int, value)"))
  (* typed_array_get(arr, index) → O(1) element access *)
  ; ("typed_array_get", VBuiltin ("typed_array_get", function
        | [VTypedArray arr; VInt i] ->
          if i >= 0 && i < Array.length arr then arr.(i)
          else eval_error "typed_array_get: index %d out of bounds (length %d)" i (Array.length arr)
        | _ -> eval_error "typed_array_get: expected (TypedArray, Int)"))
  (* typed_array_set(arr, index, value) → returns new array with element replaced (functional) *)
  ; ("typed_array_set", VBuiltin ("typed_array_set", function
        | [VTypedArray arr; VInt i; v] ->
          if i >= 0 && i < Array.length arr then begin
            let arr2 = Array.copy arr in
            arr2.(i) <- v;
            VTypedArray arr2
          end else eval_error "typed_array_set: index %d out of bounds (length %d)" i (Array.length arr)
        | _ -> eval_error "typed_array_set: expected (TypedArray, Int, value)"))
  (* typed_array_length(arr) → Int *)
  ; ("typed_array_length", VBuiltin ("typed_array_length", function
        | [VTypedArray arr] -> VInt (Array.length arr)
        | _ -> eval_error "typed_array_length: expected TypedArray"))
  (* typed_array_slice(arr, start, len) → sub-array copy *)
  ; ("typed_array_slice", VBuiltin ("typed_array_slice", function
        | [VTypedArray arr; VInt start; VInt len] ->
          let alen = Array.length arr in
          let s = max 0 (min start alen) in
          let e = max s (min (s + len) alen) in
          VTypedArray (Array.sub arr s (e - s))
        | _ -> eval_error "typed_array_slice: expected (TypedArray, Int, Int)"))
  (* typed_array_map(arr, fn) → new TypedArray with fn applied to each element *)
  ; ("typed_array_map", VBuiltin ("typed_array_map", function
        | [VTypedArray arr; f] ->
          VTypedArray (Array.map (fun v -> !apply_hook f [v]) arr)
        | _ -> eval_error "typed_array_map: expected (TypedArray, fn)"))
  (* typed_array_filter(arr, bool_arr) → new TypedArray keeping elements where bool_arr is true *)
  ; ("typed_array_filter", VBuiltin ("typed_array_filter", function
        | [VTypedArray arr; VTypedArray mask] ->
          let n = Array.length arr in
          if n <> Array.length mask then
            eval_error "typed_array_filter: array length %d != mask length %d" n (Array.length mask);
          let kept = Array.to_seq arr
            |> Seq.zip (Array.to_seq mask)
            |> Seq.filter (fun (b, _) -> b = VBool true)
            |> Seq.map snd
            |> Array.of_seq in
          VTypedArray kept
        | _ -> eval_error "typed_array_filter: expected (TypedArray, TypedArray)"))
  (* typed_array_fold(arr, init, fn) → fold left: fn(acc, elem) → new_acc *)
  ; ("typed_array_fold", VBuiltin ("typed_array_fold", function
        | [VTypedArray arr; init; f] ->
          Array.fold_left (fun acc v -> !apply_hook f [acc; v]) init arr
        | _ -> eval_error "typed_array_fold: expected (TypedArray, value, fn)"))
  (* typed_array_from_list(list) → TypedArray *)
  ; ("typed_array_from_list", VBuiltin ("typed_array_from_list", function
        | [lst] ->
          let rec to_ocaml_list acc = function
            | VCon ("Nil", []) -> List.rev acc
            | VCon ("Cons", [h; t]) -> to_ocaml_list (h :: acc) t
            | _ -> eval_error "typed_array_from_list: expected a List"
          in
          VTypedArray (Array.of_list (to_ocaml_list [] lst))
        | _ -> eval_error "typed_array_from_list: expected one list argument"))
  (* typed_array_to_list(arr) → List *)
  ; ("typed_array_to_list", VBuiltin ("typed_array_to_list", function
        | [VTypedArray arr] ->
          Array.fold_right (fun v acc -> VCon ("Cons", [v; acc]))
            arr (VCon ("Nil", []))
        | _ -> eval_error "typed_array_to_list: expected TypedArray"))
  (* ---- Distributed OTP L4 — remote registry builtins ---- *)
  (* remote_ref_hashes(module, fn) → (sig_hash, impl_hash)
     Eval-path: returns deterministic FNV-1a hashes of the qualified name so
     that eval tests can exercise the full RemoteRef pipeline without the CAS
     pipeline. The compiled path constant-folds this to the real CAS hashes. *)
  ; ("remote_ref_hashes", VBuiltin ("remote_ref_hashes", function
        | [VString mod_name; VString fn_name] ->
          let fnv1a s =
            let h = ref 0xcbf29ce484222325L in
            String.iter (fun c ->
              h := Int64.logxor !h (Int64.of_int (Char.code c));
              h := Int64.mul !h 0x100000001b3L) s;
            Printf.sprintf "%016Lx%016Lx" !h (Int64.lognot !h) in
          let key = mod_name ^ "." ^ fn_name in
          VTuple [VString (fnv1a (key ^ ".sig")); VString (fnv1a (key ^ ".impl"))]
        | _ -> eval_error "remote_ref_hashes: expected (String, String)"))
  (* remote_register_stub(impl_hash, sig_hash, stub) → Int
     Eval-path: no-op returning 0 (stubs are not needed in the interpreter).
     The compiled path delegates to march_remote_register via mangle_extern. *)
  ; ("remote_register_stub", VBuiltin ("remote_register_stub", function
        | [VString _impl; VString _sig; _stub] -> VInt 0
        | _ -> eval_error "remote_register_stub: expected (String, String, stub)"))
  (* remote_count() → Int  — number of enrolled remote targets.
     Eval-path: always 0 (no C registry in the interpreter). *)
  ; ("remote_count", VBuiltin ("remote_count", function
        | [] | [VUnit] -> VInt 0
        | _ -> eval_error "remote_count: no arguments expected"))
  (* remote_check(impl_hash, sig_hash) → Int  — admission check against the remote
     registry: 0 = NoTarget (not enrolled), 1 = sig match, 2 = TypeMismatch.
     Eval-path: the interpreter has no registry (remote_register_stub is a no-op),
     so nothing is ever enrolled → always 0/NoTarget.  This matches the compiled
     path's march_remote_check_march on an empty registry.  Real RPC dispatch is
     exercised through the injected Targets table, not this C-registry fallback. *)
  ; ("remote_check", VBuiltin ("remote_check", function
        | [VString _impl; VString _sig] -> VInt 0
        | _ -> eval_error "remote_check: expected (String, String)"))
  (* remote_invoke(impl_hash, args) → Option(Result(List(Int), String))
     Eval-path: empty registry → always None (no stub to call), consistent with
     remote_check returning NoTarget. *)
  ; ("remote_invoke", VBuiltin ("remote_invoke", function
        | [VString _impl; _args] -> VCon ("None", [])
        | _ -> eval_error "remote_invoke: expected (String, List(Int))"))
  (* ── RingBuf builtins — mutable fixed-capacity circular buffer ── *)
  (* Index convention: 0 = oldest (FIFO drain order). Single-owner — do not share
     across actor boundaries; the typechecker rejects RingBuf in send() payloads. *)
  ; ("ring_buf_make", VBuiltin ("ring_buf_make", function
        | [VInt cap] ->
          if cap <= 0 then eval_error "ring_buf_make: capacity must be > 0, got %d" cap;
          VRingBuf (ring_create cap)
        | _ -> eval_error "ring_buf_make: expected Int capacity"))
  ; ("ring_buf_push", VBuiltin ("ring_buf_push", function
        | [VRingBuf r; v] -> ring_push r v; VUnit
        | _ -> eval_error "ring_buf_push: expected (RingBuf, value)"))
  ; ("ring_buf_pop", VBuiltin ("ring_buf_pop", function
        | [VRingBuf r] ->
          (match ring_pop_oldest r with
           | None   -> VCon ("None", [])
           | Some v -> VCon ("Some", [v]))
        | _ -> eval_error "ring_buf_pop: expected RingBuf"))
  ; ("ring_buf_get", VBuiltin ("ring_buf_get", function
        (* get(rb, i): 0 = oldest. Translate to internal index (0 = newest). *)
        | [VRingBuf r; VInt i] ->
          (match ring_get r (r.rb_size - 1 - i) with
           | None   -> VCon ("None", [])
           | Some v -> VCon ("Some", [v]))
        | _ -> eval_error "ring_buf_get: expected (RingBuf, Int)"))
  ; ("ring_buf_peek_oldest", VBuiltin ("ring_buf_peek_oldest", function
        | [VRingBuf r] ->
          (match ring_get r (r.rb_size - 1) with
           | None   -> VCon ("None", [])
           | Some v -> VCon ("Some", [v]))
        | _ -> eval_error "ring_buf_peek_oldest: expected RingBuf"))
  ; ("ring_buf_peek_newest", VBuiltin ("ring_buf_peek_newest", function
        | [VRingBuf r] ->
          (match ring_get r 0 with
           | None   -> VCon ("None", [])
           | Some v -> VCon ("Some", [v]))
        | _ -> eval_error "ring_buf_peek_newest: expected RingBuf"))
  ; ("ring_buf_size", VBuiltin ("ring_buf_size", function
        | [VRingBuf r] -> VInt r.rb_size
        | _ -> eval_error "ring_buf_size: expected RingBuf"))
  ; ("ring_buf_cap", VBuiltin ("ring_buf_cap", function
        | [VRingBuf r] -> VInt r.rb_cap
        | _ -> eval_error "ring_buf_cap: expected RingBuf"))
  ; ("ring_buf_clear", VBuiltin ("ring_buf_clear", function
        | [VRingBuf r] -> r.rb_head <- 0; r.rb_size <- 0; VUnit
        | _ -> eval_error "ring_buf_clear: expected RingBuf"))
  ; ("ring_buf_to_list", VBuiltin ("ring_buf_to_list", function
        | [VRingBuf r] ->
          let n = r.rb_size in
          (* ring_get uses 0=newest. Iterate 0..n-1 with prepend → result is oldest-to-newest. *)
          let rec go i acc =
            if i >= n then acc
            else
              let v = match ring_get r i with Some x -> x | None -> assert false in
              go (i + 1) (VCon ("Cons", [v; acc]))
          in
          go 0 (VCon ("Nil", []))
        | _ -> eval_error "ring_buf_to_list: expected RingBuf"))
  ]
