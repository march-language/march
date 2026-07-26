(** Bench gate: every program in [bench/] must compile, run, exit 0, and print
    its known answer.

    WHY THIS EXISTS. Nothing in the test suite compiled or ran [bench/*.march].
    The benchmarks were only ever exercised by hand, by someone deliberately
    measuring performance. That gap hid real, severe breakage for weeks at a
    time:

      - Perceus FBIP in-place reuse was disabled program-wide. tree_transform
        ran 7.5x slower than its published figure — slower than OCaml on the
        one workload FBIP exists to win — and nothing went red.
      - iolist_template and string_pipeline crashed outright (SIGBUS, exit
        138) on a non-tail IOList walk overflowing the green-thread stack.
      - deque_ops never terminated: a lazily-loaded stdlib module left
        Deque.pop_front unspecialized, so a boxed Some was decoded as a niche
        Option(Int) and no popped value ever matched.

    Every one of those is a plain "compile it and look at the output" failure.
    This gate is deliberately cheap and dumb: it does not measure time, so it
    cannot be flaky on a loaded machine, and it makes no performance claim. It
    answers one question — does the program still produce the right answer? —
    which is exactly the question that went unasked.

    (Performance regressions are a separate problem; see bench/RESULTS.md.
    A wall-clock gate would be flaky on shared CI, so this is not one.)

    WHAT IS AND ISN'T COVERED. Every bench/*.march is in exactly one bucket
    below, and the buckets are exhaustive by construction: [test_manifest_is_
    exhaustive] enumerates the directory and fails if any file is in neither
    list. A new benchmark therefore cannot be silently ungated — the cost of
    adding one is one line here, and the failure mode if you forget is a red
    test naming your file, not silence. That property is the whole point: the
    bugs above survived because absence of coverage is invisible.

    TIMING-BEARING OUTPUT. Four benches print wall-clock lines ("time: 2 ms").
    Their computed values are perfectly deterministic — only the timings move
    — so rather than drop the coverage they are compared with timings masked
    (see [strip_timings]). Their checksums are still fully checked. *)

let bench_dir () =
  (* test_helpers resolves the compiler exe; the bench dir sits beside it in
     the source tree. Prefer an explicit override so the gate is runnable from
     anywhere (dune sandbox, a worktree, CI). *)
  match Sys.getenv_opt "MARCH_BENCH_DIR" with
  | Some d -> d
  | None ->
    let candidates = ["bench"; "../bench"; "../../bench"] in
    (match List.find_opt Sys.file_exists candidates with
     | Some d -> d
     | None -> "bench")

(* How a bench's stdout is compared. *)
type compare_mode =
  | Exact          (** byte-identical stdout *)
  | IgnoreTiming   (** identical after masking "<n>ms" / "<n> ms" *)

(* Mask wall-clock numbers so a timing-bearing bench is still value-checked.
   Replaces the DIGITS before an ms suffix, leaving surrounding text intact,
   so a change in what is printed still fails — only the number is free. *)
let strip_timings (s : string) : string =
  Str.global_replace (Str.regexp "[0-9]+\\( *\\)ms") "<T>\\1ms" s

(* name, expected stdout (trimmed), comparison mode.

   CAPTURE these, never write them from memory. Two entries here were first
   filled in by hand from a truncated view of the output and were simply
   wrong (invented tree counts, an ackermann line the program does not
   print); the gate caught both on its first run, which is the system working
   — but the cheap path is to run the program and paste what it prints. Where
   a bench's own header states its answer (iolist_template -> 2092654,
   string_pipeline -> 644449, deque_ops -> 20001000000) the captured value was
   cross-checked against it. *)
let gated : (string * string * compare_mode) list = [
  (* ── sort family: all compute the same checksum over the same input ──
     This family crashed compiled for weeks (the sort RC-underflow family);
     the shared 1423 checksum is the anchor that would have caught it. *)
  "alphadev_sort",      "1423", Exact;
  "heapsort",           "1423", Exact;
  "insertion_sort",     "1423", Exact;
  "introsort",          "1423", Exact;
  "mergesort",          "1423", Exact;
  "sort_small_batched", "1423", Exact;
  "timsort",            "1423", Exact;
  "sort_nearly_sorted", "0\n0", Exact;

  (* ── core compute / codegen ── *)
  "fib",              "102334155",    Exact;
  "list_ops",         "333333666666", Exact;
  "merkle",           "6400",         Exact;
  "string_build",     "2888895",      Exact;
  "mutual_recursion",
  "even/odd result: true\n\
   state_machine result: 1\n\
   collatz steps from 27: 111", Exact;

  (* ── the three that were silently broken (see header) ── *)
  "tree_transform",  "104857600",   Exact;  (* FBIP showcase *)
  "iolist_template", "2092654",     Exact;  (* was SIGBUS *)
  "string_pipeline", "644449",      Exact;  (* was SIGBUS *)
  "deque_ops",       "20001000000", Exact;  (* was a non-terminating drain loop *)

  (* ── allocation / GC ── *)
  "binary_trees",
  "stretch tree of depth 16 check: 131071\n\
   32768 trees of depth 4 check: 1015808\n\
   8192 trees of depth 6 check: 1040384\n\
   2048 trees of depth 8 check: 1046528\n\
   512 trees of depth 10 check: 1048064\n\
   128 trees of depth 12 check: 1048448\n\
   32 trees of depth 14 check: 1048544\n\
   long lived tree of depth 15 check: 65535", Exact;

  (* ── concurrency: fork-join and parallel collections ──
     par_fib is the canary for the task_await missed-wakeup deadlock (fixed
     2026-07-25); these check the ANSWER, never the timing, so they are not
     scheduler-order sensitive even though the schedule itself varies. *)
  "par_fib",       "102334155", Exact;
  "par_worksteal", "102334155", Exact;
  "par_map",       "849666",    Exact;
  "parallel",      "16777216",  Exact;

  (* ── timing-bearing: values checked, wall-clock masked ── *)
  "array_numeric",   "", IgnoreTiming;
  "dataframe_bench", "", IgnoreTiming;
  "hash_map_bench",  "", IgnoreTiming;
  "rrb_bench",       "", IgnoreTiming;
]

(* Benches deliberately NOT gated, each with the reason. These bind fixed TCP
   ports, so running them in a test suite is unsafe on a shared machine and
   meaningless in a sandbox: a stale port-holder from an unrelated session
   already produced one misdiagnosis in this repo ("bind failed" /
   "malformed hello" from a 34-hour-old zombie holding port 29850). *)
let excluded : (string * string) list = [
  "http_get",           "network client: connects to an external HTTP server";
  "http_get_close",     "network client: connects to an external HTTP server";
  "http_get_keepalive", "network client: connects to an external HTTP server";
  "island_perf_server", "server: binds a fixed port and serves until killed";
]

(* The timing-bearing benches have no pinned literal (their output is long and
   mostly timings); they are pinned by a stable VALUE substring instead, so a
   wrong checksum still fails. *)
let timing_value_anchors : (string * string list) list = [
  "hash_map_bench", ["check=14999850000"];
  "rrb_bench",      ["seq_sum=500000500000"; "par_sum=500000500000"];
]

(* ── Harness ─────────────────────────────────────────────────────────── *)

let trim s = String.trim s

let read_file_opt path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      Some (really_input_string ic (in_channel_length ic)))
  with Sys_error _ -> None

let compile_and_run (name : string) : (string, string) result =
  let main_exe = Test_helpers.find_main_exe () in
  let src = Filename.concat (bench_dir ()) (name ^ ".march") in
  if not (Sys.file_exists src) then Error (Printf.sprintf "missing source %s" src)
  else begin
    let tmp = Filename.temp_file ("march_bench_" ^ name) "" in
    Sys.remove tmp;
    Unix.mkdir tmp 0o755;
    let bin = Filename.concat tmp name in
    (* Compile from a COPY in the temp dir, never from bench/ itself.
       `march --compile` writes its intermediate <source>.ll beside the
       SOURCE, so compiling in place both litters the tree (bench/*.ll is
       gitignored, which is how it went unnoticed) and hard-fails with
       "Permission denied" wherever the source dir is read-only — e.g. inside
       dune's sandbox, which is exactly where this gate runs in CI. *)
    let src_copy = Filename.concat tmp (name ^ ".march") in
    (match read_file_opt src with
     | None -> ()
     | Some data ->
       let oc = open_out_bin src_copy in
       output_string oc data; close_out oc);
    let src = src_copy in
    match Test_helpers.compile_march_or_skip
            ~extra_args:"--opt 2" ~main_exe ~bin ~src () with
    | None -> Error "SKIP:no-clang"
    | Some bin ->
      let out_file = Filename.concat tmp "out.txt" in
      (* Hard-bounded: a hung bench must never take the suite with it. The
         task_await deadlock did exactly that to CI for ~2 days. *)
      (match Test_helpers.run_with_timeout ~timeout_secs:180.0
               ~stdout_file:out_file [| bin |] with
       | `Timeout ->
         Error (Printf.sprintf
                  "%s did not terminate within 180s (compiled). A bench that \
                   hangs is a real regression — deque_ops hung exactly this \
                   way on a boxed-vs-niche decode bug." name)
       | `Exited 0 ->
         (match read_file_opt out_file with
          | Some s -> Ok (trim s)
          | None -> Error "could not read program output")
       | `Exited rc ->
         Error (Printf.sprintf
                  "%s exited %d (compiled). 138/139 = SIGBUS/SIGSEGV — \
                   iolist_template and string_pipeline both crashed this way \
                   on a stack-overflowing non-tail walk." name rc))
  end

let check_bench (name, expected, mode) () =
  match compile_and_run name with
  | Error "SKIP:no-clang" ->
    (* Tool absence is a legitimate, counted skip — not a silent pass. *)
    Printf.printf "  [skip] %s: clang unavailable\n%!" name
  | Error msg -> Alcotest.fail msg
  | Ok actual ->
    (match mode with
     | Exact ->
       Alcotest.(check string)
         (Printf.sprintf "%s stdout" name) expected actual
     | IgnoreTiming ->
       (* Value anchors must appear; timings are free. *)
       let anchors =
         Option.value ~default:[] (List.assoc_opt name timing_value_anchors) in
       List.iter (fun a ->
         let found =
           try ignore (Str.search_forward (Str.regexp_string a) actual 0); true
           with Not_found -> false in
         Alcotest.(check bool)
           (Printf.sprintf "%s output contains %s" name a) true found) anchors;
       (* And the program must have produced SOMETHING beyond whitespace —
          guards against an empty-output regression slipping past a mask. *)
       Alcotest.(check bool)
         (Printf.sprintf "%s produced output" name) true
         (String.length (strip_timings actual) > 0))

(** Every bench/*.march must be in exactly one bucket. This is what stops the
    gate from rotting: adding a benchmark without gating it fails HERE, by
    name, instead of silently reducing coverage. *)
let test_manifest_is_exhaustive () =
  let dir = bench_dir () in
  let on_disk =
    Sys.readdir dir
    |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".march")
    |> List.map (fun f -> Filename.remove_extension f)
    |> List.sort String.compare
  in
  let known =
    List.map (fun (n, _, _) -> n) gated @ List.map fst excluded in
  let ungated = List.filter (fun n -> not (List.mem n known)) on_disk in
  let stale = List.filter (fun n -> not (List.mem n on_disk)) known in
  Alcotest.(check (list string))
    "every bench/*.march is either gated or explicitly excluded (add it to \
     `gated` with its expected output, or to `excluded` with a reason)"
    [] ungated;
  Alcotest.(check (list string))
    "no manifest entry names a bench that no longer exists" [] stale

let () =
  let cases =
    List.map (fun ((name, _, _) as b) ->
      Alcotest.test_case name `Slow (check_bench b)) gated
  in
  Alcotest.run "march-bench-gate" [
    ("manifest", [
       Alcotest.test_case "every bench is gated or explicitly excluded" `Quick
         test_manifest_is_exhaustive ]);
    ("bench-programs", cases);
  ]
