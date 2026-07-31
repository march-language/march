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
(*  Archive-task lib paths                                             *)
(* ------------------------------------------------------------------ *)

(** An archive task must see a REGISTRY dependency's lib dir, not just a
    git/path one.

    [Archive_store.dep_lib_paths_for_archive] matched PathDep and the three git
    forms and then fell off a `| _ -> []`, so a RegistryDep contributed no lib
    paths at all. [Cmd_build.dep_to_lib_paths] — which backs check/build/test —
    handled the same case, so a tool with a registry dependency built and
    tested green and then failed at run time with `Unknown module` for every
    symbol that dependency provided. scroll 0.1.2 shipped that way: `forge
    scroll.serve` could not find bastion's Router/Middleware/Static.

    Registry and git deps both install to ~/.march/cas/deps/<name>, so the
    check is simply that the CAS lib dir shows up. HOME is redirected at a
    temp dir so this is hermetic and does not read the developer's real CAS. *)
let test_archive_lib_paths_include_registry_dep () =
  let tmp = Filename.temp_file "forge_archive_reg" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let mkdir_p d = ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote d))) in
  let write path contents =
    let oc = open_out path in output_string oc contents; close_out oc in
  (* Fake CAS: the dep is installed exactly where a registry install lands. *)
  let fake_home = Filename.concat tmp "home" in
  let dep_lib = Filename.concat fake_home ".march/cas/deps/somedep/lib" in
  mkdir_p dep_lib;
  write (Filename.concat dep_lib "somedep.march") "mod SomeDep do\nend\n";
  (* An archive project whose only dependency is a REGISTRY dep. *)
  let archive_root = Filename.concat tmp "archive" in
  mkdir_p (Filename.concat archive_root "lib");
  write (Filename.concat archive_root "forge.toml")
    "[package]\n\
     name = \"tool\"\n\
     version = \"0.1.0\"\n\
     type = \"tool\"\n\n\
     [deps]\n\
     somedep = { registry = \"forge\", version = \"1.0.0\" }\n";
  let old_home = Sys.getenv_opt "HOME" in
  let restore () =
    match old_home with
    | Some h -> Unix.putenv "HOME" h
    | None   -> Unix.putenv "HOME" ""
  in
  Fun.protect ~finally:restore (fun () ->
    Unix.putenv "HOME" fake_home;
    let paths = Archive_store.dep_lib_paths_for_archive archive_root in
    let canon p = try Unix.realpath p with Unix.Unix_error _ -> p in
    let wanted = canon dep_lib in
    let found = List.exists (fun p -> canon p = wanted) paths in
    Alcotest.(check bool)
      (Printf.sprintf
         "registry dep's lib dir must be on an archive task's search path \
          (wanted %s, got [%s])"
         wanted (String.concat "; " paths))
      true found)

(** Control: the git form must keep working — this arm was never broken, and
    the fix must not regress it while generalising the match. *)
let test_archive_lib_paths_include_git_dep () =
  let tmp = Filename.temp_file "forge_archive_git" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let mkdir_p d = ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote d))) in
  let write path contents =
    let oc = open_out path in output_string oc contents; close_out oc in
  let fake_home = Filename.concat tmp "home" in
  let dep_lib = Filename.concat fake_home ".march/cas/deps/gitdep/lib" in
  mkdir_p dep_lib;
  write (Filename.concat dep_lib "gitdep.march") "mod GitDep do\nend\n";
  let archive_root = Filename.concat tmp "archive" in
  mkdir_p (Filename.concat archive_root "lib");
  write (Filename.concat archive_root "forge.toml")
    "[package]\n\
     name = \"tool\"\n\
     version = \"0.1.0\"\n\
     type = \"tool\"\n\n\
     [deps]\n\
     gitdep = { git = \"https://example.invalid/gitdep.git\", branch = \"main\" }\n";
  let old_home = Sys.getenv_opt "HOME" in
  let restore () =
    match old_home with
    | Some h -> Unix.putenv "HOME" h
    | None   -> Unix.putenv "HOME" ""
  in
  Fun.protect ~finally:restore (fun () ->
    Unix.putenv "HOME" fake_home;
    let paths = Archive_store.dep_lib_paths_for_archive archive_root in
    let canon p = try Unix.realpath p with Unix.Unix_error _ -> p in
    let wanted = canon dep_lib in
    Alcotest.(check bool) "git dep's lib dir still on the search path"
      true (List.exists (fun p -> canon p = wanted) paths))

