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

(* ── `march --jit file.march` (whole-program JIT) ─────────────────────────

   Task 4.1: --jit runs a whole program through the in-process ORC JIT
   (Repl_jit.run_program) instead of the tree-walking interpreter.

   Driven as a SUBPROCESS, like [check_session] above, for two reasons:
   --jit is a CLI flag, so a subprocess IS the unit under test; and
   run_program calls the program's `main` on a green thread through
   march_spawn_main/march_run_scheduler, so a miscompile shows up as a
   fatal signal that must not be able to take the test runner with it.

   Uses the same per-pid [session_home] as the REPL harnesses, so the
   stdlib prelude .so is precompiled at most once per test run. *)
let run_jit_file ?home ?(lib_path = "") ?(extra_flags = "") ~env_prefix
    (src : string) : string * int =
  let home = match home with Some h -> h | None -> Lazy.force session_home in
  let f = Filename.temp_file "march_jit_file" ".march" in
  let oc = open_out f in
  output_string oc src;
  close_out oc;
  let out_path = Filename.temp_file "march_jit_file" ".out" in
  let lib_env =
    if lib_path = "" then ""
    else Printf.sprintf "MARCH_LIB_PATH=%s " (Filename.quote lib_path) in
  let cmd =
    Printf.sprintf "HOME=%s %s%s %s --jit%s %s > %s 2>&1"
      (Filename.quote home)
      lib_env env_prefix (Filename.quote main_exe)
      (if extra_flags = "" then "" else " " ^ extra_flags)
      (Filename.quote f)
      (Filename.quote out_path) in
  let code = Sys.command cmd in
  let ic = open_in_bin out_path in
  let out = really_input_string ic (in_channel_length ic) in
  close_in ic;
  (try Sys.remove f with _ -> ());
  (try Sys.remove out_path with _ -> ());
  (out, code)

let jit_file_fib_src = {|mod JitFileTest do
  needs IO.Console

  fn fib(n : Int) : Int do
    if n < 2 do n else fib(n - 1) + fib(n - 2) end
  end

  fn main(_c : Cap(IO.Console)) : Unit do
    println("checksum=" ++ int_to_string(fib(20)))
  end
end
|}

let check_jit_file ~label (out, code) needles =
  Alcotest.(check int)
    (Printf.sprintf "%s: exit code (output: %s)" label out) 0 code;
  List.iter (fun needle ->
      if not (contains ~needle out) then
        Alcotest.failf "%s: expected %S in output, got:\n%s" label needle out)
    needles

let test_jit_file_orc () =
  if not (clang_available ()) then ()  (* skip: stdlib precompile needs clang *)
  else begin
    let (out, code) =
      run_jit_file ~env_prefix:"MARCH_JIT_BACKEND=orc" jit_file_fib_src in
    if contains ~needle:"libLLVM not found" out then ()
    else check_jit_file ~label:"--jit (ORC backend)" (out, code) ["checksum=6765"]
  end

let test_jit_file_clang () =
  if not (clang_available ()) then ()
  else
    check_jit_file ~label:"--jit (clang backend)"
      (run_jit_file ~env_prefix:"MARCH_JIT_BACKEND=clang" jit_file_fib_src)
      ["checksum=6765"]

(* An actor program must not be JIT-compiled yet: it falls back to the
   interpreter with a notice on stderr, and still produces the right answer.
   Pins BOTH halves — a silent fallback would be indistinguishable from
   --jit having grown actor support. *)
let jit_file_actor_src = {|mod JitFileActorTest do
  needs IO.Console
  needs IO.Spawn

  actor Counter do
    state { n : Int }
    init  { n: 0 }

    on Total(reply_to) do
      Actor.reply(reply_to, state.n)
      state
    end

    on Ping(k : Int) do
      { n: state.n + k }
    end
  end

  type TotalReq = TotalReq

  fn main(_c : Cap(IO.Console), _s : Cap(IO.Spawn)) do
    let pid = spawn(Counter)
    send(pid, Ping(1))
    send(pid, Ping(1))
    run_until_idle()
    match Actor.call(pid, TotalReq, 30000) do
      Ok(n)  -> println("checksum=" ++ int_to_string(n))
      Err(e) -> println("call failed: " ++ e)
    end
  end
end
|}

