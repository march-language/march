(* Concurrent `--compile` of the SAME source must not share the IR file clang
   reads.

   `march --compile` leaves its LLVM IR at `<source-without-ext>.ll`, beside
   the source, whatever `-o` says — tests and tooling read it there.  It used
   to WRITE it there too and hand clang that path, so two concurrent compiles
   of one source (different `-o` / `--opt`) raced on the one file: one
   truncated and rewrote it while the other's clang was reading it.  CI hit it
   on test/dune's `native_qctor_collision` and `native_qctor_collision_opt0`
   rules, which compile the same entry.march: the opt0 link read a
   half-written module and failed with `Undefined symbols: "_main"`.

   The natural race window is the few microseconds between the rewriting
   compile's open_out (truncate) and its write, so a plain stress run almost
   never loses it (0 failures in ~350 unsynchronised compiles on a dev Mac).
   [test_ir_not_replaced_under_clang] therefore makes it deterministic: a
   `clang` shim first on PATH parks the FIRST compile's clang on its `.ll`
   input, a second compile of the same source runs to completion meanwhile,
   and the parked clang then checks its input is still the file it was handed
   (same inode, same bytes) before exec'ing the real clang.  Sharing the path
   fails that check every time; a per-process temp passes it.
   [test_concurrent_compiles_stress] is the unsynchronised version, kept as a
   contract: every binary runs, `<source>.ll` is still there afterwards and no
   temp IR is left behind.

   Each compile runs from its own fresh CWD: the CAS artifact store lives
   under the CWD, and a cache hit skips IR emission and clang altogether,
   which would leave nothing to race. *)

(* Exe-relative, for the same reason as test_cap_strip.ml: a CWD-relative
   path returns 127 under dune's test runner. *)
let compiler_exe =
  let exe_dir = Filename.dirname Sys.executable_name in
  Filename.concat exe_dir "../bin/main.exe"

let probe_src = {|
mod LlRaceProbe do
  needs IO.Console

  fn main(_c : Cap(IO.Console)) : Unit do
    let xs = List.map(List.range(0, 40), fn x -> x * 3)
    println("ll-race " ++ int_to_string(List.length(xs)))
  end
end
|}

let expected_output = "ll-race 40"

let write_file path s =
  let oc = open_out path in
  output_string oc s;
  close_out oc

let read_file path =
  try
    let ic = open_in_bin path in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    s
  with Sys_error _ -> ""

let rec rm_rf p =
  match Sys.is_directory p with
  | true ->
    Array.iter (fun c -> rm_rf (Filename.concat p c)) (Sys.readdir p);
    (try Unix.rmdir p with Unix.Unix_error _ -> ())
  | false -> (try Sys.remove p with Sys_error _ -> ())
  | exception Sys_error _ -> ()

let with_scratch f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "march_ll_race.%d.%d" (Unix.getpid ())
       (Hashtbl.hash (Unix.gettimeofday ()))) in
  Unix.mkdir dir 0o755;
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () -> f dir)

let mkdir_in dir name =
  let p = Filename.concat dir name in
  Unix.mkdir p 0o755;
  p

(* `sh -c` so each compile gets its own CWD and redirects its own output —
   never through a pipe (a piped `--compile` can hang). *)
let compile_cmd ~cwd ~opt ~out ~src ~log =
  Printf.sprintf "cd %s && exec %s --compile%s -o %s %s > %s 2>&1"
    (Filename.quote cwd) (Filename.quote compiler_exe) opt
    (Filename.quote out) (Filename.quote src) (Filename.quote log)

let spawn ?env cmd =
  let env = match env with Some e -> e | None -> Unix.environment () in
  Unix.create_process_env "/bin/sh" [| "/bin/sh"; "-c"; cmd |] env
    Unix.stdin Unix.stdout Unix.stderr

let wait_rc pid =
  match snd (Unix.waitpid [] pid) with
  | Unix.WEXITED n -> n
  | Unix.WSIGNALED s | Unix.WSTOPPED s -> 128 + s

let run_binary bin =
  let out = bin ^ ".out" in
  let rc =
    Sys.command
      (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin) (Filename.quote out))
  in
  (rc, String.trim (read_file out))

let require_compiler () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf
      "compiler not found at %s — test/dune must declare bin/main.exe as a dep \
       of run_compiler.exe" compiler_exe

let check_binary ~what bin log =
  if not (Sys.file_exists bin) then
    Alcotest.failf "%s: no binary at %s; compile log:\n%s" what bin
      (read_file log);
  let rc, out = run_binary bin in
  Alcotest.(check int) (what ^ ": binary exits 0") 0 rc;
  Alcotest.(check string) (what ^ ": binary output") expected_output out

(* The final IR location is a contract (test/dune rules, test_cap_markers.ml,
   scripts/ir-oracle.sh read it), and the per-process temp must never leak. *)
let check_ir_left_in_place dir =
  Alcotest.(check bool) "<source>.ll exists beside the source" true
    (Sys.file_exists (Filename.concat dir "race.ll"));
  let leftovers =
    Sys.readdir dir |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".tmp.ll")
  in
  Alcotest.(check (list string)) "no temp IR left behind" [] leftovers

let real_clang () =
  let tmp = Filename.temp_file "ll_race_which" ".txt" in
  let rc =
    Sys.command (Printf.sprintf "command -v clang > %s 2>/dev/null"
                   (Filename.quote tmp))
  in
  let p = String.trim (read_file tmp) in
  (try Sys.remove tmp with Sys_error _ -> ());
  if rc <> 0 || p = "" then Alcotest.fail "clang not found on PATH";
  p

