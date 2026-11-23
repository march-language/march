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

(* ── Task 3: the static check, end to end ─────────────────────────────────

   `march --check` on the programs under test/dep_grants/apps/<case>/, with
   the dependencies under test/dep_grants/deps/ on MARCH_LIB_PATH and a
   grants file (and a forge.toml, so the grant's position is a real line)
   in a fresh temp directory, the working directory (so the project CAS is
   its own).  One private HOME for the whole run: no cache from another
   worktree leaks in, and the stdlib typecheck cache it fills is shared.
   [MARCH_BIN] overrides the compiler (to show these fail on one without
   the check). *)

let private_home =
  lazy begin
    let d = tmpdir () in
    Unix.mkdir (Filename.concat d ".cache") 0o755;
    d
  end

let main_exe () =
  match Sys.getenv_opt "MARCH_BIN" with
  | Some p when p <> "" -> p
  | _ ->
    let exe = if Filename.is_relative Sys.executable_name
      then Filename.concat (Sys.getcwd ()) Sys.executable_name else Sys.executable_name in
    Filename.concat (Filename.dirname exe) "../bin/main.exe"

(* The source tree's test/dep_grants: the parent of the `_build` this test
   runs under. *)
let fixtures () =
  let exe = if Filename.is_relative Sys.executable_name
    then Filename.concat (Sys.getcwd ()) Sys.executable_name else Sys.executable_name in
  let rec up d =
    let p = Filename.dirname d in
    if Filename.basename d = "_build" then p
    else if p = d then Alcotest.fail "no _build ancestor of the test executable"
    else up p in
  realpath (Filename.concat (up (Filename.dirname exe)) "test/dep_grants")

let dep name = Filename.concat (fixtures ()) ("deps/" ^ name)
let app name = Filename.concat (fixtures ()) ("apps/" ^ name ^ "/main.march")

(* A project directory: a forge.toml whose line [n] grants each (package,
   dir, scope) of [grants] (n = 2, 3, ...), and the grants file. *)
let project ?(grants = []) () =
  let d = tmpdir () in
  write (Filename.concat d "forge.toml")
    (String.concat "\n"
       ("[deps]" :: List.map (fun (p, dir, sc) ->
            Printf.sprintf "%s = { path = %S, grant = [%S] }" p dir sc) grants) ^ "\n");
  let lines =
    List.mapi (fun i (p, dir, sc) ->
        Printf.sprintf "%s\t%s\tforge.toml:%d\t%s" p dir (i + 2) sc) grants in
  if lines <> [] then ignore (grants_file d lines);
  d

let check_in ?(json = false) ?(env = "") ~libs d file : int * string =
  let out = Filename.concat d "check.out" in
  let grants = Filename.concat d "dep-grants" in
  let cmd =
    Printf.sprintf "cd %s && %s HOME=%s MARCH_LIB_PATH=%s %s %s %s %s > %s 2>&1"
      (Filename.quote d) env (Filename.quote (Lazy.force private_home))
      (Filename.quote (String.concat ":" libs))
      (if Sys.file_exists grants then "MARCH_DEP_GRANTS=" ^ Filename.quote grants else "")
      (Filename.quote (main_exe ())) (if json then "--check-json" else "--check")
      (Filename.quote file) (Filename.quote out) in
  let code = Sys.command cmd in
  let ic = open_in_bin out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (code, s)

let expect_pass what (code, out) =
  if code <> 0 then Alcotest.failf "%s: expected `--check` to pass, got exit %d:\n%s" what code out

let expect_fail what ~code:slug ~mentions (code, out) =
  if code = 0 then Alcotest.failf "%s: expected `--check` to fail, it passed:\n%s" what out;
  List.iter (fun m ->
      if not (has_sub out m) then
        Alcotest.failf "%s: the output does not mention %S:\n%s" what m out)
    (("[" ^ slug ^ "]") :: mentions)

let api_scope = "IO.NetConnect(\"api.weather.test/v1/\", methods(get))"

let test_api_client_within_grant () =
  with_reset (fun () ->
      let w = dep "weather_quiet" in
      let d = project ~grants:[ ("weather", w, api_scope) ] () in
      expect_pass "an API client limited to one path with GET"
        (check_in ~libs:[ w ] d (app "api_client")))

let test_unreached_telemetry () =
  with_reset (fun () ->
      let w = dep "weather_quiet" in
      let d = project ~grants:[ ("weather", w, "IO.NetConnect(\"api.weather.test\")") ] () in
      expect_pass "a dep whose unreached Telemetry.ping connects elsewhere"
        (check_in ~libs:[ w ] d (app "unreached_telemetry")))

let test_reached_telemetry () =
  with_reset (fun () ->
      let w = dep "weather_noisy" in
      let d = project ~grants:[ ("weather", w, api_scope) ] () in
      expect_fail "reaching Telemetry.ping" ~code:"dep_grant_scope"
        ~mentions:[ "`weather`"; "forge.toml:2"; "telemetry.example.net";
                    "Main.main \xe2\x86\x92 Weather.forecast \xe2\x86\x92 Weather.Telemetry.ping" ]
        (check_in ~libs:[ w ] d (app "reached_telemetry")))

let test_kind_outside_grant () =
  with_reset (fun () ->
      let s = dep "shout" in
      let d = project ~grants:[ ("shout", s, "IO.Clock") ] () in
      expect_fail "a kind outside the grant" ~code:"dep_grant_exceeded"
        ~mentions:[ "`shout` is granted `IO.Clock`, but `Shout.log` needs `IO.Console`";
                    "Main.main \xe2\x86\x92 Shout.log"; "granted at forge.toml:2";
                    "stop calling `Shout.log`" ]
        (check_in ~libs:[ s ] d (app "kind")))

let test_ungranted_dep () =
  with_reset (fun () ->
      (* Grants are in effect (another package is granted), but `shout` has
         no entry: it is limited only by its own needs and its caller. *)
      let s = dep "shout" and e = dep "each" in
      let d = project ~grants:[ ("each", e, "()") ] () in
      expect_pass "a dep with no grant entry" (check_in ~libs:[ s; e ] d (app "ungranted")))

let test_callback_charged_to_app () =
  with_reset (fun () ->
      let e = dep "each" in
      let d = project ~grants:[ ("each", e, "()") ] () in
      expect_pass "an app callback doing IO outside the grant"
        (check_in ~libs:[ e ] d (app "callback")))

let test_grant_nothing () =
  with_reset (fun () ->
      let s = dep "shout" in
      let d = project ~grants:[ ("shout", s, "()") ] () in
      expect_fail "grant = [] with a reached println" ~code:"dep_grant_exceeded"
        ~mentions:[ "`shout` is granted `()`"; "`IO.Console`" ]
        (check_in ~libs:[ s ] d (app "grant_none")))

(* A grant's root must be on MARCH_LIB_PATH or a parent of a directory on
   it (decision 2); the error is at the manifest line, and survives
   --check-json (whose filter keeps only the user's files). *)
let test_root_off_lib_path_json () =
  with_reset (fun () ->
      let s = dep "shout" and e = dep "each" in
      let d = project ~grants:[ ("shout", s, "IO.Console") ] () in
      (* `shout` is granted, but only `each` is on the library path. *)
      let human = check_in ~libs:[ e ] d (app "callback") in
      expect_fail "a root off the library path" ~code:"dep_grant_invalid"
        ~mentions:[ "not on MARCH_LIB_PATH"; "forge.toml" ] human;
      let code, json = check_in ~json:true ~libs:[ e ] d (app "callback") in
      ignore code;
      if not (has_sub json "\"code\":\"dep_grant_invalid\"" && has_sub json "\"file\":\"forge.toml\""
              && has_sub json "\"start_line\":2") then
        Alcotest.failf "--check-json dropped the manifest-anchored diagnostic:\n%s" json)

(* Decision 12 / R3: the grants file's digest is part of the --check cache
   key, so narrowing a grant re-checks instead of replaying a clean verdict.
   Same working directory (the CAS lives there), same HOME, no cache
   cleared between the runs. *)
let test_grant_change_misses_cache () =
  with_reset (fun () ->
      let s = dep "shout" in
      let d = project ~grants:[ ("shout", s, "IO.Console") ] () in
      expect_pass "granted the console" (check_in ~libs:[ s ] d (app "kind"));
      expect_pass "the same again (a cache hit)" (check_in ~libs:[ s ] d (app "kind"));
      (* One byte: IO.Console -> IO.Consolf would be invalid; narrow to
         IO.Clock instead by rewriting the same file in place. *)
      ignore (grants_file d [ Printf.sprintf "shout\t%s\tforge.toml:2\tIO.Clock" s ]);
      expect_fail "after narrowing the grant" ~code:"dep_grant_exceeded"
        ~mentions:[ "`shout` is granted `IO.Clock`" ]
        (check_in ~libs:[ s ] d (app "kind"));
      (* A one-byte edit of the position only (line 2 -> 3) is a new key too. *)
      ignore (grants_file d [ Printf.sprintf "shout\t%s\tforge.toml:3\tIO.Clock" s ]);
      expect_fail "after moving the grant's line" ~code:"dep_grant_exceeded"
        ~mentions:[ "granted at forge.toml:3" ]
        (check_in ~libs:[ s ] d (app "kind")))

(* Fix round 1: a reference spelled through an `import` or an `alias`, a
   spawn of a dependency's actor (by its bare name through an import, and
   qualified), and an interface impl of a dependency type, reached only
   through a call of its method. *)
let test_import_and_alias () =
  with_reset (fun () ->
      let s = dep "shout" in
      let d = project ~grants:[ ("shout", s, "()") ] () in
      expect_fail "`import Shout` then `log(..)`" ~code:"dep_grant_exceeded"
        ~mentions:[ "`Shout.log` needs `IO.Console`"; "Main.main \xe2\x86\x92 Shout.log" ]
        (check_in ~libs:[ s ] d (app "import_call"));
      expect_fail "`alias Shout, as: S` then `S.log(..)`" ~code:"dep_grant_exceeded"
        ~mentions:[ "`Shout.log` needs `IO.Console`"; "Main.main \xe2\x86\x92 Shout.log" ]
        (check_in ~libs:[ s ] d (app "alias_call")))

let test_spawn_actor () =
  with_reset (fun () ->
      let p = dep "pinger" in
      let d = project ~grants:[ ("pinger", p, "()") ] () in
      expect_fail "spawn(Worker) through `import Pinger`" ~code:"dep_grant_exceeded"
        ~mentions:[ "needs `IO.Console`"; "Main.main \xe2\x86\x92 Worker"; "spawn(Worker)" ]
        (check_in ~libs:[ p ] d (app "spawn_import"));
      expect_fail "spawn(Pinger.Worker)" ~code:"dep_grant_exceeded"
        ~mentions:[ "needs `IO.Console`"; "Main.main \xe2\x86\x92 Pinger.Worker" ]
        (check_in ~libs:[ p ] d (app "spawn_qualified")))

let test_impl_of_dep_type () =
  with_reset (fun () ->
      let l = dep "loud" in
      let d = project ~grants:[ ("loud", l, "()") ] () in
      (* Nothing outside the package names a method: its impls are not
         reached, though the printing one is beyond the grant. *)
      expect_pass "a dep with impls the app never calls" (check_in ~libs:[ l ] d (app "show_none"));
      expect_pass "`show` of a dep type (a pure impl)" (check_in ~libs:[ l ] d (app "show_call"));
      let code, out = check_in ~libs:[ l ] d (app "announce_call") in
      expect_fail "a call of the dep's printing method" ~code:"dep_grant_exceeded"
        ~mentions:[ "`announce` in `impl Announce(Box)` needs `IO.Console`";
                    "Main.main \xe2\x86\x92 announce in impl Announce(Box)";
                    "println(announce(Loud.make()))"; "stop calling `announce`" ]
        (code, out);
      if has_sub out "$" then Alcotest.failf "a mangled impl name leaked:\n%s" out)

(* Fix round 2: a call reaches a package's impl only when it is on the
   package's type.  The app's own interface whose method shares the name,
   and a builtin-named call on an Int, cost the package nothing. *)
let test_same_named_methods () =
  with_reset (fun () ->
      let l = dep "loud" and r = dep "render" in
      let d = project ~grants:[ ("loud", l, "()") ] () in
      expect_pass "the app's own `announce` on its own type"
        (check_in ~libs:[ l ] d (app "own_iface"));
      let d = project ~grants:[ ("render", r, "()") ] () in
      expect_pass "`to_string(5)` beside a dep's printing `to_string` impl"
        (check_in ~libs:[ r ] d (app "builtin_name"));
      expect_fail "`to_string` on the dep's type" ~code:"dep_grant_exceeded"
        ~mentions:[ "`to_string` in `impl Render(Pane)` needs `IO.Console`";
                    "stop calling `to_string`" ]
        (check_in ~libs:[ r ] d (app "render_call")))

(* The hint names what the app wrote (`log`, through an import). *)
let test_hint_as_written () =
  with_reset (fun () ->
      let s = dep "shout" in
      let d = project ~grants:[ ("shout", s, "()") ] () in
      expect_fail "the hint for an imported call" ~code:"dep_grant_exceeded"
        ~mentions:[ "stop calling `log`" ]
        (check_in ~libs:[ s ] d (app "import_call")))

(* Decision 7's input for Task 4: within the grant -> proven; beyond it, or
   calling a function value of untraceable origin -> not. *)
let test_proven () =
  with_reset (fun () ->
      let m = dep "mixed" in
      let d = project ~grants:[ ("mixed", m, "IO.Clock") ] () in
      let code, out = check_in ~env:"MARCH_DUMP_DEP_PROVEN=1" ~libs:[ m ] d (app "mixed") in
      expect_pass "the mixed dep, only `tick` reached" (code, out);
      let proven k = has_sub out ("dep-proven " ^ k ^ "\n") in
      if not (proven "Mixed.tick") then Alcotest.failf "Mixed.tick not proven:\n%s" out;
      if proven "Mixed.shout" then Alcotest.failf "Mixed.shout (IO.Console) proven:\n%s" out;
      if proven "Mixed.first_of" then Alcotest.failf "Mixed.first_of (unknown) proven:\n%s" out)

(* Fix round 3: a granted package that reaches another package's function
   through its own `import` is judged on that reach, and none of its
   functions on the way is proven. *)
let test_import_inside_package () =
  with_reset (fun () ->
      let w = dep "wrapper" and s = dep "shout" in
      let d = project ~grants:[ ("wrapper", w, "()") ] () in
      let code, out =
        check_in ~env:"MARCH_DUMP_DEP_PROVEN=1" ~libs:[ w; s ] d (app "wrapper") in
      expect_fail "Wrapper calls Shout.log through `import Shout`" ~code:"dep_grant_exceeded"
        ~mentions:[ "`Shout.log` needs `IO.Console`";
                    "Main.main \xe2\x86\x92 Wrapper.go \xe2\x86\x92 Shout.log" ]
        (code, out);
      let proven k = has_sub out ("dep-proven " ^ k ^ "\n") in
      List.iter (fun k ->
          if proven k then Alcotest.failf "%s is proven on a truncated row:\n%s" k out)
        [ "Wrapper.go"; "Wrapper.Say$Bag.say" ];
      if not (proven "Wrapper.bag") then
        Alcotest.failf "Wrapper.bag (pure) not proven:\n%s" out)

(* The app's own type named like the package's, with an impl of a method
   named like the package's: the package impl is not counted. (The module
   ceiling misreports this program independently of grants:
   specs/todos/2026-11-22-cap-ceiling-same-type-name-impl-overattribution.md.) *)
let test_same_type_name () =
  with_reset (fun () ->
      let l = dep "loud" in
      let d = project ~grants:[ ("loud", l, "()") ] () in
      let _, out = check_in ~libs:[ l ] d (app "own_box") in
      if has_sub out "[dep_grant_" then
        Alcotest.failf "a dep_grant diagnostic for the app's own Box:\n%s" out)

(* ── Task 4: the native grant frames ([March_tir.Auth_rt.grants]) ────────

   [build_in] compiles [file] as [check_in] checks it (same project
   directory, private HOME, MARCH_LIB_PATH and grants file), natively or to
   JS, and returns the build's exit code and output; [run_built] runs what
   it built. *)

let build_in ?(env = "") ~target ~libs d file : int * string =
  let out = Filename.concat d "build.out" in
  let grants = Filename.concat d "dep-grants" in
  let flags, prog =
    match target with
    | `Native -> ("--compile -o ./prog", "./prog")
    | `Js -> ("--target js -o ./prog.mjs", "./prog.mjs")
  in
  (try Sys.remove (Filename.concat d prog) with Sys_error _ -> ());
  let cmd =
    Printf.sprintf "cd %s && %s HOME=%s MARCH_LIB_PATH=%s %s %s %s %s > %s 2>&1"
      (Filename.quote d) env (Filename.quote (Lazy.force private_home))
      (Filename.quote (String.concat ":" libs))
      (if Sys.file_exists grants then "MARCH_DEP_GRANTS=" ^ Filename.quote grants else "")
      (Filename.quote (main_exe ())) flags (Filename.quote file) (Filename.quote out) in
  let code = Sys.command cmd in
  let ic = open_in_bin out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (code, s)

let run_built ~target d : string =
  let out = Filename.concat d "run.out" in
  let cmd =
    Printf.sprintf "cd %s && %s > %s 2>&1; echo \"exit $?\" >> %s" (Filename.quote d)
      (match target with `Native -> "./prog" | `Js -> "node ./prog.mjs")
      (Filename.quote out) (Filename.quote out) in
  ignore (Sys.command cmd);
  let ic = open_in_bin out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let have_node = lazy (Sys.command "command -v node >/dev/null 2>&1" = 0)

(* A scoped grant: the dependency computes a path outside it, and the
   compiled program (native, and JS under node) gets the grant's refusal. *)
let test_scoped_refusal_runs () =
  with_reset (fun () ->
      let r = dep "reader" in
      let d = project ~grants:[ ("reader", r, "IO.FileRead(\"/srv/data\")") ] () in
      let want =
        "allowed /srv/data/x\n\
         IO.FileRead(\"/etc/hosts\") refused by the grant to package reader \
         (IO.FileRead(\"/srv/data\"))\nexit 0\n" in
      let targets = `Native :: (if Lazy.force have_node then [ `Js ] else []) in
      List.iter (fun target ->
          let what = match target with `Native -> "native" | `Js -> "js" in
          let code, out = build_in ~target ~libs:[ r ] d (app "scoped_refusal") in
          if code <> 0 then Alcotest.failf "%s build failed (exit %d):\n%s" what code out;
          Alcotest.(check string) what want (run_built ~target d))
        targets)

