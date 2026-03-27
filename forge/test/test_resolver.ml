(** Tests for the forge dependency resolver — Phase 1.
    Version constraint parsing, comparison, satisfies, lockfile read/write. *)

open March_forge

(* ===================================================================== *)
(*  Helpers                                                               *)
(* ===================================================================== *)

let v = Resolver_version.parse_exn

(* ===================================================================== *)
(*  Version parsing                                                       *)
(* ===================================================================== *)

let test_version_parse_basic () =
  let ver = v "1.2.3" in
  Alcotest.(check int) "major" 1 ver.Resolver_version.major;
  Alcotest.(check int) "minor" 2 ver.Resolver_version.minor;
  Alcotest.(check int) "patch" 3 ver.Resolver_version.patch;
  Alcotest.(check (list string)) "no pre" [] ver.Resolver_version.pre

let test_version_parse_v_prefix () =
  let ver = v "v1.2.3" in
  Alcotest.(check int) "major" 1 ver.Resolver_version.major;
  Alcotest.(check int) "minor" 2 ver.Resolver_version.minor;
  Alcotest.(check int) "patch" 3 ver.Resolver_version.patch

let test_version_parse_pre_release () =
  let ver = v "1.0.0-alpha.1" in
  Alcotest.(check int) "major" 1 ver.Resolver_version.major;
  Alcotest.(check (list string)) "pre" ["alpha";"1"] ver.Resolver_version.pre

let test_version_parse_pre_release_beta () =
  let ver = v "2.3.1-beta" in
  Alcotest.(check (list string)) "pre" ["beta"] ver.Resolver_version.pre

let test_version_parse_two_component () =
  let ver = v "1.2" in
  Alcotest.(check int) "major" 1 ver.Resolver_version.major;
  Alcotest.(check int) "minor" 2 ver.Resolver_version.minor;
  Alcotest.(check int) "patch" 0 ver.Resolver_version.patch

let test_version_parse_one_component () =
  let ver = v "3" in
  Alcotest.(check int) "major" 3 ver.Resolver_version.major;
  Alcotest.(check int) "minor" 0 ver.Resolver_version.minor;
  Alcotest.(check int) "patch" 0 ver.Resolver_version.patch

let test_version_parse_build_metadata_ignored () =
  let ver = v "1.0.0+build.1" in
  Alcotest.(check int) "major" 1 ver.Resolver_version.major;
  Alcotest.(check (list string)) "pre" [] ver.Resolver_version.pre

let test_version_parse_error_non_numeric () =
  Alcotest.(check bool) "non-numeric fails"
    true (Result.is_error (Resolver_version.parse "v1.0.x"))

let test_version_parse_error_four_component () =
  Alcotest.(check bool) "four-component fails"
    true (Result.is_error (Resolver_version.parse "1.0.0.0"))

let test_version_parse_error_empty () =
  Alcotest.(check bool) "empty fails"
    true (Result.is_error (Resolver_version.parse ""))

(* ===================================================================== *)
(*  Version comparison / ordering                                         *)
(* ===================================================================== *)

let test_version_ordering_basic () =
  Alcotest.(check bool) "1.0.0 < 2.0.0" true  (Resolver_version.compare (v "1.0.0") (v "2.0.0") < 0);
  Alcotest.(check bool) "2.0.0 > 1.0.0" true  (Resolver_version.compare (v "2.0.0") (v "1.0.0") > 0);
  Alcotest.(check bool) "1.0.0 = 1.0.0" true  (Resolver_version.compare (v "1.0.0") (v "1.0.0") = 0)

let test_version_ordering_minor_patch () =
  Alcotest.(check bool) "1.1.0 > 1.0.0"  true (Resolver_version.compare (v "1.1.0") (v "1.0.0") > 0);
  Alcotest.(check bool) "1.0.1 > 1.0.0"  true (Resolver_version.compare (v "1.0.1") (v "1.0.0") > 0);
  Alcotest.(check bool) "1.2.0 < 1.10.0" true (Resolver_version.compare (v "1.2.0") (v "1.10.0") < 0)

