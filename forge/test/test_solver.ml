(** Tests for the PubGrub dependency solver and registry index. *)

open March_forge

(* ------------------------------------------------------------------ *)
(*  Test registry builder                                               *)
(* ------------------------------------------------------------------ *)

let v = Resolver_version.parse_exn
let c = Resolver_constraint.parse_exn

(** Build a test registry from a list of
    (name, version_str, deps: (name, constraint_str) list) *)
let make_registry packages =
  let idx = Resolver_registry.create () in
  List.iter (fun (name, ver_str, deps) ->
      let version = v ver_str in
      let parsed_deps = List.map (fun (dn, dc) -> (dn, c dc)) deps in
      Resolver_registry.add_version idx Resolver_registry.{
        name; version; deps = parsed_deps }
    ) packages;
  idx

(** Helper: assert solve succeeds and return solution map. *)
let solve_ok registry root_deps overrides =
  match Resolver_pubgrub.resolve registry ~root_deps ~overrides with
  | Ok sol -> sol
  | Error err ->
    Alcotest.fail ("solver unexpectedly failed: " ^
                   Resolver_pubgrub.format_error err)

(** Helper: assert solve fails. *)
let solve_fail registry root_deps overrides =
  match Resolver_pubgrub.resolve registry ~root_deps ~overrides with
  | Ok sol ->
    let pairs = List.map (fun (n, v) ->
        n ^ "=" ^ Resolver_version.to_string v) sol in
    Alcotest.fail ("solver unexpectedly succeeded: " ^ String.concat ", " pairs)
  | Error err -> err

(** Find a version in solution. *)
let find_version sol pkg =
  match List.assoc_opt pkg sol with
  | Some v -> v
  | None   -> Alcotest.fail (Printf.sprintf "package '%s' not in solution" pkg)

(* ------------------------------------------------------------------ *)
(*  Registry tests                                                      *)
(* ------------------------------------------------------------------ *)

let test_registry_versions_of () =
  let reg = make_registry [
      ("json", "1.0.0", []);
      ("json", "1.2.0", []);
      ("json", "2.0.0", []);
    ] in
  let vs = Resolver_registry.versions_of reg "json" in
  (* Should be sorted newest-first *)
  Alcotest.(check int) "3 versions" 3 (List.length vs);
  let first = (List.hd vs).Resolver_registry.version in
  Alcotest.(check string) "newest first" "2.0.0" (Resolver_version.to_string first)

let test_registry_deps_of () =
  let reg = make_registry [
      ("http", "2.0.0", [("json", "~> 1.0"); ("core", ">= 0.5")])
    ] in
  match Resolver_registry.deps_of reg "http" (v "2.0.0") with
  | None   -> Alcotest.fail "expected deps"
  | Some deps ->
    Alcotest.(check int) "2 deps" 2 (List.length deps);
    Alcotest.(check bool) "json present"
      true (List.mem_assoc "json" deps)

let test_registry_roundtrip () =
  let reg = make_registry [
      ("core", "1.0.0", []);
      ("json", "1.2.3", [("core", "~> 1.0")]);
    ] in
  let tmpdir = Filename.temp_dir "test_registry_" "" in
  let path   = Filename.concat tmpdir "index.toml" in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       Resolver_registry.save_to_file reg path;
       match Resolver_registry.load_from_file path with
       | Error e -> Alcotest.fail ("load failed: " ^ e)
       | Ok reg2 ->
         let vs = Resolver_registry.versions_of reg2 "json" in
         Alcotest.(check int) "json has 1 version" 1 (List.length vs);
         let pv = List.hd vs in
         Alcotest.(check string) "version" "1.2.3"
           (Resolver_version.to_string pv.Resolver_registry.version);
         Alcotest.(check int) "1 dep" 1 (List.length pv.Resolver_registry.deps))

(* ------------------------------------------------------------------ *)
(*  Solver happy path                                                   *)
(* ------------------------------------------------------------------ *)

let test_solver_single_package () =
  let reg = make_registry [
      ("json", "1.4.0", []);
      ("json", "1.5.0", []);
    ] in
  let sol = solve_ok reg [("json", c "~> 1.4")] [] in
  let ver = find_version sol "json" in
  (* Should select 1.5.0 (newest that satisfies ~> 1.4 = >= 1.4.0, < 2.0.0) *)
  Alcotest.(check string) "json 1.5.0"
    "1.5.0" (Resolver_version.to_string ver)