(* A granted package's actor, spawned by the app: its handler and init
   are the package's code and are wrapped, so the handler is refused what
   the grant refuses, while main keeps its own authority.  Native only:
   the JS target has no actors. *)
let test_actor_handler_under_grant () =
  with_reset (fun () ->
      let p = dep "prober" in
      let d = project ~grants:[ ("prober", p, "IO.FileRead(\"/srv/data\"), IO.Spawn") ] () in
      let code, out =
        build_in ~env:"MARCH_DUMP_GRANT_FRAMES=1" ~target:`Native ~libs:[ p ] d
          (app "actor_refusal") in
      if code <> 0 then Alcotest.failf "build failed (exit %d):\n%s" code out;
      List.iter (fun line ->
          if not (has_sub out (line ^ "\n")) then Alcotest.failf "no %S in:\n%s" line out)
        [ "grant-frame Worker_Probe pkg=prober proven=false wrapped=true";
          "grant-frame Worker_spawn pkg=prober proven=false wrapped=true" ];
      if has_sub out "grant-frame Worker_dispatch" then
        Alcotest.failf "the dispatch glue was tagged:\n%s" out;
      Alcotest.(check string) "native"
        "IO.FileRead(\"/etc/hosts\") refused by the grant to package prober \
         (IO.FileRead(\"/srv/data\"), IO.Spawn)\nmain: allowed\nexit 0\n"
        (run_built ~target:`Native d))

