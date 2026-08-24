(* test/test_jit.ml *)
let test_dlopen_libc () =
  (* On macOS, dlopen(NULL) gives the main program handle which includes libc *)
  let handle = March_jit.Jit.dlopen "" in
  (* getpid is always available *)
  let _sym = March_jit.Jit.dlsym handle "getpid" in
  March_jit.Jit.dlclose handle;
  Alcotest.(check pass) "dlopen/dlsym/dlclose round-trip" () ()

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

(* Per-process so concurrent test runners (dune runs suites in parallel) do
   not share a half-written cache — the same per-pid convention repl_jit.ml
   uses for its own artifact dir. *)
let session_home = lazy (
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_jit_test_home.%d" (Unix.getpid ())) in
  List.iter
    (fun d -> try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    [dir; Filename.concat dir ".cache"];
  dir)

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

let () =
  Alcotest.run "march_jit" [
    "jit", [
      Alcotest.test_case "dlopen_libc" `Quick test_dlopen_libc;
    ];
    "repl_session", [
      Alcotest.test_case "fn redefinition (clang JIT)" `Slow
        test_repl_session_fn_redefinition_clang;
      Alcotest.test_case "fn redefinition (ORC JIT)" `Slow
        test_repl_session_fn_redefinition_orc;
      Alcotest.test_case "fn redefinition (interpreter)" `Quick
        test_repl_session_fn_redefinition_interp;
    ];
  ]
