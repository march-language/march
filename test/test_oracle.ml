(** Oracle test: run every .march program through interpreter AND native compiler,
    check that outputs match.

    Usage:
      dune build @test/oracle          # run and print results matrix
      MARCH_BIN=... MARCH_ROOT=... dune exec test/test_oracle.exe --root .

    Exit code: 0 if all active un-triaged programs match/are accounted for,
    1 if any un-triaged divergence is found.

    --- Corpus scope (deliberate, not an oversight) ---------------------
    This sweep enumerates the top-level `.march` files directly under
    `bench/`, `examples/`, and `specs/lang/golden/` — real, runnable,
    print-driven programs whose stdout is a meaningful ground truth to diff.
    (`specs/lang/golden/` is the Core March language-spec golden corpus,
    `specs/lang/core-march.md` §5 — same criteria, so it rides the same
    sweep and its spec anchor runs in CI.) It deliberately does NOT
    walk `test/` (189+ files there are compiler-internal fixtures: single-
    feature snippets, deliberately-erroring negative cases, and partial
    fragments never meant to run standalone — sweeping them would drown
    the signal in triage noise, not raise it) and does NOT extract stdlib
    doctests (the `march>` REPL-transcript comments embedded in stdlib
    modules need a dedicated extractor, since they are not whole `.march`
    programs). See `specs/todos.md` for the tracked follow-up to extend
    the corpus to a triaged `test/` subset plus a doctest extractor.

    --- Divergence classification (the core contract) -------------------
    A DIVERGENCE is any of: Mismatch, RunFail(signal-crash), or
    CompileFail(3) (exit 3 = internal compiler error / ICE, the Phase-1
    ICE signal) — i.e. any case where the interpreter produced ground
    truth (exited 0) but the compiled backend disagrees or dies badly.
    A divergence is a FAILURE unless the program is listed in
    [known_divergence] below, in which case it is reported loudly as
    KNOWN_DIVERGENCE but does not fail the sweep. Everything else
    (InterpFail, InterpTimeout, CompileTimeout, CompileFail(non-3),
    RunFail(clean nonzero), RunTimeout, Skipped) is a non-failure: either
    there is no interpreter ground truth to compare against, or the
    program is an explicitly triaged, legitimately-skipped case. Nothing
    is silently dropped — every bucket is counted and printed in the
    results matrix (loud-skip doctrine). *)

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
(* Nondeterministic allowlist: programs that are legitimately          *)
(* non-comparable (network I/O, actor scheduling, wall-clock,          *)
(* interactive input) — SKIPPED, not failures, one-line reason each.   *)
(* ------------------------------------------------------------------ *)

