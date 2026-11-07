(** Golden test-failure reports (lib/errors/test_report.ml).

    Every [test/test_reports/<name>.march] is a test module whose tests all
    FAIL on purpose.  It is run as a user runs tests:

    - interpreted: [march test test_reports/<name>.march];
    - compiled: [march --compile --test --opt 0], then the binary (what
      [forge test] does);
    - JavaScript: [march --target js --test --opt 0], then [node] on the
      output (issue #1176), unless the fixture is in [js_unsupported] or
      [node] is not on PATH.

    From each run's output the failure blocks are taken (each `FAIL: "name"`
    line and the report under it, de-indented: the two runners frame them
    differently), and each must equal [<name>.expected] byte for byte.  So
    the suite pins the report text AND that the interpreter (OCaml,
    [Test_report]), a compiled binary (C, [march_assert_fail] in
    runtime/march_runtime.c; March, stdlib/check.march) and the JS output
    (march_assert_fail in runtime/march_runtime.mjs) print the same thing.
    Every run uses [MARCH_PROP_SEED=42].

    Regenerate after an intentional change (from the interpreted run; the
    compiled one must still match):
      [UPDATE_TEST_REPORTS=1 ./_build/default/test/run_test_reports.exe -e]
    then review [git diff test/test_reports/].

    Each program runs in a fresh temp directory as [test_reports/<file>]
    under a private [HOME], so headers carry the same path wherever the suite
    runs and no compile cache leaks in. *)

let update_mode = Sys.getenv_opt "UPDATE_TEST_REPORTS" = Some "1"

let project_root () =
  if Sys.file_exists "test/test_reports" && Sys.is_directory "test/test_reports" then "."
  else Test_helpers.march_project_root ()

let reports_dir () = Filename.concat (project_root ()) "test/test_reports"

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let write_file path s =
  let oc = open_out_bin path in
  output_string oc s;
  close_out oc

let rec rm_rf p =
  if Sys.file_exists p then
    if Sys.is_directory p then begin
      Array.iter (fun f -> rm_rf (Filename.concat p f)) (Sys.readdir p);
      Sys.rmdir p
    end else Sys.remove p

let private_home =
  lazy begin
    let d = Filename.temp_dir "march-test-reports-home" "" in
    Unix.mkdir (Filename.concat d ".cache") 0o755;
    at_exit (fun () -> try rm_rf d with _ -> ());
    d
  end

type outputs = { interp : string; interp_code : int;
                 build : string; build_code : int;
                 compiled : string; compiled_code : int;
                 js_build : string; js_build_code : int;
                 js : string; js_code : int }

(* Fixtures the JS target cannot build yet, each with the gap that stops it
   (specs/todos/2026-11-07-js-test-runner-gaps.md).  Remove an entry when its
   gap closes; the JS case then runs and must match the golden. *)
let js_unsupported = [
  "assert_records",
    "`to_string` on a record without a Show impl has no JS implementation";
  "panics",
    "Int `/` by zero is NaN on the JS target instead of a panic";
  "properties",
    "Check.all needs `__try_call` and `process_env`, which have no JS implementation";
]

let have_node = lazy (Sys.command "command -v node >/dev/null 2>&1" = 0)

let script ~dir ~rel =
  let exe = Filename.quote (Test_helpers.find_main_exe ()) in
  let home = Filename.quote (Lazy.force private_home) in
  Printf.sprintf
    "cd %s && export HOME=%s MARCH_PROP_SEED=42; \
     %s test %s > interp.out 2>&1; echo $? > interp.code; \
     %s --compile --test --opt 0 %s -o ./prog > build.out 2>&1; echo $? > build.code; \
     if [ -x ./prog ]; then ./prog > compiled.out 2>&1; echo $? > compiled.code; \
     else echo > compiled.out; echo -1 > compiled.code; fi; \
     echo > js_build.out; echo -1 > js_build.code; echo > js.out; echo -1 > js.code; \
     if %b; then \
       %s --target js --test --opt 0 %s -o ./prog.mjs > js_build.out 2>&1; echo $? > js_build.code; \
       if [ -f ./prog.mjs ]; then node ./prog.mjs > js.out 2>&1; echo $? > js.code; fi; \
     fi; true"
    (Filename.quote dir) home exe (Filename.quote rel) exe (Filename.quote rel)
    (Lazy.force have_node
     && not (List.mem_assoc (Filename.remove_extension (Filename.basename rel)) js_unsupported))
    exe (Filename.quote rel)

