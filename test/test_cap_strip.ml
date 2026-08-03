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

let compiler_exe = "./_build/default/bin/main.exe"

let compile src_text out_bin =
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
  fn main() : () do
    println(int_to_string(1 + 1))
  end
end
|}

let closure_src =
  {|
mod ClosureStripApp do
  needs IO.FileRead

  fn apply1(f : (String) -> a, p : String) : a do
    f(p)
  end

  fn main() : () do
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