(* The clang shim.  Only the first invocation that is handed a `.ll` parks
   (`mkdir` is the atomic claim); every other call — the second compile's
   link, runtime-object cache builds — passes straight through. *)
let shim_script ~gate ~clang =
  Printf.sprintf {|#!/bin/sh
ll=
for a in "$@"; do case "$a" in *.ll) ll=$a ;; esac; done
if [ -n "$ll" ] && mkdir %s/held 2>/dev/null; then
  before=$(ls -i "$ll"; cksum < "$ll")
  : > %s/holding
  n=0
  while [ ! -e %s/release ] && [ $n -lt 1800 ]; do sleep 0.1; n=$((n+1)); done
  after=$(ls -i "$ll" 2>/dev/null; cksum < "$ll" 2>/dev/null)
  if [ "$before" != "$after" ]; then
    echo "ll-race: $ll was replaced while clang held it" >&2
    exit 97
  fi
fi
exec %s "$@"
|} (Filename.quote gate) (Filename.quote gate) (Filename.quote gate)
    (Filename.quote clang)

let test_ir_not_replaced_under_clang () =
  require_compiler ();
  let clang = real_clang () in
  with_scratch (fun dir ->
    let src = Filename.concat dir "race.march" in
    write_file src probe_src;
    let gate = mkdir_in dir "gate" in
    let shim_dir = mkdir_in dir "shim" in
    let shim = Filename.concat shim_dir "clang" in
    write_file shim (shim_script ~gate ~clang);
    Unix.chmod shim 0o755;
    let path = try Sys.getenv "PATH" with Not_found -> "/usr/bin:/bin" in
    let env =
      Unix.environment () |> Array.to_list
      |> List.filter (fun kv ->
          not (String.length kv >= 5 && String.sub kv 0 5 = "PATH="))
      |> List.cons ("PATH=" ^ shim_dir ^ ":" ^ path)
      |> Array.of_list
    in
    let bin_a = Filename.concat dir "a.bin" and log_a = Filename.concat dir "a.log" in
    let bin_b = Filename.concat dir "b.bin" and log_b = Filename.concat dir "b.log" in
    (* A: --opt 0, parked by the shim once its clang is handed the IR. *)
    let pid_a =
      spawn ~env (compile_cmd ~cwd:(mkdir_in dir "cwd_a") ~opt:" --opt 0"
                    ~out:bin_a ~src ~log:log_a)
    in
    let holding = Filename.concat gate "holding" in
    let deadline = Unix.gettimeofday () +. 300. in
    let rec await_park () =
      if Sys.file_exists holding then ()
      else
        match Unix.waitpid [ Unix.WNOHANG ] pid_a with
        | (0, _) ->
          if Unix.gettimeofday () > deadline then begin
            (try Unix.kill pid_a Sys.sigkill with Unix.Unix_error _ -> ());
            ignore (Unix.waitpid [] pid_a);
            Alcotest.failf "compile A never reached clang; log:\n%s"
              (read_file log_a)
          end;
          Unix.sleepf 0.05;
          await_park ()
        | _ ->
          Alcotest.failf "compile A exited before reaching clang; log:\n%s"
            (read_file log_a)
    in
    await_park ();
    (* B: same source, default opt, runs start to finish while A's clang is
       parked on its input. *)
    let rc_b =
      wait_rc (spawn ~env (compile_cmd ~cwd:(mkdir_in dir "cwd_b") ~opt:""
                             ~out:bin_b ~src ~log:log_b))
    in
    write_file (Filename.concat gate "release") "";
    let rc_a = wait_rc pid_a in
    if rc_b <> 0 then
      Alcotest.failf "compile B failed (rc=%d):\n%s" rc_b (read_file log_b);
    if rc_a <> 0 then
      Alcotest.failf
        "compile A failed (rc=%d) — its clang input was rewritten by the \
         concurrent compile of the same source:\n%s" rc_a (read_file log_a);
    check_binary ~what:"compile A (--opt 0)" bin_a log_a;
    check_binary ~what:"compile B" bin_b log_b;
    check_ir_left_in_place dir)

let test_concurrent_compiles_stress () =
  require_compiler ();
  let rounds = 3 and jobs = 4 in
  for round = 1 to rounds do
    with_scratch (fun dir ->
      let src = Filename.concat dir "race.march" in
      write_file src probe_src;
      let procs =
        List.init jobs (fun i ->
          let bin = Filename.concat dir (Printf.sprintf "bin%d" i) in
          let log = Filename.concat dir (Printf.sprintf "log%d" i) in
          let opt = if i = 1 then " --opt 0" else "" in
          let cwd = mkdir_in dir (Printf.sprintf "cwd%d" i) in
          (spawn (compile_cmd ~cwd ~opt ~out:bin ~src ~log), bin, log, i))
      in
      List.iter (fun (pid, bin, log, i) ->
        let what = Printf.sprintf "round %d compile %d" round i in
        let rc = wait_rc pid in
        if rc <> 0 then
          Alcotest.failf "%s failed (rc=%d):\n%s" what rc (read_file log);
        check_binary ~what bin log) procs;
      check_ir_left_in_place dir)
  done

let tests =
  [ Alcotest.test_case "IR clang reads is not replaced by a concurrent compile"
      `Slow test_ir_not_replaced_under_clang;
    Alcotest.test_case "concurrent compiles of one source all link" `Slow
      test_concurrent_compiles_stress;
  ]
