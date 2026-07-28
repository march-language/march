(** Hot Code Reload test suite.

    Phase 2: boundary classification — which modules are reloadable. *)

module HR = March_tir.Hot_reload

let check name expected actual =
  Alcotest.(check bool) name expected actual

(* ── Boundary classification ──────────────────────────────────────────────── *)

let test_app_modules_reloadable_by_default () =
  let cfg = HR.default_config "MyApp" in
  check "app root module reloadable"     true (HR.is_reloadable cfg "MyApp");
  check "app submodule reloadable"       true (HR.is_reloadable cfg "MyApp.Router");
  check "deep app submodule reloadable"  true (HR.is_reloadable cfg "MyApp.Web.Endpoint")

let test_stdlib_and_deps_never_reloadable () =
  let cfg = HR.default_config "MyApp" in
  check "stdlib List not reloadable"  false (HR.is_reloadable cfg "List");
  check "stdlib Json not reloadable"  false (HR.is_reloadable cfg "Json");
  check "a dependency not reloadable" false (HR.is_reloadable cfg "Conduit.Article")

let test_prefix_is_not_substring () =
  (* A module that merely shares a string prefix with the app is NOT app code. *)
  let cfg = HR.default_config "MyApp" in
  check "MyApplication is a different module" false (HR.is_reloadable cfg "MyApplication")

let test_exclude_overrides_default () =
  let cfg = { (HR.default_config "MyApp") with HR.excludes = ["MyApp.Legacy"] } in
  check "excluded module not reloadable"        false (HR.is_reloadable cfg "MyApp.Legacy");
  check "excluded submodule not reloadable"     false (HR.is_reloadable cfg "MyApp.Legacy.Old");
  check "sibling of excluded still reloadable"  true  (HR.is_reloadable cfg "MyApp.Router")

let test_include_extends_boundary () =
  let cfg = { (HR.default_config "MyApp") with HR.includes = ["Shared"] } in
  check "included external module reloadable" true (HR.is_reloadable cfg "Shared.Util");
  check "non-included external not reloadable" false (HR.is_reloadable cfg "List")

let test_exclude_wins_over_include () =
  let cfg = { (HR.default_config "MyApp") with
              HR.includes = ["Shared"]; HR.excludes = ["Shared.Internal"] } in
  check "exclude beats include" false (HR.is_reloadable cfg "Shared.Internal");
  check "rest of include still in" true (HR.is_reloadable cfg "Shared.Util")

let test_include_root_itself_reloadable () =
  let cfg = { (HR.default_config "MyApp") with HR.includes = ["Shared"] } in
  check "include root module itself reloadable" true (HR.is_reloadable cfg "Shared")

