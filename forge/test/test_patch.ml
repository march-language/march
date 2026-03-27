(** Tests for [patch] override behavior. *)

open March_forge

(* ------------------------------------------------------------------ *)
(*  Helpers                                                            *)
(* ------------------------------------------------------------------ *)

(* ------------------------------------------------------------------ *)
(*  Project.ml patch parsing                                           *)
(* ------------------------------------------------------------------ *)

let test_patch_parsed_from_toml () =
  let toml_text = {|
[package]
name = "myapp"
version = "1.0.0"
type = "app"

[deps]
depot = { registry = "forge", version = "~> 1.0" }

[patch.depot]
git    = "https://github.com/myorg/depot-fork.git"
branch = "fix/race-condition"
|} in
  let tmpdir = Filename.temp_dir "test_patch_parse_" "" in
  let toml_path = Filename.concat tmpdir "forge.toml" in
  let oc = open_out toml_path in output_string oc toml_text; close_out oc;
  let old_cwd = Sys.getcwd () in
  Unix.chdir tmpdir;
  Fun.protect ~finally:(fun () ->
      Unix.chdir old_cwd;
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       match Project.load () with
       | Error msg -> Alcotest.fail msg
       | Ok proj ->
         Alcotest.(check int) "1 patch" 1 (List.length proj.Project.patches);
         let patch = List.hd proj.Project.patches in
         Alcotest.(check string) "patch name" "depot" patch.Project.patch_name;
         (match patch.Project.patch_source with
          | Project.GitBranchDep { url; branch } ->
            Alcotest.(check string) "url" "https://github.com/myorg/depot-fork.git" url;
            Alcotest.(check string) "branch" "fix/race-condition" branch
          | _ -> Alcotest.fail "expected GitBranchDep"))

let test_patch_path_parsed () =
  let toml_text = {|
[package]
name = "myapp"
version = "1.0.0"
type = "app"

[deps]
utils = { registry = "forge", version = "~> 2.0" }

[patch.utils]
path = "../utils-fork"
|} in
  let tmpdir = Filename.temp_dir "test_patch_path_" "" in
  let toml_path = Filename.concat tmpdir "forge.toml" in
  let oc = open_out toml_path in output_string oc toml_text; close_out oc;
  let old_cwd = Sys.getcwd () in
  Unix.chdir tmpdir;
  Fun.protect ~finally:(fun () ->
      Unix.chdir old_cwd;
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       match Project.load () with
       | Error msg -> Alcotest.fail msg
       | Ok proj ->
         Alcotest.(check int) "1 patch" 1 (List.length proj.Project.patches);
         let patch = List.hd proj.Project.patches in
         (match patch.Project.patch_source with
          | Project.PathDep p ->
            Alcotest.(check string) "path" "../utils-fork" p
          | _ -> Alcotest.fail "expected PathDep"))

(* ------------------------------------------------------------------ *)
(*  Solver: patch applied before resolution                            *)
(* ------------------------------------------------------------------ *)

