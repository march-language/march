(** Tests for the forge scaffolder and TOML parser *)

open March_forge

(* ------------------------------------------------------------------ helpers *)

let read_file path =
  let ic = open_in path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(** Run [f basename] in a temporary directory.
    The basename is the name of the project to scaffold. *)
let with_temp_parent f =
  let tmpdir = Filename.temp_dir "test_forge_" "" in
  let parent  = Filename.dirname tmpdir in
  let basename = Filename.basename tmpdir in
  Unix.rmdir tmpdir;               (* scaffold will create it *)
  let old_cwd = Sys.getcwd () in
  Unix.chdir parent;
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old_cwd;
        let _ = Sys.command
            (Printf.sprintf "rm -rf %s"
               (Filename.quote (Filename.concat parent basename)))
        in ())
    (fun () -> f basename)

(* ---------------------------------------------------------------- scaffolder *)

let test_scaffold_app () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.App with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let exists path =
        Alcotest.(check bool) ("exists: " ^ path) true
          (Sys.file_exists (Filename.concat name path))
      in
      exists "forge.toml";
      exists "README.md";
      exists ".editorconfig";
      exists ".gitignore";
      exists (Filename.concat "lib"  (name ^ ".march"));
      exists (Filename.concat "test" (name ^ "_test.march")))

let test_scaffold_lib () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.Lib with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let content = read_file (Filename.concat name "forge.toml") in
      let doc  = Toml.parse content in
      let pkg  = Toml.get_section doc "package" in
      Alcotest.(check (option string)) "type=lib"
        (Some "lib") (Toml.get_string pkg "type"))

let test_scaffold_tool () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.Tool with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let content = read_file (Filename.concat name "forge.toml") in
      let doc = Toml.parse content in
      let pkg = Toml.get_section doc "package" in
      Alcotest.(check (option string)) "type=tool"
        (Some "tool") (Toml.get_string pkg "type"))

let test_forge_toml_fields () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.App with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let content = read_file (Filename.concat name "forge.toml") in
      let doc = Toml.parse content in
      let pkg = Toml.get_section doc "package" in
      Alcotest.(check (option string)) "name"    (Some name)    (Toml.get_string pkg "name");
      Alcotest.(check (option string)) "version" (Some "0.1.0") (Toml.get_string pkg "version");
      Alcotest.(check (option string)) "type"    (Some "app")   (Toml.get_string pkg "type"))

let test_duplicate_fails () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.App with
       | Error msg -> Alcotest.fail ("first scaffold failed: " ^ msg)
       | Ok () -> ());
      match Scaffold.scaffold name Project.App with
      | Error _ -> ()   (* expected: directory already exists *)
      | Ok ()   -> Alcotest.fail "expected error for duplicate directory")

let test_gitignore_has_march () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.App with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let content = read_file (Filename.concat name ".gitignore") in
      let lines = String.split_on_char '\n' content in
      Alcotest.(check bool) "/.march/ in .gitignore"
        true (List.mem "/.march/" lines))

let test_editorconfig_indent () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.App with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let content = read_file (Filename.concat name ".editorconfig") in
      let lines = String.split_on_char '\n' content in
      Alcotest.(check bool) "indent_size = 2 present"
        true (List.exists (fun l -> String.trim l = "indent_size = 2") lines))

let test_readme_has_name () =
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.App with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let content = read_file (Filename.concat name "README.md") in
      Alcotest.(check bool) "README contains capitalized name"
        true (let cap = String.capitalize_ascii name in
              let len_cap = String.length cap in
              let len_c   = String.length content in
              len_c >= len_cap &&
              String.sub content 0 len_cap = cap ||
              (* also allow "# Name" format *)
              len_c >= len_cap + 2 &&
              String.sub content 2 len_cap = cap))

(* ----------------------------------------------------------------- module naming *)

let test_module_name_is_pascal_case () =
  (* snake_case project names should produce PascalCase module names.
     "test_project" -> "mod TestProject do" not "mod Test_project do" *)
  with_temp_parent (fun name ->
      let proj_name = name ^ "_project" in
      (match Scaffold.scaffold proj_name Project.App with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let lib_src = read_file
          (Filename.concat proj_name
             (Filename.concat "lib" (proj_name ^ ".march"))) in
      (* Expected: "mod TestProject do" — no underscore in the module name *)
      let expected_parts = String.split_on_char '_' proj_name
          |> List.filter (fun p -> p <> "")
          |> List.map String.capitalize_ascii in
      let expected_mod = "mod " ^ String.concat "" expected_parts ^ " do" in
      Alcotest.(check bool) "module name is joined PascalCase"
        true (let len = String.length expected_mod in
              String.length lib_src >= len &&
              String.sub lib_src 0 len = expected_mod))

let test_generated_march_uses_do_end () =
  (* Generated functions must use 'do ... end' not '->' syntax *)
  with_temp_parent (fun name ->
      (match Scaffold.scaffold name Project.App with
       | Error msg -> Alcotest.fail msg
       | Ok () -> ());
      let lib_src  = read_file (Filename.concat name (Filename.concat "lib"  (name ^ ".march"))) in
      let test_src = read_file (Filename.concat name (Filename.concat "test" (name ^ "_test.march"))) in
      (* Both files should contain "do" and "end" but not "fn ... ->" pattern *)
      let contains s sub =
        let n = String.length s and m = String.length sub in
        let rec loop i = if i + m > n then false
          else if String.sub s i m = sub then true else loop (i + 1) in
        loop 0 in
      Alcotest.(check bool) "lib has do keyword"   true (contains lib_src  " do\n");
      Alcotest.(check bool) "test has do keyword"  true (contains test_src " do\n");
      Alcotest.(check bool) "lib has no fn ->"     false (contains lib_src  "fn main() ->");
      Alcotest.(check bool) "test has no fn ->"    false (contains test_src "fn test_placeholder() ->"))

(* ------------------------------------------------------------------- TOML parser *)

let test_toml_simple () =
  let text = {|
[package]
name = "myapp"
version = "0.1.0"
type = "app"
description = ""
author = ""
|} in
  let doc = Toml.parse text in
  let pkg = Toml.get_section doc "package" in
  Alcotest.(check (option string)) "name"    (Some "myapp") (Toml.get_string pkg "name");
  Alcotest.(check (option string)) "version" (Some "0.1.0") (Toml.get_string pkg "version");
  Alcotest.(check (option string)) "type"    (Some "app")   (Toml.get_string pkg "type")

let test_toml_inline_table () =
  let text = {|
[deps]
stdlib = { git = "https://github.com/march-language/stdlib", rev = "main" }
|} in
  let doc  = Toml.parse text in
  let deps = Toml.get_section doc "deps" in
  (match Toml.get_table deps "stdlib" with
   | None     -> Alcotest.fail "expected inline table for stdlib"
   | Some tbl ->
     Alcotest.(check (option string)) "git url"
       (Some "https://github.com/march-language/stdlib")
       (Toml.get_string tbl "git");
     Alcotest.(check (option string)) "rev"
       (Some "main")
       (Toml.get_string tbl "rev"))

let test_toml_path_dep () =
  let text = {|
[deps]
utils = { path = "../utils" }
|} in
  let doc  = Toml.parse text in
  let deps = Toml.get_section doc "deps" in
  (match Toml.get_table deps "utils" with
   | None     -> Alcotest.fail "expected inline table for utils"
   | Some tbl ->
     Alcotest.(check (option string)) "path"
       (Some "../utils")
       (Toml.get_string tbl "path"))

let test_toml_comments_ignored () =
  let text = {|
# This is a comment
[package]
# Another comment
name = "foo"   # inline comment treated as part of bare value (harmless)
|} in
  let doc = Toml.parse text in
  let pkg = Toml.get_section doc "package" in
  Alcotest.(check (option string)) "name" (Some "foo") (Toml.get_string pkg "name")

let test_toml_missing_section () =
  let text = {|
[package]
name = "bar"
|} in
  let doc  = Toml.parse text in
  let deps = Toml.get_section doc "deps" in
  Alcotest.(check int) "empty deps section" 0 (List.length deps)

(* ---------------------------------------------------------------- toolchain *)

let test_platform_darwin_arm () =
  Alcotest.(check (result string string)) "darwin arm64"
    (Ok "darwin-arm64") (Toolchain.platform_of_uname "Darwin" "arm64")

let test_platform_linux () =
  Alcotest.(check (result string string)) "linux x86_64"
    (Ok "linux-x86_64") (Toolchain.platform_of_uname "Linux" "x86_64");
  Alcotest.(check (result string string)) "linux aarch64"
    (Ok "linux-aarch64") (Toolchain.platform_of_uname "Linux" "aarch64");
  Alcotest.(check (result string string)) "linux arm64 maps to aarch64"
    (Ok "linux-aarch64") (Toolchain.platform_of_uname "Linux" "arm64")

let test_platform_trims () =
  Alcotest.(check (result string string)) "trims uname whitespace"
    (Ok "darwin-arm64") (Toolchain.platform_of_uname "Darwin\n" "  arm64 ")

let test_platform_unsupported () =
  (match Toolchain.platform_of_uname "Darwin" "x86_64" with
   | Error _ -> () | Ok _ -> Alcotest.fail "intel macOS should be unsupported");
  (match Toolchain.platform_of_uname "Plan9" "vax" with
   | Error _ -> () | Ok _ -> Alcotest.fail "unknown platform should error")

let test_checksum_standard () =
  let sums = "abc123  march-1.0-darwin-arm64.tar.gz\ndef456  march-1.0-linux-x86_64.tar.gz" in
  Alcotest.(check (option string)) "finds the matching line's hash"
    (Some "abc123") (Toolchain.expected_hash_for ~sums ~file:"march-1.0-darwin-arm64.tar.gz")

let test_checksum_legacy_prefix () =
  let sums = "sha256:ABC123  march-1.0-darwin-arm64.tar.gz" in
  Alcotest.(check (option string)) "strips sha256: prefix and lowercases"
    (Some "abc123") (Toolchain.expected_hash_for ~sums ~file:"march-1.0-darwin-arm64.tar.gz")

let test_checksum_not_found () =
  let sums = "abc123  other.tar.gz" in
  Alcotest.(check (option string)) "unlisted file yields None (verify fails closed)"
    None (Toolchain.expected_hash_for ~sums ~file:"march-1.0-darwin-arm64.tar.gz")

(* shared test helper: substring containment *)
let contains haystack needle =
  let nl = String.length needle and hl = String.length haystack in
  let rec at i = i + nl <= hl && (String.sub haystack i nl = needle || at (i + 1)) in
  nl = 0 || at 0

(* forge bench: discovery + result formatting ----------------------------- *)

let test_bench_name () =
  Alcotest.(check string) "stem from path" "binary_trees"
    (Cmd_bench.bench_name "bench/binary_trees.march")

let test_bench_matches () =
  Alcotest.(check bool) "empty filter matches all" true  (Cmd_bench.matches ~filter:"" "x");
  Alcotest.(check bool) "substring match"          true  (Cmd_bench.matches ~filter:"tree" "binary_trees");
  Alcotest.(check bool) "no match"                 false (Cmd_bench.matches ~filter:"zzz" "binary_trees")

let test_bench_format_human () =
  let out = Cmd_bench.format_results [ ("a", 1.5, true); ("b", 0.0, false) ] ~json:false in
  Alcotest.(check bool) "shows a name and its time" true (contains out "a" && contains out "1.5");
  Alcotest.(check bool) "marks a failed bench"      true (contains out "FAILED")

let test_bench_format_json () =
  let out = Cmd_bench.format_results [ ("a", 1.5, true) ] ~json:true in
  Alcotest.(check bool) "json has name/seconds/ok" true
    (contains out "\"name\"" && contains out "\"a\"" && contains out "\"ok\"")

(* forge workspaces ------------------------------------------------------- *)

let test_workspace_parse_members () =
  let toml = {|
[workspace]
members = ["app", "lib/core", "lib/web"]
|} in
  let doc = Toml.parse toml in
  let members = Workspace.parse_members doc in
  Alcotest.(check (list string)) "three members" ["app"; "lib/core"; "lib/web"] members

let test_workspace_parse_members_empty () =
  let doc = Toml.parse "" in
  let members = Workspace.parse_members doc in
  Alcotest.(check (list string)) "no workspace -> []" [] members

let test_workspace_parse_members_no_key () =
  let toml = "[workspace]\nsome_other = \"value\"\n" in
  let doc = Toml.parse toml in
  let members = Workspace.parse_members doc in
  Alcotest.(check (list string)) "no members key -> []" [] members

let test_workspace_find_root () =
  let tmpdir = Filename.temp_dir "ws_root_test_" "" in
  Fun.protect ~finally:(fun () -> ignore (Sys.command ("rm -rf " ^ Filename.quote tmpdir))) (fun () ->
    let member_dir = Filename.concat tmpdir "app" in
    Unix.mkdir member_dir 0o755;
    let toml_content = "[workspace]\nmembers = [\"app\"]\n" in
    let oc = open_out (Filename.concat tmpdir "forge.toml") in
    output_string oc toml_content;
    close_out oc;
    let member_forge = Filename.concat member_dir "forge.toml" in
    let oc2 = open_out member_forge in
    output_string oc2 "[package]\nname = \"app\"\n";
    close_out oc2;
    let found = Workspace.find_root member_dir in
    Alcotest.(check (option string)) "finds workspace root" (Some tmpdir) found)

let test_workspace_find_root_none () =
  let tmpdir = Filename.temp_dir "ws_noroot_test_" "" in
  Fun.protect ~finally:(fun () -> ignore (Sys.command ("rm -rf " ^ Filename.quote tmpdir))) (fun () ->
    let found = Workspace.find_root tmpdir in
    Alcotest.(check (option string)) "no workspace -> None" None found)

(* forge completions + external subcommands ------------------------------- *)

let test_completion_bash () =
  let s = Cli_ext.completion_script ~shell:"bash" ~subcommands:[ "build"; "watch" ] in
  Alcotest.(check bool) "bash: complete + names" true (contains s "complete" && contains s "build" && contains s "watch")

let test_completion_zsh () =
  let s = Cli_ext.completion_script ~shell:"zsh" ~subcommands:[ "build"; "watch" ] in
  Alcotest.(check bool) "zsh: compdef + names" true (contains s "compdef" && contains s "watch")

let test_completion_fish () =
  let s = Cli_ext.completion_script ~shell:"fish" ~subcommands:[ "build"; "watch" ] in
  Alcotest.(check bool) "fish: complete -c forge + names" true (contains s "complete -c forge" && contains s "watch")

let test_external_found () =
  let lookup n = if n = "forge-hello" then Some "/x/forge-hello" else None in
  Alcotest.(check (option string)) "unknown cmd resolves to forge-<x>"
    (Some "/x/forge-hello") (Cli_ext.external_subcommand ~known:[ "build" ] ~argv1:"hello" ~path_lookup:lookup)

let test_external_builtin_wins () =
  Alcotest.(check (option string)) "built-in is never shadowed"
    None (Cli_ext.external_subcommand ~known:[ "build" ] ~argv1:"build" ~path_lookup:(fun _ -> Some "/x/forge-build"))

let test_external_not_found () =
  Alcotest.(check (option string)) "no forge-<x> on PATH -> None"
    None (Cli_ext.external_subcommand ~known:[ "build" ] ~argv1:"nope" ~path_lookup:(fun _ -> None))

(* forge licenses + --frozen --------------------------------------------- *)

let test_licenses_format_human () =
  let rows = [ ("foo", Some "1.2.0", Some "MIT"); ("bar", Some "0.1.0", None) ] in
  let out = Cmd_licenses.format rows ~json:false in
  Alcotest.(check bool) "shows a license"      true (contains out "foo" && contains out "MIT");
  Alcotest.(check bool) "flags a missing one"  true (contains out "MISSING")

let test_licenses_any_missing () =
  Alcotest.(check bool) "missing present" true
    (Cmd_licenses.any_missing [ ("a", None, Some "MIT"); ("b", None, None) ]);
  Alcotest.(check bool) "all present" false
    (Cmd_licenses.any_missing [ ("a", None, Some "MIT"); ("b", None, Some "BSD") ])

let test_frozen_error () =
  Alcotest.(check bool) "drift + frozen -> error" true  (Cmd_licenses.frozen_error ~drifted:true ~frozen:true);
  Alcotest.(check bool) "drift, not frozen -> ok" false (Cmd_licenses.frozen_error ~drifted:true ~frozen:false);
  Alcotest.(check bool) "no drift -> ok"          false (Cmd_licenses.frozen_error ~drifted:false ~frozen:true)

(* forge version: semver bump + forge.toml rewrite ------------------------ *)

let vstr = Resolver_version.to_string
let vparse = Resolver_version.parse_exn

let test_bump_patch () =
  Alcotest.(check string) "patch" "1.2.4" (vstr (Versioning.bump Versioning.Patch (vparse "1.2.3")))
let test_bump_minor () =
  Alcotest.(check string) "minor resets patch" "1.3.0" (vstr (Versioning.bump Versioning.Minor (vparse "1.2.3")))
let test_bump_major () =
  Alcotest.(check string) "major resets minor+patch" "2.0.0" (vstr (Versioning.bump Versioning.Major (vparse "1.2.3")))
let test_bump_clears_pre () =
  Alcotest.(check string) "bump drops pre-release" "1.2.4" (vstr (Versioning.bump Versioning.Patch (vparse "1.2.3-alpha.1")))

let test_rewrite_version_package_only () =
  let toml =
    "[package]\nname = \"x\"\nversion = \"1.2.3\"\n\n[deps]\nfoo = { version = \"9.9.9\" }\n" in
  let out = Versioning.rewrite_version_line ~toml ~new_version:"1.3.0" in
  Alcotest.(check bool) "package version bumped"   true  (contains out "version = \"1.3.0\"");
  Alcotest.(check bool) "old version gone"         false (contains out "1.2.3");
  Alcotest.(check bool) "dep version untouched"    true  (contains out "version = \"9.9.9\"")

(* forge watch: change detection ------------------------------------------ *)

let test_watch_no_change () =
  let s = [ ("a", 1.0); ("b", 2.0) ] in
  Alcotest.(check bool) "identical snapshot -> no change" false (Watcher.changed ~prev:s ~cur:s)

let test_watch_mtime_advances () =
  Alcotest.(check bool) "a file's mtime changed -> change"
    true (Watcher.changed ~prev:[ ("a", 1.0) ] ~cur:[ ("a", 2.0) ])

let test_watch_added () =
  Alcotest.(check bool) "a file appeared -> change"
    true (Watcher.changed ~prev:[ ("a", 1.0) ] ~cur:[ ("a", 1.0); ("b", 2.0) ])

let test_watch_removed () =
  Alcotest.(check bool) "a file disappeared -> change"
    true (Watcher.changed ~prev:[ ("a", 1.0); ("b", 2.0) ] ~cur:[ ("a", 1.0) ])

let test_watch_order_insensitive () =
  Alcotest.(check bool) "same files, different order -> no change"
    false (Watcher.changed ~prev:[ ("a", 1.0); ("b", 2.0) ] ~cur:[ ("b", 2.0); ("a", 1.0) ])

(* tag validation + default-tag selection (review fixes) ------------------ *)

let test_valid_tag () =
  List.iter (fun t -> Alcotest.(check bool) t true (Toolchain.valid_tag t))
    [ "v0.1.0"; "nightly-20260612"; "0.5.0"; "a_b.c-1" ];
  List.iter (fun t -> Alcotest.(check bool) t false (Toolchain.valid_tag t))
    [ ""; "."; ".."; "../../tmp/evil"; "a/b"; "x;reboot"; "$(id)"; "a b"; "a\nb" ]

let test_default_tag_prefers_stable () =
  Alcotest.(check (option string)) "newest stable wins over nightlies"
    (Some "v0.5.1") (Toolchain.default_tag [ "v0.5.1"; "nightly-20260612"; "v0.5.0" ])

let test_default_tag_nightly_fallback () =
  Alcotest.(check (option string)) "nightly fallback when no stable"
    (Some "nightly-20260612") (Toolchain.default_tag [ "nightly-20260612"; "nightly-20260611" ])

let test_default_tag_empty () =
  Alcotest.(check (option string)) "empty -> None" None (Toolchain.default_tag [])

(* per-project toolchain pin (.march-version) resolution ------------------- *)

let mkdir_p path =
  ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote path)))

