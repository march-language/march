(** Tests for API surface extraction and semver change classification. *)

open March_forge

(* ------------------------------------------------------------------ *)
(*  parse_fn_sig                                                       *)
(* ------------------------------------------------------------------ *)

let test_parse_fn_basic () =
  match Resolver_api_surface.parse_fn_sig "pub fn foo(x: Int) -> Bool" with
  | None -> Alcotest.fail "expected Some"
  | Some s ->
    Alcotest.(check string) "name"        "foo"    s.Resolver_api_surface.name;
    Alcotest.(check string) "params_raw"  "x: Int" s.Resolver_api_surface.params_raw;
    Alcotest.(check string) "return_raw"  "Bool"   s.Resolver_api_surface.return_raw

let test_parse_fn_no_params () =
  match Resolver_api_surface.parse_fn_sig "pub fn bar()" with
  | None -> Alcotest.fail "expected Some"
  | Some s ->
    Alcotest.(check string) "name"       "bar" s.Resolver_api_surface.name;
    Alcotest.(check string) "params_raw" ""    s.Resolver_api_surface.params_raw;
    Alcotest.(check string) "return_raw" ""    s.Resolver_api_surface.return_raw

let test_parse_fn_no_return () =
  match Resolver_api_surface.parse_fn_sig "pub fn baz(x: Int, y: String)" with
  | None -> Alcotest.fail "expected Some"
  | Some s ->
    Alcotest.(check string) "name"       "baz"            s.Resolver_api_surface.name;
    Alcotest.(check string) "params_raw" "x: Int, y: String" s.Resolver_api_surface.params_raw;
    Alcotest.(check string) "return_raw" ""               s.Resolver_api_surface.return_raw

let test_parse_fn_with_do () =
  (* "do" suffix should be stripped from return type *)
  match Resolver_api_surface.parse_fn_sig "pub fn run() -> Unit do" with
  | None -> Alcotest.fail "expected Some"
  | Some s ->
    Alcotest.(check string) "return_raw" "Unit" s.Resolver_api_surface.return_raw

let test_parse_fn_not_pub () =
  let r = Resolver_api_surface.parse_fn_sig "fn private(x: Int) -> Bool" in
  Alcotest.(check bool) "None for non-pub" true (r = None)

let test_parse_fn_leading_whitespace () =
  match Resolver_api_surface.parse_fn_sig "  pub fn indented(a: A) -> B" with
  | None -> Alcotest.fail "expected Some"
  | Some s ->
    Alcotest.(check string) "name" "indented" s.Resolver_api_surface.name

(* ------------------------------------------------------------------ *)
(*  parse_type_decl                                                    *)
(* ------------------------------------------------------------------ *)

let test_parse_type_basic () =
  match Resolver_api_surface.parse_type_decl "pub type Color = Red | Blue | Green" with
  | None -> Alcotest.fail "expected Some"
  | Some t ->
    Alcotest.(check string) "type_name" "Color"              t.Resolver_api_surface.type_name;
    Alcotest.(check string) "body_raw"  "Red | Blue | Green" t.Resolver_api_surface.body_raw

let test_parse_type_no_body () =
  match Resolver_api_surface.parse_type_decl "pub type Opaque" with
  | None -> Alcotest.fail "expected Some"
  | Some t ->
    Alcotest.(check string) "type_name" "Opaque" t.Resolver_api_surface.type_name;
    Alcotest.(check string) "body_raw"  ""       t.Resolver_api_surface.body_raw

let test_parse_type_not_pub () =
  let r = Resolver_api_surface.parse_type_decl "type Private = A | B" in
  Alcotest.(check bool) "None for non-pub" true (r = None)

(* ------------------------------------------------------------------ *)
(*  extract_from_string                                                *)
(* ------------------------------------------------------------------ *)

let test_extract_from_string () =
  let src = {|
pub fn add(x: Int, y: Int) -> Int
pub fn sub(x: Int, y: Int) -> Int
pub type Result = Ok(Int) | Err(String)
fn private_helper(x: Int) -> Int
type InternalState = { count: Int }
|} in
  let surf = Resolver_api_surface.extract_from_string src in
  Alcotest.(check int) "2 public fns"    2 (List.length surf.Resolver_api_surface.fns);
  Alcotest.(check int) "1 public type"   1 (List.length surf.Resolver_api_surface.types);
  let fn_names = List.map (fun f -> f.Resolver_api_surface.name) surf.Resolver_api_surface.fns in
  Alcotest.(check bool) "add present" true (List.mem "add" fn_names);
  Alcotest.(check bool) "sub present" true (List.mem "sub" fn_names)

let test_extract_empty_source () =
  let surf = Resolver_api_surface.extract_from_string "" in
  Alcotest.(check int) "no fns"   0 (List.length surf.Resolver_api_surface.fns);
  Alcotest.(check int) "no types" 0 (List.length surf.Resolver_api_surface.types)

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
    "parse-fn-sig", [
      Alcotest.test_case "basic fn with params and return"   `Quick test_parse_fn_basic;
      Alcotest.test_case "fn with no params"                 `Quick test_parse_fn_no_params;
      Alcotest.test_case "fn with no return type"            `Quick test_parse_fn_no_return;
      Alcotest.test_case "fn with do suffix stripped"        `Quick test_parse_fn_with_do;
      Alcotest.test_case "non-pub fn returns None"           `Quick test_parse_fn_not_pub;
      Alcotest.test_case "leading whitespace handled"        `Quick test_parse_fn_leading_whitespace;
    ];
    "parse-type-decl", [
      Alcotest.test_case "basic type with body"              `Quick test_parse_type_basic;
      Alcotest.test_case "type with no body"                 `Quick test_parse_type_no_body;
      Alcotest.test_case "non-pub type returns None"         `Quick test_parse_type_not_pub;
    ];
    "extract-surface", [
      Alcotest.test_case "extracts public fns and types"     `Quick test_extract_from_string;
      Alcotest.test_case "empty source gives empty surface"  `Quick test_extract_empty_source;
    ];
    "diff", [
      Alcotest.test_case "no change → empty diff"            `Quick test_diff_no_change;
      Alcotest.test_case "added fn detected"                 `Quick test_diff_added_fn;
      Alcotest.test_case "removed fn detected"               `Quick test_diff_removed_fn;
      Alcotest.test_case "changed fn signature detected"     `Quick test_diff_changed_fn;
      Alcotest.test_case "added type detected"               `Quick test_diff_added_type;
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
