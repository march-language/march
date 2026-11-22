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
        Alcotest.test_case "digest_tracks_contents" `Quick test_digest_tracks_contents ] ) ]
