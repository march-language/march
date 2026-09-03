(** Tests for lib-aware [forge build] and [forge check].

    Each test scaffolds a real project on disk, writes known-good or
    known-broken .march files into its lib/, invokes the library helpers
    directly, and asserts on the result.

    These tests shell out to the real [march] binary via [march --check],
    so [march] must be on PATH when the suite runs. *)

open March_forge

(* ------------------------------------------------------------------ helpers *)

(** Point the whole suite at the JUST-BUILT compiler instead of whatever
    [march] happens to be on the ambient PATH (or, via the [~/.march/current]
    global toolchain symlink, an installed release). The dune rule sets
    [MARCH_TEST_BIN] to [%{bin:march}] and guarantees it is built; we symlink
    it as [march] into a fresh bin/ prepended to PATH, and repoint MARCH_HOME
    at an empty dir so [Toolchain.path_prefix] resolves no global toolchain and
    the bare [march] in [Cmd_build.check_all] hits our symlink.

    This makes the suite hermetic and host-independent, which is the exact fix
    for its CI/local divergence: CI (a fresh checkout with no [.march-version]
    pin, no [~/.march/current], and no [march] on PATH) resolved to a bare
    [march] that did not exist, so EVERY subprocess failed identically as
    "typecheck failed" — success-expecting cases all failed and Error-expecting
    cases trivially passed. Locally the same suite silently exercised the
    installed release via the global symlink, not the build under test. *)
let setup_hermetic_march () =
  match Sys.getenv_opt "MARCH_TEST_BIN" with
  | None | Some "" ->
    prerr_endline
      "test_build_check: MARCH_TEST_BIN is not set. The dune rule must pass the \
       built compiler (see forge/test/dune) — refusing to fall back to an \
       ambient PATH `march`, which would not exercise this build.";
    exit 2
  | Some rel ->
    let abs =
      if Filename.is_relative rel then Filename.concat (Sys.getcwd ()) rel else rel
    in
    if not (Sys.file_exists abs) then begin
      Printf.eprintf "test_build_check: MARCH_TEST_BIN %s does not exist\n" abs;
      exit 2
    end;
    let bindir = Filename.temp_dir "march_hermetic_bin_" "" in
    let link = Filename.concat bindir "march" in
    (try Unix.symlink abs link
     with Unix.Unix_error _ ->
       (* Symlinks unavailable — fall back to a copy. *)
       ignore (Sys.command (Printf.sprintf "cp %s %s && chmod +x %s"
                              (Filename.quote abs) (Filename.quote link)
                              (Filename.quote link))));
    let old_path = match Sys.getenv_opt "PATH" with Some p -> p | None -> "" in
    Unix.putenv "PATH" (bindir ^ ":" ^ old_path);
    (* Empty MARCH_HOME → no global toolchain resolves → path_prefix stays empty
       → the bare `march` in the subprocess commands hits our PATH symlink. *)
    Unix.putenv "MARCH_HOME" (Filename.temp_dir "march_hermetic_home_" "")

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec loop i =
    if i + k > n then false
    else if String.sub s i k = sub then true
    else loop (i + 1)
  in loop 0

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

(* --------------------------------------------------- forge fix --contracts *)

let read_file_text path =
  let ic = open_in path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; s

(* `bump` reuses its Box in place, so it is in the default generation scope;
   `add` is verified clean but has nothing to protect. *)
let contracts_module ~mod_name =
  Printf.sprintf
    "mod %s do\n\n\
    \  ptype Box = Box(Int, Int)\n\n\
    \  fn bump(b : Box) : Box do\n\
    \    match b do\n\
    \      Box(x, y) -> Box(x + 1, y)\n\
    \    end\n\
    \  end\n\n\
    \  fn add(a : Int, b : Int) : Int do\n\
    \    a + b\n\
    \  end\n\n\
     end\n"
    mod_name

(* What `forge fix --contracts` shells out to, run directly and with BOTH
   streams captured.  Without this the suite can only say "nothing was
   inserted", which is true of a clean compile that found no candidate AND of
   a compile that died before printing anything — two very different bugs. *)
let report_contracts_output file =
  let tmp = Filename.temp_file "report_contracts" ".out" in
  let rc =
    Sys.command (Printf.sprintf "march --compile --report-contracts %s > %s 2>&1"
                   (Filename.quote file) (Filename.quote tmp)) in
  let ic = open_in tmp in
  let out = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (try Sys.remove tmp with Sys_error _ -> ());
  (rc, out)

