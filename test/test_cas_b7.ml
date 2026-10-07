(* The CAS quick wins of observability plan B7
   (specs/plans/incremental-codegen-cas-plan.md §17), each pinned end to end
   against the real `march` binary in a fresh project dir with a private HOME
   (the CAS store is <cwd>/.march/cas; ~/.cache/march is shared across
   worktrees).  Output is redirected to a file, never a pipe: a piped
   `--compile` can hang. *)

let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    s
  with Sys_error _ -> ""

let write_file path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

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

let with_scratch f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "march_cas_b7.%d.%d" (Unix.getpid ())
       (Hashtbl.hash (Unix.gettimeofday ()))) in
  Unix.mkdir dir 0o755;
  Unix.mkdir (Filename.concat dir "home") 0o755;
  Unix.mkdir (Filename.concat dir "home/.cache") 0o755;
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

(* [compile ~dir ?home entry]: `march --compile` of [entry] (relative to
   [dir], run from [dir]); returns its combined output.  [home] defaults to
   [dir]/home. *)
let compile ?home ?(extra = "") ~dir ~log entry =
  let home = match home with Some h -> h | None -> Filename.concat dir "home" in
  let cmd = Printf.sprintf "cd %s && env HOME=%s %s --compile %s -o out %s > %s 2>&1"
      (Filename.quote dir) (Filename.quote home) (Filename.quote compiler_exe)
      extra (Filename.quote entry) (Filename.quote log) in
  let rc = Sys.command cmd in
  let out = read_file log in
  if rc <> 0 then Alcotest.failf "compile failed (rc=%d):\n%s" rc out;
  out

let require_compiler () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe

(* ── B7.1: a warm build prints the warnings the cold one printed ────────── *)

let warn_src = {|mod B7Warn do
  needs IO.Console

  @[no_alloc(warn)]
  fn build(n : Int) : List(Int) do
    [n, n + 1]
  end

  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(List.length(build(3))))
  end
end
|}

(* The diagnostics part of a compile log: everything but the "compiled"
   line and clang's own chatter. *)
let diagnostics_of log =
  String.split_on_char '\n' log
  |> List.filter (fun l ->
      not (contains l "compiled ")
      && not (contains l "overriding the module target triple")
      && not (contains l "warning generated")
      && not (contains l "warnings generated"))
  |> String.concat "\n"

let test_replay_diagnostics_on_hit () =
  require_compiler ();
  with_scratch @@ fun dir ->
  write_file (Filename.concat dir "m.march") warn_src;
  let cold = compile ~dir ~log:(Filename.concat dir "cold.log") "m.march" in
  let warm = compile ~dir ~log:(Filename.concat dir "warm.log") "m.march" in
  let what s = Printf.sprintf "%s\ncold:\n%s\nwarm:\n%s" s cold warm in
  Alcotest.(check bool) (what "the cold build warns about the no_alloc contract") true
    (contains cold "[no_alloc]");
  Alcotest.(check bool) (what "the warm build is a source-level cache hit") true
    (contains warm "(cached)");
  Alcotest.(check string) (what "the warm build prints the same diagnostics")
    (diagnostics_of cold) (diagnostics_of warm)

(* ── B7.2: depend-mode source key ──────────────────────────────────────── *)

(* How a compile was satisfied, read off its --timings stamps: a
   source-level hit exits before parsing and prints none; a post-TIR hit
   prints stamps up to cas-hash and "(cached)". *)
type outcome = Source_hit | Post_tir_hit | Full

let outcome log =
  if not (contains log "[timings]") then Source_hit
  else if contains log "(cached)" then Post_tir_hit
  else Full

let show = function
  | Source_hit -> "source-level hit" | Post_tir_hit -> "post-TIR hit"
  | Full -> "full compile"

let run_out dir =
  let log = Filename.concat dir "run.log" in
  ignore (Sys.command (Printf.sprintf "%s > %s 2>&1"
      (Filename.quote (Filename.concat dir "out")) (Filename.quote log)));
  String.trim (read_file log)

let main_src = {|mod Main do
  needs IO.Console
  import Helpers
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(Helpers.twice(21)))
  end
end
|}