let test_jit_file_actor_falls_back () =
  if not (clang_available ()) then ()
  else
    check_jit_file ~label:"--jit actor fallback"
      (run_jit_file ~env_prefix:"" jit_file_actor_src)
      [ "--jit does not support actor programs yet"; "checksum=2" ]

(* `--jit --debug` must not silently drop the time-travel debugger.  The
   debugger only exists in the tree-walking interpreter ([March_debug.Debug]
   hooks the eval loop), so --jit must fall back to the interpreter with a
   notice, same as the actor and stdlib-shadowing arms above, and the
   debugger banner + the program's own output must both still appear.  Pins
   BOTH halves — a silent fallback (--jit's pre-fix behavior: nothing printed,
   JIT ran anyway) would be indistinguishable from --jit having grown
   debugger support. *)
let test_jit_file_debug_falls_back () =
  if not (clang_available ()) then ()
  else
    check_jit_file ~label:"--jit --debug fallback"
      (run_jit_file ~env_prefix:"" ~extra_flags:"--debug" jit_file_fib_src)
      [ "--jit does not support the debugger; running interpreted";
        "[debug] Trace recording enabled";
        "checksum=6765" ]

(* ── Fix round 1 regressions ──────────────────────────────────────────── *)

(* Finding 1: OCaml's buffered diagnostics were DROPPED when the JIT'd program
   terminated through the C runtime's own `exit()` (panic_, exit_, a fatal
   signal), which never runs OCaml's at_exit.  Measured pre-fix on exactly
   this shape: warnings printed interpreted, ZERO printed under --jit, same
   exit code — so the warning was invisible precisely in the runs where the
   user most needs it.  `main` here warns (structurally-recursive `fib`) and
   then panics; both the warning and the program's own output must survive. *)
let jit_file_warn_then_panic_src = {|mod JitFileWarnPanic do
  needs IO.Console

  fn fib(n : Int) : Int do
    if n < 2 do n else fib(n - 1) + fib(n - 2) end
  end

  fn main(_c : Cap(IO.Console)) : Unit do
    println("checksum=" ++ int_to_string(fib(10)))
    panic_("boom")
  end
end
|}

(* This one case gets a PRIVATE HOME rather than the shared [session_home].
   Non-vacuousness originally depended on it: the shared home used to hold a
   stdlib prelude .so whose install-name pointed at a dead subprocess's
   runtime .so, so every later run there printed "stdlib cache load failed …,
   recompiling" — and that notice is written with an explicit flush, which
   incidentally drained the very stderr buffer this test exists to check.  On
   the shared home a pre-fix binary PASSED this test for that reason; on a
   private home it failed (warnings dropped), which is the point.

   That install-name bug is fixed (see
   specs/progress/2026-08-25-macos-install-name-dead-tmp-path.md and
   [test_prelude_so_loads_cross_process] below), so the shared home no longer
   emits the notice.  The private home stays anyway: it costs one stdlib
   precompile and keeps this test's stderr assertion independent of whatever
   the shared cache happens to print. *)
