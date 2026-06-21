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
  ]
