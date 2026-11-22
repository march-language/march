(* ocap phase 6, Task 1 (dependency grants): the grants file and package
   membership ([March_caps.Dep_grants]).

   The grants file is one package per line, four tab-separated fields
   (`<package>\t<lib root>\t<manifest>:<line>\t<scope text>`), `#` comments.
   A module belongs to the package whose library root is the longest prefix
   of its file's real path.  With no flag and no MARCH_DEP_GRANTS nothing is
   loaded, [active ()] is [] and [digest ()] is [None]: every later pass is
   the identity. *)

module G = March_caps.Dep_grants

let env_var = "MARCH_DEP_GRANTS"

(* Unix has no unsetenv; [load] treats an empty value as unset. *)
let clear_env () = Unix.putenv env_var ""

let realpath p = Unix.realpath p

let tmpdir () = realpath (Filename.temp_dir "march_dep_grants" "")

let mkdir_p p = if not (Sys.file_exists p) then Sys.mkdir p 0o755

let write path s =
  let oc = open_out_bin path in
  output_string oc s;
  close_out oc

let grants_file dir lines =
  let p = Filename.concat dir "dep-grants" in
  write p (String.concat "\n" lines ^ "\n");
  p

let ok = function
  | Ok v -> v
  | Error (msg, line) ->
    Alcotest.failf "expected Ok, got Error %S at %s" msg
      (match line with Some n -> string_of_int n | None -> "-")

let expect_error_at ~line r =
  match r with
  | Ok _ -> Alcotest.failf "expected an error at line %d, got Ok" line
  | Error (_, l) -> Alcotest.(check (option int)) "error line" (Some line) l

let with_reset f =
  clear_env ();
  G.set_active [];
  Fun.protect ~finally:(fun () -> clear_env (); G.set_active []) f

let test_load_none () =
  with_reset (fun () ->
      let gs = ok (G.load ()) in
      Alcotest.(check int) "no grants" 0 (List.length gs);
      G.set_active gs;
      Alcotest.(check (option string)) "no digest" None (G.digest ());
      Alcotest.(check int) "nothing active" 0 (List.length (G.active ()));
      Alcotest.(check bool) "no membership" true (G.package_of_file "/etc/hosts" = None))

let test_load_two () =
  with_reset (fun () ->
      let d = tmpdir () in
      let ra = Filename.concat d "a" and rb = Filename.concat d "b" in
      mkdir_p ra; mkdir_p rb;
      let f =
        grants_file d
          [ "# written by forge";
            "";
            "http_kit\t" ^ ra ^ "/\tforge.toml:12\tIO.NetConnect(\"a.test/v1/\", methods(get))";
            "logger\t" ^ rb ^ "\t/proj/forge.toml:14\tIO.Console, IO.Clock" ]
      in
      let gs = ok (G.load ~flag:f ()) in
      match gs with
      | [ a; b ] ->
        Alcotest.(check string) "pkg a" "http_kit" a.G.g_pkg;
        Alcotest.(check string) "root a (no trailing slash)" ra a.G.g_root;
        Alcotest.(check string) "manifest a" "forge.toml" a.G.g_manifest;
        Alcotest.(check int) "line a" 12 a.G.g_line;
        Alcotest.(check string) "text a" "IO.NetConnect(\"a.test/v1/\", methods(get))" a.G.g_text;
        Alcotest.(check bool) "scoped a" true a.G.g_scoped;
        Alcotest.(check int) "entries a" 1 (List.length a.G.g_entries);
        Alcotest.(check string) "pkg b" "logger" b.G.g_pkg;
        Alcotest.(check string) "root b" rb b.G.g_root;
        Alcotest.(check string) "manifest b" "/proj/forge.toml" b.G.g_manifest;
        Alcotest.(check int) "line b" 14 b.G.g_line;
        Alcotest.(check string) "text b" "IO.Console, IO.Clock" b.G.g_text;
        Alcotest.(check bool) "scoped b" false b.G.g_scoped;
        Alcotest.(check (list string)) "entries b" [ "IO.Console"; "IO.Clock" ]
          (List.map (fun (p, _) -> String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) p))
             b.G.g_entries);
        G.set_active gs;
        Alcotest.(check bool) "digest when active" true (G.digest () <> None)
      | _ -> Alcotest.failf "expected two grants, got %d" (List.length gs))