let test_exclude_does_not_widen_boundary () =
  (* An exclude on a module outside the boundary doesn't make it reloadable. *)
  let cfg = { (HR.default_config "MyApp") with HR.excludes = ["External"] } in
  check "external module still not reloadable" false (HR.is_reloadable cfg "External")

let test_dotted_app_prefix_is_path_aware () =
  let cfg = HR.default_config "MyApp.Web" in
  check "MyApp.Web.Handler under MyApp.Web"   true  (HR.is_reloadable cfg "MyApp.Web.Handler");
  check "MyApp.WebSocket NOT under MyApp.Web" false (HR.is_reloadable cfg "MyApp.WebSocket")

(* ── dispatch-edge decision ───────────────────────────────────────────────── *)

let test_boundary_to_boundary_needs_dispatch () =
  let cfg = HR.default_config "MyApp" in
  check "app→app routes through the table" true
    (HR.needs_dispatch cfg ~caller_module:"MyApp.Router" ~callee_module:"MyApp.Service")

let test_boundary_to_stdlib_is_direct () =
  let cfg = HR.default_config "MyApp" in
  check "app→stdlib stays direct" false
    (HR.needs_dispatch cfg ~caller_module:"MyApp.Router" ~callee_module:"List")

let test_stdlib_to_boundary_is_direct () =
  (* Non-boundary callers are fully optimised and never dispatch-indirect. *)
  let cfg = HR.default_config "MyApp" in
  check "stdlib→app stays direct" false
    (HR.needs_dispatch cfg ~caller_module:"List" ~callee_module:"MyApp.Service")

let test_excluded_callee_is_direct () =
  let cfg = { (HR.default_config "MyApp") with HR.excludes = ["MyApp.Hot.Inner"] } in
  check "app→excluded stays direct" false
    (HR.needs_dispatch cfg ~caller_module:"MyApp.Router" ~callee_module:"MyApp.Hot.Inner")

(* ── NAME_ID interning ────────────────────────────────────────────────────── *)

module NT = March_tir.Hot_reload.Name_table

let oid = Alcotest.(option int)
let ostr = Alcotest.(option string)

let test_ids_assigned_in_sorted_order () =
  let t = NT.build ["b"; "a"; "c"] in
  Alcotest.(check oid) "a → 0" (Some 0) (NT.id_of t "a");
  Alcotest.(check oid) "b → 1" (Some 1) (NT.id_of t "b");
  Alcotest.(check oid) "c → 2" (Some 2) (NT.id_of t "c")

let test_round_trips_id_to_name () =
  let t = NT.build ["a"; "b"; "c"] in
  Alcotest.(check ostr) "0 → a" (Some "a") (NT.name_of t 0);
  Alcotest.(check ostr) "2 → c" (Some "c") (NT.name_of t 2);
  Alcotest.(check ostr) "out of range → None" None (NT.name_of t 3)

let test_unknown_name_has_no_id () =
  let t = NT.build ["a"; "b"] in
  Alcotest.(check oid) "unknown name → None" None (NT.id_of t "z")

let test_assignment_is_order_independent () =
  (* Same name set in different input order yields the same id for each name. *)
  let t1 = NT.build ["x"; "y"; "z"] in
  let t2 = NT.build ["z"; "x"; "y"] in
  List.iter (fun n ->
    Alcotest.(check oid) ("stable id for " ^ n) (NT.id_of t1 n) (NT.id_of t2 n))
    ["x"; "y"; "z"]

let test_deduplicates_names () =
  let t = NT.build ["a"; "a"; "b"; "b"; "b"] in
  Alcotest.(check int) "unique count" 2 (NT.count t);
  Alcotest.(check (list string)) "names in id order" ["a"; "b"] (NT.names t)

let test_empty_table () =
  let t = NT.build [] in
  Alcotest.(check int) "empty count" 0 (NT.count t);
  Alcotest.(check oid) "no id for any name" None (NT.id_of t "x");
  Alcotest.(check ostr) "no name at id 0" None (NT.name_of t 0);
  Alcotest.(check (list string)) "no names" [] (NT.names t)

let test_negative_id_has_no_name () =
  let t = NT.build ["a"] in
  Alcotest.(check ostr) "negative id → None" None (NT.name_of t (-1))

(* ── Llvm_emit dispatch emission (IR-level) ───────────────────────────────── *)

module Tir = March_tir.Tir
module LE = March_tir.Llvm_emit

let contains (haystack : string) (needle : string) : bool =
  let nl = String.length needle and hl = String.length haystack in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  nl = 0 || go 0

(* MyApp.A() = MyApp.B();  MyApp.B() = 1  — both reloadable under "MyApp". *)
let two_boundary_module () : Tir.tir_module =
  let b : Tir.fn_def =
    { fn_name = "MyApp.B"; fn_params = []; fn_ret_ty = Tir.TInt;
      fn_body = Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 1));
      fn_kind = Tir.FnNormal } in
  let a : Tir.fn_def =
    { fn_name = "MyApp.A"; fn_params = []; fn_ret_ty = Tir.TInt;
      fn_body = Tir.EApp ({ Tir.v_name = "MyApp.B";
                            v_ty = Tir.TFn ([], Tir.TInt); v_lin = Tir.Unr }, []);
      fn_kind = Tir.FnNormal } in
  { Tir.tm_name = "MyApp"; tm_fns = [a; b]; tm_types = []; tm_externs = [];
    tm_exports = []; tm_tests = []; tm_io_fns = [] }