let write_file path contents =
  let oc = open_out path in output_string oc contents; close_out oc

let fresh_dir () =
  let d = Filename.temp_file "march_pin_" "" in
  Sys.remove d; Unix.mkdir d 0o755; d

let test_pin_in_current_dir () =
  let dir = fresh_dir () in
  write_file (Filename.concat dir ".march-version") "0.5.0\n";
  Alcotest.(check (option string)) "pin read from cwd"
    (Some "0.5.0") (Toolchain.find_pin dir)

let test_pin_walks_up_parents () =
  let root = fresh_dir () in
  write_file (Filename.concat root ".march-version") "0.4.2\n";
  let child = Filename.concat root "a/b" in
  mkdir_p child;
  Alcotest.(check (option string)) "pin found by walking up to an ancestor"
    (Some "0.4.2") (Toolchain.find_pin child)

let test_pin_absent () =
  let dir = fresh_dir () in
  Alcotest.(check (option string)) "no .march-version anywhere -> None"
    None (Toolchain.find_pin dir)

(* Point a temp MARCH_HOME's `current` symlink at [tag] (the global default). *)
let set_fake_global tag =
  let home = fresh_dir () in
  Unix.putenv "MARCH_HOME" home;
  mkdir_p (Filename.concat home "versions");
  Unix.symlink (Filename.concat "versions" tag) (Filename.concat home "current")

let test_resolve_prefers_pin () =
  set_fake_global "9.9.9";
  let dir = fresh_dir () in
  write_file (Filename.concat dir ".march-version") "0.5.0\n";
  Alcotest.(check (option string)) "project pin wins over the global default"
    (Some "0.5.0") (Toolchain.resolve_version ~cwd:dir ())

let test_resolve_falls_back_to_global () =
  set_fake_global "0.6.0";
  let dir = fresh_dir () in   (* no .march-version *)
  Alcotest.(check (option string)) "no pin -> global default"
    (Some "0.6.0") (Toolchain.resolve_version ~cwd:dir ())

let test_resolve_none_when_unset () =
  Unix.putenv "MARCH_HOME" (fresh_dir ());   (* empty home, no current *)
  let dir = fresh_dir () in
  Alcotest.(check (option string)) "no pin and no global -> None"
    None (Toolchain.resolve_version ~cwd:dir ())

(* Create a fake installed toolchain at <home>/versions/<tag>/bin/march. *)
let install_fake home tag =
  let bin = Filename.concat (Filename.concat (Filename.concat home "versions") tag) "bin" in
  mkdir_p bin;
  write_file (Filename.concat bin "march") "#!/bin/sh\n"

let test_march_command_uses_installed_version () =
  let home = fresh_dir () in
  Unix.putenv "MARCH_HOME" home;
  install_fake home "0.6.0";
  Unix.symlink (Filename.concat "versions" "0.6.0") (Filename.concat home "current");
  (match Toolchain.march_command ~cwd:(fresh_dir ()) () with
   | Ok path -> Alcotest.(check bool) "march path points at the resolved version"
                  true (Filename.check_suffix path "versions/0.6.0/bin/march")
   | Error e -> Alcotest.failf "expected Ok, got Error: %s" e)

let test_march_command_errors_when_pinned_version_missing () =
  let home = fresh_dir () in
  Unix.putenv "MARCH_HOME" home;
  let dir = fresh_dir () in
  write_file (Filename.concat dir ".march-version") "0.7.0\n";  (* not installed *)
  (match Toolchain.march_command ~cwd:dir () with
   | Error _ -> ()
   | Ok p -> Alcotest.failf "expected Error for uninstalled pin, got %s" p)

let test_march_command_falls_back_to_path () =
  Unix.putenv "MARCH_HOME" (fresh_dir ());
  Alcotest.(check (result string string)) "no resolution -> bare 'march' on PATH"
    (Ok "march") (Toolchain.march_command ~cwd:(fresh_dir ()) ())

let test_path_prefix_installed () =
  let home = fresh_dir () in
  Unix.putenv "MARCH_HOME" home;
  install_fake home "0.6.0";
  Unix.symlink (Filename.concat "versions" "0.6.0") (Filename.concat home "current");
  (match Toolchain.path_prefix ~cwd:(fresh_dir ()) () with
   | Ok p -> Alcotest.(check bool) "prefix puts the version bin on PATH"
               true (contains p "PATH=" && contains p "versions/0.6.0/bin")
   | Error e -> Alcotest.failf "expected Ok, got Error: %s" e)

let test_path_prefix_empty_on_fallback () =
  Unix.putenv "MARCH_HOME" (fresh_dir ());
  Alcotest.(check (result string string)) "no resolution -> empty prefix (use PATH)"
    (Ok "") (Toolchain.path_prefix ~cwd:(fresh_dir ()) ())

(* forge.toml `march` constraint check ------------------------------------ *)

let is_ok = function Ok () -> true | Error _ -> false

let test_constraint_satisfied () =
  Alcotest.(check bool) "0.5.3 satisfies ~> 0.5.0"
    true (is_ok (Toolchain.check_constraint ~resolved:"0.5.3" ~req:"~> 0.5.0"))

let test_constraint_violated () =
  Alcotest.(check bool) "0.7.0 violates ~> 0.5.0"
    false (is_ok (Toolchain.check_constraint ~resolved:"0.7.0" ~req:"~> 0.5.0"))

let test_constraint_skips_non_semver_tag () =
  Alcotest.(check bool) "a nightly tag can't be evaluated -> allowed through"
    true (is_ok (Toolchain.check_constraint ~resolved:"nightly-20260612" ~req:"~> 0.5.0"))

let test_constraint_rejects_malformed_req () =
  Alcotest.(check bool) "a malformed constraint is a config error"
    false (is_ok (Toolchain.check_constraint ~resolved:"0.5.0" ~req:"not-a-constraint"))

(* remote version listing (forge toolchain list --remote) ----------------- *)

let test_classify_remote_groups_and_marks () =
  let remote = [ "v0.5.1"; "v0.5.0"; "nightly-20260612"; "nightly-20260611" ] in
  let installed = [ "v0.5.0"; "nightly-20260611" ] in
  let (stable, nightly) = Toolchain.classify_remote ~remote ~installed in
  Alcotest.(check (list (pair string bool))) "stable group marks installed, order preserved"
    [ ("v0.5.1", false); ("v0.5.0", true) ] stable;
  Alcotest.(check (list (pair string bool))) "nightly group marks installed, order preserved"
    [ ("nightly-20260612", false); ("nightly-20260611", true) ] nightly

(* auto-install of a missing pin (ensure_installed) ----------------------- *)
(* The download-triggering branch needs the network and is covered e2e; here we
   check the no-op branches that must NOT attempt an install. *)

let test_ensure_installed_noop_when_present () =
  let home = fresh_dir () in
  Unix.putenv "MARCH_HOME" home;
  install_fake home "0.6.0";
  let dir = fresh_dir () in
  write_file (Filename.concat dir ".march-version") "0.6.0\n";
  Alcotest.(check bool) "already-installed pin -> Ok without installing"
    true (is_ok (Toolchain.ensure_installed ~cwd:dir ()))

let test_ensure_installed_noop_when_unresolved () =
  Unix.putenv "MARCH_HOME" (fresh_dir ());
  Alcotest.(check bool) "nothing resolved -> Ok (PATH fallback, nothing to install)"
    true (is_ok (Toolchain.ensure_installed ~cwd:(fresh_dir ()) ()))

(* dependency tree / why (Deptree) ---------------------------------------- *)

let adj pairs name = Option.value ~default:[] (List.assoc_opt name pairs)

let test_deptree_render () =
  let g = [ ("app", ["a"; "b"]); ("a", ["c"]); ("b", []); ("c", []) ] in
  let lines = Deptree.render_tree ~root:"app" ~deps_of:(adj g) in
  Alcotest.(check (list string)) "ascii tree with connectors"
    [ "app"; "├── a"; "│   └── c"; "└── b" ] lines

let test_deptree_render_cycle_breaks () =
  let g = [ ("app", ["a"]); ("a", ["app"]) ] in   (* cycle *)
  let lines = Deptree.render_tree ~root:"app" ~deps_of:(adj g) in
  Alcotest.(check (list string)) "cycle is marked and not re-expanded"
    [ "app"; "└── a"; "    └── app (*)" ] lines

let test_deptree_why_paths () =
  let g = [ ("app", ["a"; "b"]); ("a", ["c"]); ("b", ["c"]); ("c", []) ] in
  let paths = Deptree.why ~root:"app" ~deps_of:(adj g) ~target:"c" in
  Alcotest.(check (list (list string))) "all paths from root to target"
    [ ["app"; "a"; "c"]; ["app"; "b"; "c"] ] paths

let test_deptree_why_none () =
  let g = [ ("app", ["a"]); ("a", []) ] in
  Alcotest.(check (list (list string))) "no path to an absent target"
    [] (Deptree.why ~root:"app" ~deps_of:(adj g) ~target:"zzz")

(* toolchain recorded in forge.lock (Option B: record + drift-warn) -------- *)

let test_lockfile_records_toolchain () =
  let lock = Filename.concat (fresh_dir ()) "forge.lock" in
  Resolver_lockfile.write ~toolchain:(Some "0.5.0") lock [] ~manifest_hash:"abc";
  Alcotest.(check (option string)) "toolchain recorded and read back"
    (Some "0.5.0") (Resolver_lockfile.read_toolchain lock)

let test_lockfile_no_toolchain () =
  let lock = Filename.concat (fresh_dir ()) "forge.lock" in
  Resolver_lockfile.write lock [] ~manifest_hash:"abc";
  Alcotest.(check (option string)) "no toolchain section -> None"
    None (Resolver_lockfile.read_toolchain lock)

let test_drift_warns_on_mismatch () =
  Alcotest.(check bool) "locked != resolved -> warning"
    true (Toolchain.toolchain_drift ~locked:(Some "0.5.0") ~resolved:(Some "0.7.0") <> None)

let test_drift_silent_on_match () =
  Alcotest.(check bool) "locked == resolved -> no warning"
    true (Toolchain.toolchain_drift ~locked:(Some "0.5.0") ~resolved:(Some "0.5.0") = None)

let test_drift_silent_when_unlocked () =
  Alcotest.(check bool) "no lock entry -> no warning (record-only, never override)"
    true (Toolchain.toolchain_drift ~locked:None ~resolved:(Some "0.7.0") = None)

(* forge.toml metadata fields (license / repository / homepage) ----------- *)

let test_project_metadata_fields () =
  let dir = fresh_dir () in
  write_file (Filename.concat dir "forge.toml")
    "[package]\n\
     name = \"x\"\n\
     license = \"MIT\"\n\
     repository = \"https://github.com/o/x\"\n\
     homepage = \"https://x.dev\"\n";
  match Project.load_from_dir dir with
  | Error e -> Alcotest.failf "load failed: %s" e
  | Ok p ->
    Alcotest.(check (option string)) "license"    (Some "MIT") p.Project.license;
    Alcotest.(check (option string)) "repository" (Some "https://github.com/o/x") p.Project.repository;
    Alcotest.(check (option string)) "homepage"   (Some "https://x.dev") p.Project.homepage

let test_project_metadata_absent () =
  let dir = fresh_dir () in
  write_file (Filename.concat dir "forge.toml") "[package]\nname = \"x\"\n";
  match Project.load_from_dir dir with
  | Error e -> Alcotest.failf "load failed: %s" e
  | Ok p -> Alcotest.(check (option string)) "absent license -> None" None p.Project.license

(* -------------------------------------------------------------------- ffi *)

let test_ffi_gen_c () =
  let dir = Filename.temp_file "march_ffi_gen" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  let mfile = Filename.concat dir "b.march" in
  let oc = open_out mfile in
  output_string oc
    "mod B do\n\
    \  needs Ffi\n\
    \  extern \"demo\" : Cap(Ffi) do\n\
    \    fn add(a: Int, b: Int): Int = \"demo_add\"\n\
    \    fn greet(name: String): String = \"demo_greet\"\n\
    \  end\n\
     end\n";
  close_out oc;
  let cfile = Filename.concat dir "out.c" in
  (match Cmd_ffi.run ~file:mfile ~out:(Some cfile) with
   | Error e -> Alcotest.failf "gen-c failed: %s" e
   | Ok () -> ());
  let ic = open_in cfile in
  let body = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let contains sub =
    let n = String.length sub and h = String.length body in
    let rec go i = i + n <= h && (String.sub body i n = sub || go (i+1)) in go 0 in
  Alcotest.(check bool) "primitive signature" true (contains "int64_t demo_add(int64_t a, int64_t b)");
  Alcotest.(check bool) "string return signature" true (contains "march_value demo_greet(march_value name)");
  Alcotest.(check bool) "string borrow stub" true (contains "march_str_borrow(name)");
  Alcotest.(check bool) "includes the ABI header" true (contains "march_ffi.h")

let test_ffi_gen_c_codecs () =
  let dir = Filename.temp_file "march_ffi_codec" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  let mfile = Filename.concat dir "c.march" in
  let oc = open_out mfile in
  output_string oc
    "mod C do\n\
    \  needs Ffi\n\
    \  type Point = { x : Int, y : Int }\n\
    \  type Shape = Circle(Int) | Rect(Int, Int)\n\
    \  type Labeled = { name : String, at : Point, kind : Shape }\n\
    \  extern \"demo\" : Cap(Ffi) do\n\
    \    fn area(s: Shape): Int = \"demo_area\"\n\
    \    fn describe(l: Labeled): String = \"demo_describe\"\n\
    \    fn origin(): Point = \"demo_origin\"\n\
    \  end\n\
     end\n";
  close_out oc;
  let cfile = Filename.concat dir "out.c" in
  (match Cmd_ffi.run ~file:mfile ~out:(Some cfile) with
   | Error e -> Alcotest.failf "gen-c failed: %s" e
   | Ok () -> ());
  let ic = open_in cfile in
  let body = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let contains sub =
    let n = String.length sub and h = String.length body in
    let rec go i = i + n <= h && (String.sub body i n = sub || go (i+1)) in go 0 in
  (* mirror structs *)
  Alcotest.(check bool) "record mirror struct" true (contains "} Point_c;");
  Alcotest.(check bool) "variant tagged union" true (contains "    int32_t tag;");
  Alcotest.(check bool) "variant ctor field tuple" true (contains "struct { int64_t f0; int64_t f1; } Rect;");
  (* decode / encode *)
  Alcotest.(check bool) "variant decode reads tag" true (contains "o.tag = march_variant_tag(v);");
  Alcotest.(check bool) "record encode interns shape" true (contains "march_make_record(\"x:i;y:i;\", 2, f)");
  Alcotest.(check bool) "variant encode builds" true (contains "march_make_variant(1, 2, f)");
  (* nesting: Labeled decode recurses into Point/Shape codecs *)
  Alcotest.(check bool) "nested decode recurses" true (contains "march_decode_Point(march_record_field");
  Alcotest.(check bool) "nested encode recurses" true (contains "march_encode_Shape(o.kind)");
  (* topo order: Point defined before Labeled that embeds it *)
  let idx sub =
    let n = String.length sub and h = String.length body in
    let rec go i = if i + n > h then -1 else if String.sub body i n = sub then i else go (i+1) in go 0 in
  Alcotest.(check bool) "nested type defined after its members" true
    (idx "} Point_c;" < idx "} Labeled_c;");
  (* shim wiring: codec param decoded, codec return encoded *)
  Alcotest.(check bool) "shim decodes codec param" true (contains "march_decode_Labeled(l_v)");
  Alcotest.(check bool) "shim encodes codec return" true (contains "return march_encode_Point(result)")

let test_ffi_gen_c_optres_fields () =
  let dir = Filename.temp_file "march_ffi_optres" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  let mfile = Filename.concat dir "o.march" in
  let oc = open_out mfile in
  output_string oc
    "mod O do\n\
    \  needs Ffi\n\
    \  type Box = { tag : Int, maybe : Option(Int), res : Result(Int, String) }\n\
    \  extern \"demo\" : Cap(Ffi) do\n\
    \    fn mk(): Box = \"demo_mk\"\n\
    \  end\n\
     end\n";
  close_out oc;
  let cfile = Filename.concat dir "out.c" in
  (match Cmd_ffi.run ~file:mfile ~out:(Some cfile) with
   | Error e -> Alcotest.failf "gen-c failed: %s" e
   | Ok () -> ());
  let ic = open_in cfile in
  let body = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let contains sub =
    let n = String.length sub and h = String.length body in
    let rec go i = i + n <= h && (String.sub body i n = sub || go (i+1)) in go 0 in
  (* synthetic Option/Result field codecs *)
  Alcotest.(check bool) "Option(Int) mirror" true (contains "} Option_Int_c;");
  Alcotest.(check bool) "Option(Int) niche decode" true (contains "if (v == 0) o.is_some = 0;");
  Alcotest.(check bool) "Result mirror" true (contains "} Result_Int_String_c;");
  Alcotest.(check bool) "Result boxed decode" true (contains "march_variant_tag(v) == 0");
  (* the record's mirror uses the typed field codecs, not raw march_value *)
  Alcotest.(check bool) "record field typed" true (contains "Option_Int_c maybe;");
  Alcotest.(check bool) "record decodes via field codec" true
    (contains "march_decode_Result_Int_String(march_record_field")

let mk_gen_c_output dir name src =
  let mfile = Filename.concat dir (name ^ ".march") in
  let oc = open_out mfile in output_string oc src; close_out oc;
  let cfile = Filename.concat dir (name ^ ".c") in
  (match Cmd_ffi.run ~file:mfile ~out:(Some cfile) with
   | Error e -> Alcotest.failf "gen-c failed: %s" e | Ok () -> ());
  let ic = open_in cfile in
  let body = really_input_string ic (in_channel_length ic) in
  close_in ic; body

let contains_sub body sub =
  let n = String.length sub and h = String.length body in
  let rec go i = i + n <= h && (String.sub body i n = sub || go (i+1)) in go 0

let pos_of body sub =
  let n = String.length sub and h = String.length body in
  let rec go i = if i + n > h then h else if String.sub body i n = sub then i else go (i+1) in go 0

let test_ffi_gen_c_optres_float_unit () =
  let dir = Filename.temp_file "march_ffi_optres_fu" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  let body = mk_gen_c_output dir "t"
    "mod T do\n\
    \  needs Ffi\n\
    \  type Box = { f : Option(Float), u : Option(Unit), rf : Result(Float, String) }\n\
    \  extern \"x\" : Cap(Ffi) do\n\
    \    fn make(): Box = \"x_make\"\n\
    \  end\n\
     end\n" in
  let has s = contains_sub body s in
  (* Option(Float): fully boxed — tag check + march_none_boxed / march_some_boxed *)
  Alcotest.(check bool) "Option_Float mirror"       true (has "} Option_Float_c;");
  Alcotest.(check bool) "Option_Float boxed tag"    true (has "march_variant_tag(v) == 0");
  Alcotest.(check bool) "Option_Float none_boxed"   true (has "march_none_boxed()");
  Alcotest.(check bool) "Option_Float some_boxed"   true (has "march_some_boxed(march_make_float");
  (* Option(Unit): mixed — is_some only, niche None + boxed Some *)
  Alcotest.(check bool) "Option_Unit no value field" true (has "int32_t is_some; } Option_Unit_c;");
  Alcotest.(check bool) "Option_Unit niche decode"   true (has "o.is_some = (v != 0)");
  Alcotest.(check bool) "Option_Unit none niche"     true (has "return march_none();");
  Alcotest.(check bool) "Option_Unit some boxed"     true (has "march_some_boxed(0)");
  (* Result(Float, String): ok field is double *)
  Alcotest.(check bool) "Result_Float_String mirror" true (has "double ok;");
  Alcotest.(check bool) "Result_Float decode"        true (has "march_get_float(march_variant_field")

let test_ffi_gen_c_optres_nested () =
  let dir = Filename.temp_file "march_ffi_optres_nested" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  let body = mk_gen_c_output dir "t"
    "mod T do\n\
    \  needs Ffi\n\
    \  type Point = { x : Int, y : Int }\n\
    \  type Shape = Circle(Int) | Rect(Int, Int)\n\
    \  type Wrap = { pt : Option(Point), sh : Result(Shape, String) }\n\
    \  extern \"x\" : Cap(Ffi) do\n\
    \    fn make(): Wrap = \"x_make\"\n\
    \  end\n\
     end\n" in
  let has s = contains_sub body s in
  (* Option(Point): niche, value is Point_c *)
  Alcotest.(check bool) "Option_Point mirror"      true (has "Point_c value; } Option_Point_c;");
  Alcotest.(check bool) "Option_Point niche decode" true (has "march_decode_Point(v)");
  Alcotest.(check bool) "Option_Point niche encode" true (has "march_some(march_encode_Point");
  (* Result(Shape, String): ok field is Shape_c *)
  Alcotest.(check bool) "Result_Shape_String mirror" true (has "Shape_c ok;");
  Alcotest.(check bool) "Result_Shape decode"        true (has "march_decode_Shape(march_variant_field");
  (* Point_c must be defined before Option_Point_c (ordering) *)
  Alcotest.(check bool) "Point_c before Option_Point_c" true
    (pos_of body "} Point_c;" < pos_of body "Option_Point_c")

let test_ffi_gen_c_list_fields () =
  let dir = Filename.temp_file "march_ffi_list" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  let body = mk_gen_c_output dir "t"
    "mod T do\n\
    \  needs Ffi\n\
    \  type Batch = { ids : List(Int), names : List(String) }\n\
    \  extern \"x\" : Cap(Ffi) do\n\
    \    fn process(b: Batch): Int = \"x_process\"\n\
    \  end\n\
     end\n" in
  let has s = contains_sub body s in
  Alcotest.(check bool) "stdlib.h included"   true (has "#include <stdlib.h>");
  Alcotest.(check bool) "List_Int mirror"     true (has "int64_t *items; int32_t length; } List_Int_c;");
  Alcotest.(check bool) "List_Int length"     true (has "march_list_length");
  Alcotest.(check bool) "List_Int malloc"     true (has "malloc(o.length * sizeof");
  Alcotest.(check bool) "List_Int decode head" true (has "march_variant_field(v, 0)");
  Alcotest.(check bool) "List_Int decode tail" true (has "march_variant_field(v, 1)");
  Alcotest.(check bool) "List_Int encode cons" true (has "march_list_cons(");
  Alcotest.(check bool) "List_Int encode nil"  true (has "march_list_nil()");
  Alcotest.(check bool) "List_String mirror"   true (has "march_slice *items");
  Alcotest.(check bool) "Batch uses List_Int_c" true (has "List_Int_c ids;")

let test_ffi_gen_c_raises () =
  let dir = Filename.temp_file "march_ffi_raises" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  let mfile = Filename.concat dir "r.march" in
  let oc = open_out mfile in
  output_string oc
    "mod R do\n\
    \  needs Ffi\n\
    \  extern \"demo\" : Cap(Ffi) do\n\
    \    raises fn parse(s: String): Result(Int, String) = \"demo_parse\"\n\
    \  end\n\
     end\n";
  close_out oc;
  let cfile = Filename.concat dir "out.c" in
  (match Cmd_ffi.run ~file:mfile ~out:(Some cfile) with
   | Error e -> Alcotest.failf "gen-c failed: %s" e
   | Ok () -> ());
  let ic = open_in cfile in
  let body = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let contains sub =
    let n = String.length sub and h = String.length body in
    let rec go i = i + n <= h && (String.sub body i n = sub || go (i+1)) in go 0 in
  (* env-routed signature: hidden march_env* first param, bare Ok-payload return *)
  Alcotest.(check bool) "env param + bare Int return" true
    (contains "int64_t demo_parse(march_env *env, march_value s)");
  Alcotest.(check bool) "march_raise hint" true (contains "march_raise(env,")

let test_ffi_add_rust () =
  let dir = Filename.temp_file "march_addrust" "" in
  Sys.remove dir; Unix.mkdir dir 0o755;
  (match Cmd_ffi.add_rust ~name:"mylib" ~dir ~march_path:"/path/to/march" with
   | Error e -> Alcotest.failf "add-rust failed: %s" e
   | Ok () -> ());
  let read p = let ic = open_in p in
    let s = really_input_string ic (in_channel_length ic) in close_in ic; s in
  let crate = Filename.concat dir "mylib" in
  let cargo = read (Filename.concat crate "Cargo.toml") in
  let lib = read (Filename.concat crate "src/lib.rs") in
  let gen = read (Filename.concat crate "src/bin/gen_extern.rs") in
  let contains hay sub =
    let n = String.length sub and h = String.length hay in
    let rec go i = i + n <= h && (String.sub hay i n = sub || go (i+1)) in go 0 in
  Alcotest.(check bool) "staticlib+lib crate-type" true
    (contains cargo "crate-type = [\"staticlib\", \"lib\"]");
  Alcotest.(check bool) "march path dep" true (contains cargo "/path/to/march");
  Alcotest.(check bool) "panic = unwind" true (contains cargo "panic = \"unwind\"");
  Alcotest.(check bool) "uses #[march]" true (contains lib "use march::{march, Error}");
  Alcotest.(check bool) "init! manifest" true (contains lib "march::init!(\"mylib\"");
  Alcotest.(check bool) "gen_extern prints block" true
    (contains gen "march_print_extern_block")

let test_ffi_gen_c_no_extern () =
  let mfile = Filename.temp_file "march_noffi" ".march" in
  let oc = open_out mfile in
  output_string oc "mod N do\n  fn main() : Unit do () end\nend\n"; close_out oc;
  (match Cmd_ffi.run ~file:mfile ~out:None with
   | Error _ -> ()  (* expected: no extern blocks *)
   | Ok () -> Alcotest.fail "expected an error for a file with no extern blocks")

(* ---------------------------------------------------- hcr capability gate *)

let write_manifest_file (lines : string list) : string =
  let path = Filename.temp_file "test_hcr_manifest" ".hcr_manifest" in
  let oc = open_out path in
  List.iter (fun l -> output_string oc (l ^ "\n")) lines;
  close_out oc;
  path

let with_manifest_file lines f =
  let path = write_manifest_file lines in
  Fun.protect ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () -> f path)

let cas_hash_line = "# cas_hash " ^ String.make 64 'a'
(* Legacy pre-2026-07-04 manifests could carry a whole-artifact
   "ROOT cap_root=<hex>" line (now retired by the granularity revision — see
   specs/plans/2026-06-25-hcr-phase5c-capability-safe-deploys.md, "Granularity
   revision"). A current parser must still tolerate an old ROOT line on disk
   (from a manifest baseline written by a pre-revision compiler) without
   fabricating a phantom "ROOT" function. *)
let root_line = "ROOT cap_root=" ^ String.make 64 'b'

let test_parse_manifest_root_line_no_phantom_fn () =
  with_manifest_file [cas_hash_line; root_line; "MyApp.f implhash sighash caps="]
    (fun path ->
      match Cmd_deploy_hot.parse_manifest path with
      | Error m -> Alcotest.fail m
      | Ok m ->
        Alcotest.(check int) "no phantom ROOT function" 1 (List.length m.Cmd_deploy_hot.functions);
        List.iter (fun fm ->
          Alcotest.(check bool) "ROOT is not a function name" true
            (fm.Cmd_deploy_hot.fn_name <> "ROOT")
        ) m.Cmd_deploy_hot.functions)

let test_parse_manifest_no_caps_anywhere_is_legacy () =
  (* A genuine pre-Phase-5C manifest: no FN line anywhere carries a `caps=`
     field. is_legacy_manifest must recognize this and callers fall back to
     ACTIVATE3. *)
  with_manifest_file [cas_hash_line; "MyApp.f implhash sighash"]
    (fun path ->
      match Cmd_deploy_hot.parse_manifest path with
      | Error m -> Alcotest.fail m
      | Ok m ->
        Alcotest.(check bool) "no caps= anywhere -> legacy" true
          (Cmd_deploy_hot.is_legacy_manifest m))

let test_parse_manifest_caps_field_present_is_not_legacy () =
  (* A current manifest with a capless function still has `caps=` (empty) on
     its FN line, so it must NOT be classified as legacy. *)
  with_manifest_file [cas_hash_line; "MyApp.f implhash sighash caps="]
    (fun path ->
      match Cmd_deploy_hot.parse_manifest path with
      | Error m -> Alcotest.fail m
      | Ok m ->
        Alcotest.(check bool) "caps= present (even empty) -> not legacy" false
          (Cmd_deploy_hot.is_legacy_manifest m))

let test_parse_manifest_caps_no_callers () =
  (* caps= at the earlier field position (no callers: token present) *)
  with_manifest_file [cas_hash_line; "MyApp.f implhash sighash caps=IO.Console,IO.NetConnect"]
    (fun path ->
      match Cmd_deploy_hot.parse_manifest path with
      | Error m -> Alcotest.fail m
      | Ok m ->
        (match m.Cmd_deploy_hot.functions with
         | [fm] ->
           Alcotest.(check (list string)) "caps parsed (no callers)"
             ["IO.Console"; "IO.NetConnect"] fm.Cmd_deploy_hot.fn_caps
         | _ -> Alcotest.fail "expected exactly one function"))

let test_parse_manifest_caps_with_callers () =
  (* caps= at the later field position, after a callers: token *)
  with_manifest_file
    [cas_hash_line;
     "MyApp.g implhash sighash callers:MyApp.a,MyApp.b caps=IO.FileRead"]
    (fun path ->
      match Cmd_deploy_hot.parse_manifest path with
      | Error m -> Alcotest.fail m
      | Ok m ->
        (match m.Cmd_deploy_hot.functions with
         | [fm] ->
           Alcotest.(check (list string)) "callers parsed"
             ["MyApp.a"; "MyApp.b"] fm.Cmd_deploy_hot.fn_callers;
           Alcotest.(check (list string)) "caps parsed (with callers)"
             ["IO.FileRead"] fm.Cmd_deploy_hot.fn_caps
         | _ -> Alcotest.fail "expected exactly one function"))

let test_parse_manifest_caps_empty () =
  with_manifest_file [cas_hash_line; "MyApp.h implhash sighash caps="]
    (fun path ->
      match Cmd_deploy_hot.parse_manifest path with
      | Error m -> Alcotest.fail m
      | Ok m ->
        (match m.Cmd_deploy_hot.functions with
         | [fm] -> Alcotest.(check (list string)) "no caps" [] fm.Cmd_deploy_hot.fn_caps
         | _ -> Alcotest.fail "expected exactly one function"))

let test_gate_no_prior_is_permissive () =
  (* No baseline file at all -> caller treats prior_caps as empty / gate skipped.
     At the pure-function level, computing widening against an empty prior
     baseline is the well-defined "not gated" case tested elsewhere (the
     `run` function skips the gate entirely when old_manifest_path doesn't
     exist — this test exercises the pure diff fn with no prior data, which
     callers must not invoke when there's genuinely no baseline). *)
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior:[] ~new_caps:["IO.Console"] in
  Alcotest.(check (list string)) "everything looks like widening vs an empty baseline"
    ["IO.Console"] widening

let test_gate_pure_narrowing_allowed () =
  let prior = ["IO.Console"; "IO.NetConnect"] in
  let new_caps = ["IO.Console"] in
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior ~new_caps in
  let narrowing = Cmd_deploy_hot.compute_cap_narrowing ~prior ~new_caps in
  Alcotest.(check (list string)) "no widening" [] widening;
  Alcotest.(check (list string)) "narrowing reported" ["IO.NetConnect"] narrowing

(* I2 fix: compute_cap_narrowing must use subsumption, not exact match.
   Prior use of List.mem misreported narrowing whenever the new build still
   holds a broader (root) cap that covers the prior, more specific cap — new
   build holding IO (root) still covers a prior IO.FileRead, so no actual
   narrowing occurred even though IO.FileRead itself is no longer literally
   present in new_caps. *)
let test_gate_narrowing_root_cap_covers_prior_specific_not_misreported () =
  let prior = ["IO.FileRead"] in
  let new_caps = ["IO"] in
  let narrowing = Cmd_deploy_hot.compute_cap_narrowing ~prior ~new_caps in
  Alcotest.(check (list string))
    "IO root in new_caps subsumes prior IO.FileRead: not narrowing"
    [] narrowing

let test_gate_subsumed_add_allowed () =
  (* prior already holds the IO root cap, so any IO.* child is already covered *)
  let prior = ["IO"] in
  let new_caps = ["IO"; "IO.FileRead"] in
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior ~new_caps in
  Alcotest.(check (list string)) "subsumed add is not widening" [] widening

let test_gate_sibling_widen_blocked () =
  let prior = ["IO.Console"] in
  let new_caps = ["IO.Console"; "IO.Process"] in
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior ~new_caps in
  Alcotest.(check (list string)) "sibling cap is widening" ["IO.Process"] widening

let test_gate_parent_widen_blocked () =
  (* prior only has the child; new build asks for the parent -> widening,
     since the child does not subsume the parent. *)
  let prior = ["IO.FileRead"] in
  let new_caps = ["IO.FileSystem"] in
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior ~new_caps in
  Alcotest.(check (list string)) "parent cap is widening" ["IO.FileSystem"] widening

let test_gate_io_root_add_blocked () =
  let prior = ["IO.Console"] in
  let new_caps = ["IO.Console"; "IO"] in
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior ~new_caps in
  Alcotest.(check (list string)) "IO root add is widening" ["IO"] widening

let test_gate_attribution_names_introducing_function () =
  let functions = [
    { Cmd_deploy_hot.fn_name = "MyApp.Server.handle"; fn_impl_hash = "h1"; fn_sig_hash = "s1";
      fn_callers = []; fn_caps = ["IO.Process"]; fn_has_caps = true };
    { Cmd_deploy_hot.fn_name = "MyApp.Other.fn"; fn_impl_hash = "h2"; fn_sig_hash = "s2";
      fn_callers = []; fn_caps = ["IO.Console"]; fn_has_caps = true };
  ] in
  let attributed = Cmd_deploy_hot.attribute_widening functions ["IO.Process"] in
  Alcotest.(check (list (pair string string))) "attributes widened cap to its function"
    [("IO.Process", "MyApp.Server.handle")] attributed

(* ─── compute_scoped_caps: per-fn monotonicity scoping (Granularity revision,
   2026-07-04) ── this is the pure function factored out of `run`'s inlined
   prior/new computation so the rescoped gate (own-caps of ACTIVATED
   functions only, not the whole-artifact union) is unit-testable without a
   live socket. *)

let fm ~name ~caps =
  { Cmd_deploy_hot.fn_name = name; fn_impl_hash = "h"; fn_sig_hash = "s";
    fn_callers = []; fn_caps = caps; fn_has_caps = true }

let test_scoped_caps_no_prior_baseline_permissive () =
  let to_activate = [ fm ~name:"MyApp.f" ~caps:["IO.Console"; "IO.FileWrite"] ] in
  let (prior_caps, new_caps) = Cmd_deploy_hot.compute_scoped_caps ~to_activate ~prior:None in
  Alcotest.(check (list string)) "no baseline -> empty prior" [] prior_caps;
  Alcotest.(check (list string)) "no baseline -> normalized new caps"
    ["IO.Console"; "IO.FileWrite"] new_caps

let test_scoped_caps_new_function_compares_against_empty () =
  (* Function present in to_activate but absent from the prior baseline
     entirely (e.g. newly added this deploy) -> its caps compare against
     [], so ALL its caps show up as widening. *)
  let to_activate = [ fm ~name:"MyApp.brand_new" ~caps:["IO.Console"; "IO.FileWrite"] ] in
  let prior_manifest = { Cmd_deploy_hot.cas_hash = "cas"; functions = [] } in
  let (prior_caps, new_caps) =
    Cmd_deploy_hot.compute_scoped_caps ~to_activate ~prior:(Some prior_manifest) in
  Alcotest.(check (list string)) "new fn has no prior caps" [] prior_caps;
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior:prior_caps ~new_caps in
  Alcotest.(check (list string)) "all of new fn's caps widen"
    ["IO.Console"; "IO.FileWrite"] widening

let test_scoped_caps_existing_function_adds_cap_widens () =
  let to_activate = [ fm ~name:"MyApp.f" ~caps:["IO.Console"; "IO.FileWrite"] ] in
  let prior_manifest =
    { Cmd_deploy_hot.cas_hash = "cas";
      functions = [ fm ~name:"MyApp.f" ~caps:["IO.Console"] ] } in
  let (prior_caps, new_caps) =
    Cmd_deploy_hot.compute_scoped_caps ~to_activate ~prior:(Some prior_manifest) in
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior:prior_caps ~new_caps in
  let narrowing = Cmd_deploy_hot.compute_cap_narrowing ~prior:prior_caps ~new_caps in
  Alcotest.(check (list string)) "added cap widens" ["IO.FileWrite"] widening;
  Alcotest.(check (list string)) "nothing narrows" [] narrowing

let test_scoped_caps_existing_function_drops_cap_narrows () =
  let to_activate = [ fm ~name:"MyApp.f" ~caps:["IO.Console"] ] in
  let prior_manifest =
    { Cmd_deploy_hot.cas_hash = "cas";
      functions = [ fm ~name:"MyApp.f" ~caps:["IO.Console"; "IO.FileWrite"] ] } in
  let (prior_caps, new_caps) =
    Cmd_deploy_hot.compute_scoped_caps ~to_activate ~prior:(Some prior_manifest) in
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior:prior_caps ~new_caps in
  let narrowing = Cmd_deploy_hot.compute_cap_narrowing ~prior:prior_caps ~new_caps in
  Alcotest.(check (list string)) "nothing widens" [] widening;
  Alcotest.(check (list string)) "dropped cap narrows" ["IO.FileWrite"] narrowing

let test_scoped_caps_existing_function_adds_subsumed_cap_no_widen () =
  (* prior holds IO.Network; new adds IO.NetConnect, which IO.Network
     subsumes -> normalize drops it, so no widening is reported. *)
  let to_activate = [ fm ~name:"MyApp.f" ~caps:["IO.Network"; "IO.NetConnect"] ] in
  let prior_manifest =
    { Cmd_deploy_hot.cas_hash = "cas";
      functions = [ fm ~name:"MyApp.f" ~caps:["IO.Network"] ] } in
  let (prior_caps, new_caps) =
    Cmd_deploy_hot.compute_scoped_caps ~to_activate ~prior:(Some prior_manifest) in
  Alcotest.(check (list string)) "subsumed cap dropped from new_caps" ["IO.Network"] new_caps;
  let widening = Cmd_deploy_hot.compute_cap_widening ~prior:prior_caps ~new_caps in
  Alcotest.(check (list string)) "subsumed add is not widening" [] widening

(* ─── fn_cap_root: per-function cap_root, must match the server's recipe ────
   runtime/march_reload.c's compute_cap_root: split_cap_csv -> sort_uniq ->
   march_cap_normalize -> join "\n" -> blake3. Forge's fn_cap_root mirrors
   this as normalize (order-preserving) -> List.sort -> concat "\n" ->
   Blake3.hash_string. A mismatch here would make every real deploy fail the
   server's tamper check (cap_root recomputed server-side must equal the
   signed value). *)

let test_fn_cap_root_single_cap_matches_blake3_of_bare_string () =
  (* For a single-cap set, normalize is a no-op and there is nothing to sort,
     so fn_cap_root ["IO.Console"] must equal blake3("IO.Console") exactly —
     the same value runtime/march_reload.c's compute_cap_root computes for
     the CSV "IO.Console" (one token, joined with no separator needed). *)
  let expected = March_cas.Blake3.hash_string "IO.Console" in
  Alcotest.(check string) "fn_cap_root single-cap matches raw blake3"
    expected (Cmd_deploy_hot.fn_cap_root ["IO.Console"])

let test_fn_cap_root_empty_matches_blake3_of_empty_string () =
  let expected = March_cas.Blake3.hash_string "" in
  Alcotest.(check string) "fn_cap_root [] matches blake3(\"\")"
    expected (Cmd_deploy_hot.fn_cap_root [])

let test_fn_cap_root_sorts_before_joining () =
  (* Order of the input list must not matter — both must sort to the same
     canonical "IO.Console\nIO.Process" join before hashing. *)
  let a = Cmd_deploy_hot.fn_cap_root ["IO.Process"; "IO.Console"] in
  let b = Cmd_deploy_hot.fn_cap_root ["IO.Console"; "IO.Process"] in
  Alcotest.(check string) "fn_cap_root is order-independent" a b;
  let expected = March_cas.Blake3.hash_string "IO.Console\nIO.Process" in
  Alcotest.(check string) "fn_cap_root matches sorted-join blake3" expected a

let test_fn_cap_root_normalizes_subsumed_caps () =
  (* IO subsumes IO.Console, so normalize drops IO.Console before hashing —
     fn_cap_root ["IO"; "IO.Console"] must equal fn_cap_root ["IO"]. *)
  let with_subsumed = Cmd_deploy_hot.fn_cap_root ["IO"; "IO.Console"] in
  let just_root = Cmd_deploy_hot.fn_cap_root ["IO"] in
  Alcotest.(check string) "normalize collapses subsumed cap before hashing"
    just_root with_subsumed

(* Multi-cap agreement with the SERVER's independent recipe (runtime/
   march_reload.c's compute_cap_root: split -> sort_uniq -> normalize ->
   join "\n" -> blake3). These hand-encode the server's expected output
   directly (sorted order, literal "\n" join, no call to fn_cap_root's own
   Cap_lattice.normalize) so a future accidental reordering on EITHER side
   (forge's fn_cap_root or the server's recipe) that still agrees with
   itself internally would be caught here — the existing
   test_fn_cap_root_sorts_before_joining only checks internal
   order-independence, not agreement with an independently-computed
   server-shaped expected value. *)

let test_fn_cap_root_multi_cap_disjoint_matches_server_recipe () =
  (* Disjoint set: neither cap subsumes the other, so normalize keeps both.
     Server sorts ["IO.FileWrite"; "IO.Console"] -> ["IO.Console"; "IO.FileWrite"],
     joins with "\n", hashes. Hand-encode that exact string independently of
     fn_cap_root's own normalize call. *)
  let expected = March_cas.Blake3.hash_string "IO.Console\nIO.FileWrite" in
  Alcotest.(check string) "multi-cap disjoint set matches hand-encoded server recipe"
    expected (Cmd_deploy_hot.fn_cap_root ["IO.FileWrite"; "IO.Console"])

let test_fn_cap_root_multi_cap_subsumption_matches_server_recipe () =
  (* IO.NetConnect's parent is IO.Network (lib/caps/cap_lattice.ml hierarchy),
     so normalize drops IO.NetConnect, leaving only IO.Network to hash. *)
  let expected = March_cas.Blake3.hash_string "IO.Network" in
  Alcotest.(check string) "multi-cap subsumed set matches hand-encoded server recipe"
    expected (Cmd_deploy_hot.fn_cap_root ["IO.Network"; "IO.NetConnect"])

(* ─── --grant-cap: filter_granted_widening (Phase 5C Part B, Task 5) ──────── *)

let test_grant_no_grants_leaves_widening_blocked () =
  let widening = ["IO.Process"] in
  let granted = Cmd_deploy_hot.filter_granted_widening ~widening ~grant_caps:[] in
  Alcotest.(check (list string)) "no grants -> widening unchanged" ["IO.Process"] granted

let test_grant_exact_match_covers_widening () =
  let widening = ["IO.Process"] in
  let granted = Cmd_deploy_hot.filter_granted_widening ~widening ~grant_caps:["IO.Process"] in
  Alcotest.(check (list string)) "exact-match grant clears widening" [] granted

let test_grant_broader_subsuming_grant_covers_widening () =
  let widening = ["IO.FileWrite"] in
  let granted = Cmd_deploy_hot.filter_granted_widening ~widening ~grant_caps:["IO.FileSystem"] in
  Alcotest.(check (list string)) "broader grant subsumes narrower widened cap" [] granted

let test_grant_partial_leaves_only_ungranted () =
  let widening = ["IO.Process"; "IO.FileWrite"] in
  let granted = Cmd_deploy_hot.filter_granted_widening ~widening ~grant_caps:["IO.Process"] in
  Alcotest.(check (list string)) "only ungranted cap remains" ["IO.FileWrite"] granted

let test_grant_unused_grant_is_inert () =
  (* A grant for a cap that isn't actually being widened has no effect and
     causes no error. *)
  let widening = ["IO.Process"] in
  let granted = Cmd_deploy_hot.filter_granted_widening ~widening ~grant_caps:["IO.Console"] in
  Alcotest.(check (list string)) "unrelated grant is inert" ["IO.Process"] granted

let test_grant_multiple_grants_cover_multiple_widenings () =
  let widening = ["IO.Process"; "IO.FileWrite"] in
  let granted = Cmd_deploy_hot.filter_granted_widening ~widening
      ~grant_caps:["IO.Process"; "IO.FileSystem"] in
  Alcotest.(check (list string)) "both widenings granted" [] granted

(* ─── ACTIVATE4 wire builders (Phase 5C Part C, Task C4) ─────────────────── *)

let cap_root_hex = String.make 64 'c'

let test_activate4_signed_excludes_caps_includes_cap_root () =
  let (signed, wire_head) =
    Cmd_deploy_hot.build_activate4_lines
      ~name:"MyApp.f" ~impl:"implhash" ~cas:"cashash"
      ~migrate:0 ~epoch:5 ~cap_root:cap_root_hex ~callers_csv:"MyApp.a,MyApp.b"
  in
  Alcotest.(check string) "wire_head" "ACTIVATE4 MyApp.f implhash cashash" wire_head;
  let expected_signed =
    Printf.sprintf "ACTIVATE4 MyApp.f implhash cashash 0 epoch:5 cap_root:%s callers:MyApp.a,MyApp.b"
      cap_root_hex
  in
  Alcotest.(check string) "signed message" expected_signed signed;
  (* caps: must NOT appear anywhere in the signed message *)
  let contains_substr hay needle =
    let hl = String.length hay and nl = String.length needle in
    let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
    nl = 0 || go 0
  in
  Alcotest.(check bool) "signed message excludes 'caps:'" false
    (contains_substr signed "caps:");
  Alcotest.(check bool) "signed message includes 'cap_root:'" true
    (contains_substr signed "cap_root:")

let test_activate4_wire_line_orders_cap_root_and_caps_before_callers () =
  let (_, wire_head) =
    Cmd_deploy_hot.build_activate4_lines
      ~name:"MyApp.f" ~impl:"implhash" ~cas:"cashash"
      ~migrate:1 ~epoch:7 ~cap_root:cap_root_hex ~callers_csv:"MyApp.a,MyApp.b"
  in
  let caps_csv = "IO,IO.NetConnect" in
  let wire = Printf.sprintf "%s SIGB64 %d epoch:%d cap_root:%s caps:%s callers:%s"
    wire_head 1 7 cap_root_hex caps_csv "MyApp.a,MyApp.b" in
  let idx_of sub =
    let hl = String.length wire and nl = String.length sub in
    let rec go i = if i + nl > hl then -1 else if String.sub wire i nl = sub then i else go (i + 1) in
    go 0
  in
  let cap_root_idx = idx_of "cap_root:" in
  let caps_idx = idx_of "caps:" in
  let callers_idx = idx_of "callers:" in
  Alcotest.(check bool) "cap_root: appears" true (cap_root_idx >= 0);
  Alcotest.(check bool) "caps: appears" true (caps_idx >= 0);
  Alcotest.(check bool) "callers: appears" true (callers_idx >= 0);
  Alcotest.(check bool) "cap_root: before callers:" true (cap_root_idx < callers_idx);
  Alcotest.(check bool) "caps: before callers:" true (caps_idx < callers_idx);
  Alcotest.(check bool) "wire starts with ACTIVATE4" true
    (String.length wire >= 9 && String.sub wire 0 9 = "ACTIVATE4")

let test_activate3_signed_shape_unchanged () =
  let (signed, wire_head) =
    Cmd_deploy_hot.build_activate3_lines
      ~name:"MyApp.f" ~impl:"implhash" ~cas:"cashash"
      ~migrate:0 ~epoch:3 ~callers_csv:"MyApp.a"
  in
  Alcotest.(check string) "ACTIVATE3 wire_head" "ACTIVATE3 MyApp.f implhash cashash" wire_head;
  Alcotest.(check string) "ACTIVATE3 signed message"
    "ACTIVATE3 MyApp.f implhash cashash 0 epoch:3 callers:MyApp.a" signed

let test_activate4_caps_csv_is_sorted_own_caps_per_function () =
  (* Granularity revision (2026-07-04): the caps: CSV sent on an activated
     function's ACTIVATE4 is THAT function's own sorted caps, never a
     whole-artifact union across other functions in the manifest. A sibling
     function's caps must not leak into this one's CSV. *)
  let handle_fn =
    { Cmd_deploy_hot.fn_name = "MyApp.handle"; fn_impl_hash = "h"; fn_sig_hash = "s";
      fn_callers = []; fn_caps = ["IO.NetConnect"; "IO.Console"]; fn_has_caps = true } in
  let caps_csv = String.concat "," (List.sort String.compare handle_fn.Cmd_deploy_hot.fn_caps) in
  Alcotest.(check string) "own caps CSV, sorted" "IO.Console,IO.NetConnect" caps_csv

(* --no-cap-gate / legacy-manifest branch logic: the `run` function itself
   requires a live socket, so these exercise the same predicate `run` uses
   internally (not (is_legacy_manifest manifest) && not no_cap_gate) via
   is_legacy_manifest directly, mirroring how the cap-widening gate above is
   tested at the pure-predicate level. *)
let activate4_selected ~manifest ~no_cap_gate =
  (not (Cmd_deploy_hot.is_legacy_manifest manifest)) && not no_cap_gate

let manifest_with_caps =
  { Cmd_deploy_hot.cas_hash = String.make 64 'a';
    functions = [
      { Cmd_deploy_hot.fn_name = "MyApp.f"; fn_impl_hash = "h"; fn_sig_hash = "s";
        fn_callers = []; fn_caps = ["IO.Console"]; fn_has_caps = true } ] }

let legacy_manifest =
  { Cmd_deploy_hot.cas_hash = String.make 64 'a';
    functions = [
      { Cmd_deploy_hot.fn_name = "MyApp.f"; fn_impl_hash = "h"; fn_sig_hash = "s";
        fn_callers = []; fn_caps = []; fn_has_caps = false } ] }

let test_branch_caps_present_no_flag_selects_activate4 () =
  Alcotest.(check bool) "ACTIVATE4 selected" true
    (activate4_selected ~manifest:manifest_with_caps ~no_cap_gate:false)

let test_branch_no_cap_gate_flag_forces_activate3 () =
  Alcotest.(check bool) "ACTIVATE3 forced by --no-cap-gate" false
    (activate4_selected ~manifest:manifest_with_caps ~no_cap_gate:true)

let test_branch_legacy_manifest_forces_activate3 () =
  Alcotest.(check bool) "ACTIVATE3 forced by legacy manifest (no caps= anywhere)" false
    (activate4_selected ~manifest:legacy_manifest ~no_cap_gate:false)

(* ------------------------------------------------------- search index cache *)

(** Final-review Critical 1: a cache written before [Search.current_index_version]
    was bumped (e.g. a v1 cache predating the `references` table) must be
    treated as a cache miss and rebuilt, not loaded as-is forever. Writes a
    hand-crafted stale-version cache file, then asserts [load_or_build_index]
    silently rebuilds it to the current version rather than returning it
    unchanged. *)
let test_load_or_build_index_rebuilds_on_stale_version () =
  let tmpdir = Filename.temp_dir "test_search_cache_" "" in
  Fun.protect
    ~finally:(fun () ->
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir))))
    (fun () ->
       let cache_path = Cmd_search.index_cache_path tmpdir in
       Project.mkdir_p (Filename.dirname cache_path);
       let oc = open_out cache_path in
       (* Shape of a pre-[references] cache: version 1, no "references" key. *)
       output_string oc
         {|{"version":1,"generated_at":"2020-01-01T00:00:00Z","entries":[]}|};
       close_out oc;
       match Cmd_search.load_or_build_index ~verbose:false ~root:tmpdir [] with
       | Error msg -> Alcotest.fail msg
       | Ok idx ->
         Alcotest.(check bool) "stale v1 cache is rebuilt to the current version" true
           (idx.March_search.Search.version = March_search.Search.current_index_version);
         Alcotest.(check bool) "rebuilt index has real entries, not the stale empty stub" true
           (List.length idx.March_search.Search.entries > 0))

