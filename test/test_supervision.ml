(** Dedicated supervision tree tests for March.

    Covers:
    - Phase 1: monitors, links, Down/crash propagation
    - Phase 2: supervisor restart strategies (one_for_one, one_for_all, rest_for_one)
    - Phase 3: epoch-based capability staleness
    - Phase 5: task_spawn_link
    - New: epoch propagation across restarts, restart() builtin, nested supervisors

    These tests complement the supervision suite in test_march.ml with
    additional edge cases and the new epoch-propagation semantics. *)

(* ------------------------------------------------------------------ *)
(* Helpers shared with test_march.ml (duplicated to keep files standalone) *)
(* ------------------------------------------------------------------ *)

let dummy_actor_def = March_ast.Ast.{
  actor_state     = [];
  actor_init      = ELit (LitInt 0, March_ast.Ast.dummy_span);
  actor_handlers  = [];
  actor_supervise = None;
}

let mk_actor_inst name alive st = March_eval.Eval.{
  ai_name          = name;
  ai_def           = dummy_actor_def;
  ai_env_ref       = ref [];
  ai_state         = st;
  ai_alive         = alive;
  ai_monitors      = [];
  ai_links         = [];
  ai_mailbox       = Queue.create ();
  ai_supervisor    = None;
  ai_restart_count = [];
  ai_epoch         = 0;
  ai_resources     = [];
}

let add_fresh_actor pid name =
  let inst = mk_actor_inst name true March_eval.Eval.VUnit in
  Hashtbl.replace March_eval.Eval.actor_registry pid inst;
  inst

let parse_and_desugar src =
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
  March_desugar.Desugar.desugar_module m

let eval_module src =
  let m = parse_and_desugar src in
  March_eval.Eval.eval_module_env m

let call_fn env name args =
  let fn_val = List.assoc name env in
  March_eval.Eval.apply fn_val args

let with_reset f () =
  March_eval.Eval.reset_scheduler_state ();
  f ()

(** Read the VInt stored in a supervisor state field.
    Returns -1 if the actor/field is not found. *)
let sup_child_int sup_pid field_name =
  match Hashtbl.find_opt March_eval.Eval.actor_registry sup_pid with
  | None -> -1
  | Some inst ->
    (match inst.March_eval.Eval.ai_state with
     | March_eval.Eval.VRecord fields ->
       (match List.assoc_opt field_name fields with
        | Some (March_eval.Eval.VInt p) -> p
        | _ -> -1)
     | _ -> -1)

let is_alive pid =
  match Hashtbl.find_opt March_eval.Eval.actor_registry pid with
  | Some inst -> inst.March_eval.Eval.ai_alive
  | None -> false

(* ------------------------------------------------------------------ *)
(* Phase 1 — Monitors and Links                                        *)
(* ------------------------------------------------------------------ *)

(** Crash propagates through a chain: A → B → C via links. *)
let test_link_chain_propagation () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let _ib = add_fresh_actor 1 "B" in
  let _ic = add_fresh_actor 2 "C" in
  March_eval.Eval.link_actors 0 1;
  March_eval.Eval.link_actors 1 2;
  March_eval.Eval.crash_actor 0 "chain test";
  Alcotest.(check bool) "A dead" false (is_alive 0);
  Alcotest.(check bool) "B dead (linked to A)" false (is_alive 1);
  Alcotest.(check bool) "C dead (linked to B)" false (is_alive 2)

(** Monitor is independent from links: monitoring does not kill the watcher. *)
let test_monitor_does_not_kill_watcher () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let ib  = add_fresh_actor 1 "B" in
  let _   = March_eval.Eval.monitor_actor ~watcher_pid:1 ~target_pid:0 in
  March_eval.Eval.crash_actor 0 "target crashed";
  (* B got a Down message but did not die *)
  Alcotest.(check bool) "B still alive after A crash" true ib.March_eval.Eval.ai_alive;
  Alcotest.(check bool) "B mailbox has Down" true
    (not (Queue.is_empty ib.March_eval.Eval.ai_mailbox))

(** Multiple monitors on the same target all fire with distinct mon_refs. *)
let test_monitor_multiple_distinct_refs () =
  March_eval.Eval.reset_scheduler_state ();
  let _ia = add_fresh_actor 0 "A" in
  let ib  = add_fresh_actor 1 "B" in
  let ic  = add_fresh_actor 2 "C" in
  let m1 = March_eval.Eval.monitor_actor ~watcher_pid:1 ~target_pid:0 in
  let m2 = March_eval.Eval.monitor_actor ~watcher_pid:2 ~target_pid:0 in
  Alcotest.(check bool) "distinct monitor refs" true (m1 <> m2);
  March_eval.Eval.crash_actor 0 "killed";
  let b_msg = Queue.pop ib.March_eval.Eval.ai_mailbox in
  let c_msg = Queue.pop ic.March_eval.Eval.ai_mailbox in
  let ref_of = function
    | March_eval.Eval.VCon ("Down", [March_eval.Eval.VInt r; _]) -> r
    | _ -> -1
  in
  Alcotest.(check int) "B's Down has m1 ref" m1 (ref_of b_msg);
  Alcotest.(check int) "C's Down has m2 ref" m2 (ref_of c_msg)

