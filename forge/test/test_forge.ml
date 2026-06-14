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

let contains haystack needle =
  let nl = String.length needle and hl = String.length haystack in
  let rec at i = i + nl <= hl && (String.sub haystack i nl = needle || at (i + 1)) in
  nl = 0 || at 0

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
    ];
  ]
