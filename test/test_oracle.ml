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
    sweep and its spec anchor runs in CI.) It additionally pulls in a
    CURATED, EXPLICITLY-NAMED subset of `test/native/`'s standalone programs
    (see [test_native_allowlist]) — it deliberately does NOT walk `test/`
    wholesale (189+ files there are compiler-internal fixtures: single-
    feature snippets, deliberately-erroring negative cases, FFI programs
    needing `.c` shims, `--target js` programs, and actor/PID/hash/network/
    scheduler-timing programs never byte-stable across runs — sweeping them
    all would drown the signal in triage noise, not raise it). Only named,
    deterministic, self-contained, terminating fixtures verified to MATCH
    interp==compiled are added individually. It still does NOT extract stdlib
    doctests (the `march>` REPL-transcript comments embedded in stdlib
    modules need a dedicated extractor, since they are not whole `.march`
    programs). See `specs/todos.md` for the tracked follow-up on the
    remaining doctest extractor.

    A handful of checksum-style programs additionally carry a FIXED
    expected-stdout anchor ([expected_stdout]) so a backend-SYMMETRIC
    regression — interpreter and compiler drifting TOGETHER, invisible to
    the interp-vs-compiled diff — still reddens the sweep. The sort-bench
    family (`mergesort`/`heapsort`/`timsort`/`alphadev_sort` -> "1423",
    `sort_nearly_sorted` -> "0\n0") is the canonical case. Those five used
    to crash COMPILED (the sort RC-underflow family, fixed 2026-07-17 and
    pruned from [known_divergence] 2026-07-24), so the pair now covers both
    halves: the interp-vs-compiled diff catches a backend regression, and
    the anchor independently guards the interpreter's checksum ground truth
    from silent drift.

    --- Divergence classification (the core contract) -------------------
    A DIVERGENCE is any of: Mismatch, RunFail(signal-crash), or
    CompileFail(3) (exit 3 = internal compiler error / ICE, the Phase-1
    ICE signal) — i.e. any case where the interpreter produced ground
    truth (exited 0) but the compiled backend disagrees or dies badly.
    A divergence is a FAILURE unless the program is listed in
    [known_divergence] below, in which case it is reported loudly as
    KNOWN_DIVERGENCE but does not fail the sweep.

    InterpFail is ALSO a failure (added 2026-07-10) even though it is not
    a backend divergence: this corpus is by definition real, RUNNABLE
    programs, so a clean interpreter failure means the program no longer
    compiles/runs at all. Crucially, a typecheck rejection is
    backend-SYMMETRIC (both paths share the typechecker), so a corpus
    program regressing from working to NOT-COMPILING is invisible to
    divergence comparison — exactly how the 2026-07-10 bench/ breakage
    (stdlib ordered_map/sorted_set `Tree`/`Leaf`/`Node` colliding with the
    benches' own `ptype Tree`) passed this sweep silently while
    tree_transform and binary_trees were dead. An InterpFail requires the
    same [known_divergence] triage as a divergence.

    Everything else (InterpTimeout — fib-shaped programs legitimately
    exceed the interpreter budget, CompileTimeout, CompileFail(non-3),
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
    (* Wall-clock timing lines in output ("Filter: 49 ms") — never byte-stable
       between the tree-walking interpreter and the compiled binary.  Formerly
       masked under known_divergence while the group_by/join empty-result bug
       was open (FIXED 2026-07-18: emit_case niche-recovery ctor ambiguity);
       its correctness is pinned timing-free by examples/dataframe_basic.march
       (full-sweep MATCH) + test/native/{niche_ctor_ambiguity,
       dataframe_groupby_count}.march. *)
    "dataframe_bench";
    (* Parallel string-scan scaling benchmark: prints "workers=N ms=T" wall-
       clock lines for N in {1,2,4,8} before the final deterministic
       "checksum=16000000" line. The timings are never byte-stable across
       runs (let alone between interpreter and compiled binary), so this
       program is structurally non-comparable, not a divergence — the
       checksum is the only part worth pinning, and that already has
       ground truth in the leading doc comment
       (bench/string_parallel_scan.march: "Expected output:
       checksum=16000000"). Same class as dataframe_bench above. *)
    "string_parallel_scan";
    (* Interactive or needs real files *)
    "debugger"; "read_file";
    (* Supervision trees (start actors / servers; scheduler-order-dependent) *)
    "supervision_basic"; "app_basic";
    (* WebSocket echo server (binds a port, serves forever; interp exits 2
       with EADDRINUSE if any other instance holds the port) *)
    "ws_echo";
    (* Islands perf HTTP server (binds a port, serves forever). Its stale
       actor-init/record-update syntax was fixed 2026-07-10 when the new
       InterpFail gate first flagged it — it must still TYPECHECK, but as a
       server it can never produce comparable stdout. *)
    "island_perf_server";
    (* Supervision/actor demo: pids and restart ordering vary across runs *)
    "supervision_strategies";
    (* Monitor demo: Down-notification delivery timing / mailbox-size prints
       are scheduler-order-dependent. Byte-identical when run in isolation,
       but interleaves differently under the full-sweep process load. Same
       class as the other supervision_* entries. *)
    "supervision_monitor";
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
    (* EMPTY as of 2026-07-24 — every previously-triaged entry has been
       confirmed fixed and pruned.  An empty list is the intended steady
       state: it means the compiled backend agrees with the interpreter on
       the entire sweep corpus, so ANY divergence is an un-triaged failure
       that reddens the sweep.  Add an entry here only to triage a
       genuinely-open compiler bug, and always with the specs/todos.md
       pointer for the tracked fix.

       PRUNE LOG (kept so a re-appearance is recognised, not re-diagnosed
       from scratch):

       - dataframe_bench / dataframe_basic — pruned 2026-07-18.  Three
         stacked bugs: the float SIGSEGV (native_float_arr <-> List(Float)
         boxing, runtime fix), which unmasked group_by/inner_join/summarize
         returning EMPTY compiled — root-caused to emit_case's TVar-erased
         niche recovery committing on the FIRST niche-shaped ctor-name owner
         (Csv's `Row` hijacked boxed DataFrame.Row's decode; llvm_case.ml
         all-owners fix).  Pinned by niche_ctor_ambiguity +
         dataframe_groupby_count.

       - hello / list_lib — "to_string-on-container `#<tag:N>`": to_string()
         on a List/Option/Result/tuple/ADT fell through to the runtime's
         generic tag fallback compiled instead of dispatching through Show.
         FIXED 2026-07-17 (to_string now routes through Show dispatch);
         entries went stale and were pruned 2026-07-24 after the sweep
         reported both as MATCH.  Pinned by native/to_string_show.march.

       - alphadev_sort / heapsort / mergesort / sort_nearly_sorted / timsort
         — the "sort RC-underflow family": a compiled-only garbage-pointer-
         into-an-RC-op crash in the Sort module's merge/heap internals.
         Long-lived (it once manifested as an UNKILLABLE macOS `UE` kernel
         wedge, later as clean exit 138/139).  ROOT-CAUSED AND FIXED
         2026-07-17 (see specs/todos.md, "sort-RC-underflow family"); entries
         went stale and were pruned 2026-07-24 after the sweep reported all
         five as MATCH against their pinned [expected_stdout] checksums
         (1423 / "0\n0"), which still guard the interpreter ground truth. *)
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
(* Curated test/native subset (corpus extension, 2026-07-15)           *)
(*                                                                     *)
(* test/ is NOT swept wholesale (see the header: 189+ compiler-internal *)
(* fixtures, negative cases, FFI/.c-shim programs, --target js programs, *)
(* and actor/PID/hash/network/scheduler-timing programs that are never  *)
(* byte-stable across runs). Instead these NAMED, deterministic, self-  *)
(* contained, terminating programs from test/native/ are pulled in      *)
(* individually. Each was confirmed to MATCH interp==compiled at add    *)
(* time (both-ways run, output byte-identical across 3 compiled runs).  *)
(* They exercise language-feature codegen paths (closures, niches,      *)
(* tuple/newtype layout, let-shadowing, default args, qualified/nested  *)
(* module calls) that bench/+examples/ under-cover.                     *)
(* ------------------------------------------------------------------ *)

let test_native_allowlist =
  [ "atom_ctor_field"; "closure_bool_field"; "default_args_nested";
    "default_method_args"; "ctor_pattern_multi_param"; "float_arr_list_boxing";
    "nested_cons_ctor_heap"; "fn_arities_shadow_poisoning";
    "niche_ctor_ambiguity"; "dataframe_groupby_count"; "cap_epoch_plane";
    "actor_call_canonical"; "actor_call_timeout"; "hash_cross_backend";
    "bare_none_print"; "lazy_niche"; "let_shadow_rebind"; "let_tuple_destructure";
    "let_tuple_nested"; "task_race_cancel";
    "march_prefixed_local"; "nested_mod_qualcall"; "newtype_counter";
    "native_arr_map_closure_abi";
    "niche_reuse_closure"; "option_niche"; "qualified_ctor_pattern";
    "shadow_selfref_let"; "to_string_show"; "tuple_scalar_fields";
    "tuple_show"; "typed_array_map_closure_abi"; "unboxed_aggregate"; "unboxed_aggregate_boundaries";
    "zero_arg_closure_default" ]

let curated_test_files root =
  let dir = Filename.concat root "test/native" in
  List.filter_map (fun base ->
    let p = Filename.concat dir (base ^ ".march") in
    if Sys.file_exists p then Some p else None)
    test_native_allowlist

(* ------------------------------------------------------------------ *)
(* Fixed expected-stdout anchors (corpus extension, 2026-07-15)        *)
(*                                                                     *)
(* A backend-SYMMETRIC regression — interpreter AND compiler drifting   *)
(* TOGETHER — is invisible to the interp-vs-compiled diff (the same     *)
(* blind spot as the bench/ Tree-collision episode in the header). For  *)
(* a handful of checksum-style programs we therefore pin the EXACT      *)
(* expected stdout as an independent ground-truth anchor: the           *)
(* interpreter's output is asserted byte-equal to the literal below     *)
(* (verdict ExpectedMismatch, a hard failure never masked by            *)
(* known_divergence). The sort-bench family is the canonical case —     *)
(* it crashes COMPILED today (sort RC family, known_divergence), so the *)
(* compiled side is already a triaged KNOWN_DIVERGENCE; this anchor     *)
(* guards the interpreter checksum so a future regression that changes  *)
(* the sort RESULT (rather than crashing) surfaces immediately.        *)
(* Values verified 2026-07-15 by running each interpreted.             *)
(* ------------------------------------------------------------------ *)

let expected_stdout =
  [ "mergesort", "1423\n";
    "heapsort", "1423\n";
    "timsort", "1423\n";
    "alphadev_sort", "1423\n";
    "sort_nearly_sorted", "0\n0\n";
    "to_string_show", "[1, 2, 3]\nSome(9)\nOk(7)\n5\n4.\ntrue\nhi\nnums=[4, 5]\n";
    "let_tuple_nested", "10\n100\nhi 5 2.5\n";
    "bare_none_print", "None\nNone\nNone\n";
    "task_race_cancel", "race=1\nany=10\ncancelled=true\n";
    "default_method_args", "true\nfalse\ntrue\n";
    "ctor_pattern_multi_param", "false\ntrue\n6\n15\n";
    "float_arr_list_boxing", "1\n0\n7.\n[1.5, 2.5, 3.]\n";
    "nested_cons_ctor_heap", "2\n1\n";
    "fn_arities_shadow_poisoning", "11\n6\n3\n";
    "niche_ctor_ambiguity", "len=2\n";
    "dataframe_groupby_count", "Groups: 2\n";
    "cap_epoch_plane", "valid: true\nsend_checked live: :ok\nvalid after revoke: false\nsend_checked revoked: :error\nsend dead: None\nget_cap dead: None\nstale cap valid: false\nsend_checked stale: :error\n";
    "actor_call_canonical", "count = 2\n";
    "actor_call_timeout", "timeout_ok\n";
    "hash_cross_backend", "2835554897195333154\n2607821981565500683\n1989520218106164979\n2520916703919743830\n";
    "tuple_show", "(1, 2)\n(1, a, true)\n(1.5, 2)\n[(1, 2), (3, 4)]\n((1, 2), 3)\n(1, 2, 3, 4)\n" ]

let expected_stdout_tbl =
  let tbl = Hashtbl.create 8 in
  List.iter (fun (k, v) -> Hashtbl.replace tbl k v) expected_stdout;
  tbl

let expected_stdout_for path =
  let base = Filename.basename (Filename.remove_extension path) in
  Hashtbl.find_opt expected_stdout_tbl base

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
      (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
      (* Reap with a bounded WNOHANG grace loop — NEVER a blocking waitpid.
         SIGKILL is not a guarantee: a process stuck in an UNINTERRUPTIBLE
         kernel wait (macOS `ps` state `UE`) has the signal pending but
         cannot act on it, and a blocking waitpid then hangs forever.
         Observed live 2026-07-10: the compiled bench_alphadev_sort binary
         wedged in `UE` while exiting; the sweep's blocking reap froze the
         ENTIRE 105-program run at [1/105] for hours — twice.  If the child
         has not been reaped after the grace window, LEAK it (a tiny,
         already-signaled zombie) and let the sweep move on; the verdict is
         `Timeout either way. *)
      let reap_deadline = Unix.gettimeofday () +. 2.0 in
      let rec reap () =
        match Unix.waitpid [Unix.WNOHANG] pid with
        | (0, _) ->
          if Unix.gettimeofday () < reap_deadline
          then (Unix.sleepf 0.05; reap ())
          else Printf.eprintf
                 "[oracle] WARNING: pid %d ignored SIGKILL (uninterruptible \
                  kernel wait?) — leaking it and moving on\n%!" pid
        | _ | exception Unix.Unix_error _ -> ()
      in
      reap ()
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
  | ExpectedMismatch of string * string (** expected-anchor, actual interp: ground-truth drift *)
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
    | `Ok interp_out when
        (match expected_stdout_for src_path with
         | Some exp -> exp <> interp_out | None -> false) ->
      (* Fixed-anchor ground-truth drift: the interpreter ran clean but its
         output no longer matches the pinned checksum (see [expected_stdout]).
         Short-circuit before compiling — the ground truth itself is wrong, so
         an interp-vs-compiled diff would be meaningless. Hard failure. *)
      let exp = match expected_stdout_for src_path with Some e -> e | None -> "" in
      ExpectedMismatch (exp, interp_out)
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
  | ExpectedMismatch _ -> "EXPECTED_MISMATCH"
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
  | RunFail n when n = exit_signal_killed   -> true  (* compiled binary crashed (WIFSIGNALED) *)
  (* The runtime's fatal-fault handler now _exit(128+signo)s instead of
     re-raising the signal (re-raise wedged the process unkillably over the
     green-thread ucontext — see runtime/march_scheduler.c), so a compiled
     crash arrives as a clean exit 139 (SIGSEGV) / 138 (SIGBUS) / 134
     (SIGABRT) / 132 (SIGILL) / 136 (SIGFPE) rather than WIFSIGNALED.  Treat
     those conventional 128+fatal-signo codes as crash divergences too, so a
     NEW compiled segfault is still caught and not mistaken for a clean
     nonzero exit. *)
  | RunFail (139 | 138 | 134 | 132 | 136)    -> true  (* compiled binary crashed (_exit 128+signo) *)
  | CompileFail 3                            -> true  (* internal compiler error / ICE *)
  | _                                        -> false

(** Un-triaged gate: a divergence FAILS the sweep unless [path] is listed
    in [known_divergence] (an already-open, cited compiler bug), in which
    case it is reported as KNOWN_DIVERGENCE instead. This is the whole
    point of the sweep: a newly-added or newly-regressed divergent
    program reddens `@oracle` until it is triaged into one of the two
    named lists above.

    A clean [InterpFail] gates identically (2026-07-10): not a backend
    divergence, but on a real-runnable corpus it means the program no
    longer compiles/runs at all — and a typecheck rejection is
    backend-symmetric, so it can NEVER show up as a divergence (see the
    header's classification contract for the bench/ Tree-collision
    episode this closes). [InterpTimeout] deliberately stays a
    non-failure: the fib-shaped bench programs legitimately exceed the
    interpreter budget. *)
let is_failure (path, verdict) =
  match verdict with
  (* A fixed-anchor ground-truth drift is a HARD failure regardless of
     known_divergence: known_divergence masks a COMPILED-side divergence
     (e.g. the sort family's crash), never a drift of the interpreter's
     pinned checksum, which is the independent ground truth. *)
  | ExpectedMismatch _ -> true
  | _ ->
    (is_divergence verdict
     || (match verdict with InterpFail _ -> true | _ -> false))
    && known_divergence_reason path = None

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
      (* Native lane: bench/ + examples/ + Core golden + the curated
         test/native/ subset. The curated subset is native-only for now
         (deterministic and cross-safe in principle, but the cross lane is
         deliberately scoped to examples/+golden — the docker round-trip is
         slow and these fixtures add no cross-arch codegen signal the
         examples don't already carry). *)
      find_march_files bench_dir @ find_march_files examples_dir
      @ find_march_files golden_dir
      @ curated_test_files project_root
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
      else match v with
        | ExpectedMismatch _ -> verdict_label v ^ "  <-- FIXED-ANCHOR DRIFT (ground truth)"
        | _ -> verdict_label v
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
     | ExpectedMismatch (exp, got) ->
       Printf.printf "  expected: %s\n" (truncate_output exp);
       Printf.printf "  interp  : %s\n" (truncate_output got)
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
      (* A known-broken program that TIMES OUT (or is killed by a signal at
         the run step) is still broken — it must not read as "no longer
         reproduces / consider pruning".  Observed 2026-07-10: the sort
         RC-underflow family and dataframe_bench changed failure MODE from
         crash to an UNKILLABLE kernel wedge (macOS `UE` state, pinned at
         march_incrc inside a lambda apply; SIGKILL pending but undeliverable
         — see specs/todos.md), so their verdicts became RUN_TIMEOUT.  Only a
         genuinely-clean verdict (Match, or a clean-exit run) marks an entry
         prunable. *)
      | (_, (RunTimeout | RunFail _ | CompileTimeout)) :: _ -> None
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
  let n_anchor     = count (function ExpectedMismatch _ -> true | _ -> false) in
  let n_skip       = count (function Skipped _ -> true | _ -> false) in

  Printf.printf "\n=== RESULTS MATRIX ===\n";
  Printf.printf "  MATCH             : %d   interpreter == compiled\n" n_match;
  Printf.printf "  KNOWN_DIVERGENCE  : %d   open compiler bug, triaged (see known_divergence list) — not a failure\n" n_known_div;
  Printf.printf "  UN-TRIAGED FAILURE: %d   <-- oracle failures (un-triaged divergence, clean InterpFail, or fixed-anchor drift)\n" n_failure;
  Printf.printf "  ANCHOR_DRIFT      : %d   (subset of above) interpreter ground truth != pinned expected_stdout\n" n_anchor;
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

  Printf.printf "Corpus scope: bench/ + examples/ + specs/lang/golden/ top-level .march files\n";
  Printf.printf "              + a curated test/native/ subset (test_native_allowlist).\n";
  Printf.printf "              test/ is NOT swept wholesale; stdlib doctests are NOT swept (see file header).\n\n";

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