let test_load_unit () =
  with_reset (fun () ->
      let d = tmpdir () in
      let f = grants_file d [ "nothing\t" ^ d ^ "\tforge.toml:3\t()" ] in
      match ok (G.load ~flag:f ()) with
      | [ g ] ->
        Alcotest.(check int) "no entries" 0 (List.length g.G.g_entries);
        Alcotest.(check string) "text" "()" g.G.g_text;
        Alcotest.(check bool) "unscoped" false g.G.g_scoped
      | gs -> Alcotest.failf "expected one grant, got %d" (List.length gs))

let test_load_rejects () =
  with_reset (fun () ->
      let d = tmpdir () in
      let good = "ok\t" ^ d ^ "\tforge.toml:1\tIO.Console" in
      let case name bad =
        let f = grants_file d [ "# header"; good; bad ] in
        (try expect_error_at ~line:3 (G.load ~flag:f ())
         with e -> Alcotest.failf "%s: %s" name (Printexc.to_string e))
      in
      case "malformed scope" ("x\t" ^ d ^ "\tforge.toml:2\tIO.NetConnect(\"a.test\"");
      case "trailing junk after the needs line"
        ("x\t" ^ d ^ "\tforge.toml:2\tIO.Console end fn f() do 1 end mod H do needs IO.Clock");
      case "relative root" "x\trel/dir\tforge.toml:2\tIO.Console";
      case "missing field" ("x\t" ^ d ^ "\tIO.Console");
      case "tab inside the scope text" ("x\t" ^ d ^ "\tforge.toml:2\tIO.Console\tIO.Clock");
      case "nonexistent root" ("x\t" ^ Filename.concat d "nope" ^ "\tforge.toml:2\tIO.Console");
      case "bad manifest line" ("x\t" ^ d ^ "\tforge.toml\tIO.Console");
      case "empty package" ("\t" ^ d ^ "\tforge.toml:2\tIO.Console");
      case "duplicate package" ("ok\t" ^ Filename.concat d "." ^ "\tforge.toml:2\tIO.Clock");
      (* A missing file is an error with no line. *)
      match G.load ~flag:(Filename.concat d "no-such-file") () with
      | Ok _ -> Alcotest.fail "a missing grants file loaded"
      | Error (_, l) -> Alcotest.(check (option int)) "no line" None l)

let test_parse_scope_text () =
  (match G.parse_scope_text "()" with
   | Ok [] -> ()
   | _ -> Alcotest.fail "() is no entries");
  (match G.parse_scope_text "IO.FileRead(\"/srv/\"), IO.Console" with
   | Ok [ (_, Some "/srv/"); (_, None) ] -> ()
   | _ -> Alcotest.fail "two entries, the first scoped");
  (match G.parse_scope_text "" with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "empty text accepted")

let test_membership_longest_prefix () =
  with_reset (fun () ->
      let d = tmpdir () in
      let a = Filename.concat d "a" in
      let sub = Filename.concat a "sub" in
      let ab = Filename.concat d "ab" in
      List.iter mkdir_p [ a; sub; ab ];
      let fa = Filename.concat a "y.march"
      and fs = Filename.concat sub "x.march"
      and fab = Filename.concat ab "x.march" in
      List.iter (fun p -> write p "") [ fa; fs; fab ];
      let f =
        grants_file d
          [ "outer\t" ^ a ^ "\tforge.toml:1\tIO.Console";
            "inner\t" ^ sub ^ "\tforge.toml:2\tIO.Clock" ]
      in
      G.set_active (ok (G.load ~flag:f ()));
      let pkg p = Option.map (fun g -> g.G.g_pkg) (G.package_of_file p) in
      Alcotest.(check (option string)) "sub file in inner" (Some "inner") (pkg fs);
      Alcotest.(check (option string)) "a file in outer" (Some "outer") (pkg fa);
      Alcotest.(check (option string)) "ab file in neither" None (pkg fab))