let test_version_ordering_pre_release () =
  (* Pre-release has lower precedence than release *)
  Alcotest.(check bool) "1.0.0-alpha < 1.0.0"
    true (Resolver_version.compare (v "1.0.0-alpha") (v "1.0.0") < 0);
  Alcotest.(check bool) "1.0.0 > 1.0.0-alpha"
    true (Resolver_version.compare (v "1.0.0") (v "1.0.0-alpha") > 0)

let test_version_ordering_pre_release_numeric () =
  (* numeric pre-release identifiers compared numerically *)
  Alcotest.(check bool) "1.0.0-alpha.1 < 1.0.0-alpha.2"
    true (Resolver_version.compare (v "1.0.0-alpha.1") (v "1.0.0-alpha.2") < 0);
  Alcotest.(check bool) "1.0.0-alpha < 1.0.0-alpha.1"
    true (Resolver_version.compare (v "1.0.0-alpha") (v "1.0.0-alpha.1") < 0)

let test_version_ordering_pre_release_alphanum () =
  (* numeric identifiers < alphanumeric identifiers *)
  Alcotest.(check bool) "1.0.0-1 < 1.0.0-alpha"
    true (Resolver_version.compare (v "1.0.0-1") (v "1.0.0-alpha") < 0)

let test_version_to_string () =
  Alcotest.(check string) "1.2.3"       "1.2.3"       (Resolver_version.to_string (v "1.2.3"));
  Alcotest.(check string) "1.0.0-alpha" "1.0.0-alpha" (Resolver_version.to_string (v "1.0.0-alpha"));
  Alcotest.(check string) "2.0.0-rc.1"  "2.0.0-rc.1"  (Resolver_version.to_string (v "2.0.0-rc.1"))

(* ===================================================================== *)
(*  Constraint parsing                                                    *)
(* ===================================================================== *)

let test_constraint_parse_exact () =
  let c = Resolver_constraint.parse_exn "1.4.2" in
  Alcotest.(check bool) "exact satisfies 1.4.2"
    true  (Resolver_constraint.satisfies (v "1.4.2") c);
  Alcotest.(check bool) "exact rejects 1.4.3"
    false (Resolver_constraint.satisfies (v "1.4.3") c)

let test_constraint_parse_gte () =
  let c = Resolver_constraint.parse_exn ">= 2.0" in
  Alcotest.(check bool) "2.0.0 satisfies >= 2.0"  true  (Resolver_constraint.satisfies (v "2.0.0") c);
  Alcotest.(check bool) "2.1.0 satisfies >= 2.0"  true  (Resolver_constraint.satisfies (v "2.1.0") c);
  Alcotest.(check bool) "1.9.9 rejects >= 2.0"    false (Resolver_constraint.satisfies (v "1.9.9") c)

let test_constraint_parse_lt () =
  let c = Resolver_constraint.parse_exn "< 3.0" in
  Alcotest.(check bool) "2.9.9 satisfies < 3.0"  true  (Resolver_constraint.satisfies (v "2.9.9") c);
  Alcotest.(check bool) "3.0.0 rejects < 3.0"    false (Resolver_constraint.satisfies (v "3.0.0") c);
  Alcotest.(check bool) "3.0.1 rejects < 3.0"    false (Resolver_constraint.satisfies (v "3.0.1") c)

let test_constraint_parse_lte () =
  let c = Resolver_constraint.parse_exn "<= 2.5.0" in
  Alcotest.(check bool) "2.5.0 satisfies <= 2.5.0" true  (Resolver_constraint.satisfies (v "2.5.0") c);
  Alcotest.(check bool) "2.4.9 satisfies <= 2.5.0" true  (Resolver_constraint.satisfies (v "2.4.9") c);
  Alcotest.(check bool) "2.5.1 rejects <= 2.5.0"   false (Resolver_constraint.satisfies (v "2.5.1") c)

let test_constraint_parse_gt () =
  let c = Resolver_constraint.parse_exn "> 1.0.0" in
  Alcotest.(check bool) "1.0.1 satisfies > 1.0.0" true  (Resolver_constraint.satisfies (v "1.0.1") c);
  Alcotest.(check bool) "1.0.0 rejects > 1.0.0"   false (Resolver_constraint.satisfies (v "1.0.0") c)