let test_hot_reload_emits_dispatch_call () =
  let ir = LE.emit_module ~hot_reload:(Some (HR.default_config "MyApp"))
             (two_boundary_module ()) in
  check "boundary→boundary emits dispatch enter" true
    (contains ir "call ptr @march_dispatch_enter");
  check "boundary→boundary emits dispatch leave" true
    (contains ir "call void @march_dispatch_leave");
  (* Startup-warmup guard: march_dispatch_enter returns NULL while the target
     slot is still being published (a request served during boot), so the call
     site null-checks the fn_ptr and falls back to a DIRECT static call to the
     baseline symbol instead of jumping through NULL.  A direct `call @MyApp.B`
     therefore now DOES appear — but only inside the guarded fallback block, not
     as the primary path.  Assert the guard (icmp eq ptr ..., null) is present so
     the direct call can never be reached unless enter() signalled "not ready". *)
  check "boundary call site null-checks the dispatch fn_ptr" true
    (contains ir "icmp eq ptr" && contains ir "null");
  check "warmup fallback keeps a direct call to the baseline symbol" true
    (contains ir "call i64 @MyApp.B(");
  (* The indirect (dispatched) call through the pinned fn_ptr is still the live
     path — verify a call through a %hrfp register exists. *)
  check "boundary→boundary calls through the dispatched fn_ptr" true
    (contains ir "call i64 %hrfp")

let test_no_flag_keeps_direct_call () =
  let ir = LE.emit_module (two_boundary_module ()) in  (* hot_reload defaults None *)
  check "no dispatch enter call when flag off" false
    (contains ir "call ptr @march_dispatch_enter");
  check "direct call to MyApp.B preserved" true
    (contains ir "call i64 @MyApp.B(")

(* MyApp.A → MyApp.B (boundary), plus a bare `main` so @main is emitted. *)
let boundary_module_with_main () : Tir.tir_module =
  let m = two_boundary_module () in
  let main : Tir.fn_def =
    { fn_name = "main"; fn_params = []; fn_ret_ty = Tir.TInt;
      fn_body = Tir.EApp ({ Tir.v_name = "MyApp.A";
                            v_ty = Tir.TFn ([], Tir.TInt); v_lin = Tir.Unr }, []);
      fn_kind = Tir.FnNormal } in
  { m with Tir.tm_fns = m.Tir.tm_fns @ [main] }

let test_startup_registers_boundary_fns () =
  let ir = LE.emit_module ~hot_reload:(Some (HR.default_config "MyApp"))
             (boundary_module_with_main ()) in
  (* Slot IDs are 1-based (slot 0 reserved as "not set" sentinel).
     dispatch_init receives n+1 where n=2 boundary fns. *)
  check "table sized to 2 boundary fns (n+1 = 3)" true
    (contains ir "call void @march_dispatch_init(i32 3)");
  check "MyApp.A published at slot 1" true
    (contains ir "@march_dispatch_publish(i32 1, ptr @MyApp.A");
  check "MyApp.B published at slot 2" true
    (contains ir "@march_dispatch_publish(i32 2, ptr @MyApp.B");
  check "bare main not published (not on boundary)" false
    (contains ir "ptr @main,")

let test_no_startup_registration_without_flag () =
  let ir = LE.emit_module (boundary_module_with_main ()) in
  check "no dispatch_init when flag off" false
    (contains ir "call void @march_dispatch_init")

(* ── Phase 9: .so patch mode (emit_main=false) + hot-reload epoch path ──────── *)