(* ------------------------------------------------------------------ *)
(* Phase 2 — Supervisor Restart Strategies                             *)
(* ------------------------------------------------------------------ *)

(** one_for_one: new child has a different pid and is alive. *)
let test_one_for_one_basic () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        W w
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1 = sup_child_int sup "w" in
  Alcotest.(check bool) "child spawned" true (w1 >= 0);
  March_eval.Eval.crash_actor w1 "test";
  let w2 = sup_child_int sup "w" in
  Alcotest.(check bool) "new child has different pid" true (w2 <> w1);
  Alcotest.(check bool) "new child is alive" true (is_alive w2);
  Alcotest.(check bool) "old child is dead" false (is_alive w1)

(** one_for_one: sibling of crashed child keeps its pid. *)
let test_one_for_one_sibling_unchanged () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { wa : Int, wb : Int }
      init { wa = 0, wb = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        W wa
        W wb
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let wa1 = sup_child_int sup "wa" in
  let wb1 = sup_child_int sup "wb" in
  March_eval.Eval.crash_actor wa1 "test";
  let wb2 = sup_child_int sup "wb" in
  Alcotest.(check int) "sibling wb unchanged" wb1 wb2

(** one_for_all: all siblings get new pids when one crashes. *)
let test_one_for_all_restarts_all () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { wa : Int, wb : Int, wc : Int }
      init { wa = 0, wb = 0, wc = 0 }
      supervise do
        strategy one_for_all
        max_restarts 5 within 60
        W wa
        W wb
        W wc
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let wa1 = sup_child_int sup "wa" in
  let wb1 = sup_child_int sup "wb" in
  let wc1 = sup_child_int sup "wc" in
  March_eval.Eval.crash_actor wa1 "test";
  let wa2 = sup_child_int sup "wa" in
  let wb2 = sup_child_int sup "wb" in
  let wc2 = sup_child_int sup "wc" in
  Alcotest.(check bool) "wa restarted" true (wa2 <> wa1);
  Alcotest.(check bool) "wb restarted" true (wb2 <> wb1);
  Alcotest.(check bool) "wc restarted" true (wc2 <> wc1);
  Alcotest.(check bool) "all alive" true
    (is_alive wa2 && is_alive wb2 && is_alive wc2)

(** rest_for_one: first child unchanged; second and third restart. *)
let test_rest_for_one_downstream_only () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { r : Int, p : Int, wr : Int }
      init  { r = 0, p = 0, wr = 0 }
      supervise do
        strategy rest_for_one
        max_restarts 5 within 60
        W r
        W p
        W wr
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let r1  = sup_child_int sup "r" in
  let p1  = sup_child_int sup "p" in
  let w1  = sup_child_int sup "wr" in
  March_eval.Eval.crash_actor p1 "test";
  let r2  = sup_child_int sup "r" in
  let p2  = sup_child_int sup "p" in
  let w2  = sup_child_int sup "wr" in
  Alcotest.(check int)  "r unchanged"   r1 r2;
  Alcotest.(check bool) "p restarted"   true (p2 <> p1);
  Alcotest.(check bool) "wr restarted"  true (w2 <> w1);
  Alcotest.(check bool) "p alive"       true (is_alive p2);
  Alcotest.(check bool) "wr alive"      true (is_alive w2)

(** max_restarts: exceeding the limit crashes the supervisor. *)
let test_max_restarts_escalation () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w = 0 }
      supervise do
        strategy one_for_one
        max_restarts 2 within 60
        W w
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1 = sup_child_int sup "w" in
  March_eval.Eval.crash_actor w1 "kill 1";
  let w2 = sup_child_int sup "w" in
  March_eval.Eval.crash_actor w2 "kill 2";
  let w3 = sup_child_int sup "w" in
  March_eval.Eval.crash_actor w3 "kill 3";  (* exceeds max_restarts=2 *)
  Alcotest.(check bool) "supervisor dead after max_restarts exceeded" false
    (is_alive sup)

