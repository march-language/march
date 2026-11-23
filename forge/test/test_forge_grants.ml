(** Dependency grants (ocap phase 6, Task 7): `grant = [...]` in forge.toml,
    the grants file forge writes for the compiler, its cache key, and
    `forge audit` / forge.caps.lock.

    In-process: the TOML reader, [Project.load_from], [Cmd_build.lib_path_env]
    (the prefix every `march` forge runs is started with, so what it writes
    and sets is what `forge build` writes and sets), the check cache key and
    the audit's pure layers.  The end-to-end `forge build` + run of a granted
    project is test/test_dep_grants.ml's "forge" group. *)

open March_forge

let write_file path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let rec mkdir_p d =
  if not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    Unix.mkdir d 0o755
  end

let fresh_dir () =
  let d = Filename.temp_file "forge_grants_" "" in
  Sys.remove d;
  Unix.mkdir d 0o755;
  Unix.realpath d

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec at i = i + m <= n && (String.sub hay i m = needle || at (i + 1)) in
  at 0

let load dir =
  match Project.load_from_dir dir with
  | Ok p -> p
  | Error e -> Alcotest.failf "load failed: %s" e

(* ------------------------------------------------------------------ *)
(*  TOML: literal strings, and strings holding , ] # inside arrays     *)
(* ------------------------------------------------------------------ *)

let test_toml_literal_strings () =
  let doc =
    Toml.parse
      "[t]\n\
       a = 'IO.NetConnect(\"api.test/v1/\", methods(get))'\n\
       b = ['IO.FileRead(\"/srv/data\")', 'IO.Console']  # comment\n\
       c = ['x, ] # y', \"p, ] # q\"]\n\
       d = 'C:\\path\\no\\escapes'\n\
       e = [\n\
      \  'IO.NetConnect(\"a.test\", methods(get, post))',  # first\n\
      \  'IO.Clock',\n\
       ]\n"
  in
  let t = Toml.get_section doc "t" in
  Alcotest.(check (option string)) "a literal string keeps its double quotes and commas"
    (Some "IO.NetConnect(\"api.test/v1/\", methods(get))") (Toml.get_string t "a");
  Alcotest.(check (list string)) "literal strings in an array, comment after"
    [ "IO.FileRead(\"/srv/data\")"; "IO.Console" ] (Toml.get_string_list t "b");
  Alcotest.(check (list string)) ", ] and # inside both string kinds"
    [ "x, ] # y"; "p, ] # q" ] (Toml.get_string_list t "c");
  Alcotest.(check (option string)) "no escapes in a literal string"
    (Some "C:\\path\\no\\escapes") (Toml.get_string t "d");
  Alcotest.(check (list string)) "a multi-line array of literal strings"
    [ "IO.NetConnect(\"a.test\", methods(get, post))"; "IO.Clock" ]
    (Toml.get_string_list t "e")

let test_toml_unterminated_literal () =
  match Toml.parse_located "[t]\na = 'oops\n" with
  | Ok _ -> Alcotest.fail "an unterminated literal string must not parse"
  | Error (line, _) -> Alcotest.(check int) "its line" 2 line

(* ------------------------------------------------------------------ *)
(*  Project: a dep's grant and its line                                *)
(* ------------------------------------------------------------------ *)

let manifest =
  "[package]\n\
   name = \"app\"\n\
   \n\
   [deps]\n\
   weather = { path = \"deps/weather\", grant = ['IO.NetConnect(\"api.weather.test/v1/\", methods(get))'] }\n\
   plain = { path = \"deps/plain\" }\n\
   nothing = { path = \"deps/nothing\", grant = [] }\n\
   \n\
   [deps.shout]\n\
   path = \"deps/shout\"\n\
   grant = [\n\
  \  'IO.Console',\n\
  \  'IO.Clock',\n\
   ]\n\
   \n\
   [dev-deps]\n\
   devdep = { path = \"deps/devdep\", grant = ['IO.Clock'] }\n\
   \n\
   [test-deps.tdep]\n\
   path = \"deps/tdep\"\n\
   grant = ['IO.Console']\n"

let test_project_grants () =
  let dir = fresh_dir () in
  write_file (Filename.concat dir "forge.toml") manifest;
  let warnings = ref [] in
  let saved = !Project.warning_sink in
  Project.warning_sink := (fun w -> warnings := w :: !warnings);
  let p = Fun.protect ~finally:(fun () -> Project.warning_sink := saved) (fun () -> load dir) in
  Alcotest.(check (list string)) "`grant` is a known dep key" [] !warnings;
  let g name = Project.grant_of p name in
  let pp = Alcotest.(option (pair (list string) int)) in
  Alcotest.check pp "inline table, its key's line"
    (Some ([ "IO.NetConnect(\"api.weather.test/v1/\", methods(get))" ], 5)) (g "weather");
  Alcotest.check pp "no grant" None (g "plain");
  Alcotest.check pp "grant = []" (Some ([], 7)) (g "nothing");
  Alcotest.check pp "[deps.X] section: the grant key's line" (Some ([ "IO.Console"; "IO.Clock" ], 11))
    (g "shout");
  Alcotest.check pp "dev-deps" (Some ([ "IO.Clock" ], 17)) (g "devdep");
  Alcotest.check pp "[test-deps.X]" (Some ([ "IO.Console" ], 21)) (g "tdep");
  (* The dep itself still reads as before. *)
  Alcotest.(check bool) "weather is still a path dep" true
    (List.assoc_opt "weather" p.Project.deps = Some (Project.PathDep "deps/weather"));
  Alcotest.(check bool) "shout is still a path dep" true
    (List.assoc_opt "shout" p.Project.deps = Some (Project.PathDep "deps/shout"))

let test_project_bad_grant () =
  let bad body =
    let dir = fresh_dir () in
    write_file (Filename.concat dir "forge.toml")
      ("[package]\nname = \"app\"\n\n[deps]\n" ^ body ^ "\n");
    match Project.load_from_dir dir with
    | Ok _ -> Alcotest.failf "accepted %s" body
    | Error e ->
      if not (contains e "forge.toml:5" && contains e "grant") then
        Alcotest.failf "%s: the error should name forge.toml:5 and `grant`: %s" body e
  in
  bad "w = { path = \"w\", grant = 'IO.Console' }";
  bad "w = { path = \"w\", grant = [true] }";
  bad "w = { path = \"w\", grant = [\"IO.Console\\tIO.Clock\"] }"

(* ------------------------------------------------------------------ *)
(*  The grants file and MARCH_DEP_GRANTS                               *)
(* ------------------------------------------------------------------ *)

(* A two-package project: the app and a path dep under deps/<pkg>/lib,
   outside the app's own lib/ (Task 2: a granted root nested in another
   lib dir is a module conflict). *)
let two_packages ?(grant = Some "['IO.FileRead(\"/srv/data\")']") () =
  let dir = fresh_dir () in
  mkdir_p (Filename.concat dir "lib");
  write_file (Filename.concat dir "lib/app.march") "mod App do\nend\n";
  mkdir_p (Filename.concat dir "deps/reader/lib");
  write_file (Filename.concat dir "deps/reader/forge.toml")
    "[package]\nname = \"reader\"\ntype = \"lib\"\n";
  write_file (Filename.concat dir "deps/reader/lib/reader.march") "mod Reader do\nend\n";
  write_file (Filename.concat dir "forge.toml")
    (Printf.sprintf "[package]\nname = \"app\"\n\n[deps]\nreader = { path = \"deps/reader\"%s }\n"
       (match grant with None -> "" | Some g -> ", grant = " ^ g));
  dir

let grants_file dir = Filename.concat dir ".forge/dep-grants"

let test_build_writes_grants_file () =
  let dir = two_packages () in
  let p = load dir in
  let env = Cmd_build.lib_path_env p in
  let file = grants_file dir in
  Alcotest.(check bool) ("MARCH_DEP_GRANTS is set: " ^ env) true
    (contains env ("MARCH_DEP_GRANTS=" ^ Filename.quote file ^ " "));
  Alcotest.(check bool) "the file exists" true (Sys.file_exists file);
  let lib_root = Unix.realpath (Filename.concat dir "deps/reader/lib") in
  let lines =
    String.split_on_char '\n' (read_file file)
    |> List.filter (fun l -> l <> "" && l.[0] <> '#')
  in
  Alcotest.(check (list string)) "one line: package, lib root, manifest:line, scope text"
    [ Printf.sprintf "reader\t%s\t%s:5\tIO.FileRead(\"/srv/data\")" lib_root
        (Filename.concat dir "forge.toml") ]
    lines;
  (* The lib root forge writes is on the MARCH_LIB_PATH it sets. *)
  Alcotest.(check bool) "the root is on MARCH_LIB_PATH" true (contains env lib_root)

let test_build_grant_nothing () =
  let dir = two_packages ~grant:(Some "[]") () in
  ignore (Cmd_build.lib_path_env (load dir));
  let lines =
    String.split_on_char '\n' (read_file (grants_file dir))
    |> List.filter (fun l -> l <> "" && l.[0] <> '#')
  in
  match lines with
  | [ l ] ->
    Alcotest.(check bool) ("grant = [] is written as ()" ^ l) true
      (String.ends_with ~suffix:"\t()" l)
  | _ -> Alcotest.failf "expected one line, got %d" (List.length lines)

let test_no_grant_no_file () =
  let dir = two_packages ~grant:None () in
  let env = Cmd_build.lib_path_env (load dir) in
  Alcotest.(check bool) ("no MARCH_DEP_GRANTS: " ^ env) false (contains env "MARCH_DEP_GRANTS");
  Alcotest.(check bool) "no grants file" false (Sys.file_exists (grants_file dir));
  (* A file left from an earlier build that had a grant is removed, so it
     cannot be mistaken for the current grants. *)
  mkdir_p (Filename.concat dir ".forge");
  write_file (grants_file dir) "stale\n";
  let env' = Cmd_build.lib_path_env (load dir) in
  Alcotest.(check string) "the prefix is unchanged" env env';
  Alcotest.(check bool) "a stale grants file is removed" false (Sys.file_exists (grants_file dir))

let test_test_env_carries_grants () =
  let dir = two_packages () in
  let lib_path_env, _, _, env_pfx = Cmd_test.project_env (load dir) in
  let want = "MARCH_DEP_GRANTS=" ^ Filename.quote (grants_file dir) in
  Alcotest.(check bool) "forge test's prefix" true (contains lib_path_env want);
  (* The prefix forge test rebuilds MARCH_LIB_PATH behind (with test/ added)
     keeps it too. *)
  Alcotest.(check bool) "the rebuilt prefix" true (contains env_pfx want)

let test_check_cache_key_hashes_grants () =
  let dir = two_packages () in
  let p = load dir in
  let env = Cmd_build.lib_path_env p in
  let files = [ Filename.concat dir "lib/app.march" ] in
  let k1 = Cmd_build.check_all_cache_key ~lib_path_env:env ~compiler_id:"c" files in
  (* One byte of the grant text, same path, same prefix. *)
  let text = read_file (grants_file dir) in
  write_file (grants_file dir)
    (Str.global_replace (Str.regexp_string "/srv/data") "/srv/datb" text);
  let k2 = Cmd_build.check_all_cache_key ~lib_path_env:env ~compiler_id:"c" files in
  Alcotest.(check bool) "a grants-file edit changes the key" true (k1 <> k2);
  (* No grants: the key is exactly what it was before grants existed. *)
  let dir0 = two_packages ~grant:None () in
  let env0 = Cmd_build.lib_path_env (load dir0) in
  let files0 = [ Filename.concat dir0 "lib/app.march" ] in
  let buf = Buffer.create 256 in
  Buffer.add_string buf "\x00compiler:c\x00";
  List.iter (fun f -> Buffer.add_string buf f; Buffer.add_string buf (read_file f)) files0;
  Buffer.add_string buf env0;
  Alcotest.(check string) "grant-free key unchanged"
    (Digest.to_hex (Digest.string (Buffer.contents buf)))
    (Cmd_build.check_all_cache_key ~lib_path_env:env0 ~compiler_id:"c" files0)

(* ------------------------------------------------------------------ *)
(*  forge audit and forge.caps.lock                                    *)
(* ------------------------------------------------------------------ *)

let dc ?grant name caps =
  { Cmd_audit.dc_name = name; dc_caps = caps; dc_installed = true; dc_grant = grant;
    dc_nested_grants = [] }

let test_baseline_records_grant () =
  let dir = fresh_dir () in
  let path = Filename.concat dir "forge.caps.lock" in
  let g = [ "IO.NetConnect(\"api.test/v1/\", methods(get))"; "IO.Clock" ] in
  Cmd_audit.write_baseline path
    [ dc ~grant:g "alpha" [ "IO.NetConnect" ]; dc ~grant:[] "beta" []; dc "gamma" [ "IO.Clock" ] ];
  Alcotest.(check (list (pair string (list string)))) "caps read as before"
    [ ("alpha", [ "IO.NetConnect" ]); ("beta", []); ("gamma", [ "IO.Clock" ]) ]
    (Cmd_audit.read_baseline path);
  Alcotest.(check (list (pair string (list string)))) "grants, commas and quotes intact"
    [ ("alpha", g); ("beta", []) ]
    (Cmd_audit.read_baseline_grants path);
  (* A dep with no grant writes no grant line: a grant-free baseline is
     byte-identical to one written before grants existed. *)
  Cmd_audit.write_baseline path [ dc "gamma" [ "IO.Clock" ] ];
  Alcotest.(check bool) "no grant line" false (contains (read_file path) "grant")

let escalates changes = List.exists Cmd_audit.is_escalation changes

let test_diff_grants () =
  let base_grants = [ ("alpha", [ "IO.FileRead(\"/srv/data\")" ]) ] in
  let diff current =
    Cmd_audit.diff_grants ~baseline_grants:base_grants ~baseline:[ ("alpha", [ "IO.FileRead" ]) ]
      ~current:[ current ]
  in
  Alcotest.(check int) "same grant: no change" 0
    (List.length (diff (dc ~grant:[ "IO.FileRead(\"/srv/data\")" ] "alpha" [ "IO.FileRead" ])));
  let widened =
    diff (dc ~grant:[ "IO.FileRead(\"/srv/data\")"; "IO.Console" ] "alpha" [ "IO.FileRead" ]) in
  Alcotest.(check bool) "a widened grant is reported" true
    (List.exists (function Cmd_audit.Grant_widened ("alpha", [ "IO.Console" ]) -> true | _ -> false)
       widened);
  Alcotest.(check bool) "and escalates" true (escalates widened);
  let removed = diff (dc "alpha" [ "IO.FileRead" ]) in
  Alcotest.(check bool) "dropping the grant escalates (no grant = no limit)" true
    (escalates removed);
  let narrowed = diff (dc ~grant:[] "alpha" [ "IO.FileRead" ]) in
  Alcotest.(check bool) "a narrowed grant is reported" true (narrowed <> []);
  Alcotest.(check bool) "but does not escalate" false (escalates narrowed);
  (* A grant on a dep the baseline recorded without one limits it: no
     escalation.  A brand-new dep's grant is part of an Added. *)
  let newly =
    Cmd_audit.diff_grants ~baseline_grants:[] ~baseline:[ ("beta", []) ]
      ~current:[ dc ~grant:[ "IO.Clock" ] "beta" [] ] in
  Alcotest.(check bool) "a new grant on an ungranted dep is reported" true (newly <> []);
  Alcotest.(check bool) "but limits, so does not escalate" false (escalates newly);
  (* Old call shape (no grants anywhere) behaves exactly as before. *)
  Alcotest.(check int) "no grants, no grant changes" 0
    (List.length
       (Cmd_audit.diff ~baseline:[ ("alpha", [ "IO.FileRead" ]) ]
          ~current:[ dc "alpha" [ "IO.FileRead" ] ]))

let test_collect_grants_and_nested () =
  let dir = fresh_dir () in
  mkdir_p (Filename.concat dir "deps/alpha/lib");
  mkdir_p (Filename.concat dir "deps/beta/lib");
  write_file (Filename.concat dir "deps/alpha/lib/alpha.march")
    "mod Alpha do\n  needs IO.FileRead\nend\n";
  write_file (Filename.concat dir "deps/beta/lib/beta.march")
    "mod Beta do\n  needs IO.Console\nend\n";
  (* alpha's own manifest grants its dep beta: not applied (Q1). *)
  write_file (Filename.concat dir "deps/alpha/forge.toml")
    "[package]\nname = \"alpha\"\ntype = \"lib\"\n\n[deps]\nbeta = { path = \"../beta\", grant = ['IO.Console'] }\n";
  write_file (Filename.concat dir "deps/beta/forge.toml")
    "[package]\nname = \"beta\"\ntype = \"lib\"\n";
  write_file (Filename.concat dir "forge.toml")
    "[package]\nname = \"app\"\n\n[deps]\nalpha = { path = \"deps/alpha\", grant = ['IO.FileRead(\"/srv\")'] }\n";
  match Cmd_audit.collect (load dir) with
  | Error e -> Alcotest.failf "collect: %s" e
  | Ok c ->
    let find n = List.find (fun d -> d.Cmd_audit.dc_name = n) c.Cmd_audit.deps in
    let a = find "alpha" and b = find "beta" in
    Alcotest.(check (option (list string))) "alpha's grant" (Some [ "IO.FileRead(\"/srv\")" ])
      a.Cmd_audit.dc_grant;
    Alcotest.(check (option (list string))) "beta has no grant from the app" None b.Cmd_audit.dc_grant;
    Alcotest.(check (list (pair string (list string)))) "beta's nested grant"
      [ ("alpha", [ "IO.Console" ]) ] b.Cmd_audit.dc_nested_grants;
    let la = Cmd_audit.describe_dep a and lb = Cmd_audit.describe_dep b in
    Alcotest.(check bool) ("alpha shows its grant: " ^ la) true
      (contains la "grant: IO.FileRead(\"/srv\")");
    Alcotest.(check bool) ("beta shows no grant: " ^ lb) true (contains lb "no grant");
    Alcotest.(check bool) ("beta's nested grant is not applied: " ^ lb) true
      (contains lb "not applied" && contains lb "alpha")

let () =
  Alcotest.run "forge-grants"
    [ ( "toml",
        [ Alcotest.test_case "literal strings with , ] #" `Quick test_toml_literal_strings;
          Alcotest.test_case "unterminated literal string" `Quick test_toml_unterminated_literal ] );
      ( "project",
        [ Alcotest.test_case "grants round-trip with their lines" `Quick test_project_grants;
          Alcotest.test_case "a malformed grant is an error at its line" `Quick
            test_project_bad_grant ] );
      ( "grants file",
        [ Alcotest.test_case "forge build writes it and sets the env" `Quick
            test_build_writes_grants_file;
          Alcotest.test_case "grant = [] is ()" `Quick test_build_grant_nothing;
          Alcotest.test_case "no grant: no file, no env" `Quick test_no_grant_no_file;
          Alcotest.test_case "forge test's env" `Quick test_test_env_carries_grants;
          Alcotest.test_case "check cache key hashes the file" `Quick
            test_check_cache_key_hashes_grants ] );
      ( "audit",
        [ Alcotest.test_case "forge.caps.lock records the grant" `Quick test_baseline_records_grant;
          Alcotest.test_case "diff: widened grant escalates" `Quick test_diff_grants;
          Alcotest.test_case "collect: grant, no grant, not applied" `Quick
            test_collect_grants_and_nested ] ) ]
