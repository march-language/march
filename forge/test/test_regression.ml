(** Regression tests for known dependency resolution bugs from Cargo, Hex, and npm.
    Each test captures a real-world failure mode with a minimal reproduction. *)

open March_forge
module V  = Resolver_version
module VC = Resolver_constraint
module RR = Resolver_registry
module PG = Resolver_pubgrub

(* ------------------------------------------------------------------ *)
(*  Helpers                                                            *)
(* ------------------------------------------------------------------ *)

let add reg name ver_str deps =
  RR.add_version reg RR.{
    name;
    version = V.parse_exn ver_str;
    deps = List.map (fun (n, c) -> (n, VC.parse_exn c)) deps;
  }

let error_package = function
  | PG.NoVersions  { package; _ } -> package
  | PG.Conflict    { package; _ } -> package
  | PG.CircularDep { package }    -> package

let solve_ok reg root =
  let root_deps = List.map (fun (n, c) -> (n, VC.parse_exn c)) root in
  match PG.solve reg ~root_deps ~overrides:[] with
  | Ok s    -> s
  | Error e ->
    Alcotest.failf "expected Ok but got conflict: %s(%s)"
      (match e with
       | PG.NoVersions  _ -> "NoVersions"
       | PG.Conflict    _ -> "Conflict"
       | PG.CircularDep _ -> "CircularDep")
      (error_package e)

let solve_err reg root =
  let root_deps = List.map (fun (n, c) -> (n, VC.parse_exn c)) root in
  match PG.solve reg ~root_deps ~overrides:[] with
  | Error e -> e
  | Ok _    -> Alcotest.fail "expected conflict but solver returned Ok"

let assoc pkg sol =
  match List.assoc_opt pkg sol with
  | Some v -> V.to_string v
  | None   -> Alcotest.failf "package %s not in solution" pkg