let test_fix_contracts_inserts_and_is_idempotent () =
  setup_hermetic_march ();
  with_project ~project_type:Project.Lib (fun name root ->
      ignore name;
      let f = Filename.concat (Filename.concat root "lib") "boxes.march" in
      write_file f (contracts_module ~mod_name:"Boxes");
      (* Non-vacuity: prove the compiler emits a candidate for `bump` before
         asserting that forge applied one.  A failure here names the actual
         compiler output instead of leaving an empty diff to guess at. *)
      let (rc, out) = report_contracts_output f in
      if rc <> 0 || not (contains out "`bump`") then
        Alcotest.failf
          "march --compile --report-contracts did not report `bump` (rc=%d):\n%s"
          rc out;
      (match Cmd_fix.run ~contracts:true () with
       | Ok _ -> ()
       | Error e -> Alcotest.failf "forge fix --contracts failed: %s" e);
      let after = read_file_text f in
      Alcotest.(check bool) "bump got the attribute" true
        (contains after "@[no_alloc]\n  fn bump");
      Alcotest.(check bool) "add did not (no reuse to protect)" false
        (contains after "@[no_alloc]\n  fn add");
      (* A second run must be a no-op: bump now carries the attribute, so it
         is out of scope. *)
      (match Cmd_fix.run ~contracts:true () with
       | Ok _ -> () | Error e -> Alcotest.failf "second run failed: %s" e);
      Alcotest.(check string) "file unchanged by the second run" after
        (read_file_text f))

let test_fix_without_contracts_inserts_nothing () =
  setup_hermetic_march ();
  with_project ~project_type:Project.Lib (fun name root ->
      ignore name;
      let f = Filename.concat (Filename.concat root "lib") "boxes.march" in
      write_file f (contracts_module ~mod_name:"Boxes");
      (match Cmd_fix.run () with
       | Ok _ -> () | Error e -> Alcotest.failf "forge fix failed: %s" e);
      Alcotest.(check bool) "no contract inserted without --contracts" false
        (contains (read_file_text f) "@[no_alloc]"))

let test_fix_contracts_honors_forge_toml_globs () =
  setup_hermetic_march ();
  with_project ~project_type:Project.Lib (fun name root ->
      ignore name;
      let f = Filename.concat (Filename.concat root "lib") "boxes.march" in
      write_file f (contracts_module ~mod_name:"Boxes");
      let toml = Filename.concat root "forge.toml" in
      let cur = read_file_text toml in
      write_file toml (cur ^ "\n[contracts]\nno_alloc = [\"*add\"]\n");
      (match Cmd_fix.run ~contracts:true () with
       | Ok _ -> () | Error e -> Alcotest.failf "forge fix --contracts failed: %s" e);
      Alcotest.(check bool) "add is in scope via the glob" true
        (contains (read_file_text f) "@[no_alloc]\n  fn add"))

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

(** Regression test for a module-ordering bug in [dependency_order_dmod_run]
    (lib/typecheck/typecheck.ml): sibling modules that mutually reference each
    other through QUALIFIED calls (a "soft" dependency — tolerated regardless
    of check order via pass-1 placeholders, see [prebind_mod_members]) can
    form a real cycle, e.g. a facade module delegating to an internal worker
    module which delegates back to the facade's own module.  One of those
    modules can ALSO bare-pattern-match a constructor owned by another sibling
    (a "hard" dependency — the defining module's DMod must actually be
    processed by [check_decl] first, since bare ctor names have no pass-1
    placeholder). The ordering DFS previously mixed both kinds of edges into
    one graph and picked whichever edge it reached an ancestor through first —
    so a soft-edge cycle could silently push the hard dependency's definer
    AFTER its bare-pattern-matching dependent, producing a spurious "I cannot
    find `Ctor`" error despite the constructor being correctly declared.
    Confirmed live against a real project (`conduit`): a base module
    delegating to `Conduit.API`, which calls into `Conduit.Worker`, which
    bare-matches a constructor (`WorkerError`) declared in the base module.
    Minimized here to the same three-module shape.

    The bug is order-sensitive: it only reproduces when the DMod carrying the
    hard dependency's DEFINITION is the first one the ordering DFS visits (it
    then sits "in progress" while recursing through the soft-edge cycle, so
    the hard dependent gets pushed to the output before it — see the fix's
    comment in [dependency_order_dmod_run] for the full mechanics).
    [Cmd_build.find_march_files] walks directory entries in ascending sorted
    order but PREPENDS each match, so the file list handed to `march check`
    ends up in *descending* alphabetical order — hence naming this file
    `zcore.march`: it sorts last ascending, so it is discovered FIRST. *)