let test_depend_mode_unrelated_sibling () =
  require_compiler ();
  with_scratch @@ fun dir ->
  let w f s = write_file (Filename.concat dir f) s in
  w "main.march" main_src;
  w "helpers.march" "mod Helpers do\n  fn twice(n : Int) : Int do n * 2 end\nend\n";
  w "unrelated.march" "mod Unrelated do\n  fn noise() : Int do 1 end\nend\n";
  let step name =
    let log = compile ~extra:"--timings" ~dir ~log:(Filename.concat dir (name ^ ".log")) "main.march" in
    (outcome log, run_out dir, log) in
  let check name (o, out, log) want_o want_out =
    Alcotest.(check string) (name ^ ": how the build was satisfied\n" ^ log) (show want_o) (show o);
    Alcotest.(check string) (name ^ ": program output") want_out out in
  check "cold" (step "cold") Full "42";
  check "warm" (step "warm") Source_hit "42";
  (* The build never loads Unrelated (pruned: nothing names it).  Before
     depend mode its bytes were in the key, so this edit was a miss. *)
  w "unrelated.march" "mod Unrelated do\n  fn noise() : Int do 2 end\nend\n";
  check "unrelated sibling edited" (step "edit_unrelated") Source_hit "42";
  (* An `interface` is a global-effect declaration: the resolver now keeps
     the module, so the old load set is wrong and the key must fall back. *)
  w "unrelated.march"
    "mod Unrelated do\n  interface Noisy(a) do\n    fn noisy(x : a) : Int\n  end\nend\n";
  let (o, _, log) = step "global_effect" in
  Alcotest.(check bool) ("a sibling that gains a global-effect decl is not a source-level hit\n" ^ log)
    true (o <> Source_hit);
  (* A loaded file's bytes are in the key. *)
  w "helpers.march" "mod Helpers do\n  fn twice(n : Int) : Int do n * 2 + 1 end\nend\n";
  check "loaded sibling edited" (step "edit_helpers") Full "43"

let test_depend_mode_new_sibling_imported () =
  require_compiler ();
  with_scratch @@ fun dir ->
  let lib = Filename.concat dir "lib" and app = Filename.concat dir "app" in
  Unix.mkdir lib 0o755; Unix.mkdir app 0o755;
  write_file (Filename.concat lib "helpers.march")
    "mod Helpers do\n  fn twice(n : Int) : Int do n * 2 end\nend\n";
  write_file (Filename.concat app "main.march") main_src;
  let build name =
    let log = Filename.concat dir (name ^ ".log") in
    let cmd = Printf.sprintf
        "cd %s && env HOME=%s MARCH_LIB_PATH=%s %s --compile -o out main.march > %s 2>&1"
        (Filename.quote app) (Filename.quote (Filename.concat dir "home"))
        (Filename.quote lib) (Filename.quote compiler_exe) (Filename.quote log) in
    if Sys.command cmd <> 0 then Alcotest.failf "%s: compile failed:\n%s" name (read_file log);
    run_out app in
  Alcotest.(check string) "cold: Helpers comes from MARCH_LIB_PATH" "42" (build "cold");
  Alcotest.(check string) "warm" "42" (build "warm");
  (* A new sibling in the entry's own directory is found first and replaces
     the library's Helpers.  It is a NEW file in a walked directory, so the
     recorded load set is no longer trusted; a stale hit would print 42. *)
  write_file (Filename.concat app "helpers.march")
    "mod Helpers do\n  fn twice(n : Int) : Int do n * 3 end\nend\n";
  Alcotest.(check string) "a new sibling that is imported is picked up" "63" (build "new_sibling")

(* ── B7.3: write-through to the global store ───────────────────────────── *)

let test_global_store_write_through () =
  require_compiler ();
  with_scratch @@ fun dir ->
  let home = Filename.concat dir "home" in
  let mk name =
    let p = Filename.concat dir name in
    Unix.mkdir p 0o755;
    write_file (Filename.concat p "m.march") warn_src;
    p in
  let a = mk "project_a" and b = mk "project_b" in
  let cold = compile ~home ~extra:"--timings" ~dir:a ~log:(Filename.concat dir "a.log") "m.march" in
  Alcotest.(check string) ("project A builds from scratch\n" ^ cold) "full compile" (show (outcome cold));
  let gstore = Filename.concat home ".march/cas/artifacts-v2" in
  Alcotest.(check bool) "the build wrote through to ~/.march/cas/artifacts-v2" true
    (Sys.file_exists gstore && Array.length (Sys.readdir gstore) > 0);
  (* Project B has never built anything: no .march/cas of its own. *)
  let warm = compile ~home ~extra:"--timings" ~dir:b ~log:(Filename.concat dir "b.log") "m.march" in
  Alcotest.(check string) ("project B is a source-level hit from the global store\n" ^ warm)
    "source-level hit" (show (outcome warm));
  Alcotest.(check string) "and replays the same diagnostics"
    (diagnostics_of cold |> String.split_on_char '\n'
     |> List.filter (fun l -> not (contains l "[timings]")) |> String.concat "\n")
    (diagnostics_of warm);
  Alcotest.(check string) "project B's binary runs" "2" (run_out b);
  Alcotest.(check bool) "the hit warmed project B's local store" true
    (Sys.file_exists (Filename.concat b ".march/cas/artifacts-v2"))

let tests =
  [ Alcotest.test_case "B7.3: a build writes through to ~/.march/cas; another project hits it" `Slow
      test_global_store_write_through;
    Alcotest.test_case "B7.1: a cache hit replays the build's warnings" `Slow
      test_replay_diagnostics_on_hit;
    Alcotest.test_case "B7.2: editing an unloaded sibling is still a source-level hit" `Slow
      test_depend_mode_unrelated_sibling;
    Alcotest.test_case "B7.2: a new sibling that becomes imported is not a stale hit" `Slow
      test_depend_mode_new_sibling_imported;
  ]