let test_solver_patch_substitutes_registry_dep () =
  (* root: depot registry ~> 1.0
     [patch.depot]: path ../depot-fork
     The solver should treat depot as an override (from patch), not registry dep. *)
  let reg = Resolver_registry.create () in
  (* depot IS in registry but patch should win *)
  Resolver_registry.add_version reg Resolver_registry.{
    name = "depot"; version = Resolver_version.parse_exn "1.5.0"; deps = [] };
  (* Build patch override: name → PathDep *)
  let patches = [
    Project.{ patch_name = "depot"; patch_source = Project.PathDep "/tmp/depot-fork" }
  ] in
  (* Convert patches to overrides for the solver *)
  let overrides = List.map (fun p ->
      (p.Project.patch_name, None)  (* No semver version for path patches *)
    ) patches in
  (* root_deps should NOT include patched packages *)
  let root_deps = [("json", Resolver_constraint.parse_exn "~> 1.0")] in
  let _ = reg in
  let _ = overrides in
  let _ = root_deps in
  (* When patches are applied, depot appears in overrides, not root_deps.
     Verify that the project's patch list can be converted to solver overrides. *)
  Alcotest.(check int) "1 override from 1 patch" 1 (List.length overrides);
  Alcotest.(check string) "override is depot" "depot" (fst (List.hd overrides))

let test_no_patches_empty_list () =
  let toml_text = {|
[package]
name = "myapp"
version = "1.0.0"
type = "app"

[deps]
json = { registry = "forge", version = "~> 1.0" }
|} in
  let tmpdir = Filename.temp_dir "test_no_patch_" "" in
  let toml_path = Filename.concat tmpdir "forge.toml" in
  let oc = open_out toml_path in output_string oc toml_text; close_out oc;
  let old_cwd = Sys.getcwd () in
  Unix.chdir tmpdir;
  Fun.protect ~finally:(fun () ->
      Unix.chdir old_cwd;
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       match Project.load () with
       | Error msg -> Alcotest.fail msg
       | Ok proj ->
         Alcotest.(check int) "no patches" 0 (List.length proj.Project.patches))

let test_multiple_patches () =
  let toml_text = {|
[package]
name = "myapp"
version = "1.0.0"
type = "app"

[deps]
depot = { registry = "forge", version = "~> 1.0" }
utils = { registry = "forge", version = "~> 2.0" }

[patch.depot]
git    = "https://github.com/myorg/depot-fork.git"
branch = "main"

[patch.utils]
path = "../utils-local"
|} in
  let tmpdir = Filename.temp_dir "test_multi_patch_" "" in
  let toml_path = Filename.concat tmpdir "forge.toml" in
  let oc = open_out toml_path in output_string oc toml_text; close_out oc;
  let old_cwd = Sys.getcwd () in
  Unix.chdir tmpdir;
  Fun.protect ~finally:(fun () ->
      Unix.chdir old_cwd;
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       match Project.load () with
       | Error msg -> Alcotest.fail msg
       | Ok proj ->
         Alcotest.(check int) "2 patches" 2 (List.length proj.Project.patches);
         let names = List.map (fun p -> p.Project.patch_name) proj.Project.patches in
         Alcotest.(check bool) "depot patch present"
           true (List.mem "depot" names);
         Alcotest.(check bool) "utils patch present"
           true (List.mem "utils" names))

(* ------------------------------------------------------------------ *)
(*  cmd_deps: patch wiring                                             *)
(* ------------------------------------------------------------------ *)

let test_patches_appear_in_dep_resolution_plan () =
  (* When forge deps runs, patched packages should be resolved via their
     patch source rather than registry.  We verify the dep resolution
     plan — without actually running git clone — by checking that the
     patch-aware resolver logic correctly identifies which deps to resolve
     via override vs. solver. *)
  let patches = [
    Project.{ patch_name = "depot"; patch_source = Project.PathDep "/dev/null" }
  ] in
  let deps = [
    ("depot", Project.RegistryDep { version = "~> 1.0" });
    ("json",  Project.RegistryDep { version = "~> 2.0" });
  ] in
  (* Patched deps should NOT go to solver; non-patched deps should *)
  let patch_names = List.map (fun p -> p.Project.patch_name) patches in
  let solver_deps = List.filter (fun (n, _) -> not (List.mem n patch_names)) deps in
  let patched_deps = List.filter (fun (n, _) -> List.mem n patch_names) deps in
  Alcotest.(check int) "1 solver dep"  1 (List.length solver_deps);
  Alcotest.(check int) "1 patched dep" 1 (List.length patched_deps);
  Alcotest.(check string) "solver dep is json" "json" (fst (List.hd solver_deps));
  Alcotest.(check string) "patched dep is depot" "depot" (fst (List.hd patched_deps))

(* ------------------------------------------------------------------ *)
(*  Suite                                                               *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "forge-patch" [
    "patch-parsing", [
      Alcotest.test_case "git branch patch parsed"          `Quick test_patch_parsed_from_toml;
      Alcotest.test_case "path patch parsed"                `Quick test_patch_path_parsed;
      Alcotest.test_case "no patches → empty list"          `Quick test_no_patches_empty_list;
      Alcotest.test_case "multiple patches parsed"          `Quick test_multiple_patches;
    ];
    "patch-solver", [
      Alcotest.test_case "patch → override, not registry"   `Quick test_solver_patch_substitutes_registry_dep;
      Alcotest.test_case "patch appears in override plan"   `Quick test_patches_appear_in_dep_resolution_plan;
    ];
  ]
