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

(** A module that typechecks cleanly but triggers an unused_binding warning
    on its second parameter. *)
let warning_module_source ~mod_name =
  Printf.sprintf
    "mod %s do\n\n  fn f(x : Int, unused_param : Int) : Int do\n    x\n  end\n\nend\n"
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

let test_check_reports_warnings_from_combined_module () =
  with_project ~project_type:Project.Lib (fun _name root ->
      let extra = Filename.concat root (Filename.concat "lib" "warns.march") in
      write_file extra (warning_module_source ~mod_name:"Warns");
      (* A warning must not fail the build ... *)
      match Cmd_check.check () with
      | Error m -> Alcotest.fail ("expected Ok despite warning, got Error: " ^ m)
      | Ok _    -> ())

(** Regression test for a duplicate-declaration bug in [run_check_cmd]
    (bin/main.ml): each input file's auto-discovered/imported modules used
    to be nested inside that file's OWN wrapper DMod instead of emitted as
    flat top-level siblings, which (a) gave them the wrong qualified name
    and (b) hid cross-file duplicates from dedup — when N files were
    checked together, EACH file's independent [resolve_imports] call
    re-auto-discovers the whole search path, so any module visible to more
    than one input file got typechecked (and its diagnostics counted)
    once per file that saw it. Confirmed live against a real ~85-file
    project: checking 5 files together took 24x longer than checking 1,
    and a shared dependency's warning/error was counted once per file.
    Here: two clean files plus one file with a real warning must yield a
    total warning count of exactly 1, not once per other file in the
    batch (calls [Cmd_build.check_all] directly to inspect its returned
    warning count rather than relying on stderr text). *)
let test_check_does_not_duplicate_shared_module_diagnostics () =
  with_project ~project_type:Project.Lib (fun _name root ->
      let extra1 = Filename.concat root (Filename.concat "lib" "helper1.march") in
      let extra2 = Filename.concat root (Filename.concat "lib" "helper2.march") in
      let warns  = Filename.concat root (Filename.concat "lib" "warns.march") in
      write_file extra1 (good_module_source ~mod_name:"Helper1");
      write_file extra2 (good_module_source ~mod_name:"Helper2");
      write_file warns (warning_module_source ~mod_name:"Warns");
      match Project.load () with
      | Error msg -> Alcotest.fail ("project load failed: " ^ msg)
      | Ok proj ->
        let lib_dir = Filename.concat proj.Project.root "lib" in
        let files = Cmd_build.find_march_files lib_dir in
        let lib_path_env = Cmd_build.lib_path_env proj in
        let cache_dir = Filename.concat proj.Project.root (Filename.concat ".forge" "check-cache") in
        let (failed, _errors, warnings) = Cmd_build.check_all ~lib_path_env ~cache_dir files in
        Alcotest.(check int) "check succeeds (warnings don't fail a build)" 0 failed;
        Alcotest.(check int)
          "Warns.march's single unused-param warning is counted exactly once, \
           not once per other file checked alongside it"
          1 warnings)

