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

(* Fix round 1 (C1): membership is decided by the location the loader
   found a file at AND its real path.  A file under a granted root that is
   a symlink to code outside it (or under a symlinked subdirectory) is a
   conflict, and still the package's (fail closed).  A project reached
   through a symlinked parent (/tmp -> /private/tmp) is not a conflict. *)
let test_membership_symlink_escape () =
  with_reset (fun () ->
      let d = tmpdir () in
      let root = Filename.concat d "dep" in
      let lib = Filename.concat root "lib" and hidden = Filename.concat root "hidden" in
      let hidden_sub = Filename.concat hidden "sub" in
      List.iter mkdir_p [ root; lib; hidden; hidden_sub ];
      write (Filename.concat lib "plain.march") "";
      write (Filename.concat hidden "esc.march") "";
      write (Filename.concat hidden_sub "deep.march") "";
      Unix.symlink "../hidden/esc.march" (Filename.concat lib "esc.march");
      Unix.symlink "../hidden/sub" (Filename.concat lib "sub");
      (* The whole tree also reached through a symlinked parent. *)
      let alias = Filename.concat (tmpdir ()) "alias" in
      Unix.symlink d alias;
      let alias_lib = Filename.concat alias "dep/lib" in
      let f = grants_file d [ "dep	" ^ lib ^ "	forge.toml:1	IO.Console" ] in
      let saved = Sys.getenv_opt "MARCH_LIB_PATH" in
      Fun.protect ~finally:(fun () -> Unix.putenv "MARCH_LIB_PATH" (Option.value saved ~default:""))
        (fun () ->
           Unix.putenv "MARCH_LIB_PATH"
             (String.concat ":" [ alias_lib; Filename.concat alias_lib "sub" ]);
           G.set_active (ok (G.load ~flag:f ()));
           let pkg p = Option.map (fun g -> g.G.g_pkg) (G.package_of_file p) in
           Alcotest.(check (option string)) "plain file, spelled through the alias" (Some "dep")
             (pkg (Filename.concat alias_lib "plain.march"));
           Alcotest.(check (list string)) "no conflict for it" []
             (List.map (fun c -> c.G.c_file) (G.conflicts ()));
           let esc = Filename.concat alias_lib "esc.march" in
           let deep = Filename.concat alias_lib "sub/deep.march" in
           Alcotest.(check (option string)) "a symlinked file is still the package's" (Some "dep")
             (pkg esc);
           Alcotest.(check (option string)) "so is a file in a symlinked subdirectory" (Some "dep")
             (pkg deep);
           Alcotest.(check (list string)) "both are conflicts" [ esc; deep ]
             (List.map (fun c -> c.G.c_file) (G.conflicts ()));
           List.iter (fun c ->
               Alcotest.(check (option string)) "resolves outside" None
                 (Option.map (fun g -> g.G.g_pkg) c.G.c_resolved))
             (G.conflicts ())))

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

(* A package's own call of `Authority.check` asks about a kind no row can
   name, so a function reaching it is never proven, and natively it keeps
   its frame under an unscoped grant (Task 6: it had been proven and its
   frame dropped, so native admitted what the interpreter refused). *)
let test_authority_check_not_proven () =
  with_reset (fun () ->
      let p = dep "peeker" in
      let d = project ~grants:[ ("peeker", p, "IO.Console") ] () in
      let code, out = check_in ~env:"MARCH_DUMP_DEP_PROVEN=1" ~libs:[ p ] d (app "peeker") in
      expect_pass "Peeker.peek's check names no kind statically" (code, out);
      let proven k = has_sub out ("dep-proven " ^ k ^ "\n") in
      if proven "Peeker.peek" then
        Alcotest.failf "Peeker.peek (calls Authority.check) proven:\n%s" out;
      if not (proven "Peeker.twice") then Alcotest.failf "Peeker.twice (pure) not proven:\n%s" out)

(* The guard behind [test_authority_check_not_proven]: the checker treats a
   package's own reference to `Authority.check` as an unknown reach, but a
   stdlib function contributes only its row.  That is sound while every
   stdlib call of `Authority.check` names its kind as a literal (the row then
   carries it).  A stdlib function forwarding a caller's kind String would
   let a package ask about any kind through it, proven by kind, and natively
   frameless under an unscoped grant.  So: every `Authority.check` in stdlib
   code (comments stripped) is followed by an open paren and a string
   literal. *)