let test_compile_so_with_hot_reload_epoch () =
  (* emit_main=false simulates --compile-so; hot_reload=Some cfg enables Phase 9. *)
  let ir = LE.emit_module ~emit_main:false
             ~hot_reload:(Some (HR.default_config "MyApp"))
             (two_boundary_module ()) in
  check "epoch cell emitted in .so mode" true
    (contains ir "@__march_hcr_epoch = private global i32 0");
  check "__march_init exported for reload server" true
    (contains ir "define void @__march_init(i32 %epoch)");
  check "epoch-aware enter used in .so (not bare enter)" true
    (contains ir "march_dispatch_enter_gen");
  check "leave still emitted" true
    (contains ir "call void @march_dispatch_leave")

(* ── Protocol v2: ACTIVATE2 signed message format ───────────────────────── *)

let test_activate2_signed_message_format () =
  let name = "Foo_dispatch" and impl_hash = "abc123" and cas_hash = "def456" in
  let callers = ["B.bar"; "A.foo"] in
  let callers_sorted = List.sort String.compare callers in
  let callers_csv = String.concat "," callers_sorted in
  let epoch = 5 in
  let msg = Printf.sprintf "ACTIVATE2 %s %s %s epoch:%d callers:%s"
    name impl_hash cas_hash epoch callers_csv in
  check "ACTIVATE2 prefix" true (String.length msg >= 9 && String.sub msg 0 9 = "ACTIVATE2");
  check "epoch in signed msg" true (contains msg "epoch:5");
  check "callers in signed msg (sorted)" true (contains msg "callers:A.foo,B.bar");
  check "callers NOT in unsorted order" false (contains msg "callers:B.bar,A.foo");
  check "full canonical form" true
    (msg = "ACTIVATE2 Foo_dispatch abc123 def456 epoch:5 callers:A.foo,B.bar")

let test_activate2_callers_are_sorted () =
  let join cs = String.concat "," (List.sort String.compare cs) in
  check "empty callers"        true (join [] = "");
  check "single caller"        true (join ["A.foo"] = "A.foo");
  check "two callers sorted"   true (join ["B.bar"; "A.foo"] = "A.foo,B.bar");
  check "already sorted"       true (join ["A.foo"; "B.bar"] = "A.foo,B.bar");
  check "three callers sorted" true (join ["C.baz"; "A.foo"; "B.bar"] = "A.foo,B.bar,C.baz")

let test_compile_so_without_hot_reload_no_epoch () =
  (* --compile-so without --hot-reload must not emit the epoch entry point. *)
  let ir = LE.emit_module ~emit_main:false (two_boundary_module ()) in
  check "no epoch cell without --hot-reload" false
    (contains ir "@__march_hcr_epoch");
  check "no __march_init without --hot-reload" false
    (contains ir "__march_init")

(* ── inliner no-inline guard for boundary edges ───────────────────────────── *)

let a_body_after_inline (cfg : HR.config option) : Tir.expr =
  March_tir.Inline.boundary_config := cfg;
  let changed = ref false in
  let result = March_tir.Inline.run ~changed (two_boundary_module ()) in
  March_tir.Inline.boundary_config := None;  (* reset shared state *)
  let a = List.find (fun fd -> fd.Tir.fn_name = "MyApp.A") result.Tir.tm_fns in
  a.Tir.fn_body

let a_still_calls_b (body : Tir.expr) : bool =
  match body with
  | Tir.EApp (f, _) -> f.Tir.v_name = "MyApp.B"
  | _ -> false

let test_inliner_skips_boundary_callee () =
  (* With a boundary config, B (reloadable) must NOT be inlined into A. *)
  check "A still calls B under hot-reload" true
    (a_still_calls_b (a_body_after_inline (Some (HR.default_config "MyApp"))))

let test_inliner_inlines_without_boundary () =
  (* Without a config, B is a normal candidate and IS inlined into A. *)
  check "A no longer calls B (inlined) when flag off" false
    (a_still_calls_b (a_body_after_inline None))

(* ── single-use inliner no-inline guard for reloadable callees ───────────── *)