let test_membership_symlink () =
  with_reset (fun () ->
      let d = tmpdir () in
      let root = Filename.concat d "dep" and app = Filename.concat d "app" in
      List.iter mkdir_p [ root; app ];
      let real = Filename.concat root "m.march" in
      write real "";
      let link = Filename.concat app "m_link.march" in
      Unix.symlink real link;
      (* A root given through a symlink is stored as its real path. *)
      let root_link = Filename.concat d "dep_link" in
      Unix.symlink root root_link;
      let f = grants_file d [ "dep\t" ^ root_link ^ "\tforge.toml:1\tIO.Console" ] in
      let gs = ok (G.load ~flag:f ()) in
      Alcotest.(check (list string)) "root realpath" [ root ] (List.map (fun g -> g.G.g_root) gs);
      G.set_active gs;
      let pkg p = Option.map (fun g -> g.G.g_pkg) (G.package_of_file p) in
      Alcotest.(check (option string)) "symlinked file attributed by real path" (Some "dep") (pkg link);
      Alcotest.(check (option string)) "app file" None (pkg (Filename.concat app "other.march")))

let test_flag_overrides_env () =
  with_reset (fun () ->
      let d = tmpdir () in
      let fe = grants_file d [ "from_env\t" ^ d ^ "\tforge.toml:1\tIO.Console" ] in
      let ff = Filename.concat d "flag-grants" in
      write ff ("from_flag\t" ^ d ^ "\tforge.toml:1\tIO.Clock\n");
      Unix.putenv env_var fe;
      let pkgs r = List.map (fun g -> g.G.g_pkg) (ok r) in
      Alcotest.(check (list string)) "env alone" [ "from_env" ] (pkgs (G.load ()));
      Alcotest.(check (list string)) "flag wins" [ "from_flag" ] (pkgs (G.load ~flag:ff ())))

let test_digest_tracks_contents () =
  with_reset (fun () ->
      let d = tmpdir () in
      let f1 = grants_file d [ "p\t" ^ d ^ "\tforge.toml:1\tIO.Console" ] in
      G.set_active (ok (G.load ~flag:f1 ()));
      let d1 = G.digest () in
      let f2 = Filename.concat d "g2" in
      write f2 ("p\t" ^ d ^ "\tforge.toml:1\tIO.Clock\n");
      G.set_active (ok (G.load ~flag:f2 ()));
      Alcotest.(check bool) "different grant, different digest" true (d1 <> G.digest ());
      (* A file with no entries is no grants: no digest. *)
      let f3 = Filename.concat d "g3" in
      write f3 "# nothing granted\n";
      G.set_active (ok (G.load ~flag:f3 ()));
      Alcotest.(check (option string)) "comment-only file" None (G.digest ()))

(* ── Task 2: the same module name in two packages (Q2) ───────────────────

   Under a grants file a module name must belong to one side: each granted
   package is a side, code under no granted root (the app and ungranted deps)
   is one side, and the stdlib is one side.  A name defined on two sides is
   [dep_module_conflict]; without grants the resolver keeps today's
   behaviour (the first file wins, silently).  The resolver is driven in
   process, as bin/main.ml drives it. *)

module R = March_resolver.Resolver
module Code = March_errors.Code

let mkdirs p =
  let rec go p =
    if not (Sys.file_exists p) then begin
      go (Filename.dirname p);
      Sys.mkdir p 0o755
    end in
  go p

let put path src = mkdirs (Filename.dirname path); write path src

(* The resolver's errors for [entry] with MARCH_LIB_PATH = [libs] and the
   grants in [grant_lines] installed ([] = no grants). *)
