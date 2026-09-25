(** Tests for `forge audit --inferred`'s toolchain probe, per-dependency cache
    and `--allow-unanalyzable` (specs/todos/2026-08-04-dependency-cap-audit-followups.md).

    Every case runs [Cmd_audit.run] in-process against a scratch project whose
    `march` is a FAKE shell script first on PATH, under an empty MARCH_HOME so
    no installed toolchain (~/.march/current, a .march-version pin) can take
    over. The fake logs every invocation, which is what lets the cache cases
    assert that `march caps` was NOT run — the only observable difference
    between a hit and a miss, since their output must be identical. *)

open March_forge

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    s
  with Sys_error _ -> ""

let rec mkdir_p d =
  if not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    Unix.mkdir d 0o755
  end

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec at i = i + m <= n && (String.sub hay i m = needle || at (i + 1)) in
  at 0

(* ------------------------------------------------------------------ *)
(*  Fixture                                                            *)
(* ------------------------------------------------------------------ *)

(* A `march` that supports `caps`: answers the probe and every package with
   a fixed set, except a package under /bad/, which fails like a dependency
   with a real type error. *)
let modern_march ~log =
  Printf.sprintf
    "#!/bin/sh\n\
     echo \"$*\" >> %s\n\
     case \"$1\" in\n\
    \  --version) echo 'march 9.9.9-fake'; exit 0 ;;\n\
    \  caps)\n\
    \    case \"$*\" in *forge_caps_probe*) echo '{\"caps\":[]}'; exit 0 ;; esac\n\
    \    case \"$*\" in */bad/*) echo 'error: ambiguous constructor `Leaf`' >&2; exit 1 ;; esac\n\
    \    echo '{\"caps\":[\"IO.Clock\"]}'; exit 0 ;;\n\
     esac\n\
     echo \"march: $1: No such file or directory\" >&2\n\
     exit 1\n"
    (Filename.quote log)

(* A `march` that predates the `caps` subcommand: `caps` is taken as an input
   file name, and two positional files are a usage error — what 0.2.0 did. *)
let old_march ~log =
  Printf.sprintf
    "#!/bin/sh\n\
     echo \"$*\" >> %s\n\
     if [ \"$1\" = --version ]; then echo 'march 0.2.0'; exit 0; fi\n\
     echo 'Usage: march [options] [file.march]' >&2\n\
     exit 1\n"
    (Filename.quote log)

type fixture = {
  base : string;     (* scratch root *)
  app : string;      (* the project being audited *)
  bindir : string;   (* holds the fake `march` *)
  log : string;      (* one line per fake-march invocation *)
}

let counter = ref 0

let lib_toml name deps =
  Printf.sprintf "[package]\nname = %S\nversion = \"0.1.0\"\ntype = \"lib\"\n\n[deps]\n%s" name
    (String.concat ""
       (List.map (fun d -> Printf.sprintf "%s = { path = \"../%s\" }\n" d d) deps))

let add_package f ~name ~deps =
  let dir = Filename.concat f.base name in
  mkdir_p (Filename.concat dir "lib");
  write_file (Filename.concat dir "forge.toml") (lib_toml name deps);
  write_file
    (Filename.concat (Filename.concat dir "lib") (name ^ ".march"))
    (Printf.sprintf "mod %s do\n  fn f() : Int do 1 end\nend\n" (String.capitalize_ascii name))

(* [packages]: (name, its own deps). The app depends on [app_deps]. *)
let make_fixture ~script ~app_deps ~packages =
  incr counter;
  let base =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "forge-audit-inferred-%d-%d" (Unix.getpid ()) !counter)
  in
  mkdir_p base;
  let f =
    { base;
      app = Filename.concat base "app";
      bindir = Filename.concat base "bin";
      log = Filename.concat base "march.log" }
  in
  mkdir_p f.bindir;
  mkdir_p (Filename.concat base "march_home");
  let exe = Filename.concat f.bindir "march" in
  write_file exe (script ~log:f.log);
  Unix.chmod exe 0o755;
  mkdir_p (Filename.concat f.app "lib");
  write_file (Filename.concat f.app "forge.toml")
    (Printf.sprintf "[package]\nname = \"app\"\nversion = \"0.1.0\"\n\n[deps]\n%s"
       (String.concat ""
          (List.map (fun d -> Printf.sprintf "%s = { path = \"../%s\" }\n" d d) app_deps)));
  List.iter (fun (name, deps) -> add_package f ~name ~deps) packages;
  f