let test_check_qualified_cycle_does_not_break_bare_ctor_ordering () =
  with_project ~project_type:Project.Lib (fun _name root ->
      let core   = Filename.concat root (Filename.concat "lib" "zcore.march") in
      let facade = Filename.concat root (Filename.concat "lib" "facade.march") in
      let worker = Filename.concat root (Filename.concat "lib" "worker.march") in
      (* Core delegates to Facade via a QUALIFIED call (soft edge, tolerates
         any order) and declares a type whose constructor is only ever
         referenced BARE by a different sibling below (hard edge). *)
      write_file core
        "mod Core do\n\n  type CoreError = Bad(String)\n\n  \
         fn delegate(x) do\n    Facade.run(x)\n  end\n\nend\n";
      (* Facade delegates to Worker via a QUALIFIED call (soft edge). *)
      write_file facade
        "mod Facade do\n\n  fn run(x) do\n    Worker.process(x)\n  end\n\nend\n";
      (* Worker closes the qualified cycle back to Core, AND bare-matches
         Core's constructor — the hard edge that must win the ordering. *)
      write_file worker
        "mod Worker do\n\n  fn process(x) do\n    \
         match x do\n    \
         Bad(msg) -> msg\n    \
         _ -> \"\"\n    end\n  end\n\nend\n";
      match Cmd_check.check () with
      | Error m ->
        Alcotest.fail
          ("expected Ok despite the qualified-call cycle between Core/Facade/Worker, \
            got Error: " ^ m)
      | Ok _ -> ())

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

(** Scaffold a minimal standalone lib project by hand (no [Scaffold], since
    we need full control over its [deps] section): [name]/forge.toml +
    [name]/lib/, with [deps] entries pointing at other path-dep roots. *)
let make_path_dep_project ~name ~deps =
  let root = Filename.temp_dir ("forge_transdep_" ^ name ^ "_") "" in
  Unix.mkdir (Filename.concat root "lib") 0o755;
  let deps_lines = String.concat "" (List.map (fun (dep_name, dep_root) ->
      Printf.sprintf "%s = { path = %S }\n" dep_name dep_root) deps) in
  write_file (Filename.concat root "forge.toml")
    (Printf.sprintf
       "[package]\nname = %S\nversion = \"0.1.0\"\ntype = \"lib\"\n\n[deps]\n%s"
       name deps_lines);
  root

(** Regression test for forge's dependency resolver not walking transitive
    deps: a project depending on B (path dep), where B itself depends on C
    (path dep), never got C on its own MARCH_LIB_PATH — so C's modules were
    unreachable to the depending project's own code even though B could see
    them directly. Confirmed live: `scroll` depends on `bastion` (path/git
    dep), `bastion` itself depends on `depot` (git dep); scroll's own
    `forge check` failed with "Unknown module Pool" (a depot module) until
    [Cmd_build.lib_path_env] and [Cmd_deps.run]'s install walk were both
    made to recurse into each dep's own forge.toml. Repro: A depends on B
    via path; B depends on C via path; A's own code calls C's module
    directly (never imports B at all) — this only typechecks if C's lib/
    made it onto A's MARCH_LIB_PATH transitively through B. *)
let test_lib_path_env_walks_transitive_path_deps () =
  let c_root = make_path_dep_project ~name:"leafc" ~deps:[] in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote c_root)) in ())
    (fun () ->
      write_file (Filename.concat c_root (Filename.concat "lib" "leaf.march"))
        "mod Leaf do\n\n  fn value() : Int do\n    99\n  end\n\nend\n";
      let b_root = make_path_dep_project ~name:"midb" ~deps:["leafc", c_root] in
      Fun.protect ~finally:(fun () ->
          let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote b_root)) in ())
        (fun () ->
          write_file (Filename.concat b_root (Filename.concat "lib" "mid.march"))
            "mod Mid do\n\n  fn value() : Int do\n    1\n  end\n\nend\n";
          with_project ~project_type:Project.Lib (fun _name root ->
              let toml_path = Filename.concat root "forge.toml" in
              let oc = open_out_gen [Open_append] 0o644 toml_path in
              Printf.fprintf oc "\n[deps.midb]\npath = %S\n" b_root;
              close_out oc;
              let user_mod = Filename.concat root (Filename.concat "lib" "user_mod.march") in
              write_file user_mod
                "mod UserMod do\n\n  fn use_leaf() : Int do\n    Leaf.value()\n  end\n\nend\n";
              match Cmd_check.check () with
              | Error m ->
                Alcotest.fail
                  ("expected transitive dep leafc's Leaf module to be reachable \
                    through midb, got Error: " ^ m)
              | Ok _ -> ())))