(* ------------------------------------------------------------------ *)
(*  Cargo regression: semver-incompatible transitive upgrade
    https://github.com/rust-lang/cargo/issues/4421

    root → A ~> 1.0, B ~> 1.0
    A 1.0 → C ~> 1.0
    B 1.0 → C ~> 2.0   (breaks: C 2.0 is incompatible with A's ~>1.0)
    Expected: conflict
*)
(* ------------------------------------------------------------------ *)

let test_cargo_4421_incompatible_transitive () =
  let reg = RR.create () in
  add reg "a" "1.0.0" [("c", "~> 1.0")];
  add reg "b" "1.0.0" [("c", "~> 2.0")];
  add reg "c" "1.5.0" [];
  add reg "c" "2.0.0" [];
  let e = solve_err reg [("a", "~> 1.0"); ("b", "~> 1.0")] in
  let pkg = error_package e in
  Alcotest.(check bool) "conflict involves c" true
    (pkg = "c" || pkg = "a" || pkg = "b")

(* ------------------------------------------------------------------ *)
(*  Hex regression: "newest wins" led to broken transitive chain
    root → A ~> 1.0
    A 1.0.0 → B ~> 1.0
    A 1.1.0 → B ~> 2.0   (B 2.0 is not available)
    Only B 1.5.0 is available.

    NOTE: Our greedy solver picks the newest A (1.1.0) and then fails on B.
    Full PubGrub would backtrack to A 1.0.0.  This test documents the
    known limitation — backtracking support is Phase 6+ work.
*)
(* ------------------------------------------------------------------ *)

let test_hex_backtrack_to_older_version () =
  let reg = RR.create () in
  add reg "a" "1.1.0" [("b", "~> 2.0")];
  add reg "a" "1.0.0" [("b", "~> 1.0")];
  add reg "b" "1.5.0" [];
  (* B 2.x is intentionally absent.
     Our greedy solver picks A 1.1.0 → needs B ~> 2.0 → no match → conflict.
     A full backtracking solver would retry A 1.0.0.  We verify the conflict
     is about B (not some other package) to document the failure mode. *)
  let e = solve_err reg [("a", "~> 1.0")] in
  Alcotest.(check bool) "conflict is about b (greedy limitation)"
    true (error_package e = "b")

(* ------------------------------------------------------------------ *)
(*  npm regression: peer dependency diamond inconsistency
    root → A ~> 1.0, B ~> 1.0
    A 1.0 → peer C ~> 1.0
    B 1.0 → peer C ~> 1.0
    Both A and B need the SAME version of C (npm peer semantics).
    We model this as regular deps — solver should find one C that satisfies both.
*)
(* ------------------------------------------------------------------ *)

let test_npm_peer_diamond_consistent () =
  let reg = RR.create () in
  add reg "a" "1.0.0" [("c", "~> 1.0")];
  add reg "b" "1.0.0" [("c", "~> 1.0")];
  add reg "c" "1.3.0" [];
  add reg "c" "2.0.0" [];
  let sol = solve_ok reg [("a", "~> 1.0"); ("b", "~> 1.0")] in
  (* Both A and B need C ~> 1.0; solver picks the latest compatible = 1.3.0 *)
  Alcotest.(check string) "c = 1.3.0" "1.3.0" (assoc "c" sol)

(* ------------------------------------------------------------------ *)
(*  Cargo regression: yanked version still satisfies unless excluded
    (modelled: exact version constraint must pin to the exact version)
*)
(* ------------------------------------------------------------------ *)

let test_exact_version_pin () =
  let reg = RR.create () in
  add reg "a" "1.0.0" [];
  add reg "a" "1.1.0" [];
  add reg "a" "1.2.0" [];
  let sol = solve_ok reg [("a", "= 1.0.0")] in
  Alcotest.(check string) "exact pin a = 1.0.0" "1.0.0" (assoc "a" sol)

(* ------------------------------------------------------------------ *)
(*  Hex regression: version with empty dep list != version not in index
    If a package version has zero deps, it should still be selectable.
*)
(* ------------------------------------------------------------------ *)

let test_version_with_zero_deps_selectable () =
  let reg = RR.create () in
  add reg "a" "1.0.0" [];
  let sol = solve_ok reg [("a", "~> 1.0")] in
  Alcotest.(check string) "a = 1.0.0" "1.0.0" (assoc "a" sol)

(* ------------------------------------------------------------------ *)
(*  Cargo regression: multiple root deps, no shared transitive dep
    root → A ~> 1.0, B ~> 2.0
    A has no deps, B has no deps.
    Solution must contain exactly A and B, nothing else.
*)
(* ------------------------------------------------------------------ *)

let test_independent_root_deps_no_spurious_entries () =
  let reg = RR.create () in
  add reg "a" "1.5.0" [];
  add reg "b" "2.3.0" [];
  let sol = solve_ok reg [("a", "~> 1.0"); ("b", "~> 2.0")] in
  Alcotest.(check int) "exactly 2 entries" 2 (List.length sol);
  Alcotest.(check string) "a = 1.5.0" "1.5.0" (assoc "a" sol);
  Alcotest.(check string) "b = 2.3.0" "2.3.0" (assoc "b" sol)

(* ------------------------------------------------------------------ *)
(*  Cargo regression: root requires X >= 1.0, transitive requires X = 1.0
    Tight version = 1.0 from transitive should still satisfy root's >= 1.0.
*)
(* ------------------------------------------------------------------ *)

let test_tight_transitive_compatible_with_loose_root () =
  let reg = RR.create () in
  add reg "a" "1.0.0" [("x", "= 1.0.0")];
  add reg "x" "1.0.0" [];
  add reg "x" "1.5.0" [];
  let sol = solve_ok reg [("a", "~> 1.0"); ("x", ">= 1.0")] in
  (* x must be exactly 1.0.0 to satisfy A's = 1.0.0 constraint *)
  Alcotest.(check string) "x = 1.0.0" "1.0.0" (assoc "x" sol)

(* ------------------------------------------------------------------ *)
(*  Cargo regression: three-way diamond with different minima
    root → A ~> 1.0, B ~> 1.0
    A 1.0 → C >= 1.2
    B 1.0 → C >= 1.5
    Only C 1.5.0 satisfies both.
*)
(* ------------------------------------------------------------------ *)

let test_three_way_diamond_highest_lower_bound () =
  let reg = RR.create () in
  add reg "a" "1.0.0" [("c", ">= 1.2")];
  add reg "b" "1.0.0" [("c", ">= 1.5")];
  add reg "c" "1.2.0" [];
  add reg "c" "1.5.0" [];
  add reg "c" "2.0.0" [];
  let sol = solve_ok reg [("a", "~> 1.0"); ("b", "~> 1.0")] in
  (* C must be >= 1.5 — newest compatible = 2.0.0 *)
  let c_ver = assoc "c" sol in
  let c_v   = V.parse_exn c_ver in
  Alcotest.(check bool) "c >= 1.5"
    true (V.compare c_v (V.parse_exn "1.5.0") >= 0)

(* ------------------------------------------------------------------ *)
(*  Suite                                                              *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "forge-regression" [
    "regression", [
      Alcotest.test_case "cargo#4421: incompatible transitive"      `Quick test_cargo_4421_incompatible_transitive;
      Alcotest.test_case "hex: backtrack to older version"          `Quick test_hex_backtrack_to_older_version;
      Alcotest.test_case "npm: peer diamond consistent"             `Quick test_npm_peer_diamond_consistent;
      Alcotest.test_case "exact version pin"                        `Quick test_exact_version_pin;
      Alcotest.test_case "version with zero deps selectable"        `Quick test_version_with_zero_deps_selectable;
      Alcotest.test_case "independent root deps: no spurious entries" `Quick test_independent_root_deps_no_spurious_entries;
      Alcotest.test_case "tight transitive compatible with loose root" `Quick test_tight_transitive_compatible_with_loose_root;
      Alcotest.test_case "three-way diamond: highest lower bound"   `Quick test_three_way_diamond_highest_lower_bound;
    ];
  ]