(* Run [k] with the fake march first on PATH, an empty MARCH_HOME, and the
   app as cwd; restore all three afterwards. *)
let in_fixture f k =
  let old_path = Option.value ~default:"" (Sys.getenv_opt "PATH") in
  let old_home = Sys.getenv_opt "MARCH_HOME" in
  let old_cwd = Sys.getcwd () in
  Unix.putenv "PATH" (f.bindir ^ ":" ^ old_path);
  Unix.putenv "MARCH_HOME" (Filename.concat f.base "march_home");
  Sys.chdir f.app;
  Fun.protect
    ~finally:(fun () ->
        Sys.chdir old_cwd;
        Unix.putenv "PATH" old_path;
        Unix.putenv "MARCH_HOME" (Option.value ~default:"" old_home))
    k

(* Run [f], returning its result and everything it printed to stdout. *)
let capture f =
  flush stdout;
  let tmp = Filename.temp_file "audit_out" ".txt" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o644 in
  let saved = Unix.dup Unix.stdout in
  Unix.dup2 fd Unix.stdout;
  Unix.close fd;
  let r = try Ok (f ()) with e -> Error e in
  flush stdout;
  Unix.dup2 saved Unix.stdout;
  Unix.close saved;
  let out = read_file tmp in
  Sys.remove tmp;
  match r with Ok v -> (v, out) | Error e -> raise e

(* `march caps` invocations over [pkg]'s own files (the probe excluded). *)
let caps_runs f pkg =
  String.split_on_char '\n' (read_file f.log)
  |> List.filter (fun l ->
      String.length l >= 5 && String.sub l 0 5 = "caps "
      && contains l (Printf.sprintf "/%s/lib/" pkg))
  |> List.length

let probe_runs f =
  String.split_on_char '\n' (read_file f.log)
  |> List.filter (fun l -> contains l "forge_caps_probe")
  |> List.length

let audit ?(record_mode = false) ?allow_unanalyzable f =
  in_fixture f (fun () ->
      capture (fun () -> Cmd_audit.run ~record_mode ~inferred:true ?allow_unanalyzable ()))

let code_of = function
  | Ok c -> c
  | Error m -> Alcotest.failf "audit returned an error instead of an exit code:\n%s" m

(* ------------------------------------------------------------------ *)
(*  1. A toolchain that predates `march caps`                          *)
(* ------------------------------------------------------------------ *)

let test_old_toolchain_is_named () =
  let f =
    make_fixture ~script:old_march ~app_deps:[ "alpha"; "beta" ]
      ~packages:[ ("alpha", []); ("beta", []) ]
  in
  let r, out = audit f in
  match r with
  | Ok code ->
    Alcotest.failf
      "an old toolchain must fail the audit with one clear error, not report \
       per dependency (exit %d):\n%s" code out
  | Error msg ->
    Alcotest.(check bool) "says the toolchain lacks `march caps`" true
      (contains msg "does not support `march caps`");
    Alcotest.(check bool) "names the toolchain path" true
      (contains msg (Filename.concat f.bindir "march"));
    Alcotest.(check bool) "names the toolchain's version" true (contains msg "march 0.2.0");
    Alcotest.(check bool) "names the version needed" true (contains msg "0.3.0");
    Alcotest.(check int) "probed once per audit, not once per dependency" 1
      (List.length
         (List.filter (fun l -> contains l "caps")
            (String.split_on_char '\n' (read_file f.log))));
    Alcotest.(check int) "no dependency was run through the old compiler" 0
      (caps_runs f "alpha" + caps_runs f "beta")

let test_uninstalled_pin_is_an_error () =
  (* A .march-version naming a toolchain that is not installed used to fall
     through silently to whatever `march` was on PATH. *)
  let f =
    make_fixture ~script:modern_march ~app_deps:[ "alpha" ] ~packages:[ ("alpha", []) ]
  in
  write_file (Filename.concat f.app ".march-version") "v9.9.9\n";
  let r, out = audit f in
  match r with
  | Ok code -> Alcotest.failf "expected an error, got exit %d:\n%s" code out
  | Error msg ->
    Alcotest.(check bool) "names the missing toolchain" true (contains msg "not installed");
    Alcotest.(check int) "nothing was analyzed" 0 (caps_runs f "alpha")

(* ------------------------------------------------------------------ *)
(*  2. The cache                                                       *)
(* ------------------------------------------------------------------ *)

let test_cache_hit_skips_march_and_prints_the_same () =
  let f =
    make_fixture ~script:modern_march ~app_deps:[ "good" ]
      ~packages:[ ("good", [ "util" ]); ("util", []) ]
  in
  let r, _ = audit ~record_mode:true f in
  Alcotest.(check int) "record passes" 0 (code_of r);
  Alcotest.(check int) "record analyzed good once" 1 (caps_runs f "good");
  (* A MISS, after clearing the cache, then a HIT: identical output. *)
  let cache = Filename.concat f.app ".forge/audit-cache" in
  Alcotest.(check bool) "cache directory was written" true (Sys.file_exists cache);
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote cache)));
  let r_miss, out_miss = audit f in
  Alcotest.(check int) "miss re-ran march caps" 2 (caps_runs f "good");
  let r_hit, out_hit = audit f in
  Alcotest.(check int) "hit did NOT run march caps" 2 (caps_runs f "good");
  Alcotest.(check int) "hit did NOT re-run the probe" 2 (probe_runs f);
  Alcotest.(check int) "miss exit" 0 (code_of r_miss);
  Alcotest.(check int) "hit exit" 0 (code_of r_hit);
  Alcotest.(check string) "a hit prints exactly what a miss does" out_miss out_hit;
  Alcotest.(check bool) "and it reported the (non-empty) set" true
    (contains out_hit "capabilities unchanged")