(** Regression for the direct-vs-transitive same-name dep precedence bug.

    A depends DIRECTLY (path) on both [midb] and [leafc]; [midb] itself
    depends on [leafc] via a GIT dep (which resolves to the empty CAS dir
    and contributes NO lib path).  [collect_transitive_deps] used to walk
    DEPTH-FIRST: for [deps = [midb; leafc]] it descended into midb's deps and
    claimed midb's git `leafc` FIRST, so A's own direct path `leafc` was
    dropped as already-visited — leaving leafc's lib entirely off
    MARCH_LIB_PATH.  A's own code calling [Leaf.value()] then failed with
    "Unknown module Leaf" even though A directly path-deps leafc.

    This is the minimal shape of the observed bastion+depot+march_doc failure:
    bastion git-deps depot, the consumer path-deps depot, and depot's modules
    (Depot/Connection/Db/Pool + their constructors) all went unresolvable.

    The fix walks BREADTH-FIRST by depth, so every DIRECT dep is claimed
    before any transitive dep — the direct path dep wins. *)
let test_direct_path_dep_beats_transitive_git_dep () =
  let c_root = make_path_dep_project ~name:"leafc" ~deps:[] in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote c_root)) in ())
    (fun () ->
      write_file (Filename.concat c_root (Filename.concat "lib" "leaf.march"))
        "mod Leaf do\n\n  fn value() : Int do\n    99\n  end\n\nend\n";
      (* midb: same-named [leafc] dep, but via GIT (unresolvable — empty CAS). *)
      let b_root = Filename.temp_dir "forge_transdep_midb_" "" in
      Unix.mkdir (Filename.concat b_root "lib") 0o755;
      write_file (Filename.concat b_root "forge.toml")
        "[package]\nname = \"midb\"\nversion = \"0.1.0\"\ntype = \"lib\"\n\n\
         [deps]\nleafc = { git = \"https://example.invalid/leafc.git\", branch = \"main\" }\n";
      write_file (Filename.concat b_root (Filename.concat "lib" "mid.march"))
        "mod Mid do\n\n  fn value() : Int do\n    1\n  end\n\nend\n";
      Fun.protect ~finally:(fun () ->
          let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote b_root)) in ())
        (fun () ->
          with_project ~project_type:Project.Lib (fun _name root ->
              let toml_path = Filename.concat root "forge.toml" in
              let oc = open_out_gen [Open_append] 0o644 toml_path in
              (* midb declared BEFORE leafc so a depth-first walk hits midb's
                 transitive git `leafc` before A's own direct path `leafc`. *)
              Printf.fprintf oc "\n[deps.midb]\npath = %S\n" b_root;
              Printf.fprintf oc "\n[deps.leafc]\npath = %S\n" c_root;
              close_out oc;
              let user_mod = Filename.concat root (Filename.concat "lib" "user_mod.march") in
              write_file user_mod
                "mod UserMod do\n\n  fn use_leaf() : Int do\n    Leaf.value()\n  end\n\nend\n";
              match Cmd_check.check () with
              | Error m ->
                Alcotest.fail
                  ("expected A's DIRECT path dep leafc to win over midb's \
                    transitive git leafc, got Error: " ^ m)
              | Ok _ -> ())))

(** Regression test: `forge test`'s [Cmd_test.project_env] must prepend the
    same toolchain PATH prefix as `forge build`'s [Cmd_build.lib_path_env],
    so the bare `march` invoked by `forge test` resolves to the project's
    pinned `.march-version` rather than whatever `march` happens to be on
    the ambient PATH. Confirmed live: a project pinned to a toolchain other
    than the one on PATH had `forge check` honor the pin but `forge test`
    silently compile with the ambient (wrong) compiler. *)