(* Run every fixture, interpreted and compiled, in parallel. *)
let run_all (names : string list) : (string, outputs) Hashtbl.t =
  let results = Hashtbl.create 8 in
  let running = Hashtbl.create 8 in
  List.iter (fun name ->
      let tmp = Filename.temp_dir "march-test-reports" "" in
      let d = Filename.concat tmp "test_reports" in
      Unix.mkdir d 0o755;
      write_file (Filename.concat d (name ^ ".march"))
        (read_file (Filename.concat (reports_dir ()) (name ^ ".march")));
      let rel = "test_reports/" ^ name ^ ".march" in
      let pid =
        Unix.create_process "/bin/sh" [| "/bin/sh"; "-c"; script ~dir:tmp ~rel |]
          Unix.stdin Unix.stdout Unix.stderr in
      Hashtbl.replace running pid (name, tmp))
    names;
  while Hashtbl.length running > 0 do
    let (pid, _) = Unix.wait () in
    match Hashtbl.find_opt running pid with
    | None -> ()
    | Some (name, tmp) ->
      Hashtbl.remove running pid;
      let f x = read_file (Filename.concat tmp x) in
      let code x = int_of_string (String.trim (f x)) in
      Hashtbl.replace results name
        { interp = f "interp.out"; interp_code = code "interp.code";
          build = f "build.out"; build_code = code "build.code";
          compiled = f "compiled.out"; compiled_code = code "compiled.code";
          js_build = f "js_build.out"; js_build_code = code "js_build.code";
          js = f "js.out"; js_code = code "js.code" };
      (try rm_rf tmp with _ -> ())
  done;
  results

(* ── The failure blocks of a run ─────────────────────────────────────── *)

let indent_of l =
  let n = String.length l in
  let i = ref 0 in
  while !i < n && l.[!i] = ' ' do incr i done;
  !i

let starts_with ~prefix s = String.starts_with ~prefix s

(* Each `FAIL: "name"` line with the report under it, de-indented, as
   `FAIL: "name"\n<report>\n\n`, in order; then the exit code. *)
let failure_blocks (out : string) (code : int) : string =
  let lines = Array.of_list (String.split_on_char '\n' out) in
  let n = Array.length lines in
  let buf = Buffer.create 1024 in
  let is_fail l = starts_with ~prefix:"FAIL: \"" (String.trim l) in
  let i = ref 0 in
  while !i < n do
    let l = lines.(!i) in
    if is_fail l then begin
      let k = indent_of l in
      Buffer.add_string buf (String.trim l);
      Buffer.add_char buf '\n';
      let body = ref [] in
      incr i;
      let stop = ref false in
      while !i < n && not !stop do
        let m = lines.(!i) in
        if m = "" then (body := "" :: !body; incr i)
        else if indent_of m > k then begin
          body := String.sub m (k + 2) (String.length m - k - 2) :: !body;
          incr i
        end else stop := true
      done;
      let rec drop_blank = function "" :: r -> drop_blank r | r -> r in
      List.iter (fun m -> Buffer.add_string buf m; Buffer.add_char buf '\n')
        (List.rev (drop_blank !body));
      Buffer.add_char buf '\n'
    end else incr i
  done;
  Printf.bprintf buf "exit %d\n" code;
  Buffer.contents buf

let has_ansi s = String.contains s '\027'

(* ── The cases ───────────────────────────────────────────────────────── *)

let fixtures () =
  Sys.readdir (reports_dir ())
  |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".march")
  |> List.map Filename.remove_extension
  |> List.sort compare

let results = lazy (run_all (fixtures ()))

let case name =
  let expected_path = Filename.concat (reports_dir ()) (name ^ ".expected") in
  let r () = Hashtbl.find (Lazy.force results) name in
  [ Alcotest.test_case (name ^ " interpreted") `Quick (fun () ->
        let r = r () in
        let got = failure_blocks r.interp r.interp_code in
        if update_mode then write_file expected_path got;
        let expected =
          if Sys.file_exists expected_path then read_file expected_path else "" in
        Alcotest.(check string) (name ^ ".expected (interpreted)") expected got);
    Alcotest.test_case (name ^ " compiled") `Quick (fun () ->
        let r = r () in
        if r.build_code <> 0 then
          Alcotest.failf "%s did not compile (exit %d):\n%s" name r.build_code r.build;
        let got = failure_blocks r.compiled r.compiled_code in
        let expected =
          if Sys.file_exists expected_path then read_file expected_path else "" in
        Alcotest.(check string) (name ^ ".expected (compiled)") expected got);
    Alcotest.test_case (name ^ " javascript") `Quick (fun () ->
        match List.assoc_opt name js_unsupported with
        | Some why -> Printf.printf "  SKIP (js_unsupported): %s\n" why
        | None when not (Lazy.force have_node) ->
          print_endline "  SKIP: node not on PATH"
        | None ->
          let r = r () in
          if r.js_build_code <> 0 then
            Alcotest.failf "%s did not build for JS (exit %d):\n%s" name
              r.js_build_code r.js_build;
          let got = failure_blocks r.js r.js_code in
          let expected =
            if Sys.file_exists expected_path then read_file expected_path else "" in
          Alcotest.(check string) (name ^ ".expected (javascript)") expected got);
    Alcotest.test_case (name ^ " no colour") `Quick (fun () ->
        let r = r () in
        let blocks = failure_blocks r.interp r.interp_code
                     ^ failure_blocks r.compiled r.compiled_code
                     ^ failure_blocks r.js r.js_code in
        Alcotest.(check bool) "no ANSI escapes in a report" false (has_ansi blocks)) ]

let () =
  Alcotest.run "test_reports"
    [ ("test_reports", List.concat_map case (fixtures ())) ]