let test_constraint_parse_range () =
  let c = Resolver_constraint.parse_exn ">= 1.5, < 2.0" in
  Alcotest.(check bool) "1.5.0 satisfies range" true  (Resolver_constraint.satisfies (v "1.5.0") c);
  Alcotest.(check bool) "1.9.9 satisfies range" true  (Resolver_constraint.satisfies (v "1.9.9") c);
  Alcotest.(check bool) "2.0.0 rejects range"   false (Resolver_constraint.satisfies (v "2.0.0") c);
  Alcotest.(check bool) "1.4.9 rejects range"   false (Resolver_constraint.satisfies (v "1.4.9") c)

(* ===================================================================== *)
(*  Twiddle-wakka ~> expansion                                           *)
(* ===================================================================== *)

let test_twiddle_wakka_three_component () =
  (* ~> 1.2.3  means  >= 1.2.3, < 1.3.0 *)
  let c = Resolver_constraint.parse_exn "~> 1.2.3" in
  Alcotest.(check bool) "1.2.3 in ~> 1.2.3"  true  (Resolver_constraint.satisfies (v "1.2.3") c);
  Alcotest.(check bool) "1.2.9 in ~> 1.2.3"  true  (Resolver_constraint.satisfies (v "1.2.9") c);
  Alcotest.(check bool) "1.3.0 out ~> 1.2.3" false (Resolver_constraint.satisfies (v "1.3.0") c);
  Alcotest.(check bool) "1.2.2 out ~> 1.2.3" false (Resolver_constraint.satisfies (v "1.2.2") c)

let test_twiddle_wakka_two_component () =
  (* ~> 1.2  means  >= 1.2.0, < 2.0.0 *)
  let c = Resolver_constraint.parse_exn "~> 1.2" in
  Alcotest.(check bool) "1.2.0 in ~> 1.2"  true  (Resolver_constraint.satisfies (v "1.2.0") c);
  Alcotest.(check bool) "1.9.9 in ~> 1.2"  true  (Resolver_constraint.satisfies (v "1.9.9") c);
  Alcotest.(check bool) "2.0.0 out ~> 1.2" false (Resolver_constraint.satisfies (v "2.0.0") c);
  Alcotest.(check bool) "1.1.9 out ~> 1.2" false (Resolver_constraint.satisfies (v "1.1.9") c)

let test_twiddle_wakka_one_component () =
  (* ~> 1  means  >= 1.0.0, < 2.0.0 *)
  let c = Resolver_constraint.parse_exn "~> 1" in
  Alcotest.(check bool) "1.0.0 in ~> 1"  true  (Resolver_constraint.satisfies (v "1.0.0") c);
  Alcotest.(check bool) "1.5.3 in ~> 1"  true  (Resolver_constraint.satisfies (v "1.5.3") c);
  Alcotest.(check bool) "2.0.0 out ~> 1" false (Resolver_constraint.satisfies (v "2.0.0") c);
  Alcotest.(check bool) "0.9.9 out ~> 1" false (Resolver_constraint.satisfies (v "0.9.9") c)

let test_twiddle_wakka_zero_major () =
  (* ~> 0.2  means  >= 0.2.0, < 0.3.0  — stays within minor *)
  let c = Resolver_constraint.parse_exn "~> 0.2" in
  Alcotest.(check bool) "0.2.0 in ~> 0.2"  true  (Resolver_constraint.satisfies (v "0.2.0") c);
  Alcotest.(check bool) "0.2.9 in ~> 0.2"  true  (Resolver_constraint.satisfies (v "0.2.9") c);
  Alcotest.(check bool) "0.3.0 out ~> 0.2" false (Resolver_constraint.satisfies (v "0.3.0") c)

let test_pre_release_not_selected_by_non_pre_constraint () =
  (* ~> 1.0 should not satisfy for 1.1.0-beta *)
  let c = Resolver_constraint.parse_exn "~> 1.0" in
  Alcotest.(check bool) "1.1.0-beta not in ~> 1.0"
    false (Resolver_constraint.satisfies (v "1.1.0-beta") c)

