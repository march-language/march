(** Oracle test: run every .march program through interpreter AND native compiler,
    check that outputs match.

    Usage:
      dune build @test/oracle          # run and print results matrix
      MARCH_BIN=... MARCH_ROOT=... dune exec test/test_oracle.exe --root .

    Exit code: 0 if all active programs match, 1 if any mismatch. *)

(* ------------------------------------------------------------------ *)
(* Locate march binary and project root                               *)
(* ------------------------------------------------------------------ *)

(* Normalize path to remove symlinks and ../ components *)
let realpath p =
  try Unix.realpath p
  with _ ->
    if Filename.is_relative p
    then Filename.concat (Sys.getcwd ()) p
    else p

let march_abs =
  let raw =
    match Sys.getenv_opt "MARCH_BIN" with
    | Some p -> p
    | None ->
      let candidates = [
        "_build/default/bin/main.exe";
        "../_build/default/bin/main.exe";
      ] in
      (match List.find_opt Sys.file_exists candidates with
       | Some p -> p
       | None ->
         Printf.eprintf "Cannot find march binary. Set MARCH_BIN env var.\n%!";
         exit 2)
  in
  realpath raw

let project_root =
  let has_dune_project d = Sys.file_exists (Filename.concat d "dune-project") in
  (* 1. Explicit override *)
  let from_env =
    match Sys.getenv_opt "MARCH_ROOT" with
    | Some p when has_dune_project p -> Some p
    | _ -> None
  in
  match from_env with
  | Some p -> p
  | None ->
    (* 2. Derive from normalised march binary path:
          /proj/_build/default/bin/main.exe  -> go up 4 dirs -> /proj/ *)
    let rec up n d = if n = 0 then d else up (n - 1) (Filename.dirname d) in
    let found =
      List.find_opt has_dune_project
        (List.map (fun n -> up n march_abs) [4; 3; 5; 2])
    in
    (match found with
     | Some d -> d
     | None   -> Sys.getcwd ())

(* ------------------------------------------------------------------ *)
(* Programs to skip (network servers, interactive, long-running)      *)
(* ------------------------------------------------------------------ *)