(* Fix round 1 (C1): a function value made by a granted package's
   module-level code, a lambda or a named function read as a value, runs
   under the grant whoever calls it, native and JS. *)
let test_module_level_values_under_grant () =
  with_reset (fun () ->
      let l = dep "leaky" in
      let d = project ~grants:[ ("leaky", l, "IO.FileRead(\"/srv/data\")") ] () in
      let refusal =
        "IO.FileRead(\"/etc/hosts\") refused by the grant to package leaky \
         (IO.FileRead(\"/srv/data\"))" in
      let want =
        String.concat ""
          [ "lambda: " ^ refusal ^ "\n"; "named via let: " ^ refusal ^ "\n";
            "named via fn: " ^ refusal ^ "\n"; "exit 0\n" ] in
      let targets = `Native :: (if Lazy.force have_node then [ `Js ] else []) in
      List.iter (fun target ->
          let what = match target with `Native -> "native" | `Js -> "js" in
          let code, out = build_in ~target ~libs:[ l ] d (app "module_value") in
          if code <> 0 then Alcotest.failf "%s build failed (exit %d):\n%s" what code out;
          Alcotest.(check string) what want (run_built ~target d))
        targets)

(* Fix round 1 (I2): a granted fn whose generic `show(x)` mono resolves
   to the app's impl keeps its frame under an unscoped grant, so the impl
   runs under the grant whether or not the grant is scoped (and as the
   always-framing interpreter will run it).  The design question is open:
   specs/todos/2026-11-22-grant-app-impl-callback-authority.md. *)