let test_stdlib_checks_name_literal_kinds () =
  let stdlib = Filename.concat (Filename.dirname (Filename.dirname (fixtures ()))) "stdlib" in
  let rec files d =
    Array.to_list (Sys.readdir d)
    |> List.concat_map (fun f ->
        let p = Filename.concat d f in
        if Sys.is_directory p then files p
        else if Filename.check_suffix f ".march" then [ p ] else [])
  in
  let needle = "Authority.check" in
  let nl = String.length needle in
  let bad = ref [] in
  List.iter (fun path ->
      let ic = open_in_bin path in
      let lines = String.split_on_char '\n' (really_input_string ic (in_channel_length ic)) in
      close_in ic;
      List.iteri (fun i line ->
          let code =
            match String.index_opt line '-' with
            | Some _ ->
              let rec cut j =
                if j + 1 >= String.length line then line
                else if line.[j] = '-' && line.[j + 1] = '-' then String.sub line 0 j
                else cut (j + 1) in
              cut 0
            | None -> line in
          let n = String.length code in
          let rec scan j =
            if j + nl <= n then begin
              if String.sub code j nl = needle then begin
                let k = j + nl in
                let next_ident = k < n && (match code.[k] with
                    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true | _ -> false) in
                if not next_ident && not (k + 2 <= n && String.sub code k 2 = "(\"") then
                  bad := Printf.sprintf "%s:%d: %s" path (i + 1) (String.trim line) :: !bad
              end;
              scan (j + 1)
            end in
          scan 0)
        lines)
    (files stdlib);
  if !bad <> [] then
    Alcotest.failf
      "a stdlib Authority.check without a literal kind (see the comment on this test):\n%s"
      (String.concat "\n" (List.rev !bad))

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

(* Task 5: run [file] in the interpreter (or, with [~jit:true], through
   `--jit`) as [build_in] builds it: same project directory, private HOME,
   MARCH_LIB_PATH and grants file.  The output ends with `exit N`, as
   [run_built]'s does, so the two compare directly. *)
let run_interp ?(jit = false) ~libs d file : string =
  let out = Filename.concat d "interp.out" in
  let grants = Filename.concat d "dep-grants" in
  let cmd =
    Printf.sprintf "cd %s && HOME=%s MARCH_LIB_PATH=%s %s %s %s %s > %s 2>&1; echo \"exit $?\" >> %s"
      (Filename.quote d) (Filename.quote (Lazy.force private_home))
      (Filename.quote (String.concat ":" libs))
      (if Sys.file_exists grants then "MARCH_DEP_GRANTS=" ^ Filename.quote grants else "")
      (Filename.quote (main_exe ())) (if jit then "--jit" else "")
      (Filename.quote file) (Filename.quote out) (Filename.quote out) in
  ignore (Sys.command cmd);
  let ic = open_in_bin out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

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
        targets;
      Alcotest.(check string) "interp" want (run_interp ~libs:[ r ] d (app "scoped_refusal"));
      Alcotest.(check string) "jit" want
        (run_interp ~jit:true ~libs:[ r ] d (app "scoped_refusal")))