(** Companion to the above: a cache that's already current must be loaded
    as-is (no unnecessary rebuild) — pins that the version check only
    triggers on an actual mismatch. *)
let test_load_or_build_index_reuses_fresh_cache () =
  let tmpdir = Filename.temp_dir "test_search_cache_fresh_" "" in
  Fun.protect
    ~finally:(fun () ->
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir))))
    (fun () ->
       let cache_path = Cmd_search.index_cache_path tmpdir in
       Project.mkdir_p (Filename.dirname cache_path);
       let refs = March_search.Search.references_of_list
           [ { March_search.Search.callee = "A.helper"; caller = "A.main";
               kind = "call"; file = "a.march"; line = 1 } ] in
       let idx = March_search.Search.{
           version = current_index_version;
           generated_at = "2026-01-01T00:00:00Z";
           references = refs;
           entries = [];
         } in
       let oc = open_out cache_path in
       output_string oc (March_search.Search.index_to_json idx);
       close_out oc;
       match Cmd_search.load_or_build_index ~verbose:false ~root:tmpdir [] with
       | Error msg -> Alcotest.fail msg
       | Ok idx2 ->
         Alcotest.(check int) "fresh cache loaded as-is (not rebuilt over)" 0
           (List.length idx2.March_search.Search.entries);
         Alcotest.(check int) "fresh cache's references survive the load" 1
           (List.length (March_search.Search.callers_of idx2 "A.helper")))

