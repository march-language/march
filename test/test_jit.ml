(* test/test_jit.ml *)
let test_dlopen_libc () =
  (* On macOS, dlopen(NULL) gives the main program handle which includes libc *)
  let handle = March_jit.Jit.dlopen "" in
  (* getpid is always available *)
  let _sym = March_jit.Jit.dlsym handle "getpid" in
  March_jit.Jit.dlclose handle;
  Alcotest.(check pass) "dlopen/dlsym/dlclose round-trip" () ()

let test_orc_available_never_raises () =
  let a = March_jit.Jit_orc.available () in
  (* Second call must agree with the first (cached) *)
  Alcotest.(check bool) "stable" a (March_jit.Jit_orc.available ())

(* ── ORC REPL-session regression ──────────────────────────────────────────

   Regression for the SIGSEGV filed as
   specs/progress/2026-08-24-orc-repl-segfault-fn-def-after-let-lambda.md:
   defining a second `fn` in a MARCH_JIT_BACKEND=orc REPL session killed the
   process (exit 139).

   Two stacked defects, both needed for a green run:
     1. every REPL `fn` fragment re-emitted the prev-slot loader
        `define ptr @<prior binding>()` with EXTERNAL linkage, colliding in
        ORC's single shared JITDylib with the real `define … @<fn>(…)` from
        the fragment that defined it ("duplicate definition of symbol");
     2. jit_orc_stubs.c double-freed the ThreadSafeModule on the add-module
        error path, so that recoverable error became a segfault.

   Driven as a SUBPROCESS on purpose: a regression whose failure mode is a
   SIGSEGV must not be able to take the test runner with it, and the crash
   only surfaces through the whole REPL path (stdlib prelude precompile,
   run_decl fn/let sequencing) rather than a single fragment.  The backend is
   forced through Repl_jit's existing startup selector by setting
   MARCH_JIT_BACKEND=orc in the child's environment — no test-only seam
   needed.

   Skips cleanly when libLLVM is absent (Jit_orc.available () = false), which
   is the normal state on a machine without `brew install llvm` /
   `apt-get install llvm-*`.  CI's macOS and Linux images do have it, so the
   test really runs there. *)

(* Session HOME for the child REPL processes.  Deliberately NOT the ambient
   HOME: dune's test rule pins HOME at %{project_root}/_build/jit_home, which
   expands to a RELATIVE path in CI whose parent does not exist from the test
   cwd (a non-recursive mkdir there ENOENTs), and an own tmp directory keeps
   the stdlib-precompile / JIT .so caches out of the developer's real
   ~/.cache.  Per-pid so concurrent test runners never share a half-written
   cache; created lazily once and shared by every session in this file, so
   only the first JIT-backed session pays the stdlib precompile. *)