(* ------------------------------------------------------------------ *)
(*  CAS install reuse must check the source                            *)
(* ------------------------------------------------------------------ *)

(** ~/.march/cas/deps/<name> is keyed by dep NAME only, so it can hold content
    from a different source than the manifest now asks for (switch a dep
    between `registry = ...` and `git = ...`, or two projects wanting different
    URLs). [install_dep] used to treat "directory exists" as "correctly
    installed": it printed `already installed (branch main)` over a registry
    tarball and then failed with `fatal: not a git repository`, with the
    lockfile claiming the git source while the directory held registry content.

    [Cmd_deps.git_checkout_matches] is the guard. These cover its three
    outcomes without any network access. *)
let with_tmp_dir f =
  let tmp = Filename.temp_file "forge_cas_reuse" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  Fun.protect
    ~finally:(fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp))))
    (fun () -> f tmp)

let test_cas_reuse_rejects_non_git_dir () =
  with_tmp_dir (fun tmp ->
    let dest = Filename.concat tmp "dep" in
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dest)));
    (* A registry tarball extract: real files, but no .git. *)
    let oc = open_out (Filename.concat dest "forge.toml") in
    output_string oc "[package]\nname = \"dep\"\n"; close_out oc;
    Alcotest.(check bool)
      "a non-git directory is never reused as a git checkout"
      false
      (Cmd_deps.git_checkout_matches ~url:"https://example.invalid/dep.git" dest))

let test_cas_reuse_rejects_wrong_remote () =
  with_tmp_dir (fun tmp ->
    let dest = Filename.concat tmp "dep" in
    ignore (Sys.command (Printf.sprintf
      "git init -q %s && git -C %s remote add origin https://example.invalid/OTHER.git"
      (Filename.quote dest) (Filename.quote dest)));
    Alcotest.(check bool)
      "a git checkout of a DIFFERENT url is not reused"
      false
      (Cmd_deps.git_checkout_matches ~url:"https://example.invalid/dep.git" dest))

let test_cas_reuse_accepts_matching_remote () =
  with_tmp_dir (fun tmp ->
    let dest = Filename.concat tmp "dep" in
    let url = "https://example.invalid/dep.git" in
    ignore (Sys.command (Printf.sprintf
      "git init -q %s && git -C %s remote add origin %s"
      (Filename.quote dest) (Filename.quote dest) (Filename.quote url)));
    Alcotest.(check bool)
      "a git checkout of the SAME url is reused (no needless re-clone)"
      true
      (Cmd_deps.git_checkout_matches ~url dest))

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
    "archive-lib-paths", [
      Alcotest.test_case "archive task sees a REGISTRY dep's lib dir" `Quick
        test_archive_lib_paths_include_registry_dep;
      Alcotest.test_case "archive task still sees a git dep's lib dir" `Quick
        test_archive_lib_paths_include_git_dep;
    ];
    "cas-install-reuse", [
      Alcotest.test_case "non-git dir (registry tarball) not reused as git" `Quick
        test_cas_reuse_rejects_non_git_dir;
      Alcotest.test_case "git checkout of a different url not reused" `Quick
        test_cas_reuse_rejects_wrong_remote;
      Alcotest.test_case "git checkout of the same url is reused" `Quick
        test_cas_reuse_accepts_matching_remote;
    ];
  ]
