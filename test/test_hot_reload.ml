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
      fn_body = Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt 1)) } in
  let a : Tir.fn_def =
    { fn_name = "MyApp.A"; fn_params = []; fn_ret_ty = Tir.TInt;
      fn_body = Tir.EApp ({ Tir.v_name = "MyApp.B";
                            v_ty = Tir.TFn ([], Tir.TInt); v_lin = Tir.Unr }, []) } in
  { Tir.tm_name = "MyApp"; tm_fns = [a; b]; tm_types = []; tm_externs = [];
    tm_exports = []; tm_tests = []; tm_io_fns = [] }

let test_hot_reload_emits_dispatch_call () =
  let ir = LE.emit_module ~hot_reload:(Some (HR.default_config "MyApp"))
             (two_boundary_module ()) in
  check "boundary→boundary emits dispatch enter" true
    (contains ir "call ptr @march_dispatch_enter");
  check "boundary→boundary emits dispatch leave" true
    (contains ir "call void @march_dispatch_leave");
  check "direct call to MyApp.B is replaced" false
    (contains ir "call i64 @MyApp.B(")

let test_no_flag_keeps_direct_call () =
  let ir = LE.emit_module (two_boundary_module ()) in  (* hot_reload defaults None *)
  check "no dispatch enter call when flag off" false
    (contains ir "call ptr @march_dispatch_enter");
  check "direct call to MyApp.B preserved" true
    (contains ir "call i64 @MyApp.B(")

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
    ]);
    ("inline_guard", [
      Alcotest.test_case "boundary callee not inlined"       `Quick test_inliner_skips_boundary_callee;
      Alcotest.test_case "inlined when flag off"             `Quick test_inliner_inlines_without_boundary;
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