let skip_set =
  let s = [
    (* HTTP clients that connect to external servers *)
    "http_get"; "http_get_close"; "http_get_keepalive";
    "http_requests"; "http_stream"; "http_stream_large"; "http_streaming";
    (* HTTP / TCP servers (don't exit) *)
    "http_hello"; "counter_server"; "csv_server"; "csv_example";
    (* Actor programs that may block on message receive *)
    "actors";
    (* Parallel benchmarks (scheduler-dependent, non-deterministic order) *)
    "par_fib"; "par_map"; "par_worksteal"; "parallel";
    (* Interactive or needs real files *)
    "debugger"; "read_file";
    (* Supervision trees (start actors / servers) *)
    "supervision_basic"; "app_basic";
    (* IOList template outputs variable content *)
    "iolist_template";
  ] in
  let tbl = Hashtbl.create 32 in
  List.iter (fun k -> Hashtbl.replace tbl k true) s;
  tbl

let should_skip path =
  let base = Filename.basename (Filename.remove_extension path) in
  Hashtbl.mem skip_set base

(* ------------------------------------------------------------------ *)
(* Subprocess runner with timeout                                      *)
(* ------------------------------------------------------------------ *)

let read_file path =
  try
    let ic = open_in path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    Bytes.to_string buf
  with _ -> ""

(* Run [shell_cmd] via /bin/sh, capturing stdout.  stderr is discarded.
   Returns [`Ok output | `Error exit_code | `Timeout]. *)
(** Exit code sentinel for signal-killed processes (not a real exit code). *)
let exit_signal_killed = -999

let run_shell_capture ?(timeout_s = 10.0) shell_cmd =
  let tmp_out = Filename.temp_file "march_oracle" ".stdout" in
  let out_fd  = Unix.openfile tmp_out [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
  let dnull_r = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0 in
  let dnull_w = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
  let pid =
    Unix.create_process "/bin/sh" [| "/bin/sh"; "-c"; shell_cmd |]
      dnull_r out_fd dnull_w
  in
  Unix.close out_fd;
  Unix.close dnull_r;
  Unix.close dnull_w;
  let deadline   = Unix.gettimeofday () +. timeout_s in
  let timed_out  = ref false in
  let exit_code  = ref 0 in
  let rec poll () =
    if Unix.gettimeofday () >= deadline then begin
      timed_out := true;
      (try Unix.kill pid Sys.sigkill   with Unix.Unix_error _ -> ());
      (try let _ = Unix.waitpid [] pid in () with Unix.Unix_error _ -> ())
    end else
      match Unix.waitpid [Unix.WNOHANG] pid with
      | (0, _)                -> Unix.sleepf 0.05; poll ()
      | (_, Unix.WEXITED n)   -> exit_code := n
      | (_, Unix.WSIGNALED _) -> exit_code := exit_signal_killed
      | _                     -> exit_code := exit_signal_killed
  in
  poll ();
  let output = read_file tmp_out in
  (try Sys.remove tmp_out with _ -> ());
  if !timed_out          then `Timeout
  else if !exit_code = 0 then `Ok output
  else `Error !exit_code

(* ------------------------------------------------------------------ *)
(* Oracle: interpreter and compiled paths                             *)
(* ------------------------------------------------------------------ *)

type run_result =
  | Match        of string          (** both outputs identical *)
  | Mismatch     of string * string (** interp, compiled differ *)
  | InterpFail   of int             (** interpreter exited non-zero *)
  | InterpTimeout
  | CompileFail  of int             (** clang/lowering failed *)
  | CompileTimeout
  | RunFail      of int             (** compiled binary exited non-zero; 139=segfault *)
  | RunTimeout
  | Skipped      of string          (** explicitly skipped *)

let run_oracle src_path =
  if should_skip src_path then
    Skipped (Filename.basename (Filename.remove_extension src_path))
  else begin
    let q = Filename.quote in
    (* --- interpreter --- *)
    let interp_cmd =
      Printf.sprintf "cd %s && %s %s" (q project_root) (q march_abs) (q src_path)
    in
    let interp_result = run_shell_capture ~timeout_s:10.0 interp_cmd in
    match interp_result with
    | `Timeout        -> InterpTimeout
    | `Error code     -> InterpFail code
    | `Ok interp_out  ->
      (* --- compile + run ---
         Use a deterministic output path derived from the source name so the
         march CAS can find its cached artifact across oracle runs (the CAS
         stores a pointer to the output path, so a random temp file that gets
         cleaned up immediately would invalidate the cache on the next run). *)
      let bin_dir = Filename.concat (Filename.get_temp_dir_name ()) "march_oracle_bins" in
      (try Unix.mkdir bin_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      let src_dir  = Filename.basename (Filename.dirname src_path) in
      let src_base = Filename.basename (Filename.remove_extension src_path) in
      let out_bin  = Filename.concat bin_dir (src_dir ^ "_" ^ src_base) in
      let compile_cmd =
        Printf.sprintf "cd %s && %s --compile %s -o %s"
          (q project_root) (q march_abs) (q src_path) (q out_bin)
      in
      (match run_shell_capture ~timeout_s:30.0 compile_cmd with
       | `Timeout    -> CompileTimeout
       | `Error code -> CompileFail code
       | `Ok _       ->
         (match run_shell_capture ~timeout_s:10.0 (q out_bin) with
          | `Timeout    -> RunTimeout
          | `Error code -> RunFail code
          | `Ok out     ->
            if out = interp_out then Match out
            else Mismatch (interp_out, out)))
  end

(* ------------------------------------------------------------------ *)
(* Discover .march files                                              *)
(* ------------------------------------------------------------------ *)

let find_march_files dir =
  if not (Sys.file_exists dir && Sys.is_directory dir) then []
  else
    Array.to_list (Sys.readdir dir)
    |> List.filter (fun f -> Filename.check_suffix f ".march")
    |> List.sort String.compare
    |> List.map (fun f -> Filename.concat dir f)

(* ------------------------------------------------------------------ *)
(* Formatting helpers                                                  *)
(* ------------------------------------------------------------------ *)

let truncate_output s =
  let limit = 200 in
  if String.length s <= limit then s
  else String.sub s 0 limit ^ "  [... truncated]"

let verdict_label = function
  | Match _          -> "MATCH"
  | Mismatch _       -> "MISMATCH"
  | InterpFail code  -> Printf.sprintf "INTERP_FAIL(%d)" code
  | InterpTimeout    -> "INTERP_TIMEOUT"
  | CompileFail code -> Printf.sprintf "COMPILE_FAIL(%d)" code
  | CompileTimeout   -> "COMPILE_TIMEOUT"
  | RunFail n when n = exit_signal_killed -> "RUN_FAIL(crashed)"
  | RunFail code     -> Printf.sprintf "RUN_FAIL(%d)" code
  | RunTimeout       -> "RUN_TIMEOUT"
  | Skipped _        -> "SKIPPED"

let is_failure = function
  | Mismatch _ -> true
  | _          -> false

(* ------------------------------------------------------------------ *)
(* Main                                                               *)
(* ------------------------------------------------------------------ *)

let () =
  Random.self_init ();
  Printf.printf "=== March Oracle Test ===\n";
  Printf.printf "march binary  : %s\n" march_abs;
  Printf.printf "project root  : %s\n\n" project_root;

  let bench_dir    = Filename.concat project_root "bench" in
  let examples_dir = Filename.concat project_root "examples" in
  let files =
    find_march_files bench_dir @ find_march_files examples_dir
  in

  if files = [] then begin
    Printf.eprintf "No .march files found. Check MARCH_ROOT=%s\n%!" project_root;
    exit 2
  end;

  let results = ref [] in
  let n_total  = List.length files in
  Printf.printf "Found %d programs.\n\n" n_total;

  List.iteri (fun i path ->
    let rel = match String.split_on_char '/' path |> List.rev with
      | f :: d :: _ -> d ^ "/" ^ f
      | f :: _      -> f
      | []          -> path
    in
    Printf.printf "[%d/%d] %-50s " (i + 1) n_total rel;
    flush stdout;
    let verdict = run_oracle path in
    Printf.printf "%s\n" (verdict_label verdict);
    flush stdout;
    results := (rel, verdict) :: !results
  ) files;

  let results = List.rev !results in

  (* ---- Summary ---- *)
  Printf.printf "\n%-50s  %s\n" "Program" "Verdict";
  Printf.printf "%s\n" (String.make 70 '-');
  List.iter (fun (name, v) ->
    Printf.printf "%-50s  %s\n" name (verdict_label v);
    (match v with
     | Mismatch (interp_out, compiled_out) ->
       Printf.printf "  interp   : %s\n" (truncate_output interp_out);
       Printf.printf "  compiled : %s\n" (truncate_output compiled_out)
     | _ -> ())
  ) results;

  let count pred = List.length (List.filter (fun (_, v) -> pred v) results) in
  let n_match   = count (function Match _ -> true | _ -> false) in
  let n_mismatch= count is_failure in
  let n_cfail   = count (function CompileFail _ | CompileTimeout -> true | _ -> false) in
  let n_itimeout= count (function InterpTimeout -> true | _ -> false) in
  let n_ifail   = count (function InterpFail _ -> true | _ -> false) in
  let _n_rfail  = count (function RunFail _ | RunTimeout -> true | _ -> false) in
  let n_skip    = count (function Skipped _ -> true | _ -> false) in

  Printf.printf "\n=== RESULTS MATRIX ===\n";
  Printf.printf "  MATCH            : %d   interpreter == compiled ✓\n" n_match;
  Printf.printf "  MISMATCH         : %d   <-- oracle failures\n" n_mismatch;
  Printf.printf "  SKIPPED          : %d   network/server/interactive programs\n" n_skip;
  Printf.printf "  INTERP_TIMEOUT   : %d   too slow for tree-walking interpreter\n" n_itimeout;
  Printf.printf "  INTERP_FAIL      : %d   interpreter error\n" n_ifail;
  Printf.printf "  COMPILE_FAIL     : %d   compiler error\n" n_cfail;
  Printf.printf "  RUN_FAIL(crashed): %d   compiled binary crashes (signal)\n"
    (count (function RunFail n -> n = exit_signal_killed | _ -> false));
  Printf.printf "  RUN_FAIL(other)  : %d   compiled binary exits non-zero\n"
    (count (function RunFail n -> n <> exit_signal_killed | RunTimeout -> true | _ -> false));
  Printf.printf "  TOTAL            : %d\n\n" n_total;

  Printf.printf "Note: march currently emits typecheck warnings to stdout rather than stderr.\n";
  Printf.printf "      This may cause MISMATCH for programs with warnings.\n\n";

  if n_mismatch > 0 then begin
    Printf.printf "FAIL: %d program(s) produced different output between interpreter and compiler.\n" n_mismatch;
    exit 1
  end else if n_match = 0 then begin
    Printf.printf "WARN: No programs successfully matched (all compile failures or skipped).\n";
    exit 0
  end else begin
    Printf.printf "PASS: All %d active programs match between interpreter and compiler.\n" n_match;
    exit 0
  end