(** Restarted child has fresh init state. *)
let test_restart_fresh_state () =
  let _env = eval_module {|mod T do
    actor Counter do
      state { count : Int }
      init  { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end
    actor Sup do
      state { c : Int }
      init { c = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        Counter c
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let c1 = sup_child_int sup "c" in
  (* Advance counter state to 7 *)
  (match Hashtbl.find_opt March_eval.Eval.actor_registry c1 with
   | Some ci ->
     ci.March_eval.Eval.ai_state <-
       March_eval.Eval.VRecord [("count", March_eval.Eval.VInt 7)]
   | None -> ());
  March_eval.Eval.crash_actor c1 "test";
  let c2 = sup_child_int sup "c" in
  let fresh_count =
    match Hashtbl.find_opt March_eval.Eval.actor_registry c2 with
    | Some ci ->
      (match ci.March_eval.Eval.ai_state with
       | March_eval.Eval.VRecord fields ->
         (match List.assoc_opt "count" fields with
          | Some (March_eval.Eval.VInt n) -> n
          | _ -> -1)
       | _ -> -1)
    | None -> -1
  in
  Alcotest.(check int) "restarted counter state is 0" 0 fresh_count

(* ------------------------------------------------------------------ *)
(* Phase 3 — Epoch Propagation                                         *)
(* ------------------------------------------------------------------ *)

(** After restart, the new actor's epoch is old_epoch + 1. *)
let test_epoch_increments_on_restart () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        W w
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1 = sup_child_int sup "w" in
  let epoch1 = match Hashtbl.find_opt March_eval.Eval.actor_registry w1 with
    | Some i -> i.March_eval.Eval.ai_epoch | None -> -1 in
  March_eval.Eval.crash_actor w1 "test";
  let w2 = sup_child_int sup "w" in
  let epoch2 = match Hashtbl.find_opt March_eval.Eval.actor_registry w2 with
    | Some i -> i.March_eval.Eval.ai_epoch | None -> -1 in
  Alcotest.(check int) "epoch incremented by 1 on restart" (epoch1 + 1) epoch2

(** Capability acquired before restart is stale: send_checked returns :error. *)
let test_cap_stale_after_restart () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        W w
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1 = sup_child_int sup "w" in
  (* Build a cap at epoch 0 for w1 *)
  let epoch1 = match Hashtbl.find_opt March_eval.Eval.actor_registry w1 with
    | Some i -> i.March_eval.Eval.ai_epoch | None -> 0 in
  let old_cap = March_eval.Eval.VCap (w1, epoch1) in
  March_eval.Eval.crash_actor w1 "test";
  (* Old cap now points to dead w1 → :error *)
  let send_checked = List.assoc "send_checked" March_eval.Eval.base_env in
  let result = March_eval.Eval.apply send_checked
    [old_cap; March_eval.Eval.VCon ("Inc", [])] in
  Alcotest.(check bool) "stale cap rejected by send_checked" true
    (match result with March_eval.Eval.VAtom "error" -> true | _ -> false)

(** Cap for the NEW incarnation is valid. *)
let test_fresh_cap_after_restart_accepted () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        W w
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1 = sup_child_int sup "w" in
  March_eval.Eval.crash_actor w1 "test";
  let w2 = sup_child_int sup "w" in
  let epoch2 = match Hashtbl.find_opt March_eval.Eval.actor_registry w2 with
    | Some i -> i.March_eval.Eval.ai_epoch | None -> -1 in
  let fresh_cap = March_eval.Eval.VCap (w2, epoch2) in
  let send_checked = List.assoc "send_checked" March_eval.Eval.base_env in
  let result = March_eval.Eval.apply send_checked
    [fresh_cap; March_eval.Eval.VCon ("Inc", [])] in
  Alcotest.(check bool) "fresh cap accepted by send_checked" true
    (match result with March_eval.Eval.VAtom "ok" -> true | _ -> false)

(* ------------------------------------------------------------------ *)
(* Restart builtin                                                      *)
(* ------------------------------------------------------------------ *)

(** restart(pid) spawns a fresh child and returns a new Pid. *)
let test_restart_builtin_returns_new_pid () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        W w
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1 = sup_child_int sup "w" in
  let restart_fn = List.assoc "restart" March_eval.Eval.base_env in
  let result = March_eval.Eval.apply restart_fn
    [March_eval.Eval.VPid w1] in
  (match result with
   | March_eval.Eval.VPid w2 ->
     Alcotest.(check bool) "new pid differs from old" true (w2 <> w1);
     Alcotest.(check bool) "new actor is alive" true (is_alive w2);
     Alcotest.(check bool) "old actor is dead" false (is_alive w1)
   | _ -> Alcotest.fail "restart: expected VPid result")

(** restart(pid) increments epoch of the spawned actor. *)
let test_restart_builtin_increments_epoch () =
  let _env = eval_module {|mod T do
    actor W do
      state { x : Int }
      init { x = 0 }
      on Inc() do { x = state.x + 1 } end
    end
    actor Sup do
      state { w : Int }
      init { w = 0 }
      supervise do
        strategy one_for_one
        max_restarts 5 within 60
        W w
      end
    end
    fn main() do spawn(Sup) end
  end|} in
  let sup = match call_fn _env "main" [] with
    | March_eval.Eval.VPid p -> p | _ -> -1 in
  let w1 = sup_child_int sup "w" in
  let epoch1 = match Hashtbl.find_opt March_eval.Eval.actor_registry w1 with
    | Some i -> i.March_eval.Eval.ai_epoch | None -> -1 in
  let restart_fn = List.assoc "restart" March_eval.Eval.base_env in
  let result = March_eval.Eval.apply restart_fn [March_eval.Eval.VPid w1] in
  (match result with
   | March_eval.Eval.VPid w2 ->
     let epoch2 = match Hashtbl.find_opt March_eval.Eval.actor_registry w2 with
       | Some i -> i.March_eval.Eval.ai_epoch | None -> -1 in
     Alcotest.(check int) "epoch incremented by restart()" (epoch1 + 1) epoch2
   | _ -> Alcotest.fail "restart: expected VPid result")

(* ------------------------------------------------------------------ *)
(* Phase 6a — OS Resource Drop                                         *)
(* ------------------------------------------------------------------ *)

(** Crash cleans up resources of all children in a one_for_all restart. *)
let test_one_for_all_cleans_resources () =
  March_eval.Eval.reset_scheduler_state ();
  let a_cleaned = ref false in
  let b_cleaned = ref false in
  let _ia = add_fresh_actor 0 "A" in
  let _ib = add_fresh_actor 1 "B" in
  (* Simulate supervisor: A has supervisor=Some(999), B has supervisor=Some(999) *)
  (match Hashtbl.find_opt March_eval.Eval.actor_registry 0 with
   | Some ia -> ia.March_eval.Eval.ai_supervisor <- Some 999 | None -> ());
  (match Hashtbl.find_opt March_eval.Eval.actor_registry 1 with
   | Some ib -> ib.March_eval.Eval.ai_supervisor <- Some 999 | None -> ());
  March_eval.Eval.register_resource_ocaml 0 "a_res" (fun () -> a_cleaned := true);
  March_eval.Eval.register_resource_ocaml 1 "b_res" (fun () -> b_cleaned := true);
  March_eval.Eval.crash_actor 0 "test";
  Alcotest.(check bool) "A's resource cleaned on crash" true !a_cleaned

(* ------------------------------------------------------------------ *)
(* Test runner                                                          *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "supervision" [
    ("phase1 monitors/links", [
      Alcotest.test_case "link chain propagation"        `Quick (with_reset test_link_chain_propagation);
      Alcotest.test_case "monitor does not kill watcher" `Quick (with_reset test_monitor_does_not_kill_watcher);
      Alcotest.test_case "multiple monitors distinct refs" `Quick (with_reset test_monitor_multiple_distinct_refs);
    ]);
    ("phase2 supervisor strategies", [
      Alcotest.test_case "one_for_one basic"             `Quick (with_reset test_one_for_one_basic);
      Alcotest.test_case "one_for_one sibling unchanged" `Quick (with_reset test_one_for_one_sibling_unchanged);
      Alcotest.test_case "one_for_all restarts all"      `Quick (with_reset test_one_for_all_restarts_all);
      Alcotest.test_case "rest_for_one downstream only"  `Quick (with_reset test_rest_for_one_downstream_only);
      Alcotest.test_case "max_restarts escalation"       `Quick (with_reset test_max_restarts_escalation);
      Alcotest.test_case "restart fresh state"           `Quick (with_reset test_restart_fresh_state);
    ]);
    ("phase3 epoch propagation", [
      Alcotest.test_case "epoch increments on restart"   `Quick (with_reset test_epoch_increments_on_restart);
      Alcotest.test_case "cap stale after restart"       `Quick (with_reset test_cap_stale_after_restart);
      Alcotest.test_case "fresh cap accepted after restart" `Quick (with_reset test_fresh_cap_after_restart_accepted);
    ]);
    ("restart builtin", [
      Alcotest.test_case "restart() returns new pid"     `Quick (with_reset test_restart_builtin_returns_new_pid);
      Alcotest.test_case "restart() increments epoch"    `Quick (with_reset test_restart_builtin_increments_epoch);
    ]);
    ("phase6a resource cleanup", [
      Alcotest.test_case "one_for_all cleans resources"  `Quick (with_reset test_one_for_all_cleans_resources);
    ]);
  ]
