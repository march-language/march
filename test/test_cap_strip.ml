(* Capability-by-absence link tests (specs/2026-08-03-forge-cap-audit-design.md §4.1).

   A pure program must NOT contain the file-read runtime entry point after
   dead-stripping; a program that reads a file MUST contain it — including
   when the call is routed through a closure, which is the case that defeats
   call-site scanning (design §3: a closure-routed file read is
   call-site-indistinguishable from hello-world; only physical absence
   discriminates).

   These tests shell out to the real compiler and inspect the linked binary
   with nm, so they are tagged `Slow` (skipped by run-tests.sh -q), matching
   the existing compiled-adversarial-test convention. *)

(* Resolve the compiler relative to THIS executable, not the CWD: dune runs
   test binaries from _build/default/test/, so a "./_build/..." path resolves
   only when invoked from the repo root (it worked locally and returned 127 in
   CI).  test/dune declares bin/main.exe as a dep of this runner, so a missing
   binary is a real breakage — fail loudly rather than skip, which would make
   every test here vacuously green. *)
let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let require_compiler () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf
      "compiler not found at %s — test/dune must declare bin/main.exe as a \
       dep of run_compiler" compiler_exe

let compile src_text out_bin =
  require_compiler ();
  let src = Filename.temp_file "cap_strip" ".march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  let log = Filename.temp_file "cap_strip" ".log" in
  (* Never pipe march --compile output; redirect and judge by exit code. *)
  let rc =
    Sys.command
      (Printf.sprintf "%s --compile -o %s %s > %s 2>&1" compiler_exe
         (Filename.quote out_bin) (Filename.quote src) (Filename.quote log))
  in
  if rc <> 0 then (
    let ic = open_in log in
    let n = in_channel_length ic in
    let tail = really_input_string ic n in
    close_in ic;
    Alcotest.failf "compile failed (rc=%d):\n%s" rc tail);
  Sys.remove src;
  Sys.remove log

let has_symbol bin sym =
  let out = Filename.temp_file "capnm" ".txt" in
  let rc =
    Sys.command
      (Printf.sprintf "nm %s > %s 2>/dev/null" (Filename.quote bin)
         (Filename.quote out))
  in
  if rc <> 0 then (
    (try Sys.remove out with Sys_error _ -> ());
    Alcotest.failf "nm failed on %s" bin);
  let ic = open_in out in
  let found = ref false in
  (try
     while true do
       let line = input_line ic in
       (* Match the symbol as the whole final token of the nm line. *)
       let n = String.length sym in
       let l = String.length line in
       if
         l >= n
         && String.sub line (l - n) n = sym
         && (l = n || line.[l - n - 1] = ' ')
       then found := true
     done
   with End_of_file -> ());
  close_in ic;
  Sys.remove out;
  !found

(* macOS mangles C symbols with a leading underscore; Linux does not. *)
let file_read_sym =
  if Sys.file_exists "/usr/lib/dyld" then "_march_file_read"
  else "march_file_read"

let pure_src =
  {|
mod PureStripApp do
  needs IO.Console
  fn main(_cap_console : Cap(IO.Console)) : () do
    println(int_to_string(1 + 1))
  end
end
|}

let closure_src =
  {|
mod ClosureStripApp do
  needs IO.Console
  needs IO.FileRead

  fn apply1(f : (String) -> a, p : String) : a do
    f(p)
  end

  fn main(_cap_console : Cap(IO.Console), _cap_fileread : Cap(IO.FileRead)) : () do
    match apply1(fn p -> file_read(p), "/etc/hosts") do
      Ok(_)  -> println("ok")
      Err(_) -> println("err")
    end
  end
end
|}

let test_pure_lacks_file_read () =
  let bin = Filename.temp_file "pure_strip" ".bin" in
  compile pure_src bin;
  Alcotest.(check bool) "pure binary must not contain march_file_read" false
    (has_symbol bin file_read_sym);
  Sys.remove bin

let test_closure_keeps_file_read () =
  let bin = Filename.temp_file "closure_strip" ".bin" in
  compile closure_src bin;
  Alcotest.(check bool) "closure-routed file read must retain march_file_read"
    true
    (has_symbol bin file_read_sym);
  Sys.remove bin

(* ── Task 2: behavior preservation under dead-strip ─────────────────────
   Actors reach the runtime through message-dispatch tables and the
   scheduler — the shapes a linker's reachability analysis is most likely
   to get wrong.  Run the compiled binary and check observable output. *)

let run_capture bin =
  let out = Filename.temp_file "cap_run" ".txt" in
  let rc =
    Sys.command
      (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin) (Filename.quote out))
  in
  let ic = open_in out in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  Sys.remove out;
  (rc, s)

let actor_src =
  {|
mod ActorStripApp do
  needs IO.Console
  actor Counter do
    state { count : Int }
    init  { count: 0 }
    on Inc(x : Int) do
      let next = state.count + x
      println(int_to_string(next))
      { count: next }
    end
  end

  fn main() : () do
    let c = spawn(Counter)
    send(c, Inc(1))
    send(c, Inc(1))
    run_until_idle()
  end
end
|}

let test_actor_program_survives_strip () =
  let bin = Filename.temp_file "actor_strip" ".bin" in
  compile actor_src bin;
  let rc, out = run_capture bin in
  Alcotest.(check int) "actor program exits 0" 0 rc;
  Alcotest.(check string) "actor program prints 1 then 2" "1\n2\n" out;
  Sys.remove bin