let test_app_impl_from_generic_code () =
  with_reset (fun () ->
      let g = dep "genx" in
      List.iter (fun grant ->
          let d = project ~grants:[ ("genx", g, grant) ] () in
          let code, out =
            build_in ~env:"MARCH_DUMP_GRANT_FRAMES=1" ~target:`Native ~libs:[ g ] d
              (app "app_impl") in
          if code <> 0 then Alcotest.failf "%s: build failed (exit %d):\n%s" grant code out;
          if not (has_sub out "grant-frame Genx.describe pkg=genx proven=true wrapped=true\n") then
            Alcotest.failf "%s: Genx.describe not kept:\n%s" grant out;
          Alcotest.(check string) grant "<refused>\nexit 0\n" (run_built ~target:`Native d))
        [ "IO.Clock"; "IO.FileRead(\"/srv\")" ])

(* Fix round 2 (R1): the same with string interpolation, `"[${x}]"`, whose
   `to_string(x)` mono resolves to the app's `Show` impl. *)
let test_app_impl_from_interpolation () =
  with_reset (fun () ->
      let g = dep "genfmt" in
      List.iter (fun grant ->
          let d = project ~grants:[ ("genfmt", g, grant) ] () in
          let code, out =
            build_in ~env:"MARCH_DUMP_GRANT_FRAMES=1" ~target:`Native ~libs:[ g ] d
              (app "app_impl_interp") in
          if code <> 0 then Alcotest.failf "%s: build failed (exit %d):\n%s" grant code out;
          if not (has_sub out "grant-frame Genfmt.bracket pkg=genfmt proven=true wrapped=true\n")
          then Alcotest.failf "%s: Genfmt.bracket not kept:\n%s" grant out;
          Alcotest.(check string) grant "[refused]\nexit 0\n" (run_built ~target:`Native d))
        [ "IO.Clock"; "IO.FileRead(\"/srv\")" ])

