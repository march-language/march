(** Tests for API surface extraction (real March AST) and semver change
    classification.

    Fixtures below are real March syntax — `fn`/`pfn` visibility, `: T`
    return types — parsed with the real parser via
    [Resolver_api_surface.extract_from_string]/[extract_from_directory].
    The previous version of this suite exercised an invented `pub fn
    ... -> T` dialect that matched the (buggy) hand-rolled line scanner but
    not the language; see
    specs/progress/2026-08-03-forge-api-surface-parser-wrong-syntax.md. *)

open March_forge

(* ------------------------------------------------------------------ *)
(*  extract_from_string — real March syntax                            *)
(* ------------------------------------------------------------------ *)

let test_extract_public_and_private () =
  let src = {|
mod Test do
  fn add(x : Int, y : Int) : Int do
    x + y
  end

  fn sub(x : Int, y : Int) : Int do
    x - y
  end

  type Result = Ok(Int) | Err(String)

  pfn private_helper(x : Int) : Int do
    x
  end

  ptype InternalState = { count : Int }
end
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  Alcotest.(check int) "2 public fns"  2 (List.length surf.Resolver_api_surface.fns);
  Alcotest.(check int) "1 public type" 1 (List.length surf.Resolver_api_surface.types);
  let fn_names = List.map (fun f -> f.Resolver_api_surface.name) surf.Resolver_api_surface.fns in
  Alcotest.(check bool) "add present"             true  (List.mem "add" fn_names);
  Alcotest.(check bool) "sub present"              true  (List.mem "sub" fn_names);
  Alcotest.(check bool) "private_helper excluded"  false (List.mem "private_helper" fn_names);
  let ty_names = List.map (fun t -> t.Resolver_api_surface.type_name) surf.Resolver_api_surface.types in
  Alcotest.(check bool) "Result present"           true  (List.mem "Result" ty_names);
  Alcotest.(check bool) "InternalState excluded"   false (List.mem "InternalState" ty_names)

let test_extract_fn_signature_shape () =
  let src = {|
mod Test do
  fn greet(name : String, greeting : String) : String do
    greeting
  end
end
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  match surf.Resolver_api_surface.fns with
  | [f] ->
    Alcotest.(check string) "name"   "greet" f.Resolver_api_surface.name;
    Alcotest.(check string) "params" "name : String, greeting : String"
      f.Resolver_api_surface.params_raw;
    Alcotest.(check string) "return" "String" f.Resolver_api_surface.return_raw
  | fns -> Alcotest.failf "expected exactly 1 fn, got %d" (List.length fns)

let test_extract_fn_no_return_annotation () =
  let src = {|
mod Test do
  fn identity(x) do
    x
  end
end
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  match surf.Resolver_api_surface.fns with
  | [f] -> Alcotest.(check string) "return_raw empty" "" f.Resolver_api_surface.return_raw
  | fns -> Alcotest.failf "expected exactly 1 fn, got %d" (List.length fns)

let test_extract_empty_module () =
  let surf = Resolver_api_surface.extract_from_string "mod Empty do end" in
  Alcotest.(check int) "no fns"   0 (List.length surf.Resolver_api_surface.fns);
  Alcotest.(check int) "no types" 0 (List.length surf.Resolver_api_surface.types)

let test_extract_unparseable_source_is_empty_not_exn () =
  (* A file that fails to parse must not crash the extractor — it degrades
     to an empty surface, same as the historical bug's symptom but for a
     legitimate reason (a genuine parse failure, not a syntax the scanner
     never understood in the first place). *)
  let surf = Resolver_api_surface.extract_from_string "this is not march at all {{{" in
  Alcotest.(check int) "no fns"   0 (List.length surf.Resolver_api_surface.fns);
  Alcotest.(check int) "no types" 0 (List.length surf.Resolver_api_surface.types)

(* A line scanner can only ever see the first clause of a multi-head
   function. The parser groups same-named consecutive clauses into one
   DFn (lib/parser/parser.mly's group_fn_clauses), so the AST walk sees
   every head for free. *)
let test_extract_multi_head_clauses () =
  let src = {|
mod Test do
  fn fib(0) : Int do
    0
  end

  fn fib(1) : Int do
    1
  end

  fn fib(n) : Int do
    fib(n - 1) + fib(n - 2)
  end
end
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  match surf.Resolver_api_surface.fns with
  | [f] ->
    Alcotest.(check string) "name" "fib" f.Resolver_api_surface.name;
    Alcotest.(check string) "all three heads visible"
      "(0) | (1) | (n)" f.Resolver_api_surface.params_raw
  | fns -> Alcotest.failf "expected exactly 1 fn (clauses grouped), got %d" (List.length fns)

(* Default arguments (FPDefault) are invisible to a text scanner; the AST
   walk sees the parameter regardless. *)
let test_extract_default_argument () =
  let src = {|
mod Test do
  fn greet(name : String, greeting : String \\ "Hello") : String do
    greeting
  end
end
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  match surf.Resolver_api_surface.fns with
  | [f] ->
    Alcotest.(check string) "name" "greet" f.Resolver_api_surface.name;
    Alcotest.(check string) "params include the defaulted param"
      "name : String, greeting : String \\\\ _" f.Resolver_api_surface.params_raw
  | fns -> Alcotest.failf "expected exactly 1 fn, got %d" (List.length fns)

(* A signature wrapped across multiple lines is invisible to a scanner that
   expects `pub fn name(...)` on one line; the parser doesn't care. *)
let test_extract_wrapped_signature () =
  let src = {|
mod Test do
  fn combine(
      x : Int,
      y : Int,
      z : Int
    ) : Int do
    x + y + z
  end
end
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  match surf.Resolver_api_surface.fns with
  | [f] ->
    Alcotest.(check string) "name"   "combine" f.Resolver_api_surface.name;
    Alcotest.(check string) "params" "x : Int, y : Int, z : Int" f.Resolver_api_surface.params_raw;
    Alcotest.(check string) "return" "Int" f.Resolver_api_surface.return_raw
  | fns -> Alcotest.failf "expected exactly 1 fn, got %d" (List.length fns)

(* Nested `mod ... end` blocks must be walked too. *)
let test_extract_nested_mod () =
  let src = {|
mod Test do
  mod Inner do
    fn helper() : Int do
      1
    end

    pfn hidden() : Int do
      0
    end
  end
end
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  let fn_names = List.map (fun f -> f.Resolver_api_surface.name) surf.Resolver_api_surface.fns in
  Alcotest.(check bool) "helper found via nested mod" true (List.mem "helper" fn_names);
  Alcotest.(check bool) "hidden excluded"              false (List.mem "hidden" fn_names)

(* ------------------------------------------------------------------ *)
(*  Non-emptiness regression: the actual failure mode of the bug this   *)
(*  module was rewritten to fix was SILENCE — an empty surface with no  *)
(*  error, for every real package. Only an assertion that a REAL file's *)
(*  surface is non-empty (and contains real names) catches that class   *)
(*  of regression; a fixture written in the parser's own dialect        *)
(*  cannot, because it always "round-trips" against itself.             *)
(* ------------------------------------------------------------------ *)

(* forge_registry.march is a real, non-trivial forge source file, embedded
   into march_forge at build time (forge/lib/dune's registry_march_src.ml
   rule) so this test has no runtime filesystem dependency. *)
let test_extract_from_directory_forge_own_source_nonempty () =
  let surf = Resolver_api_surface.extract_from_string Registry_march_src.content in
  Alcotest.(check bool) "fns non-empty"   true (surf.Resolver_api_surface.fns <> []);
  let fn_names = List.map (fun f -> f.Resolver_api_surface.name) surf.Resolver_api_surface.fns in
  List.iter (fun n ->
      Alcotest.(check bool) (n ^ " present") true (List.mem n fn_names))
    ["request"; "multipart"; "publish_url"; "retire_url"; "friendly"];
  (* Known-private helpers from the same file must NOT show up. *)
  List.iter (fun n ->
      Alcotest.(check bool) (n ^ " excluded (private)") false (List.mem n fn_names))
    ["no_trailing_slash"; "path_or_root"; "json_str"]

(* Same non-emptiness property, but through extract_from_directory — the
   function forge publish actually calls — over a real .march file written
   to a temp directory, so the file-walk (march_files_under) and per-file
   parse (parse_file) paths are exercised too, not just extract_from_string. *)
let test_extract_from_directory_nonempty () =
  let tmpdir = Filename.temp_dir "test_api_surface_" "" in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       let path = Filename.concat tmpdir "registry_urls.march" in
       let oc = open_out path in
       (* Lifted verbatim from forge/tasks/forge_registry.march. *)
       output_string oc {|mod RegistryUrls do
  pfn no_trailing_slash(s) do
    if String.ends_with(s, "/") do String.slice_bytes(s, 0, String.byte_size(s) - 1) else s end
  end

  fn publish_url(registry, name) do no_trailing_slash(registry) ++ "/api/v1/packages/" ++ name ++ "/releases" end
  fn retire_url(registry, name, vsn) do publish_url(registry, name) ++ "/" ++ vsn end
end
|};
       close_out oc;
       let surf = Resolver_api_surface.extract_from_directory tmpdir in
       Alcotest.(check bool) "fns non-empty" true (surf.Resolver_api_surface.fns <> []);
       let fn_names = List.map (fun f -> f.Resolver_api_surface.name) surf.Resolver_api_surface.fns in
       Alcotest.(check bool) "publish_url present" true (List.mem "publish_url" fn_names);
       Alcotest.(check bool) "retire_url present"  true (List.mem "retire_url" fn_names);
       Alcotest.(check bool) "no_trailing_slash excluded (private)"
         false (List.mem "no_trailing_slash" fn_names))

(* The walk must not treat a package's own tests or its build tree as public
   API. Both live physically under the project root (forge resolves tests as
   <root>/test, and .march/ is the build directory), so without pruning,
   renaming a test helper reads as a breaking change and blocks a patch
   release, and a vendored dep cached under .march/ would be folded into this
   package's surface. *)
let test_extract_from_directory_prunes_tests_and_build_dir () =
  let tmpdir = Filename.temp_dir "test_api_surface_prune_" "" in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       let write dir base contents =
         let d = Filename.concat tmpdir dir in
         let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote d)) in
         let oc = open_out (Filename.concat d base) in
         output_string oc contents; close_out oc
       in
       write "src" "lib.march"
         "mod Lib do\n  fn real_api(x) do x end\nend\n";
       write "test" "test_lib.march"
         "mod TestLib do\n  fn make_fixture(n) do n end\nend\n";
       write ".march/build" "cached.march"
         "mod Cached do\n  fn vendored_helper(y) do y end\nend\n";
       let surf = Resolver_api_surface.extract_from_directory tmpdir in
       let fn_names = List.map (fun f -> f.Resolver_api_surface.name) surf.Resolver_api_surface.fns in
       Alcotest.(check bool) "src/ fn is part of the surface" true
         (List.mem "real_api" fn_names);
       Alcotest.(check bool) "top-level test/ fn is NOT public API" false
         (List.mem "make_fixture" fn_names);
       Alcotest.(check bool) "dot-dir (.march/) fn is NOT public API" false
         (List.mem "vendored_helper" fn_names))

(* A file that fails to parse must be reported, not silently skipped: its
   public items vanish from the surface, and an absent item is
   indistinguishable from a deleted one, so a removal in that file would
   classify as Patch and publish unchallenged. *)
let test_extract_from_directory_reports_parse_failures () =
  let tmpdir = Filename.temp_dir "test_api_surface_bad_" "" in
  Fun.protect ~finally:(fun () ->
      let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)) in ())
    (fun () ->
       let write base contents =
         let oc = open_out (Filename.concat tmpdir base) in
         output_string oc contents; close_out oc
       in
       write "good.march" "mod Good do\n  fn kept(x) do x end\nend\n";
       write "bad.march"  "mod Bad do\n  fn oops( <<<not march>>>\n";
       let surf, failed = Resolver_api_surface.extract_from_directory_checked tmpdir in
       let fn_names = List.map (fun f -> f.Resolver_api_surface.name) surf.Resolver_api_surface.fns in
       Alcotest.(check bool) "parseable file still contributes" true
         (List.mem "kept" fn_names);
       Alcotest.(check int) "one file reported as unparseable" 1 (List.length failed);
       Alcotest.(check bool) "the reported path is bad.march" true
         (match failed with
          | [(p, _)] -> Filename.basename p = "bad.march"
          | _ -> false))

(* ------------------------------------------------------------------ *)
(*  diff                                                               *)
(* ------------------------------------------------------------------ *)

let make_fn name params ret =
  Resolver_api_surface.{ name; params_raw = params; return_raw = ret }

let make_ty name body =
  Resolver_api_surface.{ type_name = name; body_raw = body }

let make_surface fns types =
  Resolver_api_surface.{ fns; types }

let test_diff_no_change () =
  let surf = make_surface
    [make_fn "foo" "x: Int" "Bool"]
    [make_ty "Color" "Red | Blue"] in
  let changes = Resolver_api_surface.diff ~old_:surf ~new_:surf in
  Alcotest.(check int) "no changes" 0 (List.length changes)

let test_diff_added_fn () =
  let old_ = make_surface [make_fn "foo" "" ""] [] in
  let new_ = make_surface [make_fn "foo" "" ""; make_fn "bar" "" ""] [] in
  let changes = Resolver_api_surface.diff ~old_ ~new_ in
  Alcotest.(check int) "1 change" 1 (List.length changes);
  match List.hd changes with
  | Resolver_api_surface.AddedFn f ->
    Alcotest.(check string) "added bar" "bar" f.Resolver_api_surface.name
  | _ -> Alcotest.fail "expected AddedFn"

let test_diff_removed_fn () =
  let old_ = make_surface [make_fn "foo" "" ""; make_fn "bar" "" ""] [] in
  let new_ = make_surface [make_fn "foo" "" ""] [] in
  let changes = Resolver_api_surface.diff ~old_ ~new_ in
  Alcotest.(check int) "1 change" 1 (List.length changes);
  match List.hd changes with
  | Resolver_api_surface.RemovedFn f ->
    Alcotest.(check string) "removed bar" "bar" f.Resolver_api_surface.name
  | _ -> Alcotest.fail "expected RemovedFn"

let test_diff_changed_fn () =
  let old_ = make_surface [make_fn "foo" "x: Int" "Bool"] [] in
  let new_ = make_surface [make_fn "foo" "x: Int, y: Int" "Bool"] [] in
  let changes = Resolver_api_surface.diff ~old_ ~new_ in
  Alcotest.(check int) "1 change" 1 (List.length changes);
  match List.hd changes with
  | Resolver_api_surface.ChangedFn (old_f, new_f) ->
    Alcotest.(check string) "old params" "x: Int"        old_f.Resolver_api_surface.params_raw;
    Alcotest.(check string) "new params" "x: Int, y: Int" new_f.Resolver_api_surface.params_raw
  | _ -> Alcotest.fail "expected ChangedFn"

let test_diff_added_type () =
  let old_ = make_surface [] [] in
  let new_ = make_surface [] [make_ty "Color" "Red | Blue"] in
  let changes = Resolver_api_surface.diff ~old_ ~new_ in
  Alcotest.(check int) "1 change" 1 (List.length changes);
  match List.hd changes with
  | Resolver_api_surface.AddedType t ->
    Alcotest.(check string) "added Color" "Color" t.Resolver_api_surface.type_name
  | _ -> Alcotest.fail "expected AddedType"

let test_diff_changed_type () =
  let old_ = make_surface [] [make_ty "Color" "Red | Blue"] in
  let new_ = make_surface [] [make_ty "Color" "Red | Blue | Green"] in
  let changes = Resolver_api_surface.diff ~old_ ~new_ in
  Alcotest.(check int) "1 change" 1 (List.length changes);
  match List.hd changes with
  | Resolver_api_surface.ChangedType (_, new_t) ->
    Alcotest.(check string) "new body" "Red | Blue | Green" new_t.Resolver_api_surface.body_raw
  | _ -> Alcotest.fail "expected ChangedType"

(* ------------------------------------------------------------------ *)
(*  required_bump                                                      *)
(* ------------------------------------------------------------------ *)

let test_bump_major () =
  let changes = [Resolver_api_surface.RemovedFn (make_fn "foo" "" "")] in
  let bump = Resolver_api_surface.required_bump changes in
  Alcotest.(check bool) "major"
    true (bump = Resolver_api_surface.Major)

let test_bump_minor () =
  let changes = [Resolver_api_surface.AddedFn (make_fn "foo" "" "")] in
  let bump = Resolver_api_surface.required_bump changes in
  Alcotest.(check bool) "minor"
    true (bump = Resolver_api_surface.Minor)

let test_bump_patch () =
  let bump = Resolver_api_surface.required_bump [] in
  Alcotest.(check bool) "patch"
    true (bump = Resolver_api_surface.Patch)

(* ------------------------------------------------------------------ *)
(*  check_semver_bump                                                  *)
(* ------------------------------------------------------------------ *)

let test_semver_ok_no_changes () =
  let r = Resolver_api_surface.check_semver_bump
      ~old_version:"1.0.0" ~new_version:"1.0.1" ~changes:[] in
  Alcotest.(check bool) "Ok" true (r = Resolver_api_surface.Ok)

let test_semver_ok_major_bump_for_removal () =
  let changes = [Resolver_api_surface.RemovedFn (make_fn "foo" "" "")] in
  let r = Resolver_api_surface.check_semver_bump
      ~old_version:"1.0.0" ~new_version:"2.0.0" ~changes in
  Alcotest.(check bool) "Ok" true (r = Resolver_api_surface.Ok)

let test_semver_underbumped_patch_for_removal () =
  let changes = [Resolver_api_surface.RemovedFn (make_fn "foo" "" "")] in
  let r = Resolver_api_surface.check_semver_bump
      ~old_version:"1.0.0" ~new_version:"1.0.1" ~changes in
  match r with
  | Resolver_api_surface.UnderBumped { required; declared; _ } ->
    Alcotest.(check bool) "required Major"
      true (required = Resolver_api_surface.Major);
    Alcotest.(check bool) "declared Patch"
      true (declared = Resolver_api_surface.Patch)
  | Resolver_api_surface.Ok -> Alcotest.fail "expected UnderBumped"

let test_semver_underbumped_minor_for_addition () =
  let changes = [Resolver_api_surface.AddedFn (make_fn "foo" "" "")] in
  let r = Resolver_api_surface.check_semver_bump
      ~old_version:"1.0.0" ~new_version:"1.0.1" ~changes in
  match r with
  | Resolver_api_surface.UnderBumped { required; declared; _ } ->
    Alcotest.(check bool) "required Minor"
      true (required = Resolver_api_surface.Minor);
    Alcotest.(check bool) "declared Patch"
      true (declared = Resolver_api_surface.Patch)
  | Resolver_api_surface.Ok -> Alcotest.fail "expected UnderBumped"

let test_semver_skip_pre_100 () =
  (* Pre-1.0.0 packages skip enforcement entirely *)
  let changes = [Resolver_api_surface.RemovedFn (make_fn "foo" "" "")] in
  let r = Resolver_api_surface.check_semver_bump
      ~old_version:"0.5.0" ~new_version:"0.5.1" ~changes in
  Alcotest.(check bool) "Ok for pre-1.0.0" true (r = Resolver_api_surface.Ok)

(* ------------------------------------------------------------------ *)
(*  Suite                                                              *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "forge-api-surface" [
    "extract-surface", [
      Alcotest.test_case "public fns/types extracted, private excluded" `Quick
        test_extract_public_and_private;
      Alcotest.test_case "fn signature rendered from the AST"           `Quick
        test_extract_fn_signature_shape;
      Alcotest.test_case "fn with no return annotation"                 `Quick
        test_extract_fn_no_return_annotation;
      Alcotest.test_case "empty module gives empty surface"             `Quick
        test_extract_empty_module;
      Alcotest.test_case "unparseable source gives empty surface, no exn" `Quick
        test_extract_unparseable_source_is_empty_not_exn;
      Alcotest.test_case "multi-head clauses all visible"               `Quick
        test_extract_multi_head_clauses;
      Alcotest.test_case "default argument visible"                     `Quick
        test_extract_default_argument;
      Alcotest.test_case "signature wrapped across lines"               `Quick
        test_extract_wrapped_signature;
      Alcotest.test_case "nested mod walked"                            `Quick
        test_extract_nested_mod;
    ];
    "extract-surface-regression-nonempty", [
      Alcotest.test_case "extract_from_string over forge's own source is non-empty" `Quick
        test_extract_from_directory_forge_own_source_nonempty;
      Alcotest.test_case "extract_from_directory over a real file is non-empty" `Quick
        test_extract_from_directory_nonempty;
      Alcotest.test_case "test/ and dot-dirs are not part of the public surface" `Quick
        test_extract_from_directory_prunes_tests_and_build_dir;
      Alcotest.test_case "unparseable files are reported, not silently skipped" `Quick
        test_extract_from_directory_reports_parse_failures;
    ];
    "diff", [
      Alcotest.test_case "no change → empty diff"            `Quick test_diff_no_change;
      Alcotest.test_case "added fn detected"                 `Quick test_diff_added_fn;
      Alcotest.test_case "removed fn detected"                `Quick test_diff_removed_fn;
      Alcotest.test_case "changed fn signature detected"     `Quick test_diff_changed_fn;
      Alcotest.test_case "added type detected"                `Quick test_diff_added_type;
      Alcotest.test_case "changed type body detected"        `Quick test_diff_changed_type;
    ];
    "bump-classification", [
      Alcotest.test_case "removal requires Major"            `Quick test_bump_major;
      Alcotest.test_case "addition requires Minor"           `Quick test_bump_minor;
      Alcotest.test_case "no change requires Patch"          `Quick test_bump_patch;
    ];
    "semver-check", [
      Alcotest.test_case "Ok when no changes and patch bump" `Quick test_semver_ok_no_changes;
      Alcotest.test_case "Ok when major bump for removal"    `Quick test_semver_ok_major_bump_for_removal;
      Alcotest.test_case "UnderBumped: patch for removal"    `Quick test_semver_underbumped_patch_for_removal;
      Alcotest.test_case "UnderBumped: patch for addition"   `Quick test_semver_underbumped_minor_for_addition;
      Alcotest.test_case "pre-1.0.0 skips enforcement"       `Quick test_semver_skip_pre_100;
    ];
  ]