(* Task 6, no grants: a library module's module-level let that names one
   of its own (or its parent module's) functions by bare name.  Natively the
   let's zero-arg fn kept the bare name, an undefined `@bang` at link time
   (the interpreter was right). *)
let test_lib_let_names_own_fn () =
  with_reset (fun () ->
      let l = dep "selfref" in
      let d = project () in
      let want = "own! parent!\nexit 0\n" in
      let targets = `Native :: (if Lazy.force have_node then [ `Js ] else []) in
      List.iter (fun target ->
          let what = match target with `Native -> "native" | `Js -> "js" in
          let code, out = build_in ~target ~libs:[ l ] d (app "selfref") in
          if code <> 0 then Alcotest.failf "%s build failed (exit %d):\n%s" what code out;
          Alcotest.(check string) what want (run_built ~target d))
        targets;
      Alcotest.(check string) "interp" want (run_interp ~libs:[ l ] d (app "selfref")))

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
        (run_built ~target:`Native d);
      Alcotest.(check string) "interp"
        "IO.FileRead(\"/etc/hosts\") refused by the grant to package prober \
         (IO.FileRead(\"/srv/data\"), IO.Spawn)\nmain: allowed\nexit 0\n"
        (run_interp ~libs:[ p ] d (app "actor_refusal")))

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
        targets;
      Alcotest.(check string) "interp" want (run_interp ~libs:[ l ] d (app "module_value"));
      Alcotest.(check string) "jit" want
        (run_interp ~jit:true ~libs:[ l ] d (app "module_value")))

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
          Alcotest.(check string) grant "<refused>\nexit 0\n" (run_built ~target:`Native d);
          Alcotest.(check string) (grant ^ " interp") "<refused>\nexit 0\n"
            (run_interp ~libs:[ g ] d (app "app_impl")))
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
          Alcotest.(check string) grant "[refused]\nexit 0\n" (run_built ~target:`Native d);
          Alcotest.(check string) (grant ^ " interp") "[refused]\nexit 0\n"
            (run_interp ~libs:[ g ] d (app "app_impl_interp")))
        [ "IO.Clock"; "IO.FileRead(\"/srv\")" ])

(* Task 5 fix round 1 (I2): a granted package's actor lifecycle (init,
   handler, on_stop, a supervised child and its restart), a task the
   package spawns, and a panic inside it.  Each runs under the grant, and
   the app's authority is back after each; interp and native agree. *)
let lifecycle_grant = "IO.FileRead(\"/srv/data\"), IO.Spawn, IO.Console, Actor.Introspect"

let test_lifecycle_under_grant () =
  with_reset (fun () ->
      let l = dep "lifecycle" in
      let d = project ~grants:[ ("lifecycle", l, lifecycle_grant) ] () in
      let want =
        String.concat "\n"
          [ "app-spawned: init=refused handler=refused";
            "pkg-spawned: init=refused handler=refused";
            "sup child: init=refused handler=refused";
            "restarted: true";
            "restarted child: init=refused handler=refused";
            "on_stop: refused";
            "after actors: allowed";
            "task inside the package: refused";
            "its task awaited by the app: refused";
            "after tasks: allowed";
            "boom: err";
            "after a panic in the package: allowed";
            "exit 0\n" ] in
      Alcotest.(check string) "interp" want (run_interp ~libs:[ l ] d (app "lifecycle"));
      let code, out = build_in ~target:`Native ~libs:[ l ] d (app "lifecycle") in
      if code <> 0 then Alcotest.failf "native build failed (exit %d):\n%s" code out;
      Alcotest.(check string) "native" want (run_built ~target:`Native d))

(* Fix round 1 (C1): an interface default method's body is evaluated when
   the package loads; that is the package's module-level code, so it runs
   under the grant.  Interp only: natively this program crashes (SIGSEGV or SIGBUS)
   with or without grants (specs/todos/2026-11-23-interface-eager-default-sigbus.md). *)
let test_eager_default_under_grant () =
  with_reset (fun () ->
      let e = dep "eager" in
      let d0 = project () in
      Alcotest.(check string) "no grant" "default body: eager:allowed\nexit 0\n"
        (run_interp ~libs:[ e ] d0 (app "eager_default"));
      let d = project ~grants:[ ("eager", e, "IO.FileRead(\"/srv/data\")") ] () in
      Alcotest.(check string) "granted" "default body: eager:refused\nexit 0\n"
        (run_interp ~libs:[ e ] d (app "eager_default")))

(* Fix round 1 (I1): the app's own actor named like the package's
   `Lifecycle.W` is the app's code: its handler keeps the app's authority.
   Interp only: natively the two actor names collide when clang compiles the IR with or
   without grants (same todo). *)
let test_actor_name_clash () =
  with_reset (fun () ->
      let l = dep "lifecycle" in
      let d = project ~grants:[ ("lifecycle", l, lifecycle_grant) ] () in
      Alcotest.(check string) "interp"
        "app W handler=allowed\npackage W: init=refused handler=refused\nexit 0\n"
        (run_interp ~libs:[ l ] d (app "actor_name_clash")))

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

(* ── Task 7: caches and forge ─────────────────────────────────────────── *)

(* [march query key] in [d] (same private HOME and MARCH_LIB_PATH as
   [check_in]); [grants] is the MARCH_DEP_GRANTS value, if any.  Returns the
   source-level key and the flags line. *)
let query_key ?grants ~libs d file : string * string =
  let out = Filename.concat d "key.out" in
  let cmd =
    Printf.sprintf "cd %s && HOME=%s MARCH_LIB_PATH=%s %s %s query key %s > %s 2>&1"
      (Filename.quote d) (Filename.quote (Lazy.force private_home))
      (Filename.quote (String.concat ":" libs))
      (match grants with Some g -> "MARCH_DEP_GRANTS=" ^ Filename.quote g | None -> "")
      (Filename.quote (main_exe ())) (Filename.quote file) (Filename.quote out) in
  let code = Sys.command cmd in
  let ic = open_in_bin out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  if code <> 0 then Alcotest.failf "march query key failed (exit %d):\n%s" code s;
  let field name =
    match
      List.find_opt (fun l -> has_sub l name) (String.split_on_char '\n' s)
    with
    | Some l -> String.trim l
    | None -> Alcotest.failf "no %S line in:\n%s" name s
  in
  let key =
    match String.split_on_char ' ' (field "source-level key") |> List.filter (( <> ) "") with
    | _ :: _ :: k :: _ -> k
    | _ -> Alcotest.failf "unexpected key line in:\n%s" s
  in
  (key, field "flags")

(* Decision 12 for --compile (Task 3 tested --check): the grants' digest
   is a flag tag of the compile key, one byte of the grants file changes it,
   and with no grants (no file, or a file holding only comments) there is
   no tag and the key is the grant-free one. *)
let test_compile_key_tracks_grants () =
  with_reset (fun () ->
      let s = dep "shout" in
      let d = project () in
      let k0, f0 = query_key ~libs:[ s ] d (app "kind") in
      if has_sub f0 "grants:" then Alcotest.failf "a grant-free key has a grants tag: %s" f0;
      let comments = Filename.concat d "comments-only" in
      write comments "# no grants\n";
      let kc, fc = query_key ~grants:comments ~libs:[ s ] d (app "kind") in
      Alcotest.(check string) "a file with no entries: the grant-free key" k0 kc;
      Alcotest.(check string) "and the same flags" f0 fc;
      let g = grants_file d [ Printf.sprintf "shout\t%s\tforge.toml:2\tIO.Console" s ] in
      let k1, f1 = query_key ~grants:g ~libs:[ s ] d (app "kind") in
      if not (has_sub f1 "grants:") then Alcotest.failf "no grants tag: %s" f1;
      if k1 = k0 then Alcotest.fail "grants did not change the compile key";
      ignore (grants_file d [ Printf.sprintf "shout\t%s\tforge.toml:3\tIO.Console" s ]);
      let k2, _ = query_key ~grants:g ~libs:[ s ] d (app "kind") in
      if k2 = k1 then Alcotest.fail "a one-byte grants-file edit did not change the compile key")

(* The real forge, hermetic: the just-built march as the bare `march` on
   PATH, an empty MARCH_HOME, the private HOME, and the staged stdlib and
   runtime (a PATH-symlinked march cannot find them exe-relative). *)
let forge_exe () =
  Filename.concat (Filename.dirname (main_exe ())) "../forge/bin/main.exe"

let hermetic_bin =
  lazy begin
    let d = tmpdir () in
    let real p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p in
    Unix.symlink (real (main_exe ())) (Filename.concat d "march");
    d
  end

let forge_in d args : int * string =
  let out = Filename.concat d "forge.out" in
  let staged sub =
    realpath (Filename.concat (Filename.dirname (main_exe ())) ("../" ^ sub)) in
  let cmd =
    Printf.sprintf
      "cd %s && PATH=%s:\"$PATH\" MARCH_HOME=%s HOME=%s MARCH_STDLIB=%s MARCH_RUNTIME_DIR=%s %s %s > %s 2>&1"
      (Filename.quote d) (Filename.quote (Lazy.force hermetic_bin)) (Filename.quote (tmpdir ()))
      (Filename.quote (Lazy.force private_home)) (Filename.quote (staged "stdlib"))
      (Filename.quote (staged "runtime")) (Filename.quote (forge_exe ())) args (Filename.quote out) in
  let code = Sys.command cmd in
  let ic = open_in_bin out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (code, s)

(* A fresh, writable copy of test/dep_grants/forge_e2e (dune stages source
   trees read-only). *)
let forge_project () =
  let d = Filename.concat (tmpdir ()) "forge_e2e" in
  let rc =
    Sys.command
      (Printf.sprintf "cp -R %s %s && chmod -R u+w %s"
         (Filename.quote (Filename.concat (fixtures ()) "forge_e2e")) (Filename.quote d)
         (Filename.quote d)) in
  if rc <> 0 then Alcotest.fail "could not copy the forge_e2e fixture";
  d

(* `forge build` of a two-package project whose forge.toml grants the dep
   reads under /srv/data: forge writes .forge/dep-grants and points the
   compiler at it, and the built program's read of /etc/hosts is refused
   by the grant at run time. *)
let test_forge_build_and_run () =
  with_reset (fun () ->
      let d = forge_project () in
      let code, out = forge_in d "build" in
      if code <> 0 then Alcotest.failf "forge build failed (exit %d):\n%s" code out;
      let grants =
        let fd = Filename.concat d ".forge" in
        match
          (if Sys.file_exists fd then Array.to_list (Sys.readdir fd) else [])
          |> List.filter (fun f -> String.starts_with ~prefix:"dep-grants-" f)
        with
        | [ f ] -> Filename.concat fd f
        | fs -> Alcotest.failf "expected one .forge/dep-grants-<digest>, found %d" (List.length fs)
      in
      let ic = open_in_bin grants in
      let text = really_input_string ic (in_channel_length ic) in
      close_in ic;
      let want_line =
        Printf.sprintf "reader\t%s\t%s:11\tIO.FileRead(\"/srv/data\")"
          (realpath (Filename.concat d "deps/reader/lib")) (Filename.concat d "forge.toml") in
      if not (has_sub text want_line) then
        Alcotest.failf "the grants file lacks %S:\n%s" want_line text;
      let out_file = Filename.concat d "run.out" in
      ignore
        (Sys.command
           (Printf.sprintf "cd %s && ./.march/build/debug/forge_e2e > %s 2>&1; echo \"exit $?\" >> %s"
              (Filename.quote d) (Filename.quote out_file) (Filename.quote out_file)));
      let ic = open_in_bin out_file in
      let ran = really_input_string ic (in_channel_length ic) in
      close_in ic;
      Alcotest.(check string) "the built program"
        "allowed /srv/data/x\n\
         IO.FileRead(\"/etc/hosts\") refused by the grant to package reader \
         (IO.FileRead(\"/srv/data\"))\nexit 0\n"
        ran)

(* Fix round 1 (C1): a granted dependency whose file is a symlink to code
   outside its library root (and, separately, whose lib/ holds a symlinked
   subdirectory) must not run ungranted: the build is refused with
   `dep_grant_invalid` at the grant's forge.toml line. *)
let test_forge_symlink_escape () =
  with_reset (fun () ->
      let check_refused what (code, out) =
        if code = 0 then Alcotest.failf "%s: forge build passed:\n%s" what out;
        List.iter (fun m ->
            if not (has_sub out m) then
              Alcotest.failf "%s: the output does not mention %S:\n%s" what m out)
          [ "[dep_grant_invalid]"; "forge.toml:11";
            "lies under the granted root of package `reader` but resolves to" ]
      in
      (* a symlinked file *)
      let d = forge_project () in
      let r = Filename.concat d "deps/reader" in
      Unix.mkdir (Filename.concat r "hidden") 0o755;
      Sys.rename (Filename.concat r "lib/reader.march") (Filename.concat r "hidden/reader.march");
      Unix.symlink "../hidden/reader.march" (Filename.concat r "lib/reader.march");
      check_refused "a symlinked file" (forge_in d "build");
      (* a symlinked subdirectory *)
      let d = forge_project () in
      let r = Filename.concat d "deps/reader" in
      Unix.mkdir (Filename.concat r "hidden") 0o755;
      Unix.mkdir (Filename.concat r "hidden/sub") 0o755;
      Sys.rename (Filename.concat r "lib/reader.march")
        (Filename.concat r "hidden/sub/reader.march");
      Unix.symlink "../hidden/sub" (Filename.concat r "lib/sub");
      check_refused "a symlinked subdirectory" (forge_in d "build"))

(* Follow-up M7: `march repl <entry>` runs the same grant checks as
   `march --check` before loading the entry, in both REPL modes (JIT, and
   the interpreter under MARCH_REPL_INTERP=1), and refuses the load: a
   malformed grant, and a granted file that is a symlink out of its root. *)
let repl_in ?(interp = false) ~libs d file : int * string =
  let out = Filename.concat d "repl.out" in
  let grants = Filename.concat d "dep-grants" in
  let cmd =
    Printf.sprintf "cd %s && %s HOME=%s MARCH_LIB_PATH=%s %s %s repl %s < /dev/null > %s 2>&1"
      (Filename.quote d) (if interp then "MARCH_REPL_INTERP=1" else "")
      (Filename.quote (Lazy.force private_home))
      (Filename.quote (String.concat ":" libs))
      (if Sys.file_exists grants then "MARCH_DEP_GRANTS=" ^ Filename.quote grants else "")
      (Filename.quote (main_exe ())) (Filename.quote file) (Filename.quote out) in
  let code = Sys.command cmd in
  let ic = open_in_bin out in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (code, s)

let test_repl_refuses_bad_grants () =
  with_reset (fun () ->
      let expect what ~mentions (code, out) =
        if code = 0 then Alcotest.failf "%s: the REPL loaded the entry:\n%s" what out;
        if has_sub out "loaded " then Alcotest.failf "%s: the REPL says it loaded:\n%s" what out;
        List.iter (fun m ->
            if not (has_sub out m) then
              Alcotest.failf "%s: the output does not mention %S:\n%s" what m out)
          ("[dep_grant_invalid]" :: mentions)
      in
      (* a malformed grant (a relative path scope) *)
      let r = dep "reader" in
      let d = project ~grants:[ ("reader", r, "IO.FileRead(\"srv/data\")") ] () in
      List.iter (fun interp ->
          expect (if interp then "interp REPL, malformed grant" else "JIT REPL, malformed grant")
            ~mentions:[ "is not valid" ]
            (repl_in ~interp ~libs:[ r ] d (app "scoped_refusal")))
        [ false; true ];
      (* a granted file that is a symlink out of its root *)
      let pkg = Filename.concat (tmpdir ()) "reader" in
      List.iter mkdir_p [ pkg; Filename.concat pkg "lib"; Filename.concat pkg "hidden" ];
      let src = Filename.concat r "reader.march" in
      let ic = open_in_bin src in
      let text = really_input_string ic (in_channel_length ic) in
      close_in ic;
      write (Filename.concat pkg "hidden/reader.march") text;
      Unix.symlink "../hidden/reader.march" (Filename.concat pkg "lib/reader.march");
      let lib = Filename.concat pkg "lib" in
      let d = project ~grants:[ ("reader", lib, "IO.FileRead(\"/srv/data\")") ] () in
      List.iter (fun interp ->
          expect (if interp then "interp REPL, symlink" else "JIT REPL, symlink")
            ~mentions:[ "lies under the granted root of package `reader`" ]
            (repl_in ~interp ~libs:[ lib ] d (app "scoped_refusal")))
        [ false; true ])

(* A malformed grant in forge.toml (a relative path scope) is reported by
   `forge check` and `forge build` as `dep_grant_invalid` at its forge.toml
   line. *)
let test_forge_bad_grant_at_manifest_line () =
  with_reset (fun () ->
      let d = forge_project () in
      let toml = Filename.concat d "forge.toml" in
      let ic = open_in_bin toml in
      let text = really_input_string ic (in_channel_length ic) in
      close_in ic;
      write toml
        (Str.global_replace (Str.regexp_string "/srv/data") "srv/data" text);
      List.iter (fun cmd ->
          let code, out = forge_in d cmd in
          if code = 0 then Alcotest.failf "forge %s passed a malformed grant:\n%s" cmd out;
          List.iter (fun m ->
              if not (has_sub out m) then
                Alcotest.failf "forge %s: the output does not mention %S:\n%s" cmd m out)
            [ "[dep_grant_invalid]"; "forge.toml:11" ])
        [ "check"; "build" ])

(* Final review C1, static half: an `extern` in a granted package needs
   `IO.Foreign` in the grant whether or not the static reach sees the call.
   Here the app reaches the package's extern only through generic code
   (`gopeek(x)`, whose first argument has no solved type), which the reach
   does not follow into the impl. *)
let test_extern_needs_foreign_package_wide () =
  with_reset (fun () ->
      let c = dep "cpid_iface" in
      let d = project ~grants:[ ("cpid", c, "IO.Console") ] () in
      expect_fail "an extern reached only through generic code" ~code:"dep_grant_exceeded"
        ~mentions:[ "`cpid` is granted `IO.Console`"; "IO.Foreign"; "getpid" ]
        (check_in ~libs:[ c ] d (app "extern_dispatch"));
      let d = project ~grants:[ ("cpid", c, "IO.Console, IO.Foreign") ] () in
      expect_pass "the same under a grant naming IO.Foreign"
        (check_in ~libs:[ c ] d (app "extern_dispatch")))

(* Final review C1, run-time half: an ungranted package's extern reached
   from inside a granted package by a route the static reach does not follow
   (generic `show` into the ungranted package's impl) is refused at run time
   by the grant, interpreted and native (the JIT and JS cannot run a C
   extern at all; the static half is backend-independent).  Called from the
   app, and from an app callback the granted package calls, it runs: only a
   grant layer refuses an extern. *)
let test_extern_refused_under_grant_at_run_time () =
  with_reset (fun () ->
      let l = dep "pidlib" and s = dep "pidshow" in
      let d = project ~grants:[ ("pidshow", s, "IO.Console") ] () in
      expect_pass "the static reach does not see the extern"
        (check_in ~libs:[ l; s ] d (app "extern_backstop"));
      let want =
        "direct: ran getpid\ncallback: ran getpid\nthrough pidshow: refused\nexit 0\n" in
      Alcotest.(check string) "interp" want (run_interp ~libs:[ l; s ] d (app "extern_backstop"));
      let code, out = build_in ~target:`Native ~libs:[ l; s ] d (app "extern_backstop") in
      if code <> 0 then Alcotest.failf "native build failed (exit %d):\n%s" code out;
      Alcotest.(check string) "native" want (run_built ~target:`Native d);
      (* Granted IO.Foreign: nothing is refused. *)
      let d = project ~grants:[ ("pidshow", s, "IO.Console, IO.Foreign") ] () in
      let want_ok =
        "direct: ran getpid\ncallback: ran getpid\nthrough pidshow: ran getpid\nexit 0\n" in
      Alcotest.(check string) "interp, IO.Foreign granted" want_ok
        (run_interp ~libs:[ l; s ] d (app "extern_backstop"));
      let code, out = build_in ~target:`Native ~libs:[ l; s ] d (app "extern_backstop") in
      if code <> 0 then Alcotest.failf "native build failed (exit %d):\n%s" code out;
      Alcotest.(check string) "native, IO.Foreign granted" want_ok (run_built ~target:`Native d))

(* Final review I2: an app impl that inherits a granted package's interface
   default body runs the package's code, so the static reach charges it to
   the package. *)
let test_inherited_default_charged_to_package () =
  with_reset (fun () ->
      let y = dep "loudy" in
      let d = project ~grants:[ ("loudy", y, "()") ] () in
      expect_fail "an inherited default that prints" ~code:"dep_grant_exceeded"
        ~mentions:[ "`loudy` is granted `()`"; "IO.Console" ]
        (check_in ~libs:[ y ] d (app "default_method"));
      let d = project ~grants:[ ("loudy", y, "IO.Console") ] () in
      expect_pass "the same under a grant naming IO.Console"
        (check_in ~libs:[ y ] d (app "default_method")))

(* Final review M4: `march repl FILE` loads the entry only when its
   `--check` child came back clean, or failed with ordinary diagnostics the
   REPL reports itself.  A child that crashed, was killed, or exited
   non-zero with no diagnostic it can recognise is refused (fail closed),
   as is one that reported a grant diagnostic. *)
let test_repl_preload_verdict () =
  let module G = March_caps.Dep_grants in
  let load what st out =
    match G.preload_check_verdict st out with
    | G.Load -> ()
    | G.Refuse why -> Alcotest.failf "%s: refused (%s)" what why
  in
  let refuse what st out =
    match G.preload_check_verdict st out with
    | G.Load -> Alcotest.failf "%s: loaded" what
    | G.Refuse _ -> ()
  in
  let diag slug =
    Printf.sprintf "-- CAPABILITY --------- main.march\n\nsomething. [%s]\n\n1 | x\n" slug in
  load "a clean check" (Unix.WEXITED 0) "";
  load "a clean check with warnings" (Unix.WEXITED 0) (diag "unused_needs");
  load "an ordinary type error (the REPL reports it)" (Unix.WEXITED 1) (diag "type_mismatch");
  refuse "a grant diagnostic" (Unix.WEXITED 1) (diag "dep_grant_exceeded");
  refuse "a module conflict" (Unix.WEXITED 1) (diag "dep_module_conflict");
  refuse "a grant diagnostic even on exit 0" (Unix.WEXITED 0) (diag "dep_grant_invalid");
  refuse "an uncaught exception" (Unix.WEXITED 2)
    "Fatal error: exception Not_found\nRaised at ...\n";
  refuse "exit 1 with no diagnostic" (Unix.WEXITED 1) "";
  refuse "killed by a signal" (Unix.WSIGNALED Sys.sigkill) "";
  refuse "killed after printing a diagnostic" (Unix.WSIGNALED Sys.sigsegv) (diag "type_mismatch");
  refuse "stopped" (Unix.WSTOPPED Sys.sigstop) ""

let tests =
  [ ( "dep_grants",
      [ Alcotest.test_case "load_none" `Quick test_load_none;
        Alcotest.test_case "load_two" `Quick test_load_two;
        Alcotest.test_case "load_unit" `Quick test_load_unit;
        Alcotest.test_case "load_rejects" `Quick test_load_rejects;
        Alcotest.test_case "parse_scope_text" `Quick test_parse_scope_text;
        Alcotest.test_case "membership_longest_prefix" `Quick test_membership_longest_prefix;
        Alcotest.test_case "membership_symlink" `Quick test_membership_symlink;
        Alcotest.test_case "membership_symlink_escape" `Quick test_membership_symlink_escape;
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
        Alcotest.test_case "Authority.check is never proven" `Quick test_authority_check_not_proven;
        Alcotest.test_case "every stdlib Authority.check names a literal kind" `Quick
          test_stdlib_checks_name_literal_kinds;
        Alcotest.test_case "same-named methods elsewhere" `Quick test_same_named_methods;
        Alcotest.test_case "hint as written" `Quick test_hint_as_written;
        Alcotest.test_case "import inside a granted package" `Quick test_import_inside_package;
        Alcotest.test_case "same type name in the app" `Quick test_same_type_name;
        Alcotest.test_case "an extern in a granted package needs IO.Foreign, reached or not"
          `Quick test_extern_needs_foreign_package_wide;
        Alcotest.test_case "an inherited interface default is the package's" `Quick
          test_inherited_default_charged_to_package ] );
    ( "frames",
      [ Alcotest.test_case "a scoped grant refuses at run time, native, JS, interp and --jit" `Quick
          test_scoped_refusal_runs;
        Alcotest.test_case "the proof bit is read by the checker's key" `Quick
          test_proof_bit_read;
        Alcotest.test_case "a library let naming its own fn builds (no grants)" `Quick
          test_lib_let_names_own_fn;
        Alcotest.test_case "a dep actor's handler runs under the grant" `Quick
          test_actor_handler_under_grant;
        Alcotest.test_case "module-level function values run under the grant" `Quick
          test_module_level_values_under_grant;
        Alcotest.test_case "an app impl reached from generic package code keeps the frame"
          `Quick test_app_impl_from_generic_code;
        Alcotest.test_case "an app impl reached by interpolation keeps the frame" `Quick
          test_app_impl_from_interpolation;
        Alcotest.test_case "a dep's actors, tasks and panics run under the grant" `Quick
          test_lifecycle_under_grant;
        Alcotest.test_case "an interface default body runs under the grant at load" `Quick
          test_eager_default_under_grant;
        Alcotest.test_case "an app actor named like a dep actor keeps the app's authority"
          `Quick test_actor_name_clash;
        Alcotest.test_case "an extern under a grant without IO.Foreign is refused at run time"
          `Quick test_extern_refused_under_grant_at_run_time ] );
    ( "forge",
      [ Alcotest.test_case "the compile key tracks the grants" `Quick
          test_compile_key_tracks_grants;
        Alcotest.test_case "forge build writes the grants and the program is refused" `Quick
          test_forge_build_and_run;
        Alcotest.test_case "a malformed grant is reported at its forge.toml line" `Quick
          test_forge_bad_grant_at_manifest_line;
        Alcotest.test_case "a symlink out of a granted root is refused" `Quick
          test_forge_symlink_escape;
        Alcotest.test_case "the REPL refuses an entry that breaks its grants" `Quick
          test_repl_refuses_bad_grants;
        Alcotest.test_case "the REPL's preload check fails closed" `Quick
          test_repl_preload_verdict ] ) ]
