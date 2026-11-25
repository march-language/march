(* ocap phase 8a, Task 8 (specs/plans/2026-11-24-ocap-p8a-capture-sets-plan.md):
   the soundness oracle.

   Each program runs interpreted with MARCH_CAPTURE_ORACLE=1
   (bin/capture_oracle.ml): while a function value is running, every
   capability operation the run-time layer admits, done by it or by anything
   it calls or spawns, must be inside that value's inferred capture set.  A
   miss is an unsound rule in the capture pass.

   The oracle is only worth its green if it can go red: the last group runs
   the pass with one rule deliberately broken and requires a miss. *)

let compiler_exe = Test_captures.compiler_exe

let read_file path = In_channel.with_open_bin path In_channel.input_all

let find_dir (rel : string) : string =
  match List.find_opt Sys.file_exists [ rel; Filename.concat "test" rel; Filename.concat "../../../test" rel ] with
  | Some d when Filename.is_relative d -> Filename.concat (Sys.getcwd ()) d
  | Some d -> d
  | None -> Alcotest.failf "cannot find %s" rel

let march_files (dir : string) : string list =
  List.sort compare
    (List.filter (fun f -> Filename.check_suffix f ".march") (Array.to_list (Sys.readdir dir)))

type summary = { calls : int; ops : int; refused : int; checks : int; tracked : int; misses : int; text : string }

let field (line : string) (name : string) : int =
  match Test_captures.after line (name ^ "=") with
  | Some rest ->
    let n = ref 0 in
    (try String.iter (fun c -> if c >= '0' && c <= '9' then n := (!n * 10) + Char.code c - 48 else raise Exit) rest
     with Exit -> ());
    !n
  | None -> -1

(* Run shell commands, [jobs] at a time (MARCH_TEST_PROCS, default 4). *)
let run_parallel (cmds : string list) : unit =
  let work = Lazy.force Test_captures.work_dir in
  let d = Filename.temp_dir ~temp_dir:work "par" "" in
  List.iteri
    (fun i c -> Out_channel.with_open_bin (Filename.concat d (Printf.sprintf "%04d.sh" i)) (fun oc -> output_string oc c))
    cmds;
  let jobs = match Option.bind (Sys.getenv_opt "MARCH_TEST_PROCS") int_of_string_opt with Some n when n > 0 -> n | _ -> 4 in
  ignore (Sys.command (Printf.sprintf "cd %s && ls *.sh | xargs -P %d -n 1 sh" (Filename.quote d) jobs))

(* The command that runs [name] (copied beside its siblings into a scratch
   directory) under the oracle, and how to read its result afterwards. *)