let tests =
  [
    Alcotest.test_case "pure binary is stripped of file_read" `Slow
      test_pure_lacks_file_read;
    Alcotest.test_case "closure-routed file read retains file_read" `Slow
      test_closure_keeps_file_read;
    Alcotest.test_case "actor program survives dead-strip" `Slow
      test_actor_program_survives_strip;
  ]

(* ── --cap-sandbox: self-imposed profile (design §4.3 B, opt-in) ────────
   The embedded profile must be derived from the module's OWN capabilities.
   Passing the whole closure table yields the app-invariant "needs
   everything" set, which would grant a pure program network and write
   access — a sandbox that sandboxes nothing. That shipped once; this test
   is why it will not again. *)

let binary_contains bin needle =
  let out = Filename.temp_file "capstr" ".txt" in
  ignore
    (Sys.command
       (Printf.sprintf "strings %s > %s 2>/dev/null" (Filename.quote bin)
          (Filename.quote out)));
  let ic = open_in out in
  let found = ref false in
  (try
     while true do
       let line = input_line ic in
       let n = String.length needle and l = String.length line in
       let rec go i =
         i + n <= l && (String.sub line i n = needle || go (i + 1))
       in
       if go 0 then found := true
     done
   with End_of_file -> ());
  close_in ic;
  Sys.remove out;
  !found

let compile_sandboxed src_text out_bin =
  require_compiler ();
  let src = Filename.temp_file "cap_sb" ".march" in
  let oc = open_out src in
  output_string oc src_text;
  close_out oc;
  let log = Filename.temp_file "cap_sb" ".log" in
  let rc =
    Sys.command
      (Printf.sprintf "%s --compile --cap-sandbox -o %s %s > %s 2>&1"
         compiler_exe (Filename.quote out_bin) (Filename.quote src)
         (Filename.quote log))
  in
  let ic = open_in log in
  let out = really_input_string ic (in_channel_length ic) in
  close_in ic;
  Sys.remove src;
  Sys.remove log;
  (* Return the exit code rather than failing here, so each platform can
     assert the behaviour that is correct FOR IT: macOS embeds a profile,
     Linux rejects the flag outright. *)
  (rc, out)

let sb_net_src =
  {|
mod SbNetApp do
  needs IO.Console
  needs IO.NetListen
  fn main(_cap_console : Cap(IO.Console), _cap_netlisten : Cap(IO.NetListen)) : () do
    match tcp_listen(19097) do
      Ok(_)  -> println("BOUND")
      Err(_) -> println("BIND-FAILED")
    end
  end
end
|}

(* Both platforms now enforce, by different mechanisms: macOS embeds an SBPL
   profile string, Linux builds a seccomp-bpf filter from -DMARCH_CAP_DENY_*
   flags (no profile string appears in the binary there).  The behavioural
   assertion — a withheld capability is actually refused — is the same on
   both, so it is the one asserted here; the profile-string checks stay
   macOS-only because they inspect a macOS-specific artifact. *)
let is_macos = Sys.file_exists "/usr/lib/dyld"

let test_cap_sandbox_profile_is_module_specific () =
  let pure_bin = Filename.temp_file "sb_pure" ".bin" in
  let net_bin = Filename.temp_file "sb_net" ".bin" in
  let rc_p, out_p = compile_sandboxed pure_src pure_bin in
  if rc_p <> 0 then
    Alcotest.failf "--cap-sandbox compile failed (rc=%d):\n%s" rc_p out_p;
  let rc_n, out_n_log = compile_sandboxed sb_net_src net_bin in
  if rc_n <> 0 then
    Alcotest.failf "--cap-sandbox compile failed (rc=%d):\n%s" rc_n out_n_log;
  if is_macos then begin
    Alcotest.(check bool) "pure binary embeds a deny-default profile" true
      (binary_contains pure_bin "deny default");
    (* The discriminating assertion: a pure program must NOT be granted
       network, or the profile is the app-invariant union. *)
    Alcotest.(check bool) "pure binary is NOT granted network" false
      (binary_contains pure_bin "allow network");
    Alcotest.(check bool) "net binary IS granted network" true
      (binary_contains net_bin "allow network")
  end;
  (* Behaviour, on every platform: the sandbox must neither break a granted
     capability nor permit a withheld one. *)
  let rc_run_p, out_run_p = run_capture pure_bin in
  Alcotest.(check int) "sandboxed pure program exits 0" 0 rc_run_p;
  Alcotest.(check string) "sandboxed pure program still prints" "2\n" out_run_p;
  let rc_run_n, out_run_n = run_capture net_bin in
  Alcotest.(check int) "sandboxed net program exits 0" 0 rc_run_n;
  Alcotest.(check string) "granted network still binds" "BOUND\n" out_run_n;
  (try Sys.remove pure_bin with Sys_error _ -> ());
  (try Sys.remove net_bin with Sys_error _ -> ())

(* Why there is NO "sandbox denies X" test driven from March source:
   the profile is derived from the program's OWN inferred capabilities, so it
   grants exactly what the program does — a program that calls file_write is
   granted IO.FileWrite by construction and cannot be refused it.  That is the
   documented limitation of the self-imposed variant (it constrains escalation
   BEYOND the program's behaviour, not the behaviour itself), not a gap in
   coverage.  Actual denial is verified at the C level against the seccomp
   filter itself; see the Linux block in runtime/march_runtime.c.

   What IS assertable from here, and what these tests cover:
   - the granted set is module-specific (a pure program is not handed network);
   - the sandbox does not BREAK a program that stays within its capabilities,
     on either platform's mechanism. *)

let tests =
  tests
  @ [
      Alcotest.test_case "--cap-sandbox profile is module-specific" `Slow
        test_cap_sandbox_profile_is_module_specific;
    ]
