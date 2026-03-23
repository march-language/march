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
stdlib = { git = "https://github.com/march-lang/stdlib", rev = "main" }
|} in
  let doc  = Toml.parse text in
  let deps = Toml.get_section doc "deps" in
  (match Toml.get_table deps "stdlib" with
   | None     -> Alcotest.fail "expected inline table for stdlib"
   | Some tbl ->
     Alcotest.(check (option string)) "git url"
       (Some "https://github.com/march-lang/stdlib")
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
  ]