let prepare ?unsound ~(dir : string) (name : string) : string * (unit -> summary) =
  let work = Lazy.force Test_captures.work_dir in
  let scratch = Filename.concat work ("oracle_" ^ Filename.basename dir) in
  if not (Sys.file_exists scratch) then begin
    ignore (Sys.command (Printf.sprintf "cp -R %s %s" (Filename.quote dir) (Filename.quote scratch)));
    ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote (Filename.concat scratch "deps"))))
  end;
  let src = read_file (Filename.concat dir name) in
  let grant =
    List.find_map
      (fun l -> Test_captures.after l "-- GRANT:")
      (String.split_on_char '\n' src)
  in
  (* `-- DEP: <package> <dir> [<grant>]` (test/run_cap_conformance.ml): the
     package's library root goes on MARCH_LIB_PATH and its grant, if any, in
     a grants file. *)
  let deps =
    List.filter_map
      (fun l ->
         match Test_captures.after l "-- DEP:" with
         | None -> None
         | Some rest -> (
           match String.split_on_char ' ' (String.trim rest) with
           | pkg :: d :: grant_words ->
             (* Beside the scratch directory, not in it: a library root
                inside the entry's own directory is a module conflict. *)
             let root = Filename.concat work "oracle_deps" in
             if not (Sys.file_exists root) then Sys.mkdir root 0o755;
             let dst = Filename.concat root (Filename.basename d) in
             if not (Sys.file_exists dst) then
               ignore
                 (Sys.command
                    (Printf.sprintf "cp -R %s %s" (Filename.quote (Filename.concat dir d)) (Filename.quote dst)));
             let grant = String.concat " " grant_words in
             Some (pkg, Unix.realpath dst, if grant = "none" then "" else grant)
           | _ -> None))
      (String.split_on_char '\n' src)
  in
  let deps_env =
    if deps = [] then "unset MARCH_LIB_PATH; unset MARCH_DEP_GRANTS;"
    else begin
      let granted = List.filter (fun (_, _, g) -> g <> "") deps in
      let grants_env =
        if granted = [] then "unset MARCH_DEP_GRANTS;"
        else begin
          let f = Filename.concat (Unix.realpath scratch) (name ^ ".dep-grants") in
          Out_channel.with_open_bin f (fun oc ->
              List.iteri
                (fun i (pkg, at, g) -> Printf.fprintf oc "%s\t%s\tforge.toml:%d\t%s\n" pkg at (i + 1) g)
                granted);
          Printf.sprintf "export MARCH_DEP_GRANTS=%s;" (Filename.quote f)
        end
      in
      Printf.sprintf "export MARCH_LIB_PATH=%s; %s"
        (Filename.quote (String.concat ":" (List.map (fun (_, at, _) -> at) deps)))
        grants_env
    end
  in
  let err = Filename.concat scratch (name ^ ".oracle.err") in
  let env =
    Printf.sprintf "export HOME=%s; %s %s %s export MARCH_CAPTURE_ORACLE=1;"
      (Filename.quote (Filename.concat work "home"))
      deps_env
      (match grant with
       | Some g -> Printf.sprintf "export MARCH_GRANT=%s;" (Filename.quote (String.trim g))
       | None -> "unset MARCH_GRANT;")
      (match unsound with
       | Some u -> Printf.sprintf "export MARCH_CAPTURE_ORACLE_UNSOUND=%s;" u
       | None -> "unset MARCH_CAPTURE_ORACLE_UNSOUND;")
  in
  (* `-- TEST` (test/run_cap_conformance.ml): a test build, for the programs
     that use `mock` (ocap phase 7). *)
  let test_build = List.exists (fun l -> String.trim l = "-- TEST") (String.split_on_char '\n' src) in
  let cmd =
    Printf.sprintf "cd %s && %s %s%s %s > /dev/null 2> %s" (Filename.quote scratch) env (Filename.quote compiler_exe)
      (if test_build then " --test" else "") (Filename.quote name) (Filename.quote err)
  in
  let read () =
    let text = read_file err in
    match
      List.find_opt
        (fun l -> Test_captures.after l "[capture-oracle] sites=" <> None)
        (String.split_on_char '\n' text)
    with
    | None -> Alcotest.failf "%s: the oracle printed no summary:\n%s" name text
    | Some l ->
      { calls = field l "calls"; ops = field l "ops"; refused = field l "refused"; checks = field l "checks";
        tracked = field l "tracked"; misses = field l "misses"; text }
  in
  (cmd, read)

let run ?unsound ~(dir : string) (name : string) : summary =
  let cmd, read = prepare ?unsound ~dir name in
  ignore (Sys.command cmd);
  read ()

let misses_of (s : summary) : string =
  String.concat "\n"
    (List.filter (fun l -> Test_captures.after l "MISS" <> None) (String.split_on_char '\n' s.text))

(* The fixtures written for the oracle: each must do real work under it. *)
let test_fixture (name : string) () =
  let s = run ~dir:(find_dir "captures/oracle") name in
  if s.misses <> 0 then Alcotest.failf "%s: %d miss(es):\n%s" name s.misses (misses_of s);
  Alcotest.(check bool) (name ^ ": function values ran") true (s.calls > 0);
  (* Against a set the pass tracks: a check against `not tracked` proves nothing. *)
  Alcotest.(check bool) (name ^ ": operations were checked against tracked sets") true (s.tracked > 0)

(* The run-time authority conformance corpus (ocap phase 4 to 6). *)
let test_conformance () =
  let dir = find_dir "cap_conformance" in
  let ran = ref 0 and checks = ref 0 and calls = ref 0 and tracked = ref 0 in
  let bad = ref [] in
  let jobs = List.map (fun name -> (name, prepare ~dir name)) (march_files dir) in
  run_parallel (List.map (fun (_, (cmd, _)) -> cmd) jobs);
  List.iter
    (fun (name, (_, read)) ->
       let s = read () in
       incr ran;
       checks := !checks + s.checks;
       tracked := !tracked + s.tracked;
       calls := !calls + s.calls;
       if s.misses <> 0 then bad := Printf.sprintf "%s:\n%s" name (misses_of s) :: !bad)
    jobs;
  if !bad <> [] then Alcotest.failf "unsound capture sets:\n%s" (String.concat "\n" (List.rev !bad));
  Printf.printf
    "capture oracle over cap_conformance: %d programs, %d function-value calls, %d checks (%d against a tracked set), 0 misses\n%!"
    !ran !calls !checks !tracked;
  Alcotest.(check bool) "the corpus exercised function values" true (!ran > 60 && !checks > 0)

(* One broken rule, one fixture that must catch it. *)
let test_red (unsound : string) (fixture : string) () =
  let s = run ~unsound ~dir:(find_dir "captures/oracle") fixture in
  if s.misses = 0 then
    Alcotest.failf "with the rule `%s` removed the oracle still passed %s: it cannot be trusted" unsound fixture

(* ── the sweep: the pass finishes, on everything ────────────────────────── *)

(* `march --check` on [file] with the pass forced on ([mode]: "1" for the
   file's own reach, "all" for every stdlib function too).  The exit code,
   the output, and the pass's own time in seconds. *)
let forced_cmd ~(mode : string) (file : string) : string * (unit -> int * string * float) =
  let work = Lazy.force Test_captures.work_dir in
  (* Its own directory: the check artifact cache lives in the working
     directory, and a hit would skip the pass. *)
  let scratch = Filename.temp_dir ~temp_dir:work "sweep" "" in
  let out = Filename.concat scratch "out" in
  let cmd =
    Printf.sprintf "cd %s && HOME=%s MARCH_CAPTURES=%s %s --check --timings %s > %s 2>&1; echo $? > %s"
      (Filename.quote scratch)
      (Filename.quote (Filename.concat work "home"))
      mode (Filename.quote compiler_exe) (Filename.quote file) (Filename.quote out)
      (Filename.quote (out ^ ".rc"))
  in
  let read () =
  let rc = match int_of_string_opt (String.trim (read_file (out ^ ".rc"))) with Some n -> n | None -> -1 in
  let text = read_file out in
  let stamp label =
    List.find_map
      (fun l ->
         if Test_captures.after l "[timings]" <> None && Test_captures.after l ("s  " ^ label) <> None then
           Scanf.sscanf_opt (String.trim l) "[timings] %fs" (fun t -> t)
         else None)
      (String.split_on_char '\n' text)
  in
  let pass = match stamp "captures", stamp "typecheck" with Some c, Some t -> c -. t | _ -> -1.0 in
  (rc, text, pass)
  in
  (cmd, read)

let forced ~(mode : string) (file : string) : int * string * float =
  let cmd, read = forced_cmd ~mode file in
  ignore (Sys.command cmd);
  read ()

let crashed (text : string) : bool =
  List.exists
    (fun needle -> Test_captures.after text needle <> None)
    [ "Fatal error"; "Stack overflow"; "Stack_overflow"; "Not_found"; "Invalid_argument"; "Assert_failure";
      "Match_failure"; "internal compiler error" ]

let test_sweep_stdlib () =
  let work = Lazy.force Test_captures.work_dir in
  let file = Filename.concat work "sweep_hello.march" in
  Out_channel.with_open_bin file (fun oc ->
      output_string oc "mod SweepHello do\n  needs IO.Console\n  fn main() do println(\"hello\") end\nend\n");
  let rc, text, pass = forced ~mode:"all" file in
  if rc <> 0 || crashed text then Alcotest.failf "the pass failed over the stdlib (exit %d):\n%s" rc text;
  Printf.printf "capture pass over every stdlib function: %.3fs\n%!" pass;
  Alcotest.(check bool) "the pass ran" true (pass >= 0.0);
  Alcotest.(check bool) "within 10 seconds" true (pass < 10.0)

let test_sweep_programs () =
  let dirs = [ find_dir "../bench"; find_dir "../examples" ] in
  let n = ref 0 and total = ref 0.0 and worst = ref (0.0, "") in
  let jobs =
    List.concat_map
      (fun dir -> List.map (fun name -> (name, forced_cmd ~mode:"1" (Filename.concat dir name))) (march_files dir))
      dirs
  in
  run_parallel (List.map (fun (_, (cmd, _)) -> cmd) jobs);
  List.iter
    (fun _dir ->
       List.iter
         (fun (name, (_, read)) ->
            let rc, text, pass = read () in
            (* A program the checker rejects is still a program the pass must
               survive: only a crash or a hang fails here. *)
            if crashed text || rc > 1 then Alcotest.failf "%s: the pass crashed (exit %d):\n%s" name rc text;
            if pass > 10.0 then Alcotest.failf "%s: the pass took %.1fs" name pass;
            if pass >= 0.0 then begin
              incr n;
              total := !total +. pass;
              if pass > fst !worst then worst := (pass, name)
            end)
         jobs)
    [ () ];
  Printf.printf "capture pass over %d bench and example programs: %.3fs in all, worst %.3fs (%s)\n%!" !n !total
    (fst !worst) (snd !worst);
  Alcotest.(check bool) "programs were swept" true (!n > 50)

let tests =
  let fixtures = march_files (find_dir "captures/oracle") in
  [ ( "capture_oracle",
      List.map (fun f -> Alcotest.test_case f `Quick (test_fixture f)) fixtures
      @ [ Alcotest.test_case "the conformance corpus" `Slow test_conformance;
          Alcotest.test_case "red: a called value's set dropped" `Quick
            (test_red "drop_callee_effect" "capture_laundered.march");
          Alcotest.test_case "red: arguments do not flow to parameters" `Quick
            (test_red "drop_arg_flow" "capture_laundered.march");
          Alcotest.test_case "red: arriving values narrowed by a restrict" `Quick
            (test_red "narrow_values" "capture_restrict_mixed.march") ] );
    ( "capture_sweep",
      [ Alcotest.test_case "every stdlib function" `Quick test_sweep_stdlib;
        Alcotest.test_case "bench and examples" `Slow test_sweep_programs ] ) ]
