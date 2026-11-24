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
  | Some d -> d
  | None -> Alcotest.failf "cannot find %s" rel

let march_files (dir : string) : string list =
  List.sort compare
    (List.filter (fun f -> Filename.check_suffix f ".march") (Array.to_list (Sys.readdir dir)))

type summary = { calls : int; ops : int; refused : int; checks : int; misses : int; text : string }

let field (line : string) (name : string) : int =
  match Test_captures.after line (name ^ "=") with
  | Some rest ->
    let n = ref 0 in
    (try String.iter (fun c -> if c >= '0' && c <= '9' then n := (!n * 10) + Char.code c - 48 else raise Exit) rest
     with Exit -> ());
    !n
  | None -> -1

(* Run [file] (copied beside its siblings into a scratch directory) under
   the oracle. *)
let run ?unsound ~(dir : string) (name : string) : summary =
  let work = Lazy.force Test_captures.work_dir in
  let scratch = Filename.concat work ("oracle_" ^ Filename.basename dir) in
  if not (Sys.file_exists scratch) then
    ignore (Sys.command (Printf.sprintf "cp -R %s %s" (Filename.quote dir) (Filename.quote scratch)));
  let src = read_file (Filename.concat dir name) in
  let grant =
    List.find_map
      (fun l -> Test_captures.after l "-- GRANT:")
      (String.split_on_char '\n' src)
  in
  let err = Filename.concat scratch (name ^ ".oracle.err") in
  let env =
    Printf.sprintf "export HOME=%s; %s %s export MARCH_CAPTURE_ORACLE=1;"
      (Filename.quote (Filename.concat work "home"))
      (match grant with
       | Some g -> Printf.sprintf "export MARCH_GRANT=%s;" (Filename.quote (String.trim g))
       | None -> "unset MARCH_GRANT;")
      (match unsound with
       | Some u -> Printf.sprintf "export MARCH_CAPTURE_ORACLE_UNSOUND=%s;" u
       | None -> "unset MARCH_CAPTURE_ORACLE_UNSOUND;")
  in
  ignore
    (Sys.command
       (Printf.sprintf "cd %s && %s %s %s > /dev/null 2> %s" (Filename.quote scratch) env (Filename.quote compiler_exe)
          (Filename.quote name) (Filename.quote err)));
  let text = read_file err in
  match
    List.find_opt
      (fun l -> Test_captures.after l "[capture-oracle] sites=" <> None)
      (String.split_on_char '\n' text)
  with
  | None -> Alcotest.failf "%s: the oracle printed no summary:\n%s" name text
  | Some l ->
    { calls = field l "calls"; ops = field l "ops"; refused = field l "refused"; checks = field l "checks";
      misses = field l "misses"; text }

let misses_of (s : summary) : string =
  String.concat "\n"
    (List.filter (fun l -> Test_captures.after l "MISS" <> None) (String.split_on_char '\n' s.text))

(* The fixtures written for the oracle: each must do real work under it. *)
let test_fixture (name : string) () =
  let s = run ~dir:(find_dir "captures/oracle") name in
  if s.misses <> 0 then Alcotest.failf "%s: %d miss(es):\n%s" name s.misses (misses_of s);
  Alcotest.(check bool) (name ^ ": function values ran") true (s.calls > 0);
  Alcotest.(check bool) (name ^ ": operations were checked against them") true (s.checks > 0)

(* The run-time authority conformance corpus (ocap phase 4 to 6). *)
let test_conformance () =
  let dir = find_dir "cap_conformance" in
  let ran = ref 0 and checks = ref 0 and calls = ref 0 in
  let bad = ref [] in
  List.iter
    (fun name ->
       let src = read_file (Filename.concat dir name) in
       (* A fixture with dependency packages needs the grants channel the
          conformance driver sets up; the interpreter run here has none. *)
       if Test_captures.after src "-- DEP:" = None then begin
         let s = run ~dir name in
         incr ran;
         checks := !checks + s.checks;
         calls := !calls + s.calls;
         if s.misses <> 0 then bad := Printf.sprintf "%s:\n%s" name (misses_of s) :: !bad
       end)
    (march_files dir);
  if !bad <> [] then Alcotest.failf "unsound capture sets:\n%s" (String.concat "\n" (List.rev !bad));
  Printf.printf "capture oracle over cap_conformance: %d programs, %d function-value calls, %d checks, 0 misses\n%!"
    !ran !calls !checks;
  Alcotest.(check bool) "the corpus exercised function values" true (!ran > 40 && !checks > 0)

(* One broken rule, one fixture that must catch it. *)
let test_red (unsound : string) (fixture : string) () =
  let s = run ~unsound ~dir:(find_dir "captures/oracle") fixture in
  if s.misses = 0 then
    Alcotest.failf "with the rule `%s` removed the oracle still passed %s: it cannot be trusted" unsound fixture

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
            (test_red "narrow_values" "capture_restrict_mixed.march") ] ) ]