let test_solver_two_independent_packages () =
  let reg = make_registry [
      ("json",   "1.0.0", []);
      ("http",   "2.0.0", []);
    ] in
  let sol = solve_ok reg [("json", c "~> 1.0"); ("http", c "~> 2.0")] [] in
  let _j = find_version sol "json" in
  let _h = find_version sol "http" in
  Alcotest.(check int) "2 packages resolved" 2 (List.length sol)

let test_solver_transitive () =
  (* root → http ~> 2.0, http → json ~> 1.0 *)
  let reg = make_registry [
      ("json", "1.2.0", []);
      ("http", "2.0.0", [("json", "~> 1.0")]);
    ] in
  let sol = solve_ok reg [("http", c "~> 2.0")] [] in
  (* Both http and json should be in the solution *)
  let _h = find_version sol "http" in
  let _j = find_version sol "json" in
  Alcotest.(check bool) "json in solution" true (List.mem_assoc "json" sol)

let test_solver_diamond_compatible () =
  (* root → A, root → B
     A → D ~> 1.0
     B → D ~> 1.2
     D available: 1.0.0, 1.2.0, 1.3.0
     Expected: D selected at 1.3.0 (satisfies both ~> 1.0 and ~> 1.2) *)
  let reg = make_registry [
      ("d", "1.0.0", []);
      ("d", "1.2.0", []);
      ("d", "1.3.0", []);
      ("a", "1.0.0", [("d", "~> 1.0")]);
      ("b", "1.0.0", [("d", "~> 1.2")]);
    ] in
  let sol = solve_ok reg [("a", c "~> 1.0"); ("b", c "~> 1.0")] [] in
  let d_ver = find_version sol "d" in
  (* ~> 1.2 = >= 1.2.0, < 2.0.0 AND ~> 1.0 = >= 1.0.0, < 2.0.0
     Both constraints satisfied by 1.3.0 (newest) *)
  Alcotest.(check bool) "d >= 1.2.0"
    true (Resolver_version.compare d_ver (v "1.2.0") >= 0)

let test_solver_exact_version () =
  let reg = make_registry [
      ("json", "1.0.0", []);
      ("json", "1.4.2", []);
      ("json", "2.0.0", []);
    ] in
  let sol = solve_ok reg [("json", c "1.4.2")] [] in
  let ver = find_version sol "json" in
  Alcotest.(check string) "exact 1.4.2"
    "1.4.2" (Resolver_version.to_string ver)

let test_solver_override_bypass () =
  (* Override package should be in solution with its given version,
     no registry lookup needed *)
  let reg = make_registry [] in  (* empty registry *)
  let sol = solve_ok reg []
      [("bastion", Some (v "0.3.1"))] in
  let ver = find_version sol "bastion" in
  Alcotest.(check string) "override version"
    "0.3.1" (Resolver_version.to_string ver)

let test_solver_override_and_registry () =
  (* Mix: one registry dep, one override *)
  let reg = make_registry [("json", "1.5.0", [])] in
  let sol = solve_ok reg
      [("json", c "~> 1.0")]
      [("vault", Some (v "0.1.0"))] in
  let _j = find_version sol "json" in
  let _v = find_version sol "vault" in
  Alcotest.(check bool) "vault in solution" true (List.mem_assoc "vault" sol)

(* ------------------------------------------------------------------ *)
(*  Solver conflict scenarios                                           *)
(* ------------------------------------------------------------------ *)

let test_solver_direct_conflict () =
  (* root requires json ~> 1.0 AND json >= 2.0 — impossible *)
  let reg = make_registry [
      ("json", "1.5.0", []);
      ("json", "2.0.0", []);
    ] in
  let err = solve_fail reg
      [("json", c "~> 1.0"); ("json", c ">= 2.0")] [] in
  (* Should fail with NoVersions since ~> 1.0 = [1.0,2.0) and >= 2.0 is disjoint *)
  (match err with
   | Resolver_pubgrub.NoVersions { package; _ } ->
     Alcotest.(check string) "conflict on json" "json" package
   | _ -> Alcotest.fail "expected NoVersions error")