let nondeterministic_allowlist =
  let s = [
    (* HTTP clients that connect to external servers *)
    "http_get"; "http_get_close"; "http_get_keepalive";
    "http_requests"; "http_stream"; "http_stream_large"; "http_streaming";
    (* HTTP / TCP servers (don't exit on their own) *)
    "http_hello"; "counter_server"; "csv_server"; "csv_example";
    (* Actor programs that may block on message receive *)
    "actors";
    (* Parallel benchmarks (scheduler-dependent, non-deterministic order) *)
    "par_fib"; "par_map"; "par_worksteal"; "parallel";
    (* Interactive or needs real files *)
    "debugger"; "read_file";
    (* Supervision trees (start actors / servers; scheduler-order-dependent) *)
    "supervision_basic"; "app_basic";
    (* Supervision/actor demo: pids and restart ordering vary across runs *)
    "supervision_strategies";
    (* IOList template outputs variable content *)
    "iolist_template";
    (* HTTP client requiring a WASM-only fetch shim; compiled link fails
       cleanly (unsupported outside the browser target), not comparable *)
    "http_test";
  ] in
  let tbl = Hashtbl.create 32 in
  List.iter (fun k -> Hashtbl.replace tbl k true) s;
  tbl

let should_skip path =
  let base = Filename.basename (Filename.remove_extension path) in
  Hashtbl.mem nondeterministic_allowlist base

(* ------------------------------------------------------------------ *)
(* Known divergence list: currently-open compiler bugs this sweep      *)
(* reproduces. A program here that diverges is reported as             *)
(* KNOWN_DIVERGENCE (visible, not a failure). A program here that      *)
(* UNEXPECTEDLY matches is reported as a [WARN] (stale entry — prune   *)
(* it once the underlying bug is confirmed fixed).                     *)
(* ------------------------------------------------------------------ *)

let known_divergence =
  [
    (* to_string()/println() on a container falls through to the runtime's
       generic "#<tag:N>" fallback when compiled instead of dispatching
       through the Show interface like the interpreter does.
       specs/todos.md P1: "`to_string` on any non-primitive type (`List`,
       `Option`, `Result`, tuples, custom ADTs) is broken compiled". *)
    "hello", "to_string-on-container #<tag:N> (specs/todos.md: \"to_string on any non-primitive type\")";
    "list_lib", "to_string-on-container #<tag:N> (specs/todos.md: \"to_string on any non-primitive type\")";

    (* Sort family: compiled-only RC-underflow/misclassification crash
       family in the Sort module's merge/heap internals. Pre-existing,
       independent of every wave that has re-checked it.
       specs/progress.md: "heapsort RC underflow". *)
    "alphadev_sort", "sort RC-underflow crash family (specs/progress.md: \"heapsort RC underflow\")";
    "heapsort", "sort RC-underflow crash family (specs/progress.md: \"heapsort RC underflow\")";
    "mergesort", "sort RC-underflow crash family (specs/progress.md: \"heapsort RC underflow\")";
    "sort_nearly_sorted", "sort RC-underflow crash family (specs/progress.md: \"heapsort RC underflow\")";
    "timsort", "sort RC-underflow crash family (specs/progress.md: \"heapsort RC underflow\")";

    (* DataFrame groupby+agg: a DISTINCT compiled-only RC-misclassification
       crash (EXC_BAD_ACCESS in march_incrc, called from Stats.mean via
       DataFrame.eval_agg/apply_group_by) — same bug CLASS as the sort
       family (a corrupted/tagged-immediate value dereferenced as a heap
       pointer) but a different call site; newly filed by this sweep.
       specs/todos.md P0: "DataFrame.group_by + Stats.mean: compiled-only
       RC-misclassification SIGSEGV". *)
    "dataframe_bench", "DataFrame group_by/Stats.mean RC-misclassification SIGSEGV (specs/todos.md, filed by this sweep)";

    (* Monomorphization-limit ICE: compiling hits mono.ml's polymorphic-
       recursion specialization-count guard on a shape that is not
       actually polymorphic-recursive in the source.
       specs/todos.md P0: "Monomorphization limit reached compiling a
       self-recursive nested closure". *)
    "stats_basic", "Monomorphization limit reached ICE, exit 3 (specs/todos.md: \"Monomorphization limit reached compiling a self-recursive nested closure\"; stats_basic is a newly-confirmed trigger of the same P0)";
  ]

let known_divergence_tbl =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (k, reason) -> Hashtbl.replace tbl k reason) known_divergence;
  tbl

let oracle_cross_mode = Sys.getenv_opt "MARCH_ORACLE_CROSS" <> None

(* known_divergence stays ACTIVE in cross mode: the cross executor runs the
   NATIVE-compiled binary as its reference, so a known compiled crash (sort
   family, dataframe) reproduces in that native step and must still be masked —
   it is not a cross-compilation signal.  What cross mode DOES suppress is the
   "stale entry" warning (below): an interp-vs-compiled divergence like the
   to_string `#<tag:N>` bug produces identical output native and cross, so it
   MATCHes here — that is expected, not evidence the bug is fixed. *)
let known_divergence_reason path =
  let base = Filename.basename (Filename.remove_extension path) in
  Hashtbl.find_opt known_divergence_tbl base

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

(* Cross-compile the program for [arch] (amd64|arm64), run it under Docker, and
   diff its stdout against the NATIVE-compiled output — NOT the interpreter.
   Native-compiled is the reference because it isolates cross-arch codegen bugs
   (datalayout / arch-flag / ABI) from the pre-existing interpreter-vs-compiled
   divergences (e.g. println-of-list showing `#<tag:1>`) that this change does
   not touch.  A MISMATCH here means the cross backend computed a different
   answer than the trusted native backend for the same source. *)
let run_oracle_cross ~arch src_path =
  if should_skip src_path then
    Skipped (Filename.basename (Filename.remove_extension src_path))
  else begin
    let q = Filename.quote in
    let bin_dir = Filename.concat (Filename.get_temp_dir_name ()) "march_oracle_xc" in
    (try Unix.mkdir bin_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    let src_base = Filename.basename (Filename.remove_extension src_path) in
    (* --- reference: native compile + run --- *)
    let nat_bin = Filename.concat bin_dir ("native_" ^ src_base) in
    let nat_compile =
      Printf.sprintf "cd %s && %s --compile %s -o %s"
        (q project_root) (q march_abs) (q src_path) (q nat_bin) in
    match run_shell_capture ~timeout_s:60.0 nat_compile with
    | `Timeout    -> CompileTimeout
    | `Error code -> CompileFail code
    | `Ok _       ->
      (match run_shell_capture ~timeout_s:30.0 (q nat_bin) with
       | `Timeout    -> RunTimeout
       | `Error code -> RunFail code   (* native itself failed — not a cross signal *)
       | `Ok native_out ->
         (* --- cross compile + run under docker --- *)
         let x_bin = Filename.concat bin_dir (arch ^ "_" ^ src_base) in
         let target = if arch = "arm64" then "linux/arm64" else "linux/amd64" in
         let x_compile =
           Printf.sprintf "cd %s && %s --compile --target %s %s -o %s"
             (q project_root) (q march_abs) target (q src_path) (q x_bin) in
         (match run_shell_capture ~timeout_s:60.0 x_compile with
          | `Timeout    -> CompileTimeout
          | `Error code -> CompileFail code
          | `Ok _       ->
            let run_cmd =
              Printf.sprintf "sh %s %s %s"
                (q (Filename.concat project_root "test/xc/run_under_docker.sh"))
                (q arch) (q x_bin) in
            (match run_shell_capture ~timeout_s:30.0 run_cmd with
             | `Timeout    -> RunTimeout
             | `Error code -> RunFail code
             | `Ok cross_out ->
               if cross_out = native_out then Match cross_out
               else Mismatch (native_out, cross_out))))
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

(* ------------------------------------------------------------------ *)
(* Divergence classification (the core gap this restructure closes)   *)
(*                                                                     *)
(* BEFORE (Phase <4): [is_failure] returned true ONLY for [Mismatch]. *)
(*   A compiled binary that SIGSEGV'd/SIGABRT'd (RunFail(signal)) or  *)
(*   an internal-compiler-error exit-3 (CompileFail 3) while the      *)
(*   interpreter succeeded passed the sweep silently — the core gap   *)
(*   this task fixes (see the file-header comment and the task brief: *)
(*   "RunFail(crashed) signal deaths currently pass silently").       *)
(*                                                                     *)
(* AFTER: [is_divergence] additionally treats a signal-killed compiled *)
(*   run and an ICE (exit 3) compile as divergences. [is_failure]     *)
(*   narrows [is_divergence] to only the UN-TRIAGED ones — a          *)
(*   divergence on a program in [known_divergence] is reported but    *)
(*   does not fail the sweep (the "un-triaged gate" doctrine below).  *)
(* ------------------------------------------------------------------ *)

(** A divergence: the interpreter produced ground truth (ran) but the
    compiled backend disagrees or dies badly. Does NOT yet account for
    [known_divergence] triage — see [is_failure]. *)
let is_divergence = function
  | Mismatch _                              -> true
  | RunFail n when n = exit_signal_killed   -> true  (* compiled binary crashed *)
  | CompileFail 3                            -> true  (* internal compiler error / ICE *)
  | _                                        -> false

(** Un-triaged gate: a divergence FAILS the sweep unless [path] is listed
    in [known_divergence] (an already-open, cited compiler bug), in which
    case it is reported as KNOWN_DIVERGENCE instead. This is the whole
    point of the sweep: a newly-added or newly-regressed divergent
    program reddens `@oracle` until it is triaged into one of the two
    named lists above. *)
let is_failure (path, verdict) =
  is_divergence verdict && known_divergence_reason path = None

(* ------------------------------------------------------------------ *)
(* Main                                                               *)
(* ------------------------------------------------------------------ *)

let () =
  Random.self_init ();
  Printf.printf "=== March Oracle Test ===\n";
  Printf.printf "march binary  : %s\n" march_abs;
  Printf.printf "project root  : %s\n" project_root;
  (* MARCH_ORACLE_CROSS=amd64|arm64 → diff interpreter vs cross-compiled-in-docker
     instead of interpreter vs native-compiled. *)
  let cross_arch = Sys.getenv_opt "MARCH_ORACLE_CROSS" in
  (match cross_arch with
   | Some a -> Printf.printf "cross target  : linux/%s (via zig cc + docker)\n" a
   | None   -> ());
  Printf.printf "\n";

  let bench_dir    = Filename.concat project_root "bench" in
  let examples_dir = Filename.concat project_root "examples" in
  (* The Core March language-spec golden corpus (specs/lang/core-march.md §5):
     small, curated, deterministic, print-driven programs that anchor the
     operational-semantics rules. Same corpus criteria as bench/+examples/, so
     they belong in the same both-ways sweep — this makes the spec's golden
     anchor run in the @oracle CI lane, not only via specs/lang/golden/verify.sh. *)
  let golden_dir   = Filename.concat project_root "specs/lang/golden" in
  let files =
    match cross_arch with
    | Some _ ->
      (* Cross mode: deterministic corpora only.  bench/ prints wall-clock
         timings (non-deterministic → spurious MISMATCH) and its fib-shaped
         programs INTERP_TIMEOUT; neither is a codegen signal.  examples/ and
         the Core March golden corpus are deterministic and print-driven. *)
      find_march_files examples_dir @ find_march_files golden_dir
    | None ->
      find_march_files bench_dir @ find_march_files examples_dir
      @ find_march_files golden_dir
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
    let cross_prefix = match cross_arch with Some a -> Printf.sprintf "CROSS(%s) " a | None -> "" in
    Printf.printf "[%d/%d] %s%-50s " (i + 1) n_total cross_prefix rel;
    flush stdout;
    let verdict = match cross_arch with
      | Some a -> run_oracle_cross ~arch:a path
      | None   -> run_oracle path in
    Printf.printf "%s\n" (verdict_label verdict);
    flush stdout;
    results := (rel, verdict) :: !results
  ) files;

  let results = List.rev !results in

  (* ---- Summary ---- *)
  Printf.printf "\n%-50s  %s\n" "Program" "Verdict";
  Printf.printf "%s\n" (String.make 70 '-');
  List.iter (fun (name, v) ->
    let known = known_divergence_reason name in
    let label =
      if is_divergence v then
        match known with
        | Some _ -> verdict_label v ^ "  [KNOWN_DIVERGENCE]"
        | None   -> verdict_label v ^ "  <-- UN-TRIAGED FAILURE"
      else verdict_label v
    in
    Printf.printf "%-50s  %s\n" name label;
    (match known, is_divergence v with
     | Some reason, true -> Printf.printf "  known divergence: %s\n" reason
     | _ -> ());
    (match v with
     | Mismatch (ref_out, got_out) ->
       let l_ref, l_got = match cross_arch with
         | Some _ -> "native  ", "cross   "
         | None   -> "interp  ", "compiled" in
       Printf.printf "  %s : %s\n" l_ref (truncate_output ref_out);
       Printf.printf "  %s : %s\n" l_got (truncate_output got_out)
     | _ -> ())
  ) results;

  (* Stale known_divergence entries: listed as an open bug but this run
     did NOT reproduce a divergence for it (verdict is Match, or some
     other non-divergent outcome). Loud [WARN], not a hard failure — the
     entry should be pruned once the underlying bug is confirmed fixed. *)
  let stale_known_divergences =
    if oracle_cross_mode then []   (* known_divergence N/A in cross mode (see known_divergence_reason) *)
    else
    List.filter_map (fun (base, reason) ->
      let matching =
        List.filter (fun (name, _) ->
          Filename.basename (Filename.remove_extension name) = base
        ) results
      in
      match matching with
      | [] -> None (* program not found in this corpus run at all *)
      | (name, v) :: _ when not (is_divergence v) -> Some (name, base, reason, v)
      | _ -> None
    ) known_divergence
  in

  let count pred = List.length (List.filter (fun (_, v) -> pred v) results) in
  let n_match      = count (function Match _ -> true | _ -> false) in
  let n_divergence = count is_divergence in
  let n_known_div  = List.length (List.filter (fun (name, v) -> is_divergence v && known_divergence_reason name <> None) results) in
  let n_failure    = List.length (List.filter is_failure results) in
  (* Only clean "unsupported feature" compile exits (nonzero, ≠3) + compile
     timeouts belong here. A CompileFail 3 (internal compiler error) is a
     DIVERGENCE (see [is_divergence]) already counted under KNOWN_DIVERGENCE or
     UN-TRIAGED FAILURE — counting it here too would double-count it (the row
     label says "!=3") and break the buckets-reconcile-to-total invariant. *)
  let n_cfail      = count (function CompileFail n when n <> 3 -> true | CompileTimeout -> true | _ -> false) in
  let n_itimeout   = count (function InterpTimeout -> true | _ -> false) in
  let n_ifail      = count (function InterpFail _ -> true | _ -> false) in
  let n_skip       = count (function Skipped _ -> true | _ -> false) in

  Printf.printf "\n=== RESULTS MATRIX ===\n";
  Printf.printf "  MATCH             : %d   interpreter == compiled\n" n_match;
  Printf.printf "  KNOWN_DIVERGENCE  : %d   open compiler bug, triaged (see known_divergence list) — not a failure\n" n_known_div;
  Printf.printf "  UN-TRIAGED FAILURE: %d   <-- oracle failures (divergence not in known_divergence)\n" n_failure;
  Printf.printf "  SKIPPED           : %d   nondeterministic_allowlist (network/actor/server/interactive)\n" n_skip;
  Printf.printf "  INTERP_TIMEOUT    : %d   too slow for tree-walking interpreter (no ground truth)\n" n_itimeout;
  Printf.printf "  INTERP_FAIL       : %d   interpreter error (no ground truth)\n" n_ifail;
  Printf.printf "  COMPILE_FAIL(!=3) : %d   clean \"unsupported feature\" compile exit (no ground-truth conflict)\n" n_cfail;
  Printf.printf "  RUN_FAIL(other)   : %d   compiled binary exits clean nonzero (no ground-truth conflict)\n"
    (count (function RunFail n -> n <> exit_signal_killed | RunTimeout -> true | _ -> false));
  Printf.printf "  TOTAL DIVERGENCES : %d   (= KNOWN_DIVERGENCE + UN-TRIAGED FAILURE; Mismatch/signal-crash/ICE-exit-3)\n" n_divergence;
  Printf.printf "  TOTAL PROGRAMS    : %d\n\n" n_total;

  if stale_known_divergences <> [] then begin
    List.iter (fun (name, _base, reason, v) ->
      Printf.printf "[WARN] known_divergence entry no longer reproduces (consider pruning): %s\n" name;
      Printf.printf "       listed reason: %s\n" reason;
      Printf.printf "       actual verdict this run: %s\n" (verdict_label v)
    ) stale_known_divergences
  end;

  Printf.printf "\nNote: march currently emits typecheck warnings to stdout rather than stderr.\n";
  Printf.printf "      This may cause MISMATCH for programs with warnings.\n\n";

  Printf.printf "Corpus scope: bench/ + examples/ + specs/lang/golden/ top-level .march files.\n";
  Printf.printf "              test/ fixtures and stdlib doctests are NOT swept (see file header).\n\n";

  if n_failure > 0 then begin
    Printf.printf "FAIL: %d un-triaged divergence(s) between interpreter and compiler.\n" n_failure;
    Printf.printf "      Triage each into known_divergence (open bug) or nondeterministic_allowlist\n";
    Printf.printf "      (legitimately non-comparable) in test/test_oracle.ml, or fix the regression.\n";
    exit 1
  end else if n_match = 0 then begin
    Printf.printf "WARN: No programs successfully matched (all compile failures or skipped).\n";
    exit 0
  end else begin
    Printf.printf "PASS: %d matched, %d known-divergence (triaged), 0 un-triaged failures.\n" n_match n_known_div;
    exit 0
  end