(* The proof bit crosses stages by the checker's key: the lowering reads
   [Dep_grants.proven] by the fn's module path and name.  Under an unscoped
   grant a proven fn's frame is dropped and an unproven one's kept. *)
let test_proof_bit_read () =
  with_reset (fun () ->
      let m = dep "mixed" in
      let d = project ~grants:[ ("mixed", m, "IO.Clock") ] () in
      let code, out =
        build_in ~env:"MARCH_DUMP_GRANT_FRAMES=1" ~target:`Native ~libs:[ m ] d (app "mixed") in
      if code <> 0 then Alcotest.failf "build failed (exit %d):\n%s" code out;
      List.iter (fun line ->
          if not (has_sub out (line ^ "\n")) then
            Alcotest.failf "no %S in:\n%s" line out)
        [ "grant-frame Mixed.tick pkg=mixed proven=true wrapped=false";
          "grant-frame Mixed.shout pkg=mixed proven=false wrapped=true";
          "grant-frame Mixed.first_of pkg=mixed proven=false wrapped=true" ])

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
          test_conflict_nested_root ] );
    ( "dep_grant_check",
      [ Alcotest.test_case "API client within its grant" `Quick test_api_client_within_grant;
        Alcotest.test_case "unreached telemetry" `Quick test_unreached_telemetry;
        Alcotest.test_case "reached telemetry" `Quick test_reached_telemetry;
        Alcotest.test_case "kind outside the grant" `Quick test_kind_outside_grant;
        Alcotest.test_case "ungranted dep" `Quick test_ungranted_dep;
        Alcotest.test_case "callback charged to the app" `Quick test_callback_charged_to_app;
        Alcotest.test_case "grant = []" `Quick test_grant_nothing;
        Alcotest.test_case "root off the library path, JSON" `Quick test_root_off_lib_path_json;
        Alcotest.test_case "a grant change misses the cache" `Quick test_grant_change_misses_cache;
        Alcotest.test_case "import and alias spellings" `Quick test_import_and_alias;
        Alcotest.test_case "a dep actor spawned" `Quick test_spawn_actor;
        Alcotest.test_case "impls of a dep type" `Quick test_impl_of_dep_type;
        Alcotest.test_case "proven" `Quick test_proven;
        Alcotest.test_case "same-named methods elsewhere" `Quick test_same_named_methods;
        Alcotest.test_case "hint as written" `Quick test_hint_as_written;
        Alcotest.test_case "import inside a granted package" `Quick test_import_inside_package;
        Alcotest.test_case "same type name in the app" `Quick test_same_type_name ] );
    ( "frames",
      [ Alcotest.test_case "a scoped grant refuses at run time, native and JS" `Quick
          test_scoped_refusal_runs;
        Alcotest.test_case "the proof bit is read by the checker's key" `Quick
          test_proof_bit_read;
        Alcotest.test_case "a dep actor's handler runs under the grant" `Quick
          test_actor_handler_under_grant;
        Alcotest.test_case "module-level function values run under the grant" `Quick
          test_module_level_values_under_grant;
        Alcotest.test_case "an app impl reached from generic package code keeps the frame"
          `Quick test_app_impl_from_generic_code;
        Alcotest.test_case "an app impl reached by interpolation keeps the frame" `Quick
          test_app_impl_from_interpolation ] ) ]
