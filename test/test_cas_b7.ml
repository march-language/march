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

let tests =
  [ Alcotest.test_case "B7.1: a cache hit replays the build's warnings" `Slow
      test_replay_diagnostics_on_hit;
  ]