(** Regression test for a stdlib-shadowing bug in [run_check_cmd]
    (bin/main.ml): the single-file `--check`/`--compile` path already strips
    a stdlib module from the combined declaration list when a project file
    shadows it by name (`extern_mod_names`, added specifically for a project
    `mod Crypto do` colliding with stdlib's own `Crypto`) — but the
    multi-file `check` subcommand never had the same guard, so both DMods
    named `Crypto` ended up in the combined module together. Confirmed live
    against two real ~85-file projects: an unrelated file shadowing stdlib
    `Crypto` corrupted typecheck state badly enough that a THIRD, completely
    unrelated file's own constructor became unresolvable, with no diagnostic
    pointing at the real cause. Minimizing the real repro down to three
    files was itself load-bearing: a bare two-constructor type used only
    through a same-file `Foo(n)` construction plus a same-file pattern match
    did NOT reproduce it — the corruption only showed up once (a) a
    SEPARATE file constructs the value via a qualified call (`Defs.make`)
    and (b) a THIRD file consumes it via a bare (unqualified) constructor
    pattern match, mirroring the real depot_url.march / depot_db_repo.march
    shape exactly. *)
let test_check_stdlib_shadow_does_not_corrupt_unrelated_module () =
  with_project ~project_type:Project.Lib (fun _name root ->
      let shadow = Filename.concat root (Filename.concat "lib" "crypto_shadow.march") in
      let defs   = Filename.concat root (Filename.concat "lib" "defs.march") in
      let user   = Filename.concat root (Filename.concat "lib" "user_mod.march") in
      (* Shadows stdlib's own `Crypto` module by name. *)
      write_file shadow "mod Crypto do\n\n  fn dummy() : Int do\n    1\n  end\n\nend\n";
      (* Defines a two-constructor type and builds it via a qualified call
         site elsewhere, entirely unrelated to Crypto. *)
      write_file defs
        "mod Defs do\n\n  type Thing = Foo(Int) | Bar(String)\n\n  \
         fn make(n) do\n    Foo(n)\n  end\n\nend\n";
      (* Consumes Defs.make's result via a BARE (unqualified) constructor
         pattern match — the shape that broke in the real repro. *)
      write_file user
        "mod UserMod do\n\n  fn use_it(n) do\n    \
         match Defs.make(n) do\n    \
         Foo(x) -> x\n    \
         Bar(_) -> 0\n    end\n  end\n\nend\n";
      match Cmd_check.check () with
      | Error m -> Alcotest.fail ("expected Ok despite the stdlib-shadowing file, got Error: " ^ m)
      | Ok _    -> ())

(** Rather than breaking PATH/MARCH_HOME to prove `march` isn't re-invoked
    (tried first — but that also perturbs `lib_path_env`, since
    `Toolchain.path_prefix ()` bakes the resolved toolchain's bin/ directly
    into the command string, so neutralizing toolchain resolution changes
    the cache key itself and defeats the cache on purpose), inspect the
    cache marker directly: exactly one marker after the first clean check,
    and its mtime unchanged after a second (should-be-cached) check — a
    real second invocation would rewrite it. *)
let test_check_cache_short_circuits_unchanged_rebuild () =
  with_project ~project_type:Project.Lib (fun _name root ->
      (match Cmd_check.check () with
       | Error m -> Alcotest.fail ("expected first check to pass: " ^ m)
       | Ok _    -> ());
      let cache_dir = Filename.concat root (Filename.concat ".forge" "check-cache") in
      if not (Sys.file_exists cache_dir) then
        Alcotest.fail "expected .forge/check-cache/ to exist after a clean check"
      else begin
        let markers = Sys.readdir cache_dir in
        (if Array.length markers <> 1 then
           Alcotest.fail (Printf.sprintf
             "expected exactly one cache marker after one clean check, got %d"
             (Array.length markers)));
        let marker_path = Filename.concat cache_dir markers.(0) in
        let mtime_before = (Unix.stat marker_path).Unix.st_mtime in
        (match Cmd_check.check () with
         | Error m -> Alcotest.fail ("expected second (cached) check to pass: " ^ m)
         | Ok _    -> ());
        let mtime_after = (Unix.stat marker_path).Unix.st_mtime in
        Alcotest.(check bool)
          "cache marker untouched by a cached repeat check (no real march invocation)"
          true (mtime_before = mtime_after)
      end)

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
      Alcotest.test_case "check reports warnings from combined module" `Quick
        test_check_reports_warnings_from_combined_module;
      Alcotest.test_case "check cache short-circuits unchanged rebuild" `Quick
        test_check_cache_short_circuits_unchanged_rebuild;
      Alcotest.test_case "check does not duplicate shared-module diagnostics" `Quick
        test_check_does_not_duplicate_shared_module_diagnostics;
      Alcotest.test_case "check: stdlib shadow does not corrupt an unrelated module" `Quick
        test_check_stdlib_shadow_does_not_corrupt_unrelated_module;
    ];
    "forge build", [
      Alcotest.test_case "lib with broken orphan fails build"     `Quick test_build_lib_with_broken_orphan_fails;
      Alcotest.test_case "clean lib builds (no binary emitted)"   `Quick test_build_lib_clean_succeeds;
      Alcotest.test_case "app with broken orphan fails in check"  `Quick test_build_app_with_broken_orphan_fails_before_compile;
    ];
  ]
