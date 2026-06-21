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

let () =
  Alcotest.run "hot_reload" [
    ("boundary", [
      Alcotest.test_case "app modules reloadable by default" `Quick test_app_modules_reloadable_by_default;
      Alcotest.test_case "stdlib/deps never reloadable"      `Quick test_stdlib_and_deps_never_reloadable;
      Alcotest.test_case "prefix is not a substring match"   `Quick test_prefix_is_not_substring;
      Alcotest.test_case "exclude overrides default"         `Quick test_exclude_overrides_default;
      Alcotest.test_case "include extends boundary"          `Quick test_include_extends_boundary;
      Alcotest.test_case "exclude wins over include"         `Quick test_exclude_wins_over_include;
    ]);
    ("name_table", [
      Alcotest.test_case "ids assigned in sorted order"  `Quick test_ids_assigned_in_sorted_order;
      Alcotest.test_case "round-trips id ↔ name"         `Quick test_round_trips_id_to_name;
      Alcotest.test_case "unknown name has no id"        `Quick test_unknown_name_has_no_id;
      Alcotest.test_case "assignment is order-independent" `Quick test_assignment_is_order_independent;
      Alcotest.test_case "deduplicates names"            `Quick test_deduplicates_names;
    ]);
  ]