let flush_test_home = lazy (
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_jit_flush_home.%d" (Unix.getpid ())) in
  List.iter
    (fun d -> try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    [dir; Filename.concat dir ".cache"];
  dir)

let test_jit_file_flushes_diagnostics () =
  if not (clang_available ()) then ()
  else begin
    let (out, code) =
      run_jit_file ~home:(Lazy.force flush_test_home) ~env_prefix:""
        jit_file_warn_then_panic_src in
    (* panic_ exits nonzero — that is the whole point of this shape. *)
    Alcotest.(check int)
      (Printf.sprintf "--jit warn-then-panic: exit code (output: %s)" out) 1 code;
    List.iter (fun needle ->
        if not (contains ~needle out) then
          Alcotest.failf
            "--jit warn-then-panic: expected %S in output (host buffers not \
             flushed before handing control to JIT'd code?), got:\n%s"
            needle out)
      [ "not tail-recursive"; "checksum=55"; "panic: boom" ]
  end

(* Finding 2: a file with no `main` raised out of run_program as
   `Fatal error: exception Failure(...)` + an OCaml backtrace with rc=2.
   The interpreter is silent and exits 0 for such a file; --jit must match
   it exactly, and must decide that BEFORE emitting IR or spawning the
   scheduler. *)
let jit_file_no_main_src = {|mod JitFileNoMain do
  fn double(n : Int) : Int do n * 2 end
end
|}

let test_jit_file_no_main () =
  if not (clang_available ()) then ()
  else begin
    let (out, code) = run_jit_file ~env_prefix:"" jit_file_no_main_src in
    Alcotest.(check int)
      (Printf.sprintf "--jit no-main: exit code (output: %s)" out) 0 code;
    (* The program itself must contribute NOTHING — no crash, no backtrace.
       Asserted as "none of these appear" rather than out = "" on purpose:
       [precompile_stdlib] legitimately prints infrastructure notices ("stdlib
       cache load failed …, recompiling") whenever the shared session cache is
       cold or stale, and pinning byte-emptiness would make this test fail for
       a reason that has nothing to do with the no-main path.  Pre-fix output
       was `Fatal error: exception Failure("--jit: no `main` …")` + an OCaml
       backtrace with rc=2, so every needle below is decisive. *)
    List.iter (fun needle ->
        if contains ~needle out then
          Alcotest.failf
            "--jit no-main: output must not contain %S, got:\n%s" needle out)
      [ "Fatal error"; "Raised at"; "no `main`" ]
  end

(* Finding 3: --jit fed [get_stdlib_tc_env]'s seed env into run_program's
   typecheck unconditionally, bypassing the `no_shadowing` guard — and here
   the resulting type_map feeds LOWERING, so an unsound seed is worse than
   the wrong-diagnostics hazard the guard was originally added for.  A
   stdlib-shadowing program must fall back to the interpreter with a notice.

   Fixture is the shadowed-`Json` shape from test_tcenv_cli_cache.ml. *)
let jit_file_shadow_entry_src = {|mod JitFileShadowEntry do
  needs IO.Console

  fn main(_cap : Cap(IO.Console)) do
    println(Json.greet())
  end
end
|}

let test_jit_file_shadowing_falls_back () =
  if not (clang_available ()) then ()
  else begin
    let lib_dir =
      Filename.concat (Filename.get_temp_dir_name ())
        (Printf.sprintf "march_jit_shadow_lib.%d" (Unix.getpid ())) in
    (try Unix.mkdir lib_dir 0o755
     with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    let shadow = Filename.concat lib_dir "json.march" in
    let oc = open_out shadow in
    output_string oc "mod Json do\n  fn greet() do\n    \"shadow json\"\n  end\nend\n";
    close_out oc;
    let res =
      run_jit_file ~lib_path:lib_dir ~env_prefix:"" jit_file_shadow_entry_src in
    (try Sys.remove shadow with _ -> ());
    (try Unix.rmdir lib_dir with _ -> ());
    check_jit_file ~label:"--jit stdlib-shadowing fallback" res
      [ "--jit does not support stdlib-shadowing programs yet"; "shadow json" ]
  end

(* ── Cached stdlib prelude must be loadable from a DIFFERENT process ──────

   Regression for
   specs/progress/2026-08-25-macos-install-name-dead-tmp-path.md.

   Every cached .so in ~/.cache/march is compiled to a pid-suffixed
   "<name>.<pid>.tmp" and renamed into place (atomic publish; a concurrent
   session can never dlopen a half-written file).  The macOS linker stamps
   LC_ID_DYLIB with the path the file was BUILT at — the .tmp, which stops
   existing the instant the rename lands — and the prelude links against the
   runtime .so explicitly, so it recorded that dead path as its dependency and
   NO later process could ever dlopen it.  The failure was silent: the
   cache-hit path swallows the dlopen error and falls back to a full stdlib
   precompile, costing ~9.5s on every REPL / --jit start.

   Run a REPL session to populate the cache, then dlopen the published prelude
   .so from THIS process — a different process than the one that linked it,
   which is precisely what the bug broke.  Platform-neutral: it asserts the
   property (cross-process loadability), not the macOS mechanism.

   The prelude's own runtime symbols (e.g. native_float_arr_sum) are left
   undefined at link time and resolved at dlopen against the runtime .so.  The
   two platforms differ in HOW, and that difference decides both the bug and
   this test:

     - macOS: the prelude records an LC_LOAD_DYLIB dependency naming the
       runtime .so by its install-name (LC_ID_DYLIB).  THIS is what the bug
       corrupts — the runtime's install-name was the dead ".tmp" build path,
       so the prelude depended on a file that no longer exists.  A real
       Repl_jit session dlopens the runtime first, but that does NOT rescue a
       poisoned prelude: dyld matches an already-loaded image by install-name,
       and pre-fix BOTH the runtime's own ID and the prelude's dependency are
       the same ".tmp" string — so preloading the runtime would satisfy the
       dependency and mask the bug.  Hence on macOS we deliberately do NOT
       preload: the prelude must stand on the install-name path recorded in
       it, which is exactly the property under test.

     - Linux: the prelude has NO recorded path dependency on the runtime at
       all — just undefined symbols resolved via RTLD_GLOBAL, with the runtime
       dlopen'd first into the global namespace.  There is no stale path to go
       bad, so the macOS bug cannot occur here; the test only needs the
       runtime symbols present, so we preload the runtime .so to mirror the
       real load order (without it a HEALTHY prelude fails under RTLD_NOW
       purely for the missing symbol). *)
let test_prelude_so_loads_cross_process () =
  match march_bin () with
  | None ->
    Alcotest.(check pass) "prelude cross-process dlopen (skipped: no main.exe)" () ()
  | Some bin ->
    let (code, out) = run_jit_repl ~backend:"clang" bin ["1 + 1"; ":quit"] in
    Alcotest.(check int)
      (Printf.sprintf "populating REPL session exits 0 (output: %s)" out) 0 code;
    let cache_dir = Filename.concat (Lazy.force session_home) ".cache/march" in
    let entries =
      (try Sys.readdir cache_dir with Sys_error _ -> [||]) |> Array.to_list in
    let matching pfx =
      entries
      |> List.filter (fun f ->
          contains ~needle:pfx f && Filename.check_suffix f ".so")
      |> List.map (Filename.concat cache_dir) in
    let is_macos = Sys.file_exists "/System/Library/CoreServices" in
    (* Linux ONLY: load the runtime .so first (RTLD_GLOBAL, via Jit.dlopen) so
       the prelude's undefined runtime symbols resolve.  On macOS this would
       mask the very regression under test (see the note above), so skip it. *)
    if not is_macos then
      List.iter (fun so ->
        try ignore (March_jit.Jit.dlopen so) with _ -> ())
        (matching "libmarch_runtime");
    let preludes = matching "stdlib_prelude" in
    (* No prelude at all means the session never got as far as caching one
       (e.g. no clang on this box) — nothing to regress against. *)
    if preludes = [] then
      Alcotest.(check pass) "prelude cross-process dlopen (skipped: no cached prelude)" () ()
    else
      List.iter (fun so ->
        match March_jit.Jit.dlopen so with
        | handle -> March_jit.Jit.dlclose handle
        | exception exn ->
          Alcotest.failf
            "cached stdlib prelude %s cannot be dlopen'd from another process \
             (the prelude cache is therefore dead weight and every session \
             silently recompiles the stdlib): %s"
            so (Printexc.to_string exn))
        preludes

(* Regression: mutually tail-recursive functions must become a LOOP under
   --jit, exactly as they do when compiled.

   [Llvm_repl.emit_fns_fragment] used to emit every function individually,
   never calling [Llvm_tco.find_mutual_tco_groups] /
   [emit_mutual_tco_group] the way [Llvm_toplevel.emit_module] does.  A
   mutual tail-call cycle therefore compiled to real native recursion in a
   JIT fragment, burning one frame per iteration.  Fragments run on a green
   thread capped at MARCH_STACK_MAX (1 MiB, runtime/march_scheduler.h), so a
   few thousand iterations ran off the stack reservation and the scheduler's
   guard-page handler killed the process via `_exit(128 + sig)` — a bare exit
   138 with NO output and no backtrace.

   `JsonStream`'s tokenizer (`go` / `free_byte` / `str_byte` / `num_byte` /
   `lit_byte` / …) is exactly such a cycle, advancing one input byte per
   mutual tail call, so the default 64 KiB `feed` chunk below needs ~65k
   iterations — far past the cliff.  This is the reduced
   bench/interp/json_stream.march, kept at ITS record count and chunk size so
   the assertion below is the benchmark's own cross-checked value.

   The assertion must pin BOTH halves: exit 0 (the crash was a signal death,
   which produces no output at all) and the checksum (a stack-starved run
   that somehow limped to completion would still be wrong). *)
let jit_file_json_stream_src = {|mod JitFileJsonStream do
  needs IO.Console

pfn build_records(n, acc) do
  if n <= 0 do acc
  else
    build_records(n - 1,
      Cons("{\"id\": " ++ to_string(n) ++ ", \"name\": \"user-" ++ to_string(n)
           ++ "\", \"active\": true, \"tags\": [1, 2, 3]}\n", acc))
  end
end

fn main(_cap_console : Cap(IO.Console)) do
  let n = 2000
  let src = string_join(build_records(n, Nil), "")
  let total = run_chunked(src, 0, JsonStream.start_ndjson(), 0)
  println("checksum=" ++ to_string(total))
end

pfn run_chunked(src, off, st, n) do
  let sz = string_byte_length(src)
  if off >= sz do
    match JsonStream.finish(st) do
    Err(_) -> 0 - 1
    Ok(evs) -> n + count_list(evs)
    end
  else
    let take = if sz - off < 65536 do sz - off else 65536 end
    match JsonStream.feed(st, string_slice(src, off, take)) do
    Err(_) -> 0 - 1
    Ok((evs, st2)) -> run_chunked(src, off + take, st2, n + count_list(evs))
    end
  end
end

pfn count_list(evs) do
  count_go(evs, 0)
end

pfn count_go(evs, acc) do
  match evs do
  Nil -> acc
  Cons(_, t) -> count_go(t, acc + 1)
  end
end

end
|}

let test_jit_file_mutual_tco_no_stack_overflow () =
  if not (clang_available ()) then ()
  else begin
    let (out, code) = run_jit_file ~env_prefix:"" jit_file_json_stream_src in
    if contains ~needle:"libLLVM not found" out then ()
    else
      check_jit_file ~label:"--jit mutual-TCO (JsonStream tokenizer)"
        (out, code) ["checksum=28000"]
  end

(* ── stdlib ADT constructor tags ─────────────────────────────────────
   A stdlib constructor typed at the REPL used to be built with tag 0 and
   every `match` arm compared against 0, so the FIRST arm always won:

     match Logger.Warn do Logger.Debug -> 0 | Logger.Info -> 1
                        | Logger.Warn -> 2 | Logger.Error -> 3 end
       JIT:    0   (wrong — and wrong for Info and Error too)
       interp: 2

   A wrong answer, not a rendering defect.  Cause: the warm-cache startup
   path dlopens the prelude .so without lowering stdlib to TIR, so no stdlib
   type_def reached the expression fragment's `~types` list and codegen's
   ctor_entry lookup took its `ce_tag = 0` default; the cold path lowered but
   then dropped tm_types on the floor.  See
   specs/progress/2026-08-24-repl-jit-stdlib-adt-ctor-tags.md.

   Run TWICE against the same HOME on purpose: the first session may build
   the prelude cache (cold), the second is guaranteed to hit it (warm), and
   the warm path is the one that was broken. *)

let stdlib_ctor_tags_session =
  [ "match Logger.Debug do Logger.Debug -> 0 | Logger.Info -> 1 | Logger.Warn -> 2 | Logger.Error -> 3 end";
    "match Logger.Info do Logger.Debug -> 0 | Logger.Info -> 1 | Logger.Warn -> 2 | Logger.Error -> 3 end";
    "match Logger.Warn do Logger.Debug -> 0 | Logger.Info -> 1 | Logger.Warn -> 2 | Logger.Error -> 3 end";
    "match Logger.Error do Logger.Debug -> 0 | Logger.Info -> 1 | Logger.Warn -> 2 | Logger.Error -> 3 end";
    "match Http.Post do Http.Get -> \"get\" | Http.Post -> \"post\" | _ -> \"other\" end";
    "Http.Post" ]

let check_stdlib_ctor_tags ~label (out, code) =
  Alcotest.(check int) (label ^ ": REPL exit code") 0 code;
  (* Each level must reach its OWN arm.  All four asserted together: with the
     bug every one of them answered 0, so checking only Debug (which answers
     0 correctly by luck, being variant 0) would pass on the broken build. *)
  List.iter (fun (needle, what) ->
    if not (contains ~needle out) then
      Alcotest.failf "%s: expected %s (%s) in session output, got:\n%s"
        label needle what out)
    [ "= 0", "Logger.Debug -> 0";
      "= 1", "Logger.Info -> 1";
      "= 2", "Logger.Warn -> 2";
      "= 3", "Logger.Error -> 3";
      "= \"post\"", "match Http.Post takes the Post arm";
      "= Post", "Http.Post renders as its constructor, not #<tag:N>" ]

let test_repl_stdlib_ctor_tags_jit () =
  if not (clang_available ()) then ()  (* skip: stdlib precompile needs clang *)
  else begin
    (* Cold (or at least first) session — also writes the prelude cache. *)
    check_stdlib_ctor_tags ~label:"JIT, first session"
      (run_repl_session ~env_prefix:"" stdlib_ctor_tags_session);
    (* Warm session against the same HOME: the cache-hit path. *)
    check_stdlib_ctor_tags ~label:"JIT, warm cache"
      (run_repl_session ~env_prefix:"" stdlib_ctor_tags_session)
  end

(* Parity control: the tree-walking interpreter was always right here, so a
   failure in THIS case means the witness itself broke, not the JIT. *)
let test_repl_stdlib_ctor_tags_interp () =
  check_stdlib_ctor_tags ~label:"interpreter mode"
    (run_repl_session ~env_prefix:"MARCH_REPL_INTERP=1" stdlib_ctor_tags_session)

let () =
  Alcotest.run "march_jit" [
    "jit", [
      Alcotest.test_case "dlopen_libc" `Quick test_dlopen_libc;
      Alcotest.test_case "orc_available" `Quick test_orc_available_never_raises;
      Alcotest.test_case "prelude .so loads cross-process" `Slow
        test_prelude_so_loads_cross_process;
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
      Alcotest.test_case "stdlib ADT ctor tags, cold and warm cache (JIT)" `Slow
        test_repl_stdlib_ctor_tags_jit;
      Alcotest.test_case "stdlib ADT ctor tags (interpreter)" `Quick
        test_repl_stdlib_ctor_tags_interp;
    ];
    "jit_file", [
      Alcotest.test_case "march --jit runs a whole program (ORC JIT)" `Slow
        test_jit_file_orc;
      Alcotest.test_case "march --jit runs a whole program (clang JIT)" `Slow
        test_jit_file_clang;
      Alcotest.test_case "march --jit falls back to the interpreter for actors"
        `Slow test_jit_file_actor_falls_back;
      Alcotest.test_case
        "march --jit --debug falls back to the interpreter for the debugger"
        `Slow test_jit_file_debug_falls_back;
      Alcotest.test_case
        "march --jit flushes host diagnostics before JIT'd code exits"
        `Slow test_jit_file_flushes_diagnostics;
      Alcotest.test_case "march --jit on a file with no main is silent, exit 0"
        `Slow test_jit_file_no_main;
      Alcotest.test_case
        "march --jit falls back to the interpreter when stdlib is shadowed"
        `Slow test_jit_file_shadowing_falls_back;
      Alcotest.test_case
        "march --jit loops mutual tail calls instead of overflowing the stack"
        `Slow test_jit_file_mutual_tco_no_stack_overflow;
    ];
  ]