let test_cache_invalidation () =
  let f =
    make_fixture ~script:modern_march ~app_deps:[ "good" ]
      ~packages:[ ("good", [ "util" ]); ("util", []) ]
  in
  ignore (audit f);
  ignore (audit f);
  Alcotest.(check int) "warm" 1 (caps_runs f "good");
  (* The dependency's own file. *)
  write_file (Filename.concat f.base "good/lib/good.march")
    "mod Good do\n  fn f() : Int do 2 end\nend\n";
  ignore (audit f);
  Alcotest.(check int) "editing the dependency invalidates it" 2 (caps_runs f "good");
  (* A file on its lib path only — a path dependency edited in place, which
     leaves MARCH_LIB_PATH's string unchanged. *)
  write_file (Filename.concat f.base "util/lib/util.march")
    "mod Util do\n  fn f() : Int do 3 end\nend\n";
  ignore (audit f);
  Alcotest.(check int) "editing a file on its lib path invalidates it" 3 (caps_runs f "good");
  (* The compiler. *)
  let exe = Filename.concat f.bindir "march" in
  write_file exe (modern_march ~log:f.log ^ "# rebuilt\n");
  ignore (audit f);
  Alcotest.(check int) "a different compiler invalidates it" 4 (caps_runs f "good");
  ignore (audit f);
  Alcotest.(check int) "and is warm again after" 4 (caps_runs f "good")

(* ------------------------------------------------------------------ *)
(*  3. Unanalyzable dependencies, with and without the flag            *)
(* ------------------------------------------------------------------ *)

let unanalyzable_fixture () =
  make_fixture ~script:modern_march ~app_deps:[ "good"; "bad" ]
    ~packages:[ ("good", []); ("bad", []) ]

let lists_bad out =
  contains out "bad — NOT ANALYZABLE" && contains out "ambiguous constructor"

let test_without_flag_unanalyzable_fails () =
  let f = unanalyzable_fixture () in
  let r, out = audit ~record_mode:true f in
  (match r with
   | Ok _ -> Alcotest.failf "record must refuse while a dependency is unanalyzable:\n%s" out
   | Error msg ->
     Alcotest.(check bool) "refusal says why" true (contains msg "cannot be analyzed"));
  Alcotest.(check bool) "record lists bad and the reason" true (lists_bad out);
  Alcotest.(check bool) "no baseline written" false
    (Sys.file_exists (Filename.concat f.app "forge.caps.lock"));
  let r, out = audit f in
  Alcotest.(check int) "check fails" 1 (code_of r);
  Alcotest.(check bool) "check lists bad and the reason" true (lists_bad out);
  Alcotest.(check bool) "bad is never shown as needing nothing" false
    (contains out "bad — no capabilities")

let test_allow_unanalyzable_gates_on_the_rest () =
  let f = unanalyzable_fixture () in
  let r, out = audit ~record_mode:true ~allow_unanalyzable:true f in
  Alcotest.(check int) "record passes with the flag" 0 (code_of r);
  Alcotest.(check bool) "record still lists bad and the reason" true (lists_bad out);
  let lock = read_file (Filename.concat f.app "forge.caps.lock") in
  Alcotest.(check bool) "good is recorded" true (contains lock "name = \"good\"");
  Alcotest.(check bool) "bad is NOT recorded (not as an empty set either)" false
    (contains lock "name = \"bad\"");
  let r, out = audit ~allow_unanalyzable:true f in
  Alcotest.(check int) "check passes on the analyzable subset" 0 (code_of r);
  Alcotest.(check bool) "check still lists bad and the reason" true (lists_bad out);
  let r, out = audit f in
  Alcotest.(check int) "without the flag the same tree still fails" 1 (code_of r);
  Alcotest.(check bool) "and lists bad" true (lists_bad out)

let test_allow_unanalyzable_keeps_a_recorded_set () =
  (* A dependency that WAS analyzable when the baseline was recorded and has
     since stopped typechecking: its reviewed set must survive a re-record,
     and the check must neither call it removed nor unchanged. *)
  let f = unanalyzable_fixture () in
  write_file (Filename.concat f.app "forge.caps.lock")
    "[[package]]\nname = \"bad\"\ncaps = [\"IO.Process\"]\n\n\
     [[package]]\nname = \"good\"\ncaps = [\"IO.Clock\"]\n\n";
  let r, out = audit ~allow_unanalyzable:true f in
  Alcotest.(check int) "check passes" 0 (code_of r);
  Alcotest.(check bool) "bad is not reported as removed" false (contains out "dependency removed");
  Alcotest.(check bool) "bad is listed" true (lists_bad out);
  let r, _ = audit ~record_mode:true ~allow_unanalyzable:true f in
  Alcotest.(check int) "re-record passes" 0 (code_of r);
  Alcotest.(check (list (pair string (list string))))
    "bad's recorded set is carried over unchanged"
    [ ("bad", [ "IO.Process" ]); ("good", [ "IO.Clock" ]) ]
    (Cmd_audit.read_baseline (Filename.concat f.app "forge.caps.lock"))

let test_flag_requires_inferred () =
  let f = unanalyzable_fixture () in
  let r =
    in_fixture f (fun () -> Cmd_audit.run ~inferred:false ~allow_unanalyzable:true ())
  in
  Alcotest.(check bool) "--allow-unanalyzable without --inferred is an error" true
    (Result.is_error r)

let () =
  Alcotest.run "forge-audit-inferred"
    [ ( "toolchain",
        [ Alcotest.test_case "an old march is named, once" `Quick test_old_toolchain_is_named;
          Alcotest.test_case "an uninstalled pin is an error" `Quick
            test_uninstalled_pin_is_an_error ] );
      ( "cache",
        [ Alcotest.test_case "hit skips march caps, same output" `Quick
            test_cache_hit_skips_march_and_prints_the_same;
          Alcotest.test_case "invalidation" `Quick test_cache_invalidation ] );
      ( "unanalyzable",
        [ Alcotest.test_case "without the flag it fails" `Quick
            test_without_flag_unanalyzable_fails;
          Alcotest.test_case "--allow-unanalyzable gates on the rest" `Quick
            test_allow_unanalyzable_gates_on_the_rest;
          Alcotest.test_case "--allow-unanalyzable keeps a recorded set" `Quick
            test_allow_unanalyzable_keeps_a_recorded_set;
          Alcotest.test_case "the flag requires --inferred" `Quick test_flag_requires_inferred ] ) ]