let test_constraint_parse_errors () =
  Alcotest.(check bool) "~> latest fails"
    true (Result.is_error (Resolver_constraint.parse "~> latest"));
  Alcotest.(check bool) "=> 1.0 fails (invalid op)"
    true (Result.is_error (Resolver_constraint.parse "=> 1.0"))

(* ===================================================================== *)
(*  Project dep parsing — new source types                               *)
(* ===================================================================== *)

let test_project_registry_dep () =
  let text = {|
[package]
name = "myapp"
version = "1.0.0"
type = "app"

[deps]
json = { registry = "forge", version = "~> 1.0" }
|} in
  let doc = Toml.parse text in
  let dep_pairs = Toml.get_section doc "deps" in
  match Toml.get_table dep_pairs "json" with
  | None -> Alcotest.fail "expected inline table for json"
  | Some tbl ->
    Alcotest.(check (option string)) "registry" (Some "forge") (Toml.get_string tbl "registry");
    Alcotest.(check (option string)) "version"  (Some "~> 1.0") (Toml.get_string tbl "version")

let test_project_git_tag_dep () =
  let text = {|
[package]
name = "myapp"
version = "1.0.0"
type = "app"

[deps]
depot = { git = "https://github.com/user/depot.git", tag = "v0.2.1" }
|} in
  let doc = Toml.parse text in
  let dep_pairs = Toml.get_section doc "deps" in
  match Toml.get_table dep_pairs "depot" with
  | None -> Alcotest.fail "expected inline table for depot"
  | Some tbl ->
    Alcotest.(check (option string)) "tag" (Some "v0.2.1") (Toml.get_string tbl "tag")

let test_project_git_branch_dep () =
  let text = {|
[package]
name = "myapp"
version = "1.0.0"
type = "app"

[deps]
bastion = { git = "https://github.com/user/bastion.git", branch = "main" }
|} in
  let doc = Toml.parse text in
  let dep_pairs = Toml.get_section doc "deps" in
  match Toml.get_table dep_pairs "bastion" with
  | None -> Alcotest.fail "expected inline table for bastion"
  | Some tbl ->
    Alcotest.(check (option string)) "branch" (Some "main") (Toml.get_string tbl "branch")

let test_project_loads_all_dep_types () =
  let toml_text = {|
[package]
name = "webapp"
version = "1.0.0"
type = "app"

[deps]
json    = { registry = "forge", version = "~> 1.4" }
depot   = { git = "https://github.com/user/depot.git", tag = "v0.2.1" }
bastion = { git = "https://github.com/user/bastion.git", branch = "main" }
pinned  = { git = "https://github.com/user/pinned.git", rev = "abc123" }
vault   = { path = "../vault" }
|} in
  let tmpdir = Filename.temp_dir "test_resolver_" "" in
  let toml_path = Filename.concat tmpdir "forge.toml" in
  let oc = open_out toml_path in
  output_string oc toml_text;
  close_out oc;
  let old_cwd = Sys.getcwd () in
  Unix.chdir tmpdir;
  Fun.protect ~finally:(fun () ->
      Unix.chdir old_cwd;
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       match Project.load () with
       | Error msg -> Alcotest.fail msg
       | Ok proj ->
         Alcotest.(check int) "5 deps" 5 (List.length proj.Project.deps);
         (* registry dep *)
         (match List.assoc_opt "json" proj.Project.deps with
          | Some (Project.RegistryDep { version }) ->
            Alcotest.(check string) "json version" "~> 1.4" version
          | _ -> Alcotest.fail "json should be RegistryDep");
         (* git tag dep *)
         (match List.assoc_opt "depot" proj.Project.deps with
          | Some (Project.GitTagDep { tag; _ }) ->
            Alcotest.(check string) "depot tag" "v0.2.1" tag
          | _ -> Alcotest.fail "depot should be GitTagDep");
         (* git branch dep *)
         (match List.assoc_opt "bastion" proj.Project.deps with
          | Some (Project.GitBranchDep { branch; _ }) ->
            Alcotest.(check string) "bastion branch" "main" branch
          | _ -> Alcotest.fail "bastion should be GitBranchDep");
         (* git rev dep *)
         (match List.assoc_opt "pinned" proj.Project.deps with
          | Some (Project.GitRevDep { rev; _ }) ->
            Alcotest.(check string) "pinned rev" "abc123" rev
          | _ -> Alcotest.fail "pinned should be GitRevDep");
         (* path dep *)
         (match List.assoc_opt "vault" proj.Project.deps with
          | Some (Project.PathDep p) ->
            Alcotest.(check string) "vault path" "../vault" p
          | _ -> Alcotest.fail "vault should be PathDep"))

