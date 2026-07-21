(* Tests for the project-wide refactoring engine. Each test builds a temporary
   multi-file project, runs a transform, and asserts the resulting file contents.
   The engine is parser-based, so these also confirm strings/comments are left
   alone and that edits land on the right spans. *)

module R = March_refactor.Refactor

let counter = ref 0

(* A fresh temp project dir with the given (filename, contents) files. *)
let mk_project files =
  incr counter;
  let root = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_refac_%d_%d" (Unix.getpid ()) !counter) in
  (try Unix.mkdir root 0o755 with _ -> ());
  List.iter (fun (name, content) ->
      let oc = open_out (Filename.concat root name) in
      output_string oc content; close_out oc) files;
  root

let read root name =
  let ic = open_in (Filename.concat root name) in
  let n = in_channel_length ic in
  let b = Bytes.create n in really_input ic b 0 n; close_in ic; Bytes.to_string b

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec f i = if i + nl > hl then false
                else if String.sub hay i nl = needle then true else f (i + 1) in
  nl = 0 || f 0

(* ── rename ───────────────────────────────────────────────────────────────── *)

let test_rename_cross_file () =
  let root = mk_project [
    "a.march", "mod A do\n  fn oldName(x) do x + 1 end\n  fn caller() do oldName(41) end\nend\n";
    "b.march", "mod B do\n  fn use_it() do A.oldName(5) end\nend\n";
  ] in
  let o = R.rename_symbol ~root ~old_name:"oldName" ~new_name:"newName" ~kind:"any" ~dry_run:false in
  Alcotest.(check int) "two files changed" 2 (List.length o.R.changes);
  let a = read root "a.march" and b = read root "b.march" in
  Alcotest.(check bool) "def renamed"        true (contains a "fn newName(x)");
  Alcotest.(check bool) "call renamed"       true (contains a "newName(41)");
  Alcotest.(check bool) "qualified renamed"  true (contains b "A.newName(5)");
  Alcotest.(check bool) "no oldName left"    false (contains (a ^ b) "oldName")

let test_rename_skips_strings () =
  let root = mk_project [
    "a.march", "mod A do\n  fn foo() do \"foo is a string\" end\nend\n";
  ] in
  let _ = R.rename_symbol ~root ~old_name:"foo" ~new_name:"bar" ~kind:"any" ~dry_run:false in
  let a = read root "a.march" in
  Alcotest.(check bool) "fn renamed"          true (contains a "fn bar()");
  Alcotest.(check bool) "string left intact"  true (contains a "\"foo is a string\"")

let test_rename_regex () =
  let root = mk_project [
    "a.march", "mod A do\n  fn get_x() do 1 end\n  fn get_y() do 2 end\n  fn other() do 3 end\nend\n";
  ] in
  let o = R.rename_pattern ~root ~regex:"get_\\(.*\\)" ~replacement:"fetch_\\1" ~kind:"fn" ~dry_run:false in
  Alcotest.(check int) "one file changed" 1 (List.length o.R.changes);
  let a = read root "a.march" in
  Alcotest.(check bool) "get_x -> fetch_x" true (contains a "fn fetch_x()");
  Alcotest.(check bool) "get_y -> fetch_y" true (contains a "fn fetch_y()");
  Alcotest.(check bool) "other untouched"  true (contains a "fn other()")

let test_rename_dry_run_writes_nothing () =
  let root = mk_project [ "a.march", "mod A do\n  fn foo() do 1 end\nend\n" ] in
  let before = read root "a.march" in
  let o = R.rename_symbol ~root ~old_name:"foo" ~new_name:"bar" ~kind:"any" ~dry_run:true in
  Alcotest.(check int) "reports a change" 1 (List.length o.R.changes);
  Alcotest.(check string) "file unchanged on disk" before (read root "a.march")

(* ── fix ──────────────────────────────────────────────────────────────────── *)

let test_fix_naming () =
  let root = mk_project [
    "a.march", "mod A do\n  fn myFunc(x) do x end\n  fn run() do myFunc(1) end\nend\n";
  ] in
  let _ = R.fix_project ~root ~dry_run:false in
  let a = read root "a.march" in
  Alcotest.(check bool) "def snake-cased"  true (contains a "fn my_func(x)");
  Alcotest.(check bool) "call snake-cased" true (contains a "my_func(1)")

(* ── move ─────────────────────────────────────────────────────────────────── *)

let test_move_to_new_file () =
  let root = mk_project [
    "src.march", "mod Src do\n  fn helper(x) do x * 2 end\n  fn main() do helper(21) end\nend\n";
  ] in
  let dest = Filename.concat root "util.march" in
  (match R.move_decl ~root ~decl_name:"helper" ~dest ~dry_run:false with
   | Ok _ -> () | Error e -> Alcotest.failf "move failed: %s" e);
  let src = read root "src.march" and util = read root "util.march" in
  Alcotest.(check bool) "helper removed from src"   false (contains src "fn helper");
  Alcotest.(check bool) "main stays in src"         true  (contains src "fn main");
  Alcotest.(check bool) "helper now in util"        true  (contains util "fn helper(x)");
  Alcotest.(check bool) "util has a module wrapper" true  (contains util "mod Util do")