let test_project_env_honors_toolchain_pin () =
  let old_march_home = Sys.getenv_opt "MARCH_HOME" in
  Fun.protect ~finally:(fun () ->
      match old_march_home with
      | Some h -> Unix.putenv "MARCH_HOME" h
      | None -> Unix.putenv "MARCH_HOME" "")
    (fun () ->
      with_project ~project_type:Project.Lib (fun _name root ->
          let home = Filename.temp_dir "march_home_" "" in
          Unix.putenv "MARCH_HOME" home;
          let bin = Filename.concat (Filename.concat (Filename.concat home "versions") "0.6.0") "bin" in
          let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote bin)) in
          let march_stub = Filename.concat bin "march" in
          let oc = open_out march_stub in
          output_string oc "#!/bin/sh\n";
          close_out oc;
          let _ = Sys.command (Printf.sprintf "chmod +x %s" (Filename.quote march_stub)) in
          let oc = open_out (Filename.concat root ".march-version") in
          output_string oc "0.6.0\n";
          close_out oc;
          match Project.load () with
          | Error m -> Alcotest.fail ("expected project to load: " ^ m)
          | Ok proj ->
            let (lib_path_env, _output, _all_lib_paths, toolchain_pfx) =
              Cmd_test.project_env proj in
            Alcotest.(check bool) "toolchain_pfx points at the pinned version's bin"
              true (contains toolchain_pfx "versions/0.6.0/bin");
            Alcotest.(check bool) "lib_path_env is prefixed with the toolchain PATH override"
              true (contains lib_path_env "versions/0.6.0/bin")))

(** Regression test: `forge test`'s [Cmd_test.project_env] must walk the
    dependency graph TRANSITIVELY, exactly as [Cmd_build.lib_path_env] does.

    [project_env] used to map [dep_to_lib_paths] over the DIRECT test-scope
    deps only, so a project depending on B (which itself depends on C) got
    C's lib/ on MARCH_LIB_PATH under `forge build`/`forge check` but NOT
    under `forge test` — tests calling a transitive dep's module failed with
    "Unknown module ..." even though the same call typechecked in lib/. *)
let test_project_env_walks_transitive_path_deps () =
  let c_root = make_path_dep_project ~name:"leafc" ~deps:[] in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote c_root)) in ())
    (fun () ->
      write_file (Filename.concat c_root (Filename.concat "lib" "leaf.march"))
        "mod Leaf do\n\n  fn value() : Int do\n    99\n  end\n\nend\n";
      let b_root = make_path_dep_project ~name:"midb" ~deps:["leafc", c_root] in
      Fun.protect ~finally:(fun () ->
          let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote b_root)) in ())
        (fun () ->
          write_file (Filename.concat b_root (Filename.concat "lib" "mid.march"))
            "mod Mid do\n\n  fn value() : Int do\n    1\n  end\n\nend\n";
          with_project ~project_type:Project.Lib (fun _name root ->
              let toml_path = Filename.concat root "forge.toml" in
              let oc = open_out_gen [Open_append] 0o644 toml_path in
              Printf.fprintf oc "\n[deps.midb]\npath = %S\n" b_root;
              close_out oc;
              match Project.load () with
              | Error m -> Alcotest.fail ("expected project to load: " ^ m)
              | Ok proj ->
                let (_env, _output, all_lib_paths, _pfx) = Cmd_test.project_env proj in
                let c_lib = Filename.concat c_root "lib" in
                Alcotest.(check bool)
                  "transitive dep leafc's lib/ is on the test MARCH_LIB_PATH"
                  true (List.mem c_lib all_lib_paths))))

(* --------------------------------------------------------------- forge run *)

(** [forge run] (INTERPRETED) must pass forge.toml's [[ffi]] sources through to
    the compiler as --ffi-c, exactly as `forge build` and interpreted
    `forge test` already do.

    Without them the compiler's [setup_interpreter_ffi] sees an empty
    [ffi_c_files], builds no shim .so, and every extern call dies at RUNTIME
    with "symbol not found for interpreter FFI (build the runtime, or run with
    --compile)" — i.e. an app declaring [[ffi]] sources could not be run
    interpreted AT ALL, only via --compile.

    This asserts on the PROGRAM'S OUTPUT (42), not merely on an Ok result:
    the extern is only actually resolved and called if the shim was built and
    dlopened, so a constant/short-circuit cannot satisfy it.  A status-only
    assertion would also be satisfied by a run that never reached the extern. *)