(* ===================================================================== *)
(*  Lockfile read/write                                                   *)
(* ===================================================================== *)

let test_lockfile_write_and_read_back () =
  let tmpdir = Filename.temp_dir "test_lockfile_" "" in
  let lock_path = Filename.concat tmpdir "forge.lock" in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       let entries = [
         Resolver_lockfile.{ name = "json"; version = Some "1.4.7";
           source = "registry:forge"; commit = None;
           hash = "blake3:aabbccdd" };
         Resolver_lockfile.{ name = "depot"; version = Some "0.2.1";
           source = "git:https://github.com/user/depot.git";
           commit = Some "f7a3b1c9"; hash = "blake3:11223344" };
         Resolver_lockfile.{ name = "live"; version = None;
           source = "git:https://github.com/user/live.git";
           commit = Some "a0b1c2d3"; hash = "blake3:55667788" };
         Resolver_lockfile.{ name = "vault"; version = None;
           source = "path:../vault"; commit = None;
           hash = "blake3:99aabbcc" };
       ] in
       Resolver_lockfile.write lock_path entries ~manifest_hash:"sha256:testmhash";
       (* verify file exists *)
       Alcotest.(check bool) "forge.lock created" true (Sys.file_exists lock_path);
       (* read back *)
       match Resolver_lockfile.read lock_path with
       | Error msg -> Alcotest.fail ("read failed: " ^ msg)
       | Ok (read_entries, mhash) ->
         Alcotest.(check (option string)) "manifest hash"
           (Some "sha256:testmhash") mhash;
         Alcotest.(check int) "4 entries" 4 (List.length read_entries);
         (* json *)
         let json_e = List.assoc "json" (List.map (fun e -> (e.Resolver_lockfile.name, e)) read_entries) in
         Alcotest.(check (option string)) "json version" (Some "1.4.7") json_e.Resolver_lockfile.version;
         Alcotest.(check string) "json source" "registry:forge" json_e.Resolver_lockfile.source;
         (* depot *)
         let depot_e = List.assoc "depot" (List.map (fun e -> (e.Resolver_lockfile.name, e)) read_entries) in
         Alcotest.(check (option string)) "depot commit"
           (Some "f7a3b1c9") depot_e.Resolver_lockfile.commit;
         (* live — no version *)
         let live_e = List.assoc "live" (List.map (fun e -> (e.Resolver_lockfile.name, e)) read_entries) in
         Alcotest.(check (option string)) "live version" None live_e.Resolver_lockfile.version)

let test_lockfile_manifest_hash () =
  let content = "name = \"test\"\nversion = \"0.1.0\"\n" in
  let h1 = Resolver_lockfile.compute_manifest_hash content in
  let h2 = Resolver_lockfile.compute_manifest_hash content in
  (* same content → same hash *)
  Alcotest.(check string) "deterministic" h1 h2;
  (* different content → different hash *)
  let h3 = Resolver_lockfile.compute_manifest_hash (content ^ " ") in
  Alcotest.(check bool) "different content differs" true (h1 <> h3);
  (* starts with sha256: prefix *)
  Alcotest.(check bool) "sha256 prefix"
    true (String.length h1 > 7 && String.sub h1 0 7 = "sha256:")

