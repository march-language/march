(** Tests for lib-aware [forge build] and [forge check].

    Each test scaffolds a real project on disk, writes known-good or
    known-broken .march files into its lib/, invokes the library helpers
    directly, and asserts on the result.

    These tests shell out to the real [march] binary via [march --check],
    so [march] must be on PATH when the suite runs. *)

open March_forge

(* ------------------------------------------------------------------ helpers *)

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

(** Scaffold a fresh project, cd into it, run [f], then clean up.

    The prefix intentionally avoids the "test_" pattern so that
    [find_march_files] does not silently skip the scaffolded file — its
    name becomes the module name, which we need [march --check] to see. *)
let with_project ?(project_type=Project.Lib) f =
  let tmpdir = Filename.temp_dir "forge_buildcheck_" "" in
  let parent   = Filename.dirname tmpdir in
  let basename = Filename.basename tmpdir in
  Unix.rmdir tmpdir;
  let old_cwd = Sys.getcwd () in
  Unix.chdir parent;
  (match Scaffold.scaffold basename project_type with
   | Error msg ->
     Unix.chdir old_cwd;
     Alcotest.fail ("scaffold failed: " ^ msg)
   | Ok () -> ());
  let proj_root = Filename.concat parent basename in
  Unix.chdir proj_root;
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old_cwd;
        let _ = Sys.command
            (Printf.sprintf "rm -rf %s" (Filename.quote proj_root))
        in ())
    (fun () -> f basename proj_root)

(** A minimal valid March module that will typecheck cleanly. *)
let good_module_source ~mod_name =
  Printf.sprintf
    "mod %s do\n\n  fn answer() : Int do\n    42\n  end\n\nend\n"
    mod_name

(** A module with a type error: concatenating an Int onto a String. *)
let broken_module_source ~mod_name =
  Printf.sprintf
    "mod %s do\n\n  fn broken() : String do\n    \"count=\" ++ 1\n  end\n\nend\n"
    mod_name

(* -------------------------------------------------------------- forge check *)

let test_check_clean_lib () =
  with_project ~project_type:Project.Lib (fun _name _root ->
      (* The scaffold emits a single valid lib file.  check should succeed. *)
      match Cmd_check.check () with
      | Ok _    -> ()
      | Error m -> Alcotest.fail ("expected Ok, got Error: " ^ m))

let test_check_catches_broken_orphan_in_lib () =
  with_project ~project_type:Project.Lib (fun _name root ->
      (* Add a broken sibling.  forge check must return Error. *)
      let orphan_path = Filename.concat root (Filename.concat "lib" "orphan.march") in
      write_file orphan_path (broken_module_source ~mod_name:"Orphan");
      match Cmd_check.check () with
      | Ok msg  -> Alcotest.fail ("expected Error, got Ok: " ^ msg)
      | Error _ -> ())

let test_check_passes_with_multiple_clean_files () =
  with_project ~project_type:Project.Lib (fun _name root ->
      let extra = Filename.concat root (Filename.concat "lib" "helper.march") in
      write_file extra (good_module_source ~mod_name:"Helper");
      match Cmd_check.check () with
      | Ok _    -> ()
      | Error m -> Alcotest.fail ("expected Ok, got Error: " ^ m))

let test_check_empty_lib_fails () =
  with_project ~project_type:Project.Lib (fun name root ->
      (* Remove the scaffolded lib file — no .march files left. *)
      let scaffolded = Filename.concat root
          (Filename.concat "lib" (name ^ ".march")) in
      Sys.remove scaffolded;
      match Cmd_check.check () with
      | Ok msg  -> Alcotest.fail ("expected Error for empty lib, got Ok: " ^ msg)
      | Error _ -> ())

(* -------------------------------------------------------------- forge build *)

let test_build_lib_with_broken_orphan_fails () =
  with_project ~project_type:Project.Lib (fun _name root ->
      let orphan_path = Filename.concat root (Filename.concat "lib" "orphan.march") in
      write_file orphan_path (broken_module_source ~mod_name:"Orphan");
      match Cmd_build.build ~release:false () with
      | Ok out  -> Alcotest.fail ("expected Error, got Ok: " ^ out)
      | Error _ -> ())

let test_build_lib_clean_succeeds () =
  with_project ~project_type:Project.Lib (fun _name root ->
      let extra = Filename.concat root (Filename.concat "lib" "helper.march") in
      write_file extra (good_module_source ~mod_name:"Helper");
      match Cmd_build.build ~release:false () with
      | Ok _    -> ()
      | Error m -> Alcotest.fail ("expected Ok, got Error: " ^ m))

let test_build_app_with_broken_orphan_fails_before_compile () =
  (* An app project with a broken orphan should fail orphan-check
     before invoking the LLVM backend.  We can observe this purely
     from the Error result; whether the binary would have compiled
     is irrelevant. *)
  with_project ~project_type:Project.App (fun _name root ->
      let orphan_path = Filename.concat root (Filename.concat "lib" "orphan.march") in
      write_file orphan_path (broken_module_source ~mod_name:"Orphan");
      match Cmd_build.build ~release:false () with
      | Ok out  -> Alcotest.fail ("expected Error, got Ok: " ^ out)
      | Error m ->
        (* Verify the failure is from typecheck, not from a later stage. *)
        let contains_substring s sub =
          let n = String.length s and k = String.length sub in
          let rec loop i =
            if i + k > n then false
            else if String.sub s i k = sub then true
            else loop (i + 1)
          in loop 0
        in
        Alcotest.(check bool)
          "error mentions typecheck failure"
          true
          (contains_substring m "typecheck"))

(* -------------------------------------------------------------------- suite *)

let () =
  Alcotest.run "build_check" [
    "forge check", [
      Alcotest.test_case "clean lib project passes"          `Quick test_check_clean_lib;
      Alcotest.test_case "broken orphan in lib fails check"  `Quick test_check_catches_broken_orphan_in_lib;
      Alcotest.test_case "multiple clean files pass"         `Quick test_check_passes_with_multiple_clean_files;
      Alcotest.test_case "empty lib/ errors"                 `Quick test_check_empty_lib_fails;
    ];
    "forge build", [
      Alcotest.test_case "lib with broken orphan fails build"     `Quick test_build_lib_with_broken_orphan_fails;
      Alcotest.test_case "clean lib builds (no binary emitted)"   `Quick test_build_lib_clean_succeeds;
      Alcotest.test_case "app with broken orphan fails in check"  `Quick test_build_app_with_broken_orphan_fails_before_compile;
    ];
  ]