let one_use_impure_module callee : Tir.tir_module =
  let x = { Tir.v_name = "x"; v_ty = Tir.TString; v_lin = Tir.Unr } in
  let b : Tir.fn_def =
    { fn_name = callee; fn_params = [x]; fn_ret_ty = Tir.TString;
      fn_body =
        Tir.ESeq
          (Tir.EIncRC (Tir.AVar x),
           Tir.ESeq
             (Tir.EDecRC (Tir.AVar x), Tir.EAtom (Tir.AVar x)));
      fn_kind = Tir.FnNormal } in
  let a : Tir.fn_def =
    { fn_name = "MyApp.A"; fn_params = []; fn_ret_ty = Tir.TString;
      fn_body = Tir.EApp ({ Tir.v_name = callee;
                            v_ty = Tir.TFn ([Tir.TString], Tir.TString);
                            v_lin = Tir.Unr },
                          [Tir.ALit (March_ast.Ast.LitString "input")]);
      fn_kind = Tir.FnNormal } in
  let main : Tir.fn_def =
    { fn_name = "main"; fn_params = []; fn_ret_ty = Tir.TString;
      fn_body = Tir.EApp ({ Tir.v_name = "MyApp.A";
                            v_ty = Tir.TFn ([], Tir.TString); v_lin = Tir.Unr }, []);
      fn_kind = Tir.FnNormal } in
  { Tir.tm_name = "MyApp"; tm_fns = [main; a; b]; tm_types = []; tm_externs = [];
    tm_exports = []; tm_tests = []; tm_io_fns = [] }

let run_single_use_with_config config module_ =
  March_tir.Inline.boundary_config := config;
  Fun.protect
    ~finally:(fun () -> March_tir.Inline.boundary_config := None)
    (fun () ->
      March_tir.Single_use_inline.run ~changed:(ref false) module_)

let a_still_calls (callee : string) (module_ : Tir.tir_module) : bool =
  let a = List.find (fun fn -> fn.Tir.fn_name = "MyApp.A") module_.Tir.tm_fns in
  match a.Tir.fn_body with
  | Tir.EApp (fn, _) -> String.equal fn.Tir.v_name callee
  | _ -> false

let test_single_use_skips_reloadable_callee () =
  let result =
    run_single_use_with_config (Some (HR.default_config "MyApp"))
      (one_use_impure_module "MyApp.B.run")
  in
  check "reloadable MyApp.B.run call is preserved" true
    (a_still_calls "MyApp.B.run" result)

let test_opt_keeps_reloadable_callee_for_single_use_inline () =
  let result =
    March_tir.Opt.run ~hot_reload:(Some (HR.default_config "MyApp"))
      (one_use_impure_module "MyApp.B.run")
  in
  check "optimizer preserves reloadable MyApp.B.run call" true
    (a_still_calls "MyApp.B.run" result)

let test_single_use_inlines_without_boundary () =
  let result =
    run_single_use_with_config None (one_use_impure_module "MyApp.B.run")
  in
  check "MyApp.B.run call is removed without a boundary" false
    (a_still_calls "MyApp.B.run" result)

let test_single_use_inlines_excluded_callee () =
  let config =
    Some { (HR.default_config "MyApp") with HR.excludes = ["MyApp.B"] }
  in
  let result =
    run_single_use_with_config config (one_use_impure_module "MyApp.B.run")
  in
  check "excluded MyApp.B.run is eligible" false
    (a_still_calls "MyApp.B.run" result)

let test_single_use_skips_force_included_external_callee () =
  let config =
    Some { (HR.default_config "MyApp") with HR.includes = ["External"] }
  in
  let result =
    run_single_use_with_config config (one_use_impure_module "External.B.run")
  in
  check "force-included External.B.run call is preserved" true
    (a_still_calls "External.B.run" result)