let test_run_interpreted_passes_ffi_sources () =
  with_project ~project_type:Project.App (fun name root ->
      (* A C shim OUTSIDE the runtime: the symbol exists nowhere unless
         forge passes --ffi-c and the compiler builds the shim .so. *)
      let c_dir = Filename.concat root "c" in
      Unix.mkdir c_dir 0o755;
      write_file (Filename.concat c_dir "shim.c")
        "#include <stdint.h>\nint64_t forge_run_ffi_triple(int64_t x) { return x * 3; }\n";
      let toml_path = Filename.concat root "forge.toml" in
      let oc = open_out_gen [Open_append] 0o644 toml_path in
      Printf.fprintf oc "\n[ffi]\nsources = [\"c/shim.c\"]\n";
      close_out oc;
      (* Overwrite the scaffolded entry with one that calls the extern. *)
      let entry = Filename.concat root (Filename.concat "lib" (name ^ ".march")) in
      let mod_name =
        String.mapi (fun i c -> if i = 0 then Char.uppercase_ascii c else c) name in
      write_file entry (Printf.sprintf
        "mod %s do\n\
        \  needs IO.Console\n\
        \  needs Ffi\n\
        \  needs IO.Foreign\n\n\
        \  extern \"shim\" : Cap(Ffi) do\n\
        \    fn triple(x: Int): Int = \"forge_run_ffi_triple\"\n\
        \  end\n\n\
        \  fn main(_c : Cap(IO.Console), _f : Cap(IO.Foreign)) : Unit do\n\
        \    println(int_to_string(triple(14)))\n\
        \  end\n\
         end\n" mod_name);
      (* Capture stdout: the assertion is on the VALUE the extern returned. *)
      let out_file = Filename.concat root "run.out" in
      let saved = Unix.dup Unix.stdout in
      let fd = Unix.openfile out_file [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
      Unix.dup2 fd Unix.stdout;
      Unix.close fd;
      let result =
        Fun.protect
          ~finally:(fun () ->
              flush stdout; Unix.dup2 saved Unix.stdout; Unix.close saved)
          (fun () -> let r = Cmd_run.run () in flush stdout; r)
      in
      let output =
        try
          let ic = open_in_bin out_file in
          let n = in_channel_length ic in
          let s = really_input_string ic n in
          close_in ic; s
        with _ -> "(no output captured)"
      in
      (match result with
       | Error m ->
         Alcotest.fail
           ("forge run (interpreted) with [ffi] sources failed: " ^ m
            ^ "\n--- program output ---\n" ^ output)
       | Ok () -> ());
      Alcotest.(check bool)
        ("the extern actually ran and returned 14*3=42 (got: "
         ^ String.trim output ^ ")")
        true (contains output "42"))

(* -------------------------------------------------------------------- suite *)

let () =
  setup_hermetic_march ();
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
      Alcotest.test_case "check: qualified-call cycle does not break bare ctor ordering" `Quick
        test_check_qualified_cycle_does_not_break_bare_ctor_ordering;
      Alcotest.test_case "lib_path_env walks transitive path deps" `Quick
        test_lib_path_env_walks_transitive_path_deps;
      Alcotest.test_case "direct path dep beats transitive git dep of same name" `Quick
        test_direct_path_dep_beats_transitive_git_dep;
    ];
    "forge build", [
      Alcotest.test_case "lib with broken orphan fails build"     `Quick test_build_lib_with_broken_orphan_fails;
      Alcotest.test_case "clean lib builds (no binary emitted)"   `Quick test_build_lib_clean_succeeds;
      Alcotest.test_case "app with broken orphan fails in check"  `Quick test_build_app_with_broken_orphan_fails_before_compile;
    ];
    "forge test", [
      Alcotest.test_case "project_env honors .march-version toolchain pin" `Quick
        test_project_env_honors_toolchain_pin;
      Alcotest.test_case "project_env walks transitive path deps" `Quick
        test_project_env_walks_transitive_path_deps;
    ];
    "forge run", [
      Alcotest.test_case "interpreted run passes [ffi] sources to the compiler" `Quick
        test_run_interpreted_passes_ffi_sources;
    ];
    "forge fix --contracts", [
      Alcotest.test_case "inserts @[no_alloc] and is idempotent" `Quick
        test_fix_contracts_inserts_and_is_idempotent;
      Alcotest.test_case "plain forge fix inserts no contract" `Quick
        test_fix_without_contracts_inserts_nothing;
      Alcotest.test_case "forge.toml globs widen the scope" `Quick
        test_fix_contracts_honors_forge_toml_globs;
    ];
  ]