let test_lockfile_drift_detection () =
  let tmpdir = Filename.temp_dir "test_drift_" "" in
  let lock_path = Filename.concat tmpdir "forge.lock" in
  let toml_content = "[package]\nname = \"app\"\nversion = \"1.0.0\"\n" in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       let mhash = Resolver_lockfile.compute_manifest_hash toml_content in
       Resolver_lockfile.write lock_path [] ~manifest_hash:mhash;
       (* same content → no drift *)
       Alcotest.(check bool) "no drift same content"
         false (Resolver_lockfile.has_drifted lock_path toml_content);
       (* modified content → drift detected *)
       let modified = toml_content ^ "author = \"bob\"\n" in
       Alcotest.(check bool) "drift detected on change"
         true (Resolver_lockfile.has_drifted lock_path modified))

(* ===================================================================== *)
(*  Suite                                                                 *)
(* ===================================================================== *)

let () =
  Alcotest.run "forge-resolver" [
    "version-parse", [
      Alcotest.test_case "basic 1.2.3"               `Quick test_version_parse_basic;
      Alcotest.test_case "v prefix stripped"          `Quick test_version_parse_v_prefix;
      Alcotest.test_case "pre-release alpha.1"        `Quick test_version_parse_pre_release;
      Alcotest.test_case "pre-release beta"           `Quick test_version_parse_pre_release_beta;
      Alcotest.test_case "two-component 1.2"          `Quick test_version_parse_two_component;
      Alcotest.test_case "one-component 3"            `Quick test_version_parse_one_component;
      Alcotest.test_case "build metadata ignored"     `Quick test_version_parse_build_metadata_ignored;
      Alcotest.test_case "error: non-numeric"         `Quick test_version_parse_error_non_numeric;
      Alcotest.test_case "error: four-component"      `Quick test_version_parse_error_four_component;
      Alcotest.test_case "error: empty string"        `Quick test_version_parse_error_empty;
    ];
    "version-compare", [
      Alcotest.test_case "basic ordering"             `Quick test_version_ordering_basic;
      Alcotest.test_case "minor and patch ordering"   `Quick test_version_ordering_minor_patch;
      Alcotest.test_case "pre-release < release"      `Quick test_version_ordering_pre_release;
      Alcotest.test_case "pre-release numeric sort"   `Quick test_version_ordering_pre_release_numeric;
      Alcotest.test_case "pre-release num < alphanum" `Quick test_version_ordering_pre_release_alphanum;
      Alcotest.test_case "to_string round-trip"       `Quick test_version_to_string;
    ];
    "constraint-parse", [
      Alcotest.test_case "exact 1.4.2"                `Quick test_constraint_parse_exact;
      Alcotest.test_case ">= lower bound"             `Quick test_constraint_parse_gte;
      Alcotest.test_case "< upper bound"              `Quick test_constraint_parse_lt;
      Alcotest.test_case "<= upper bound inclusive"   `Quick test_constraint_parse_lte;
      Alcotest.test_case "> strict lower"             `Quick test_constraint_parse_gt;
      Alcotest.test_case ">= x, < y range"            `Quick test_constraint_parse_range;
      Alcotest.test_case "~> 1.2.3 three-component"  `Quick test_twiddle_wakka_three_component;
      Alcotest.test_case "~> 1.2 two-component"       `Quick test_twiddle_wakka_two_component;
      Alcotest.test_case "~> 1 one-component"         `Quick test_twiddle_wakka_one_component;
      Alcotest.test_case "~> 0.2 zero-major"          `Quick test_twiddle_wakka_zero_major;
      Alcotest.test_case "pre-release not selected"   `Quick test_pre_release_not_selected_by_non_pre_constraint;
      Alcotest.test_case "parse errors"               `Quick test_constraint_parse_errors;
    ];
    "project-deps", [
      Alcotest.test_case "registry dep toml keys"     `Quick test_project_registry_dep;
      Alcotest.test_case "git tag dep toml keys"      `Quick test_project_git_tag_dep;
      Alcotest.test_case "git branch dep toml keys"   `Quick test_project_git_branch_dep;
      Alcotest.test_case "all dep types load"         `Quick test_project_loads_all_dep_types;
    ];
    "lockfile", [
      Alcotest.test_case "write and read back"        `Quick test_lockfile_write_and_read_back;
      Alcotest.test_case "manifest hash deterministic" `Quick test_lockfile_manifest_hash;
      Alcotest.test_case "drift detection"            `Quick test_lockfile_drift_detection;
    ];
  ]
