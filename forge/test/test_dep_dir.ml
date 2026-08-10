(** Regression test for `forge audit`/`forge licenses`/`forge tree`'s
    dependency-directory resolution.

    All three commands independently reimplemented a [dep_dir] helper that
    computed git/registry dep locations under [<project_root>/.march/cas/deps]
    — but the actual installer ([Cmd_deps]/[Project.dep_root_dir]) installs
    them under [$HOME/.march/cas/deps] instead, a global cross-project
    location. That mismatch meant a just-installed git/registry dep was
    always reported "not installed" by these three commands.

    Existing tests for these commands (test_forge.ml, test_audit.ml) only
    exercise pure helpers or PathDep — which resolves relative to the
    project and never touched the buggy branch — so they never caught this.
    This test fakes HOME with a pre-populated fixture to exercise the
    git/registry branch of each command's [dep_dir] directly. *)

open March_forge

let tmp_dir prefix =
  let base = Filename.get_temp_dir_name () in
  let rec attempt n =
    let path = Filename.concat base (Printf.sprintf "%s-%d-%d" prefix (Unix.getpid ()) n) in
    if Sys.file_exists path then attempt (n + 1)
    else (Unix.mkdir path 0o755; path)
  in
  attempt 0

let rec rm_rf path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun n -> rm_rf (Filename.concat path n)) (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

let mkdir_p dir =
  let rec go d =
    if not (Sys.file_exists d) then begin
      go (Filename.dirname d);
      (try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    end
  in
  go dir

(* Run [f home] with HOME overridden to a fresh temp dir, restoring the
   previous value (or unsetting it) and cleaning up afterward. *)
let with_fake_home f =
  let home = tmp_dir "dep-dir-home" in
  let prev = Sys.getenv_opt "HOME" in
  Unix.putenv "HOME" home;
  Fun.protect
    ~finally:(fun () ->
      (match prev with Some h -> Unix.putenv "HOME" h | None -> ());
      rm_rf home)
    (fun () -> f home)

let git_dep = Project.GitTagDep { url = "https://example.com/widget.git"; tag = "v1.0" }
let registry_dep = Project.RegistryDep { version = "~> 1.0" }

let expected_cas_path home name =
  Filename.concat home
    (Filename.concat ".march" (Filename.concat "cas" (Filename.concat "deps" name)))

let wrong_project_root_path proj_root name =
  Filename.concat proj_root
    (Filename.concat ".march" (Filename.concat "cas" (Filename.concat "deps" name)))

(* For each command, a git/registry dep must resolve under $HOME (where
   `forge deps` actually installs it) and NOT under <project_root>/.march
   (the bug: that directory is never created by the installer). *)
let check_resolves_under_home ~what dep_dir_fn =
  with_fake_home (fun home ->
      let name = "widget" in
      mkdir_p (expected_cas_path home name);
      let proj_root = tmp_dir "dep-dir-proj" in
      let resolved = dep_dir_fn ~base:proj_root ~name ~dep:git_dep in
      let wrong = wrong_project_root_path proj_root name in
      rm_rf proj_root;
      Alcotest.(check string) (what ^ ": resolves to the real $HOME install location")
        (expected_cas_path home name) resolved;
      Alcotest.(check bool) (what ^ ": does NOT resolve under the project root")
        true (resolved <> wrong))

let check_registry_dep_resolves_under_home ~what dep_dir_fn =
  with_fake_home (fun home ->
      let name = "gadget" in
      mkdir_p (expected_cas_path home name);
      let proj_root = tmp_dir "dep-dir-proj" in
      let resolved = dep_dir_fn ~base:proj_root ~name ~dep:registry_dep in
      rm_rf proj_root;
      Alcotest.(check string) (what ^ ": registry dep resolves under $HOME too")
        (expected_cas_path home name) resolved)

let check_path_dep_unaffected ~what dep_dir_fn =
  let proj_root = tmp_dir "dep-dir-proj" in
  let vendor = Filename.concat proj_root "vendor/thing" in
  mkdir_p vendor;
  let dep = Project.PathDep "vendor/thing" in
  let resolved = dep_dir_fn ~base:proj_root ~name:"thing" ~dep in
  rm_rf proj_root;
  Alcotest.(check string) (what ^ ": PathDep still relative to declaring root")
    vendor resolved

let cases ~what dep_dir_fn =
  [ Alcotest.test_case (what ^ ": git dep under $HOME") `Quick
      (fun () -> check_resolves_under_home ~what dep_dir_fn);
    Alcotest.test_case (what ^ ": registry dep under $HOME") `Quick
      (fun () -> check_registry_dep_resolves_under_home ~what dep_dir_fn);
    Alcotest.test_case (what ^ ": PathDep unaffected") `Quick
      (fun () -> check_path_dep_unaffected ~what dep_dir_fn) ]

let () =
  Alcotest.run "forge-dep-dir"
    [ ( "Cmd_audit.dep_dir",
        cases ~what:"audit" (fun ~base ~name ~dep -> Cmd_audit.dep_dir ~base ~name ~dep) );
      ( "Cmd_licenses.dep_dir",
        cases ~what:"licenses" (fun ~base ~name ~dep -> Cmd_licenses.dep_dir ~base ~name ~dep) );
      ( "Cmd_tree.dep_dir",
        cases ~what:"tree" (fun ~base ~name ~dep -> Cmd_tree.dep_dir ~base ~name ~dep) ) ]