let () =
  Alcotest.run "hot_reload" [
    ("boundary", [
      Alcotest.test_case "app modules reloadable by default" `Quick test_app_modules_reloadable_by_default;
      Alcotest.test_case "stdlib/deps never reloadable"      `Quick test_stdlib_and_deps_never_reloadable;
      Alcotest.test_case "prefix is not a substring match"   `Quick test_prefix_is_not_substring;
      Alcotest.test_case "exclude overrides default"         `Quick test_exclude_overrides_default;
      Alcotest.test_case "include extends boundary"          `Quick test_include_extends_boundary;
      Alcotest.test_case "exclude wins over include"         `Quick test_exclude_wins_over_include;
      Alcotest.test_case "include root itself reloadable"    `Quick test_include_root_itself_reloadable;
      Alcotest.test_case "exclude does not widen boundary"   `Quick test_exclude_does_not_widen_boundary;
      Alcotest.test_case "dotted app_prefix is path-aware"   `Quick test_dotted_app_prefix_is_path_aware;
    ]);
    ("dispatch_edge", [
      Alcotest.test_case "boundary→boundary needs dispatch"  `Quick test_boundary_to_boundary_needs_dispatch;
      Alcotest.test_case "boundary→stdlib is direct"         `Quick test_boundary_to_stdlib_is_direct;
      Alcotest.test_case "stdlib→boundary is direct"         `Quick test_stdlib_to_boundary_is_direct;
      Alcotest.test_case "excluded callee is direct"         `Quick test_excluded_callee_is_direct;
    ]);
    ("llvm_emit", [
      Alcotest.test_case "hot_reload emits dispatch call"    `Quick test_hot_reload_emits_dispatch_call;
      Alcotest.test_case "no flag keeps direct call"         `Quick test_no_flag_keeps_direct_call;
      Alcotest.test_case "startup registers boundary fns"    `Quick test_startup_registers_boundary_fns;
      Alcotest.test_case "no startup registration off"       `Quick test_no_startup_registration_without_flag;
      Alcotest.test_case "compile_so+hot_reload emits epoch" `Quick test_compile_so_with_hot_reload_epoch;
      Alcotest.test_case "compile_so without hot_reload: no epoch" `Quick test_compile_so_without_hot_reload_no_epoch;
    ]);
    ("protocol_v2", [
      Alcotest.test_case "ACTIVATE2 signed message canonical form" `Quick test_activate2_signed_message_format;
      Alcotest.test_case "ACTIVATE2 callers sorted before signing" `Quick test_activate2_callers_are_sorted;
    ]);
    ("inline_guard", [
      Alcotest.test_case "boundary callee not inlined"       `Quick test_inliner_skips_boundary_callee;
      Alcotest.test_case "inlined when flag off"             `Quick test_inliner_inlines_without_boundary;
    ]);
    ("single_use_inline_guard", [
      Alcotest.test_case "reloadable callee not inlined" `Quick
        test_single_use_skips_reloadable_callee;
      Alcotest.test_case "optimizer keeps reloadable callee" `Quick
        test_opt_keeps_reloadable_callee_for_single_use_inline;
      Alcotest.test_case "inlined when flag off" `Quick
        test_single_use_inlines_without_boundary;
      Alcotest.test_case "excluded callee is eligible" `Quick
        test_single_use_inlines_excluded_callee;
      Alcotest.test_case "force-included external callee not inlined" `Quick
        test_single_use_skips_force_included_external_callee;
    ]);
    ("name_table", [
      Alcotest.test_case "ids assigned in sorted order"  `Quick test_ids_assigned_in_sorted_order;
      Alcotest.test_case "round-trips id ↔ name"         `Quick test_round_trips_id_to_name;
      Alcotest.test_case "unknown name has no id"        `Quick test_unknown_name_has_no_id;
      Alcotest.test_case "assignment is order-independent" `Quick test_assignment_is_order_independent;
      Alcotest.test_case "deduplicates names"            `Quick test_deduplicates_names;
      Alcotest.test_case "empty table"                   `Quick test_empty_table;
      Alcotest.test_case "negative id has no name"       `Quick test_negative_id_has_no_name;
    ]);
  ]