let resolve ~entry ~libs ~grant_lines d =
  let gs =
    if grant_lines = [] then []
    else ok (G.load ~flag:(grants_file d grant_lines) ()) in
  G.set_active gs;
  Unix.putenv "MARCH_LIB_PATH" (String.concat ":" libs);
  Fun.protect ~finally:(fun () -> Unix.putenv "MARCH_LIB_PATH" ""; G.set_active [])
    (fun () ->
       let ic = open_in_bin entry in
       let src = really_input_string ic (in_channel_length ic) in
       close_in ic;
       match March_parser.Parse.module_ ~filename:entry ~stuck:"" src with
       | Error _ -> Alcotest.failf "the entry %s does not parse" entry
       | Ok m ->
         let m = March_desugar.Desugar.desugar_module m in
         let errs, _, _ = R.resolve_imports ~source_file:entry m in
         errs)

let conflicts errs = List.filter (fun e -> R.error_code e = Code.dep_module_conflict) errs

let msg_of (_, _, m) = m

let has_sub s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let expect_conflict what errs ~mentions =
  match conflicts errs with
  | [ e ] ->
    List.iter (fun m ->
        if not (has_sub (msg_of e) m) then
          Alcotest.failf "%s: the conflict message does not mention %S: %s" what m (msg_of e))
      mentions
  | cs ->
    Alcotest.failf "%s: expected one dep_module_conflict, got %d (all errors: %s)" what
      (List.length cs) (String.concat " | " (List.map msg_of errs))

let expect_clean what errs =
  if errs <> [] then
    Alcotest.failf "%s: expected no resolver errors, got: %s" what
      (String.concat " | " (List.map msg_of errs))

let entry_calling d name =
  let e = Filename.concat d "app/main.march" in
  put e (Printf.sprintf "mod Main do\n  fn main() do\n    %s.hello()\n  end\nend\n" name);
  e

let test_conflict_app_vs_dep () =
  with_reset (fun () ->
      let d = tmpdir () in
      let entry = entry_calling d "Weather" in
      let app_lib = Filename.concat d "applib" and dep = Filename.concat d "deps/weather" in
      put (Filename.concat app_lib "weather.march") "mod Weather do\n  fn hello() do 1 end\nend\n";
      put (Filename.concat dep "weather.march") "mod Weather do\n  fn hello() do 2 end\nend\n";
      let libs = [ app_lib; dep ] in
      expect_clean "no grants" (resolve ~entry ~libs ~grant_lines:[] d);
      expect_conflict "app vs dep"
        (resolve ~entry ~libs ~grant_lines:[ "weather\t" ^ dep ^ "\tforge.toml:4\tIO.Console" ] d)
        ~mentions:[ "`Weather`"; Filename.concat app_lib "weather.march";
                    Filename.concat dep "weather.march"; "package `weather`" ])