let session_home = lazy (
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_jit_test_home.%d" (Unix.getpid ())) in
  List.iter
    (fun d -> try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    [dir; Filename.concat dir ".cache"];
  dir)

let march_bin () =
  match Sys.getenv_opt "MARCH_BIN" with
  | Some p when Sys.file_exists p -> Some p
  | _ -> if Sys.file_exists "../bin/main.exe" then Some "../bin/main.exe" else None

(* Feed [lines] to the REPL on stdin with MARCH_JIT_BACKEND=[backend]; return
   (exit_code, combined_output). *)
let run_jit_repl ~backend bin lines =
  let tmp_in  = Filename.temp_file "march_jit_repl" ".txt" in
  let tmp_out = Filename.temp_file "march_jit_repl" ".out" in
  let oc = open_out tmp_in in
  List.iter (fun l -> output_string oc (l ^ "\n")) lines;
  close_out oc;
  let cmd =
    Printf.sprintf "HOME=%s MARCH_JIT_BACKEND=%s %s < %s > %s 2>&1"
      (Filename.quote (Lazy.force session_home)) backend
      (Filename.quote bin) (Filename.quote tmp_in) (Filename.quote tmp_out) in
  let status = Sys.command cmd in
  let ic = open_in_bin tmp_out in
  let n = in_channel_length ic in
  let out = really_input_string ic n in
  close_in ic;
  (try Sys.remove tmp_in with _ -> ());
  (try Sys.remove tmp_out with _ -> ());
  (status, out)

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let check_session ?(backend = "orc") name lines expected =
  if backend = "orc" && not (March_jit.Jit_orc.available ()) then
    (* libLLVM not installed — nothing to regress against.  (The clang
       backend needs no libLLVM, so only ORC sessions skip here.) *)
    Alcotest.(check pass) (name ^ " (skipped: no libLLVM)") () ()
  else
    match march_bin () with
    | None -> Alcotest.(check pass) (name ^ " (skipped: no main.exe)") () ()
    | Some bin ->
      let (code, out) = run_jit_repl ~backend bin lines in
      (* 139 = SIGSEGV, the exact failure this pins. *)
      Alcotest.(check int)
        (Printf.sprintf "%s: exit code (output: %s)" name out) 0 code;
      List.iter (fun e ->
        Alcotest.(check bool)
          (Printf.sprintf "%s: output contains %S (got: %s)" name e out)
          true (contains out e))
        expected

(* The minimal repro from the todo: fn, then a let-bound lambda, then fn. *)
let test_orc_fn_after_let_lambda () =
  check_session "orc fn-after-let-lambda"
    [ "fn fib(n) do if n < 2 do n else fib(n-1) + fib(n-2) end end";
      "let ys = List.map(List.range(1, 10), fn x -> x * 2)";
      "fn sq(x) do x * x end";
      "sq(12)";
      ":quit" ]
    [ "val fib = <fn>";
      "val ys = [2, 4, 6, 8, 10, 12, 14, 16, 18]";
      "val sq = <fn>";
      "= 144" ]

(* The narrower control from the todo — two consecutive `fn` definitions.
   The todo believed this was healthy; it in fact crashed too, and it is the
   tightest form of the duplicate-symbol collision, so pin it directly. *)
let test_orc_two_consecutive_fns () =
  check_session "orc two consecutive fns"
    [ "fn f(x) do x + 1 end";
      "fn g(x) do x * 2 end";
      "g(3)";
      ":quit" ]
    [ "val f = <fn>"; "val g = <fn>"; "= 6" ]

(* ── fn calling a previously REPL-defined fn ──────────────────────────────

   Regression for the invalid-IR collision filed as the "Follow-up noticed,
   NOT fixed here" section of
   specs/progress/2026-08-24-orc-repl-segfault-fn-def-after-let-lambda.md:
   a `fn` fragment whose body CALLS a prior REPL binding emitted BOTH the
   prev-slot loader `define ptr @f()` and (via the unknown-function fallback
   in llvm_emit's EApp path) a `declare ptr @f(i64)` for the same symbol in
   one module — "invalid redefinition of function 'f'", after which the REPL
   reported "I cannot find `g`".  Broken identically under both backends, so
   pin both.  The call must route through the slot loader + closure dispatch
   (not a direct extern call) so it follows the slot's current contents. *)
let fn_calls_fn_session =
  [ "fn f(x) do x + 1 end";
    "fn g(x) do f(x) end";
    "g(41)";
    ":quit" ]
let fn_calls_fn_expected =
  [ "val f = <fn>"; "val g = <fn>"; "= 42" ]

let test_clang_fn_calls_prior_fn () =
  check_session ~backend:"clang" "clang fn calls prior fn"
    fn_calls_fn_session fn_calls_fn_expected

let test_orc_fn_calls_prior_fn () =
  check_session "orc fn calls prior fn"
    fn_calls_fn_session fn_calls_fn_expected

(* Same collision, let-bound-lambda flavor: the prior binding is a `let`
   holding a closure rather than a `fn`. *)
let fn_calls_let_lambda_session =
  [ "let h = fn x -> x + 5";
    "fn g2(x) do h(x) end";
    "g2(1)";
    ":quit" ]
let fn_calls_let_lambda_expected =
  [ "val g2 = <fn>"; "= 6" ]

let test_clang_fn_calls_let_lambda () =
  check_session ~backend:"clang" "clang fn calls let-bound lambda"
    fn_calls_let_lambda_session fn_calls_let_lambda_expected

let test_orc_fn_calls_let_lambda () =
  check_session "orc fn calls let-bound lambda"
    fn_calls_let_lambda_session fn_calls_let_lambda_expected

(* ── REPL session subprocess harness ──────────────────────────────────
   Runs the real `march` binary end-to-end with a scripted stdin session.
   A subprocess (rather than in-process Repl_jit calls) for two reasons:
   a backend crash (SIGSEGV) fails the one test instead of taking down the
   whole runner, and MARCH_JIT_BACKEND / MARCH_REPL_INTERP are read once at
   module init, so they can only differ per-PROCESS, not per-test.
   The session HOME is a directory this file creates itself rather than the
   ambient one: the REPL fatals on startup if $HOME/.cache cannot be created
   (so it cannot inherit a HOME that does not exist — dune's action pins one
   under _build that nothing creates), and an own directory keeps the stdlib
   precompile / JIT .so caches out of the developer's real ~/.cache. It is
   created once and shared by every session here, so only the first
   JIT-backed session pays the stdlib precompile. *)

let main_exe =
  Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

(* [session_home] (defined with the check_session harness above) is shared by
   both harnesses in this file — per-pid, so concurrent test runners never
   share a half-written cache. *)

let clang_available () =
  Sys.command "clang --version >/dev/null 2>&1" = 0

let contains ~needle hay =
  let nl = String.length needle and hl = String.length hay in
  let rec scan i = i + nl <= hl && (String.sub hay i nl = needle || scan (i + 1)) in
  nl = 0 || scan 0

(** Pipe [lines] into the REPL under [env_prefix] (e.g. "MARCH_JIT_BACKEND=orc"),
    returning (combined stdout+stderr, exit code; signals map to 128+n). *)
let run_repl_session ~env_prefix (lines : string list) : string * int =
  let input = Filename.temp_file "march_repl_session" ".txt" in
  let oc = open_out input in
  List.iter (fun l -> output_string oc l; output_char oc '\n') lines;
  close_out oc;
  let cmd = Printf.sprintf "HOME=%s %s %s < %s 2>&1"
      (Filename.quote (Lazy.force session_home))
      env_prefix (Filename.quote main_exe) (Filename.quote input) in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  (try
     while true do Buffer.add_channel buf ic 1 done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (try Sys.remove input with _ -> ());
  let code = match status with
    | Unix.WEXITED n -> n
    | Unix.WSIGNALED n | Unix.WSTOPPED n -> 128 + n
  in
  (Buffer.contents buf, code)

(* ── fn redefinition sessions ────────────────────────────────────────
   Redefining a REPL `fn` must take effect (Elixir-style rebinding, matching
   interpreter mode).  The JIT's run_decl used to skip ANY already-compiled
   bind_name (a guard meant only for :reset scroll-replay), silently keeping
   the first definition: f(1) = 2 instead of 101. *)

let redefinition_session =
  [ "fn f(x) do x + 1 end";
    "fn f(x) do x + 100 end";
    "f(1)" ]

let check_redefinition ~label (out, code) =
  Alcotest.(check int) (label ^ ": REPL exit code") 0 code;
  if not (contains ~needle:"= 101" out) then
    Alcotest.failf
      "%s: expected redefined f(1) = 101 in session output, got:\n%s"
      label out

let test_repl_session_fn_redefinition_clang () =
  if not (clang_available ()) then ()  (* skip: no clang on PATH *)
  else
    check_redefinition ~label:"clang backend"
      (run_repl_session ~env_prefix:"" redefinition_session)

let test_repl_session_fn_redefinition_orc () =
  if not (clang_available ()) then ()  (* skip: stdlib precompile needs clang *)
  else begin
    let (out, code) =
      run_repl_session ~env_prefix:"MARCH_JIT_BACKEND=orc" redefinition_session in
    (* No libLLVM on this machine: the ORC backend can't start at all. *)
    if contains ~needle:"libLLVM not found" out then ()
    else check_redefinition ~label:"orc backend" (out, code)
  end

let test_repl_session_fn_redefinition_interp () =
  check_redefinition ~label:"interpreter mode"
    (run_repl_session ~env_prefix:"MARCH_REPL_INTERP=1" redefinition_session)

(* Redefine-then-call across the two fixes that landed together: the
   slot-loader call routing (this branch) and fn-redefinition rebinding
   (#339).  Pins INTERPRETER PARITY, which is lexical: `g` keeps calling the
   `f` it was defined against (the redefinition gets a fresh slot; g's loader
   reads the slot index captured at g's compile time), while a direct call to
   `f` gets the new body.  MARCH_REPL_INTERP=1 answers 2 / 3 / 101 for this
   session, and both JIT backends must agree.  g(2)=3 (old body x+1, not
   x+100) is the distinguishing value — "= 2" alone could come from the
   pre-redefinition g(1). *)
let redefine_then_call_session =
  [ "fn f(x) do x + 1 end";
    "fn g(x) do f(x) end";
    "g(1)";
    "fn f(x) do x + 100 end";
    "g(2)";
    "f(1)";
    ":quit" ]

let check_redefine_then_call ~label (out, code) =
  Alcotest.(check int) (label ^ ": REPL exit code") 0 code;
  List.iter (fun needle ->
    if not (contains ~needle out) then
      Alcotest.failf
        "%s: expected %S in session output, got:\n%s" label needle out)
    [ "= 2"; "= 3"; "= 101" ]

let test_repl_session_redefine_then_call_clang () =
  if not (clang_available ()) then ()  (* skip: no clang on PATH *)
  else
    check_redefine_then_call ~label:"clang backend"
      (run_repl_session ~env_prefix:"" redefine_then_call_session)

let test_repl_session_redefine_then_call_orc () =
  if not (clang_available ()) then ()  (* skip: stdlib precompile needs clang *)
  else begin
    let (out, code) =
      run_repl_session ~env_prefix:"MARCH_JIT_BACKEND=orc"
        redefine_then_call_session in
    if contains ~needle:"libLLVM not found" out then ()
    else check_redefine_then_call ~label:"orc backend" (out, code)
  end

let () =
  Alcotest.run "march_jit" [
    "jit", [
      Alcotest.test_case "dlopen_libc" `Quick test_dlopen_libc;
      Alcotest.test_case "orc_available" `Quick test_orc_available_never_raises;
      Alcotest.test_case "orc_two_consecutive_fns" `Slow
        test_orc_two_consecutive_fns;
      Alcotest.test_case "orc_fn_after_let_lambda" `Slow
        test_orc_fn_after_let_lambda;
      Alcotest.test_case "clang_fn_calls_prior_fn" `Slow
        test_clang_fn_calls_prior_fn;
      Alcotest.test_case "orc_fn_calls_prior_fn" `Slow
        test_orc_fn_calls_prior_fn;
      Alcotest.test_case "clang_fn_calls_let_lambda" `Slow
        test_clang_fn_calls_let_lambda;
      Alcotest.test_case "orc_fn_calls_let_lambda" `Slow
        test_orc_fn_calls_let_lambda;
    ];
    "repl_session", [
      Alcotest.test_case "fn redefinition (clang JIT)" `Slow
        test_repl_session_fn_redefinition_clang;
      Alcotest.test_case "fn redefinition (ORC JIT)" `Slow
        test_repl_session_fn_redefinition_orc;
      Alcotest.test_case "fn redefinition (interpreter)" `Quick
        test_repl_session_fn_redefinition_interp;
      Alcotest.test_case "redefine then call through prior fn (clang JIT)" `Slow
        test_repl_session_redefine_then_call_clang;
      Alcotest.test_case "redefine then call through prior fn (ORC JIT)" `Slow
        test_repl_session_redefine_then_call_orc;
    ];
  ]