let test_solver_no_versions () =
  (* Package exists but no version satisfies the constraint *)
  let reg = make_registry [
      ("json", "1.0.0", []);
    ] in
  let err = solve_fail reg [("json", c ">= 3.0")] [] in
  (match err with
   | Resolver_pubgrub.NoVersions { package; constraint_ } ->
     Alcotest.(check string) "package" "json" package;
     Alcotest.(check bool) "constraint in error"
       true (String.length constraint_ > 0)
   | _ -> Alcotest.fail "expected NoVersions error")

let test_solver_unknown_package () =
  (* Package not in registry at all *)
  let reg = make_registry [] in
  let err = solve_fail reg [("unknown_pkg", c "~> 1.0")] [] in
  (match err with
   | Resolver_pubgrub.NoVersions { package; _ } ->
     Alcotest.(check string) "package" "unknown_pkg" package
   | _ -> Alcotest.fail "expected NoVersions error")

let test_solver_impossible_range () =
  (* >= 3.0, < 2.0 — impossible constraint *)
  let reg = make_registry [
      ("json", "1.0.0", []);
      ("json", "2.5.0", []);
      ("json", "3.1.0", []);
    ] in
  let err = solve_fail reg [("json", c ">= 3.0, < 2.0")] [] in
  (match err with
   | Resolver_pubgrub.NoVersions _ -> ()  (* expected *)
   | _ -> Alcotest.fail "expected NoVersions error")

(* ------------------------------------------------------------------ *)
(*  Pre-1.0 packages                                                   *)
(* ------------------------------------------------------------------ *)

let test_solver_pre_1_0_package () =
  (* 0.x packages resolve normally *)
  let reg = make_registry [
      ("newlib", "0.1.0", []);
      ("newlib", "0.2.0", []);
      ("newlib", "0.3.0", []);
    ] in
  let sol = solve_ok reg [("newlib", c "~> 0.2")] [] in
  let ver = find_version sol "newlib" in
  (* ~> 0.2 = >= 0.2.0, < 0.3.0 — only 0.2.0 qualifies *)
  Alcotest.(check string) "0.2.0"
    "0.2.0" (Resolver_version.to_string ver)

(* ------------------------------------------------------------------ *)
(*  Solver error message quality                                        *)
(* ------------------------------------------------------------------ *)

let test_solver_error_message_contains_package () =
  let reg = make_registry [
      ("foo", "1.0.0", []);
    ] in
  let err = solve_fail reg [("foo", c ">= 5.0")] [] in
  let msg = Resolver_pubgrub.format_error err in
  Alcotest.(check bool) "error mentions foo"
    true (let sub = "foo" in
          let n = String.length msg and m = String.length sub in
          let rec f i = if i + m > n then false
            else if String.sub msg i m = sub then true else f (i+1) in f 0)

(* ------------------------------------------------------------------ *)
(*  Suite                                                               *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "forge-solver" [
    "registry", [
      Alcotest.test_case "versions_of sorted newest-first" `Quick test_registry_versions_of;
      Alcotest.test_case "deps_of returns correct deps"    `Quick test_registry_deps_of;
      Alcotest.test_case "index file roundtrip"            `Quick test_registry_roundtrip;
    ];
    "solver-happy", [
      Alcotest.test_case "single package"                  `Quick test_solver_single_package;
      Alcotest.test_case "two independent packages"        `Quick test_solver_two_independent_packages;
      Alcotest.test_case "transitive dep resolved"         `Quick test_solver_transitive;
      Alcotest.test_case "diamond dep compatible"          `Quick test_solver_diamond_compatible;
      Alcotest.test_case "exact version constraint"        `Quick test_solver_exact_version;
      Alcotest.test_case "override bypasses solver"        `Quick test_solver_override_bypass;
      Alcotest.test_case "override + registry mix"         `Quick test_solver_override_and_registry;
    ];
    "solver-conflicts", [
      Alcotest.test_case "direct conflict same package"    `Quick test_solver_direct_conflict;
      Alcotest.test_case "no versions satisfy constraint"  `Quick test_solver_no_versions;
      Alcotest.test_case "unknown package fails"           `Quick test_solver_unknown_package;
      Alcotest.test_case "impossible range"                `Quick test_solver_impossible_range;
      Alcotest.test_case "pre-1.0 package resolves"        `Quick test_solver_pre_1_0_package;
      Alcotest.test_case "error message names the package" `Quick test_solver_error_message_contains_package;
    ];
  ]