let test_conflict_dep_vs_dep () =
  with_reset (fun () ->
      let d = tmpdir () in
      let entry = entry_calling d "Util" in
      let a = Filename.concat d "deps/a" and b = Filename.concat d "deps/b" in
      put (Filename.concat a "util.march") "mod Util do\n  fn hello() do 1 end\nend\n";
      put (Filename.concat b "util.march") "mod Util do\n  fn hello() do 2 end\nend\n";
      let libs = [ a; b ] in
      expect_clean "no grants" (resolve ~entry ~libs ~grant_lines:[] d);
      expect_conflict "two granted deps"
        (resolve ~entry ~libs d
           ~grant_lines:[ "a\t" ^ a ^ "\tforge.toml:4\tIO.Console";
                          "b\t" ^ b ^ "\tforge.toml:5\t()" ])
        ~mentions:[ "package `a`"; "package `b`" ];
      (* One granted, one not: the ungranted dep is on the app's side. *)
      expect_conflict "a granted and an ungranted dep"
        (resolve ~entry ~libs d ~grant_lines:[ "b\t" ^ b ^ "\tforge.toml:5\t()" ])
        ~mentions:[ "package `b`"; Filename.concat a "util.march" ])

let test_conflict_dep_vs_stdlib () =
  with_reset (fun () ->
      let d = tmpdir () in
      let entry = entry_calling d "List" in
      let dep = Filename.concat d "deps/weather" in
      put (Filename.concat dep "list.march") "mod List do\n  fn hello() do 1 end\nend\n";
      let libs = [ dep ] in
      expect_clean "no grants" (resolve ~entry ~libs ~grant_lines:[] d);
      expect_conflict "dep shadows the stdlib"
        (resolve ~entry ~libs ~grant_lines:[ "weather\t" ^ dep ^ "\tforge.toml:4\t()" ] d)
        ~mentions:[ "`List`"; Filename.concat dep "list.march"; "stdlib/list.march";
                    "the standard library" ])

let test_same_package_twice_is_not_a_conflict () =
  with_reset (fun () ->
      let d = tmpdir () in
      let entry = entry_calling d "Util" in
      let dep = Filename.concat d "deps/a" in
      put (Filename.concat dep "util.march") "mod Util do\n  fn hello() do 1 end\nend\n";
      put (Filename.concat dep "sub/util2.march") "mod Util do\n  fn hello() do 2 end\nend\n";
      expect_clean "one package, two files"
        (resolve ~entry ~libs:[ dep ] ~grant_lines:[ "a\t" ^ dep ^ "\tforge.toml:4\t()" ] d))

let test_conflict_nested_root () =
  with_reset (fun () ->
      let d = tmpdir () in
      let entry = entry_calling d "Weather" in
      (* A granted root inside the entry's own source directory. *)
      let in_src = Filename.concat d "app/vendor/weather" in
      put (Filename.concat in_src "weather.march") "mod Weather do\n  fn hello() do 1 end\nend\n";
      expect_clean "no grants" (resolve ~entry ~libs:[ in_src ] ~grant_lines:[] d);
      expect_conflict "a root inside the source directory"
        (resolve ~entry ~libs:[ in_src ] d
           ~grant_lines:[ "weather\t" ^ in_src ^ "\tforge.toml:4\t()" ])
        ~mentions:[ "package `weather`"; in_src; Filename.concat d "app" ];
      (* A granted root strictly inside another library directory, one that
         belongs to no granted package (the project's own lib/). *)
      let app_lib = Filename.concat d "applib" in
      let nested = Filename.concat app_lib "vendor/w" in
      put (Filename.concat nested "w.march") "mod W do\n  fn hello() do 1 end\nend\n";
      put (Filename.concat app_lib "app_util.march") "mod AppUtil do\n  fn hello() do 1 end\nend\n";
      let entry2 = entry_calling d "W" in
      expect_clean "no grants (nested)" (resolve ~entry:entry2 ~libs:[ app_lib; nested ] ~grant_lines:[] d);
      expect_conflict "a root inside the project's library directory"
        (resolve ~entry:entry2 ~libs:[ app_lib; nested ] d
           ~grant_lines:[ "w\t" ^ nested ^ "\tforge.toml:4\t()" ])
        ~mentions:[ "package `w`"; nested; app_lib ])

let tests =
  [ ( "dep_grants",
      [ Alcotest.test_case "load_none" `Quick test_load_none;
        Alcotest.test_case "load_two" `Quick test_load_two;
        Alcotest.test_case "load_unit" `Quick test_load_unit;
        Alcotest.test_case "load_rejects" `Quick test_load_rejects;
        Alcotest.test_case "parse_scope_text" `Quick test_parse_scope_text;
        Alcotest.test_case "membership_longest_prefix" `Quick test_membership_longest_prefix;
        Alcotest.test_case "membership_symlink" `Quick test_membership_symlink;
        Alcotest.test_case "flag_overrides_env" `Quick test_flag_overrides_env;
        Alcotest.test_case "digest_tracks_contents" `Quick test_digest_tracks_contents ] );
    ( "dep_module_conflict",
      [ Alcotest.test_case "app vs dep" `Quick test_conflict_app_vs_dep;
        Alcotest.test_case "dep vs dep" `Quick test_conflict_dep_vs_dep;
        Alcotest.test_case "dep vs stdlib" `Quick test_conflict_dep_vs_stdlib;
        Alcotest.test_case "one package, two files" `Quick
          test_same_package_twice_is_not_a_conflict;
        Alcotest.test_case "a granted root nested in a project dir" `Quick
          test_conflict_nested_root ] ) ]
