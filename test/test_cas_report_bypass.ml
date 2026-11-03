(* A check, report or side-file switch must not be answered by the build
   cache.

   Such a switch leaves the binary unchanged, so nothing about it belongs in
   the CAS key — but a cache hit skips the code that runs the check or prints
   the report, so a warm cache answered "nothing found".  The TIR verifier's
   first MARCH_VERIFY_TIR_LEAKS=1 sweep reported 11 programs instead of 485:
   a plain --verify-tir sweep had already cached the rest under the same key.
   bin/main.ml's [source_cache_bypass] / [post_tir_cache_bypass] now skip the
   lookup at the layer where it would hide the output
   (specs/progress/2026-10-12-cas-key-debug-flags.md).

   Each test compiles once WITHOUT the switch and once WITH it in the same
   HOME and store, and asserts the second compile really ran the check or
   produced the output.  The z3 test is the one key change: a build that
   could not find z3 accepted an obligation z3 refutes, and served that
   verdict to the next build that could. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let src = {|mod ReportBypassProbe do
  needs IO.Console

  fn main(_c : Cap(IO.Console)) : Unit do
    let xs = [1, 2, 3]
    println(int_to_string(List.length(xs)))
  end
end
|}

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    s
  with Sys_error _ -> ""

let contains hay needle =
  let n = String.length hay and m = String.length needle in
  let rec go i = i + m <= n && (String.sub hay i m = needle || go (i + 1)) in
  m = 0 || go 0

let rec rm_rf p =
  match Sys.is_directory p with
  | true ->
    Array.iter (fun c -> rm_rf (Filename.concat p c)) (Sys.readdir p);
    (try Unix.rmdir p with Unix.Unix_error _ -> ())
  | false -> (try Sys.remove p with Sys_error _ -> ())
  | exception Sys_error _ -> ()

(* A fresh project dir (the CAS store is <cwd>/.march/cas) and a private HOME
   (~/.cache/march is shared across worktrees). *)
let with_scratch ?(source = src) f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "march_cas_report_bypass.%d.%d" (Unix.getpid ())
       (Hashtbl.hash (Unix.gettimeofday (), Random.bits ()))) in
  Unix.mkdir dir 0o755;
  Out_channel.with_open_bin (Filename.concat dir "m.march")
    (fun oc -> output_string oc source);
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

(* [env] is a list of NAME=VALUE; [args] go before the file.  Redirected to
   files, never a pipe: a piped `--compile` can hang.  Returns (rc, stdout,
   stderr). *)
let run ~dir ?(env = []) ~tag args =
  let out = Filename.concat dir (tag ^ ".out")
  and err = Filename.concat dir (tag ^ ".err") in
  let cmd = Printf.sprintf "cd %s && env HOME=%s %s %s %s m.march > %s 2> %s"
      (Filename.quote dir) (Filename.quote dir)
      (String.concat " " (List.map Filename.quote env))
      (Filename.quote compiler_exe)
      (String.concat " " (List.map Filename.quote args))
      (Filename.quote out) (Filename.quote err) in
  let rc = Sys.command cmd in
  (rc, read_file out, read_file err)

let ok what (rc, out, err) =
  if rc <> 0 then Alcotest.failf "%s failed (rc=%d):\n%s%s" what rc out err

let need_compiler () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe

(* The first line of the verifier's report ("TIR verifier: N finding(s) after
   STAGE:"), or "" when it found nothing. *)
let verifier_header err =
  match List.find_opt (fun l -> contains l "TIR verifier:")
          (String.split_on_char '\n' err) with
  | Some l -> l
  | None -> ""

(* MARCH_VERIFY_TIR_LEAKS=1 after a plain --verify-tir build of the same
   source: the leak pass must run, and say what a cold run says. *)
let test_verify_leaks () =
  need_compiler ();
  let leaks = [ "MARCH_VERIFY_TIR_LEAKS=1" ] in
  let args = [ "--compile"; "--verify-tir"; "--timings"; "-o"; "out" ] in
  let cold_rc, _, cold_err =
    with_scratch (fun dir -> run ~dir ~env:leaks ~tag:"cold" args) in
  with_scratch @@ fun dir ->
  ok "the plain --verify-tir compile" (run ~dir ~tag:"plain" args);
  let rc, _, err = run ~dir ~env:leaks ~tag:"leaks" args in
  let what s = Printf.sprintf "%s; warm leaks run:\n%s\ncold leaks run:\n%s" s err cold_err in
  Alcotest.(check bool) (what "the warm run reached the TIR pipeline") true
    (contains err "perceus");
  Alcotest.(check int) (what "warm and cold leak runs exit alike") cold_rc rc;
  Alcotest.(check string) (what "warm and cold leak runs report alike")
    (verifier_header cold_err) (verifier_header err)

(* --emit-llvm --compile after a plain --compile: the .ll is written.  Both
   layers would hide it: the source-level hit exits before parsing, and the
   post-TIR hit (reached once the first is bypassed) skips emission. *)
let test_emit_llvm () =
  need_compiler ();
  with_scratch @@ fun dir ->
  ok "the plain compile" (run ~dir ~tag:"plain" [ "--compile"; "-o"; "out" ]);
  let ll = Filename.concat dir "m.ll" in
  (try Sys.remove ll with Sys_error _ -> ());
  let (_, _, err) as r =
    run ~dir ~tag:"emit" [ "--compile"; "--emit-llvm"; "--timings"; "-o"; "out" ] in
  ok "the --emit-llvm compile" r;
  Alcotest.(check bool) ("the warm --emit-llvm compile emitted IR: " ^ err) true
    (contains err "llvm-emit");
  Alcotest.(check bool) ("the warm --emit-llvm compile wrote m.ll: " ^ err) true
    (contains (read_file ll) "define ")

(* --dump-provenance --compile after a plain --compile prints the table. *)
let test_dump_provenance () =
  need_compiler ();
  with_scratch @@ fun dir ->
  ok "the plain compile" (run ~dir ~tag:"plain" [ "--compile"; "-o"; "out" ]);
  let (_, out, err) as r =
    run ~dir ~tag:"prov" [ "--compile"; "--dump-provenance"; "-o"; "out" ] in
  ok "the --dump-provenance compile" r;
  Alcotest.(check bool)
    (Printf.sprintf "the warm compile printed the provenance table; stdout:\n%s\nstderr:\n%s" out err)
    true (contains out "\t")

(* An env-var report (MARCH_TRMC_REPORT, printed from the TIR pipeline)
   after a plain --compile prints its lines. *)
let test_env_report () =
  need_compiler ();
  with_scratch @@ fun dir ->
  ok "the plain compile" (run ~dir ~tag:"plain" [ "--compile"; "-o"; "out" ]);
  let (_, _, err) as r =
    run ~dir ~env:[ "MARCH_TRMC_REPORT=1" ] ~tag:"trmc" [ "--compile"; "-o"; "out" ] in
  ok "the MARCH_TRMC_REPORT compile" r;
  Alcotest.(check bool) ("the warm compile printed the TRMC report: " ^ err) true
    (contains err "TRMC\t")

(* A build without z3 accepts (with a hint) an obligation z3 refutes; the next
   build WITH z3 must not be served that verdict. *)
let z3_src = {|mod Z3KeyProbe do
  fn inner(n : {Int | _ > 0}) : Int do
    n
  end

  fn go(x : {Int | _ > 10}) : Int do
    inner(0 - x)
  end

  fn main() : Int do
    go(11)
  end
end
|}

let test_z3_in_key () =
  need_compiler ();
  (* The compiler's own lookup: MARCH_Z3, else the first z3 on PATH. *)
  let have_z3 = match Sys.getenv_opt "MARCH_Z3" with
    | Some p -> Sys.file_exists p
    | None -> Sys.command "command -v z3 > /dev/null 2>&1" = 0 in
  if not have_z3 then Alcotest.skip ();
  with_scratch ~source:z3_src @@ fun dir ->
  ok "the z3-less compile"
    (run ~dir ~env:[ "MARCH_Z3=" ^ Filename.concat dir "no-such-z3" ] ~tag:"noz3"
       [ "--compile"; "-o"; "out" ]);
  let rc, out, err = run ~dir ~tag:"z3" [ "--compile"; "-o"; "out" ] in
  let what s = Printf.sprintf "%s; rc=%d\n%s%s" s rc out err in
  Alcotest.(check bool) (what "the z3 compile is not served the z3-less verdict") true
    (rc <> 0 && contains err "refinement_violated")

let tests =
  [ Alcotest.test_case "MARCH_VERIFY_TIR_LEAKS after plain --verify-tir runs the leak check"
      `Slow test_verify_leaks;
    Alcotest.test_case "--emit-llvm after a plain compile writes the .ll"
      `Slow test_emit_llvm;
    Alcotest.test_case "--dump-provenance after a plain compile prints the table"
      `Slow test_dump_provenance;
    Alcotest.test_case "MARCH_TRMC_REPORT after a plain compile prints the report"
      `Slow test_env_report;
    Alcotest.test_case "z3 availability is in the key"
      `Slow test_z3_in_key;
  ]