(* ── replace ──────────────────────────────────────────────────────────────── *)

let test_replace_codemod () =
  let root = mk_project [
    "a.march", "mod A do\n  fn run() do swap(1, 2) end\nend\n";
  ] in
  (match R.replace_project ~root ~pat:"swap($a, $b)" ~tmpl:"swap($b, $a)" ~dry_run:false with
   | Ok o -> Alcotest.(check int) "one file changed" 1 (List.length o.R.changes)
   | Error e -> Alcotest.failf "replace failed: %s" e);
  let a = read root "a.march" in
  Alcotest.(check bool) "args swapped" true (contains a "swap(2, 1)")

let test_bundle_param_object () =
  let root = mk_project [
    "a.march", "mod A do\n  fn connect(host: String, port: Int, timeout: Int) do\n    open(host, port, timeout)\n  end\nend\n";
    "b.march", "mod B do\n  fn go() do A.connect(\"localhost\", 8080, 30) end\nend\n";
  ] in
  (match R.bundle_fn ~root ~fn_name:"connect" ~dry_run:false () with
   | Ok o ->
     Alcotest.(check int) "two files changed" 2 (List.length o.R.changes);
     Alcotest.(check int) "nothing skipped"   0 (List.length o.R.skipped)
   | Error e -> Alcotest.failf "bundle failed: %s" e);
  let a = read root "a.march" and b = read root "b.march" in
  Alcotest.(check bool) "record type generated"   true
    (contains a "type ConnectArgs = { host : String");
  Alcotest.(check bool) "signature takes record"  true (contains a "fn connect(args: ConnectArgs)");
  Alcotest.(check bool) "body uses args.host"      true (contains a "args.host");
  Alcotest.(check bool) "body uses args.port"      true (contains a "args.port");
  Alcotest.(check bool) "call site rewritten (string arg intact)" true
    (contains b "{ host: \"localhost\", port: 8080, timeout: 30 }")

let test_bundle_requires_annotations () =
  let root = mk_project [
    "a.march", "mod A do\n  fn f(x, y) do x + y end\nend\n";
  ] in
  (match R.bundle_fn ~root ~fn_name:"f" ~dry_run:false () with
   | Ok _ -> Alcotest.fail "should have errored on unannotated params"
   | Error _ -> ())

(* A documented target fn must still bundle: the generated record type has to be
   inserted ABOVE the `doc` comment, not between the `doc` and its `fn` (which
   would not parse, making the engine silently skip the file). *)
let index_of s sub =
  let hl = String.length s and nl = String.length sub in
  let rec f i = if i + nl > hl then -1
                else if String.sub s i nl = sub then i else f (i + 1) in
  f 0

let test_bundle_documented_fn () =
  let root = mk_project [
    "a.march",
    "mod A do\n\n  doc \"Open a connection.\"\n  fn connect(host: String, port: Int) do\n    open(host, port)\n  end\n\n  fn go() do connect(\"localhost\", 8080) end\nend\n";
  ] in
  (match R.bundle_fn ~root ~fn_name:"connect" ~dry_run:false () with
   | Ok o ->
     Alcotest.(check int) "one file changed" 1 (List.length o.R.changes);
     Alcotest.(check int) "nothing skipped"  0 (List.length o.R.skipped)
   | Error e -> Alcotest.failf "bundle failed: %s" e);
  let a = read root "a.march" in
  Alcotest.(check bool) "record type generated" true
    (contains a "type ConnectArgs = { host : String");
  Alcotest.(check bool) "doc comment preserved" true
    (contains a "doc \"Open a connection.\"");
  Alcotest.(check bool) "signature takes record" true
    (contains a "fn connect(args: ConnectArgs)");
  Alcotest.(check bool) "type declared above the doc" true
    (index_of a "type ConnectArgs" < index_of a "doc \"Open a connection.\"");
  Alcotest.(check bool) "doc still sits above the fn" true
    (index_of a "doc \"Open a connection.\"" < index_of a "fn connect(args")

let () =
  Alcotest.run "refactor" [
    "rename", [
      Alcotest.test_case "cross-file rename"      `Quick test_rename_cross_file;
      Alcotest.test_case "skips strings/comments" `Quick test_rename_skips_strings;
      Alcotest.test_case "regex bulk rename"      `Quick test_rename_regex;
      Alcotest.test_case "dry-run writes nothing" `Quick test_rename_dry_run_writes_nothing;
    ];
    "fix", [
      Alcotest.test_case "snake_case naming fix"  `Quick test_fix_naming;
    ];
    "move", [
      Alcotest.test_case "move to new file"       `Quick test_move_to_new_file;
    ];
    "replace", [
      Alcotest.test_case "call-shape codemod"     `Quick test_replace_codemod;
    ];
    "bundle", [
      Alcotest.test_case "introduce parameter object" `Quick test_bundle_param_object;
      Alcotest.test_case "requires annotated params"  `Quick test_bundle_requires_annotations;
      Alcotest.test_case "documented target fn"       `Quick test_bundle_documented_fn;
    ];
  ]
