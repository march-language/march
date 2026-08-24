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

(* dune points HOME at _build/jit_home so the child's stdlib-prelude .so cache
   is per-build; dune does not create that directory, and the compiler's
   `mkdir $HOME/.cache` is non-recursive, so make it here. *)
let ensure_home () =
  match Sys.getenv_opt "HOME" with
  | None -> ()
  | Some h ->
    let mk d = try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> () in
    mk h; mk (Filename.concat h ".cache")

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
    Printf.sprintf "MARCH_JIT_BACKEND=%s %s < %s > %s 2>&1"
      backend (Filename.quote bin) (Filename.quote tmp_in) (Filename.quote tmp_out) in
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
      ensure_home ();
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
    ]
  ]