(** Final-review Important 6: `--limit` was applied to the name/type/doc
    search path (via [print_results]'s [take]) but never to the `--callers`
    branch, so `--limit` silently had no effect on reverse-reference
    queries. Runs [Cmd_search.run] end-to-end with a pre-seeded fresh-version
    cache (avoiding a real stdlib rebuild) containing 3 references to one
    callee, with `--limit 1`, and captures stdout (the command prints
    directly rather than returning a value) to confirm only 1 comes back. *)
let test_callers_respects_limit () =
  let tmpdir = Filename.temp_dir "test_search_limit_" "" in
  let old_cwd = Sys.getcwd () in
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old_cwd;
        ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir))))
    (fun () ->
       Unix.chdir tmpdir;
       let cache_path = Cmd_search.index_cache_path "." in
       Project.mkdir_p (Filename.dirname cache_path);
       let refs = March_search.Search.references_of_list [
           { March_search.Search.callee = "A.helper"; caller = "A.one";
             kind = "call"; file = "a.march"; line = 1 };
           { March_search.Search.callee = "A.helper"; caller = "A.two";
             kind = "call"; file = "a.march"; line = 2 };
           { March_search.Search.callee = "A.helper"; caller = "A.three";
             kind = "call"; file = "a.march"; line = 3 };
         ] in
       let idx = March_search.Search.{
           version = current_index_version;
           generated_at = "2026-01-01T00:00:00Z";
           references = refs;
           entries = [];
         } in
       let oc = open_out cache_path in
       output_string oc (March_search.Search.index_to_json idx);
       close_out oc;
       (* Capture stdout: [Cmd_search.run] prints directly rather than
          returning a value. *)
       let out_path = Filename.temp_file "test_search_limit_stdout_" ".json" in
       Fun.protect
         ~finally:(fun () -> (try Sys.remove out_path with Sys_error _ -> ()))
         (fun () ->
            let saved_stdout = Unix.dup Unix.stdout in
            let out_fd = Unix.openfile out_path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
            Unix.dup2 out_fd Unix.stdout;
            Unix.close out_fd;
            Fun.protect
              ~finally:(fun () ->
                  Unix.dup2 saved_stdout Unix.stdout;
                  Unix.close saved_stdout)
              (fun () ->
                 Cmd_search.run ~query:"" ~type_sig:"" ~doc_query:"" ~callers:"A.helper"
                   ~limit:1 ~as_json:true ~plain:true ~rebuild:false ());
            let captured = read_file out_path in
            let j = Yojson.Basic.from_string captured in
            match j with
            | `List items ->
              Alcotest.(check int) "--limit 1 truncates 3 references down to 1"
                1 (List.length items)
            | _ -> Alcotest.fail "expected a JSON list from --callers --json"))

(* ------------------------------------------------- interpreted-run commands *)

(* Regression: `forge run` (interpreted) used to build its `march` invocation
   without ever calling [Cmd_build.ffi_flags_full], so no --ffi-c/--ffi-link
   reached the compiler.  [setup_interpreter_ffi] is gated on ffi_c_files being
   non-empty, so it built no shim .so, and every extern declared by a
   dependency's [[ffi]] C sources died at the call site with "symbol not found
   for interpreter FFI" — while `forge run --compiled`, `forge build` and
   `forge test` all worked.  These pin the flags into the command string. *)

let index_of haystack needle =
  let nl = String.length needle and hl = String.length haystack in
  let rec at i =
    if i + nl > hl then -1
    else if String.sub haystack i nl = needle then i
    else at (i + 1)
  in at 0

let ffi_flags_sample = " --ffi-c '/dep/native/sqlite_shim.c' --ffi-link '-lsqlite3'"

let test_interp_command_includes_ffi_flags () =
  let cmd =
    Cmd_run.interp_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib "
      ~dump_flag:"" ~ffi_flags:ffi_flags_sample ~entry:"/p/lib/app.march" ()
  in
  Alcotest.(check bool) "--ffi-c reaches march" true
    (contains cmd "--ffi-c '/dep/native/sqlite_shim.c'");
  Alcotest.(check bool) "--ffi-link reaches march" true
    (contains cmd "--ffi-link '-lsqlite3'");
  Alcotest.(check bool) "entry file is still passed" true
    (contains cmd "'/p/lib/app.march'")

let test_interp_command_no_ffi_is_unchanged () =
  (* A project without [[ffi]] gets the empty string from ffi_flags_full; the
     command must not grow a stray separator. *)
  let cmd =
    Cmd_run.interp_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib "
      ~dump_flag:"" ~ffi_flags:"" ~entry:"/p/lib/app.march" ()
  in
  Alcotest.(check string) "no-ffi command shape"
    "MARCH_LIB_PATH=/p/lib march '/p/lib/app.march'" cmd

let test_interp_command_passes_program_args () =
  (* The program's own arguments ride behind --args, which must come LAST:
     the compiler collects every remaining token there (Arg.Rest_all), so a
     flag emitted after it would be swallowed as a program argument. *)
  let cmd =
    Cmd_run.interp_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib "
      ~dump_flag:"" ~ffi_flags:"" ~args:["alpha"; "two words"]
      ~entry:"/p/lib/app.march" ()
  in
  Alcotest.(check string) "args follow the entry behind --args"
    "MARCH_LIB_PATH=/p/lib march '/p/lib/app.march' --args 'alpha' 'two words'"
    cmd

let test_interp_command_empty_args_adds_nothing () =
  (* An empty arg list must not grow a stray "--args": the no-args command is
     what every existing caller (and forge watch) emits. *)
  let cmd =
    Cmd_run.interp_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib "
      ~dump_flag:"" ~ffi_flags:"" ~args:[] ~entry:"/p/lib/app.march" ()
  in
  Alcotest.(check string) "identical to the no-args command"
    "MARCH_LIB_PATH=/p/lib march '/p/lib/app.march'" cmd

let test_output_ext_by_target () =
  (* Pinned because the single-file compiled run names a temp output with this,
     and running a .mjs as if it were a native binary fails confusingly. *)
  Alcotest.(check string) "native has no extension" "" (Cmd_build.output_ext None);
  Alcotest.(check string) "js" ".mjs" (Cmd_build.output_ext (Some "js"));
  Alcotest.(check string) "javascript" ".mjs" (Cmd_build.output_ext (Some "javascript"));
  Alcotest.(check string) "wasm" ".wasm" (Cmd_build.output_ext (Some "wasm32"));
  Alcotest.(check string) "an unknown target is native" ""
    (Cmd_build.output_ext (Some "aarch64-linux"))

let test_resolve_entry_missing_file () =
  match Cmd_run.resolve_entry ~file:"/definitely/not/here.march" () with
  | Ok _ -> Alcotest.fail "a missing file must not resolve"
  | Error msg ->
    Alcotest.(check bool) "error names the file" true
      (contains msg "/definitely/not/here.march")

let test_resolve_entry_directory_is_rejected () =
  match Cmd_run.resolve_entry ~file:(Filename.get_temp_dir_name ()) () with
  | Ok _ -> Alcotest.fail "a directory must not resolve as an entry"
  | Error msg ->
    Alcotest.(check bool) "error explains it is not a file" true
      (contains msg "not a file")

let test_resolve_entry_outside_a_project_runs_bare () =
  (* Outside a project there is no forge.toml to read, so the file runs with no
     MARCH_LIB_PATH and no FFI flags — the same fallback Cmd_test.run_files
     already uses for ad-hoc test files. *)
  let tmpdir = Filename.temp_dir "resolve_bare_" "" in
  let file = Filename.concat tmpdir "scratch.march" in
  let oc = open_out file in
  output_string oc "mod Scratch do\n  fn main() do\n    ()\n  end\nend\n";
  close_out oc;
  let old_cwd = Sys.getcwd () in
  Fun.protect
    ~finally:(fun () ->
        Unix.chdir old_cwd;
        let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       Unix.chdir tmpdir;
       match Cmd_run.resolve_entry ~file:"scratch.march" () with
       | Error msg -> Alcotest.failf "expected a bare resolution, got: %s" msg
       | Ok (entry, ctx) ->
         Alcotest.(check string) "entry is the file as given" "scratch.march" entry;
         Alcotest.(check string) "no lib path" "" ctx.Cmd_run.lib_path_env;
         Alcotest.(check string) "no ffi flags" "" ctx.Cmd_run.ffi_flags)

let test_repl_command_includes_ffi_flags_after_entry () =
  let cmd =
    Cmd_interactive.repl_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib"
      ~ffi_flags:ffi_flags_sample ~entry:(Some "/p/lib/app.march")
  in
  Alcotest.(check bool) "--ffi-c reaches march repl" true
    (contains cmd "--ffi-c '/dep/native/sqlite_shim.c'");
  (* The preload file must stay in argv.(2): an older `march repl` reads that
     slot positionally and would take "--ffi-c" as the file to load. *)
  let entry_pos = index_of cmd "'/p/lib/app.march'" in
  let flag_pos  = index_of cmd "--ffi-c" in
  Alcotest.(check bool) "entry precedes the ffi flags" true
    (entry_pos >= 0 && flag_pos > entry_pos)

let test_repl_command_bare_includes_ffi_flags () =
  let cmd =
    Cmd_interactive.repl_command ~lib_path_env:"MARCH_LIB_PATH=/p/lib"
      ~ffi_flags:ffi_flags_sample ~entry:None
  in
  Alcotest.(check string) "bare REPL still gets the shims"
    ("MARCH_LIB_PATH=/p/lib march" ^ ffi_flags_sample) cmd

(* -------------------------------------------------------------------- suite *)

let () =
  Alcotest.run "forge" [
    "scaffold", [
      Alcotest.test_case "app project creates expected files" `Quick test_scaffold_app;
      Alcotest.test_case "lib project sets type=lib"          `Quick test_scaffold_lib;
      Alcotest.test_case "tool project sets type=tool"        `Quick test_scaffold_tool;
      Alcotest.test_case "forge.toml fields correct"          `Quick test_forge_toml_fields;
      Alcotest.test_case "duplicate name returns error"       `Quick test_duplicate_fails;
      Alcotest.test_case ".gitignore contains /.march/"       `Quick test_gitignore_has_march;
      Alcotest.test_case ".editorconfig indent_size=2"        `Quick test_editorconfig_indent;
      Alcotest.test_case "README.md contains project name"    `Quick test_readme_has_name;
      Alcotest.test_case "module name is PascalCase"          `Quick test_module_name_is_pascal_case;
      Alcotest.test_case "generated files use do/end syntax"  `Quick test_generated_march_uses_do_end;
    ];
    "toml", [
      Alcotest.test_case "simple key/value pairs"   `Quick test_toml_simple;
      Alcotest.test_case "inline table (git dep)"   `Quick test_toml_inline_table;
      Alcotest.test_case "inline table (path dep)"  `Quick test_toml_path_dep;
      Alcotest.test_case "comments are ignored"     `Quick test_toml_comments_ignored;
      Alcotest.test_case "missing section is empty" `Quick test_toml_missing_section;
    ];
    "toolchain", [
      Alcotest.test_case "platform: darwin arm64"            `Quick test_platform_darwin_arm;
      Alcotest.test_case "platform: linux variants"          `Quick test_platform_linux;
      Alcotest.test_case "platform: trims uname output"      `Quick test_platform_trims;
      Alcotest.test_case "platform: unsupported errors"      `Quick test_platform_unsupported;
      Alcotest.test_case "checksum: standard format"         `Quick test_checksum_standard;
      Alcotest.test_case "checksum: legacy sha256 prefix"    `Quick test_checksum_legacy_prefix;
      Alcotest.test_case "checksum: unlisted file -> None"   `Quick test_checksum_not_found;
      Alcotest.test_case "valid_tag accepts/rejects"         `Quick test_valid_tag;
      Alcotest.test_case "default_tag: prefers stable"       `Quick test_default_tag_prefers_stable;
      Alcotest.test_case "default_tag: nightly fallback"     `Quick test_default_tag_nightly_fallback;
      Alcotest.test_case "default_tag: empty -> None"        `Quick test_default_tag_empty;
      Alcotest.test_case "pin: read from current dir"        `Quick test_pin_in_current_dir;
      Alcotest.test_case "pin: walks up to ancestor"         `Quick test_pin_walks_up_parents;
      Alcotest.test_case "pin: absent -> None"               `Quick test_pin_absent;
      Alcotest.test_case "resolve: pin beats global"         `Quick test_resolve_prefers_pin;
      Alcotest.test_case "resolve: falls back to global"     `Quick test_resolve_falls_back_to_global;
      Alcotest.test_case "resolve: none when unset"          `Quick test_resolve_none_when_unset;
      Alcotest.test_case "march_command: uses installed ver" `Quick test_march_command_uses_installed_version;
      Alcotest.test_case "march_command: errors if pin missing" `Quick test_march_command_errors_when_pinned_version_missing;
      Alcotest.test_case "march_command: PATH fallback"      `Quick test_march_command_falls_back_to_path;
      Alcotest.test_case "path_prefix: installed -> PATH override" `Quick test_path_prefix_installed;
      Alcotest.test_case "path_prefix: fallback -> empty"    `Quick test_path_prefix_empty_on_fallback;
      Alcotest.test_case "constraint: satisfied"             `Quick test_constraint_satisfied;
      Alcotest.test_case "constraint: violated"              `Quick test_constraint_violated;
      Alcotest.test_case "constraint: skips non-semver tag"  `Quick test_constraint_skips_non_semver_tag;
      Alcotest.test_case "constraint: rejects malformed req" `Quick test_constraint_rejects_malformed_req;
      Alcotest.test_case "list --remote: groups + marks installed" `Quick test_classify_remote_groups_and_marks;
      Alcotest.test_case "ensure_installed: no-op when present" `Quick test_ensure_installed_noop_when_present;
      Alcotest.test_case "ensure_installed: no-op when unresolved" `Quick test_ensure_installed_noop_when_unresolved;
    ];
    "deptree", [
      Alcotest.test_case "render: ascii tree"           `Quick test_deptree_render;
      Alcotest.test_case "render: cycle breaks"         `Quick test_deptree_render_cycle_breaks;
      Alcotest.test_case "why: all paths to target"     `Quick test_deptree_why_paths;
      Alcotest.test_case "why: no path -> empty"        `Quick test_deptree_why_none;
    ];
    "lockfile-toolchain", [
      Alcotest.test_case "records + reads back toolchain" `Quick test_lockfile_records_toolchain;
      Alcotest.test_case "absent toolchain -> None"       `Quick test_lockfile_no_toolchain;
      Alcotest.test_case "drift: warns on mismatch"       `Quick test_drift_warns_on_mismatch;
      Alcotest.test_case "drift: silent on match"         `Quick test_drift_silent_on_match;
      Alcotest.test_case "drift: silent when unlocked"    `Quick test_drift_silent_when_unlocked;
    ];
    "metadata", [
      Alcotest.test_case "parses license/repository/homepage" `Quick test_project_metadata_fields;
      Alcotest.test_case "absent metadata -> None"            `Quick test_project_metadata_absent;
    ];
    "workspace", [
      Alcotest.test_case "parse_members: extracts list"    `Quick test_workspace_parse_members;
      Alcotest.test_case "parse_members: no workspace -> []" `Quick test_workspace_parse_members_empty;
      Alcotest.test_case "parse_members: no key -> []"     `Quick test_workspace_parse_members_no_key;
      Alcotest.test_case "find_root: locates root"         `Quick test_workspace_find_root;
      Alcotest.test_case "find_root: None when absent"     `Quick test_workspace_find_root_none;
    ];
    "cli-ext", [
      Alcotest.test_case "completions: bash"        `Quick test_completion_bash;
      Alcotest.test_case "completions: zsh"         `Quick test_completion_zsh;
      Alcotest.test_case "completions: fish"        `Quick test_completion_fish;
      Alcotest.test_case "external: unknown -> forge-x" `Quick test_external_found;
      Alcotest.test_case "external: built-in wins"  `Quick test_external_builtin_wins;
      Alcotest.test_case "external: not found"      `Quick test_external_not_found;
    ];
    "licenses", [
      Alcotest.test_case "format: human + MISSING"  `Quick test_licenses_format_human;
      Alcotest.test_case "any_missing"              `Quick test_licenses_any_missing;
      Alcotest.test_case "frozen_error gate"        `Quick test_frozen_error;
    ];
    "versioning", [
      Alcotest.test_case "bump patch"               `Quick test_bump_patch;
      Alcotest.test_case "bump minor resets patch"  `Quick test_bump_minor;
      Alcotest.test_case "bump major resets lower"  `Quick test_bump_major;
      Alcotest.test_case "bump clears pre-release"  `Quick test_bump_clears_pre;
      Alcotest.test_case "rewrite [package].version only" `Quick test_rewrite_version_package_only;
    ];
    "bench", [
      Alcotest.test_case "bench_name: stem from path"   `Quick test_bench_name;
      Alcotest.test_case "matches: filter predicate"    `Quick test_bench_matches;
      Alcotest.test_case "format: human table"          `Quick test_bench_format_human;
      Alcotest.test_case "format: json"                 `Quick test_bench_format_json;
    ];
    "watcher", [
      Alcotest.test_case "no change on identical snapshot"  `Quick test_watch_no_change;
      Alcotest.test_case "mtime change -> change"           `Quick test_watch_mtime_advances;
      Alcotest.test_case "added file -> change"             `Quick test_watch_added;
      Alcotest.test_case "removed file -> change"           `Quick test_watch_removed;
      Alcotest.test_case "order-insensitive"               `Quick test_watch_order_insensitive;
    ];
    "ffi", [
      Alcotest.test_case "gen-c: extern block -> C skeleton" `Quick test_ffi_gen_c;
      Alcotest.test_case "gen-c: record/variant codecs"      `Quick test_ffi_gen_c_codecs;
      Alcotest.test_case "gen-c: Option/Result field codecs"       `Quick test_ffi_gen_c_optres_fields;
      Alcotest.test_case "gen-c: Option(Float)/Option(Unit) fields" `Quick test_ffi_gen_c_optres_float_unit;
      Alcotest.test_case "gen-c: nested codec Option/Result fields" `Quick test_ffi_gen_c_optres_nested;
      Alcotest.test_case "gen-c: List(T) field codecs"              `Quick test_ffi_gen_c_list_fields;
      Alcotest.test_case "gen-c: raises (env-routed errors)"        `Quick test_ffi_gen_c_raises;
      Alcotest.test_case "add-rust: scaffolds a binding crate" `Quick test_ffi_add_rust;
      Alcotest.test_case "gen-c: errors with no extern"      `Quick test_ffi_gen_c_no_extern;
    ];
    "hcr-cap-gate", [
      Alcotest.test_case "parse_manifest: tolerates legacy ROOT line, no phantom fn" `Quick test_parse_manifest_root_line_no_phantom_fn;
      Alcotest.test_case "parse_manifest: no caps= anywhere -> legacy" `Quick test_parse_manifest_no_caps_anywhere_is_legacy;
      Alcotest.test_case "parse_manifest: caps= present (even empty) -> not legacy" `Quick test_parse_manifest_caps_field_present_is_not_legacy;
      Alcotest.test_case "parse_manifest: caps= (no callers)"  `Quick test_parse_manifest_caps_no_callers;
      Alcotest.test_case "parse_manifest: caps= (with callers)" `Quick test_parse_manifest_caps_with_callers;
      Alcotest.test_case "parse_manifest: caps= empty"          `Quick test_parse_manifest_caps_empty;
      Alcotest.test_case "gate: empty prior -> all new caps 'widen'" `Quick test_gate_no_prior_is_permissive;
      Alcotest.test_case "gate: pure narrowing allowed"         `Quick test_gate_pure_narrowing_allowed;
      Alcotest.test_case "gate: narrowing uses subsumption, root cap covers prior specific" `Quick test_gate_narrowing_root_cap_covers_prior_specific_not_misreported;
      Alcotest.test_case "gate: subsumed add allowed"           `Quick test_gate_subsumed_add_allowed;
      Alcotest.test_case "gate: sibling widen blocked"          `Quick test_gate_sibling_widen_blocked;
      Alcotest.test_case "gate: parent widen blocked"           `Quick test_gate_parent_widen_blocked;
      Alcotest.test_case "gate: IO root add blocked"            `Quick test_gate_io_root_add_blocked;
      Alcotest.test_case "gate: attribution names introducer"  `Quick test_gate_attribution_names_introducing_function;
      Alcotest.test_case "scoped caps: no prior baseline is permissive" `Quick test_scoped_caps_no_prior_baseline_permissive;
      Alcotest.test_case "scoped caps: new fn compares against empty prior" `Quick test_scoped_caps_new_function_compares_against_empty;
      Alcotest.test_case "scoped caps: existing fn adding a cap widens" `Quick test_scoped_caps_existing_function_adds_cap_widens;
      Alcotest.test_case "scoped caps: existing fn dropping a cap narrows" `Quick test_scoped_caps_existing_function_drops_cap_narrows;
      Alcotest.test_case "scoped caps: existing fn adding subsumed cap does not widen" `Quick test_scoped_caps_existing_function_adds_subsumed_cap_no_widen;
      Alcotest.test_case "fn_cap_root: single cap matches raw blake3" `Quick test_fn_cap_root_single_cap_matches_blake3_of_bare_string;
      Alcotest.test_case "fn_cap_root: empty matches blake3(\"\")" `Quick test_fn_cap_root_empty_matches_blake3_of_empty_string;
      Alcotest.test_case "fn_cap_root: order-independent, sorts before join" `Quick test_fn_cap_root_sorts_before_joining;
      Alcotest.test_case "fn_cap_root: normalizes subsumed caps before hashing" `Quick test_fn_cap_root_normalizes_subsumed_caps;
      Alcotest.test_case "fn_cap_root: multi-cap disjoint set matches server recipe" `Quick test_fn_cap_root_multi_cap_disjoint_matches_server_recipe;
      Alcotest.test_case "fn_cap_root: multi-cap subsumed set matches server recipe" `Quick test_fn_cap_root_multi_cap_subsumption_matches_server_recipe;
      Alcotest.test_case "grant: no grants leaves widening blocked" `Quick test_grant_no_grants_leaves_widening_blocked;
      Alcotest.test_case "grant: exact-match grant covers widening" `Quick test_grant_exact_match_covers_widening;
      Alcotest.test_case "grant: broader subsuming grant covers widening" `Quick test_grant_broader_subsuming_grant_covers_widening;
      Alcotest.test_case "grant: partial grant leaves only ungranted" `Quick test_grant_partial_leaves_only_ungranted;
      Alcotest.test_case "grant: unused grant is inert" `Quick test_grant_unused_grant_is_inert;
      Alcotest.test_case "grant: multiple grants cover multiple widenings" `Quick test_grant_multiple_grants_cover_multiple_widenings;
      Alcotest.test_case "ACTIVATE4: signed excludes caps, includes cap_root" `Quick test_activate4_signed_excludes_caps_includes_cap_root;
      Alcotest.test_case "ACTIVATE4: wire orders cap_root+caps before callers" `Quick test_activate4_wire_line_orders_cap_root_and_caps_before_callers;
      Alcotest.test_case "ACTIVATE3: signed/wire shape unchanged" `Quick test_activate3_signed_shape_unchanged;
      Alcotest.test_case "ACTIVATE4: caps csv is sorted own caps per function" `Quick test_activate4_caps_csv_is_sorted_own_caps_per_function;
      Alcotest.test_case "branch: caps present, no flag -> ACTIVATE4" `Quick test_branch_caps_present_no_flag_selects_activate4;
      Alcotest.test_case "branch: --no-cap-gate forces ACTIVATE3" `Quick test_branch_no_cap_gate_flag_forces_activate3;
      Alcotest.test_case "branch: legacy manifest forces ACTIVATE3" `Quick test_branch_legacy_manifest_forces_activate3;
    ];
    "interp_command", [
      Alcotest.test_case "forge run threads [ffi] flags to march" `Quick
        test_interp_command_includes_ffi_flags;
      Alcotest.test_case "no [ffi] leaves the command unchanged" `Quick
        test_interp_command_no_ffi_is_unchanged;
      Alcotest.test_case "program args ride behind --args" `Quick
        test_interp_command_passes_program_args;
      Alcotest.test_case "no program args leaves the command unchanged" `Quick
        test_interp_command_empty_args_adds_nothing;
      Alcotest.test_case "a missing FILE is rejected" `Quick
        test_resolve_entry_missing_file;
      Alcotest.test_case "a directory FILE is rejected" `Quick
        test_resolve_entry_directory_is_rejected;
      Alcotest.test_case "a FILE outside a project runs bare" `Quick
        test_resolve_entry_outside_a_project_runs_bare;
      Alcotest.test_case "forge interactive puts ffi flags after the entry" `Quick
        test_repl_command_includes_ffi_flags_after_entry;
      Alcotest.test_case "bare REPL still gets the ffi flags" `Quick
        test_repl_command_bare_includes_ffi_flags;
      Alcotest.test_case "output extension follows the target" `Quick
        test_output_ext_by_target;
    ];
    "search_index_cache", [
      Alcotest.test_case "stale version cache is rebuilt" `Quick
        test_load_or_build_index_rebuilds_on_stale_version;
      Alcotest.test_case "fresh version cache is reused" `Quick
        test_load_or_build_index_reuses_fresh_cache;
      Alcotest.test_case "--callers respects --limit" `Quick
        test_callers_respects_limit;
    ];
  ]
