(** [Procs]: process supervision (G6 of
    specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md).

    The main case starts three copies of a compiled March program that print
    fifty numbered lines and then sleep, kills one from outside, and asserts
    that [supervise ~fail_fast:true] stops the other two within the grace
    period and that every log holds every line.

    Whether a process is gone is checked with [Unix.kill pid 0] (ESRCH), not
    by trusting a kill's return value: in some sandboxes [kill] succeeds and
    delivers nothing.

    Hermetic: compiles with the just-built compiler and the staged runtime and
    stdlib (see forge/test/dune). *)

open March_forge

let setup_hermetic_toolchain () =
  let resolve env_var =
    match Sys.getenv_opt env_var with
    | None | Some "" ->
      Printf.eprintf
        "test_procs: %s is not set. The dune rule must pass it (see \
         forge/test/dune); refusing to fall back to an ambient toolchain.\n"
        env_var;
      exit 2
    | Some rel ->
      if Filename.is_relative rel then Filename.concat (Sys.getcwd ()) rel else rel
  in
  let march = resolve "MARCH_TEST_BIN" in
  Unix.putenv "MARCH_RUNTIME_DIR" (resolve "MARCH_TEST_RUNTIME_DIR");
  Unix.putenv "MARCH_STDLIB" (resolve "MARCH_TEST_STDLIB_DIR");
  Unix.putenv "HOME" (Filename.temp_dir "march_hermetic_userhome_" "");
  march

let read_file path = In_channel.with_open_text path In_channel.input_all

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let sleeper_src = {|mod Sleeper do
  needs IO.Console
  fn lines(i : Int, n : Int) : () do
    if i > n do
      ()
    else
      println("line " ++ int_to_string(i))
      lines(i + 1, n)
    end
  end
  fn main(_c : Cap(IO.Console)) : () do
    lines(1, 50)
    println("ready")
    sleep_ms(600000)
  end
end
|}

(* Compiled once for the whole suite. *)
let sleeper : string Lazy.t = lazy (
  let march = setup_hermetic_toolchain () in
  let dir = Filename.temp_dir "forge_procs_" "" in
  let src = Filename.concat dir "sleeper.march" in
  Out_channel.with_open_text src (fun oc -> output_string oc sleeper_src);
  let exe = Filename.concat dir "sleeper" in
  let log = Filename.concat dir "compile.log" in
  let cmd = Printf.sprintf "cd %s && %s --compile -o %s %s > %s 2>&1"
      (Filename.quote dir) (Filename.quote march) (Filename.quote exe)
      (Filename.quote src) (Filename.quote log) in
  if Sys.command cmd <> 0 || not (Sys.file_exists exe) then
    Alcotest.failf "compiling the sleeper failed:\n%s" (read_file log);
  exe)

let gone pid =
  match Unix.kill pid 0 with
  | () -> false
  | exception Unix.Unix_error (Unix.ESRCH, _, _) -> true
  | exception Unix.Unix_error _ -> false

let wait_for ~timeout f =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec go () = f () || (Unix.gettimeofday () < deadline && (Unix.sleepf 0.05; go ())) in
  go ()

let log_sink () = { Procs.dir = Filename.temp_dir "forge_procs_logs_" ""; follow = None }

let test_fail_fast_stops_the_rest () =
  let exe = Lazy.force sleeper in
  let log = log_sink () in
  let procs = List.map (fun name ->
      Procs.spawn ~name ~env:[ ("SLEEPER_NAME", name) ] ~argv:[| exe |] ~log)
      [ "a"; "b"; "c" ] in
  let ready p = contains (read_file (Procs.log_path p)) "ready" in
  if not (wait_for ~timeout:30. (fun () -> List.for_all ready procs)) then
    Alcotest.fail "the sleepers never became ready";
  let b = List.nth procs 1 in
  Unix.kill (Procs.pid b) Sys.sigkill;
  let grace_ms = 2000 in
  let t0 = Unix.gettimeofday () in
  let statuses = Procs.supervise ~fail_fast:true ~grace_ms procs in
  let elapsed = Unix.gettimeofday () -. t0 in
  Alcotest.(check bool)
    (Printf.sprintf "stopped within the grace period (%.2fs)" elapsed)
    true (elapsed < float_of_int grace_ms /. 1000.);
  Alcotest.(check (list string)) "statuses in start order" [ "a"; "b"; "c" ]
    (List.map fst statuses);
  Alcotest.(check bool) "b died of the outside SIGKILL" true
    (List.assoc "b" statuses = Unix.WSIGNALED Sys.sigkill);
  List.iter (fun n ->
      Alcotest.(check bool) (n ^ " was stopped with SIGTERM") true
        (List.assoc n statuses = Unix.WSIGNALED Sys.sigterm))
    [ "a"; "c" ];
  List.iter (fun p ->
      Alcotest.(check bool) (Procs.name p ^ " is gone (kill 0 says ESRCH)") true
        (gone (Procs.pid p));
      let text = read_file (Procs.log_path p) in
      for i = 1 to 50 do
        if not (contains text (Printf.sprintf "line %d\n" i)) then
          Alcotest.failf "%s's log is missing line %d" (Procs.name p) i
      done)
    procs

let test_without_fail_fast_the_rest_keep_running () =
  let exe = Lazy.force sleeper in
  let log = log_sink () in
  let a = Procs.spawn ~name:"a" ~env:[] ~argv:[| exe |] ~log in
  let quick = Procs.spawn ~name:"quick" ~env:[] ~argv:[| "true" |] ~log in
  (match Procs.wait_any [ a; quick ] with
   | Some (p, st) ->
     Alcotest.(check string) "the quick one exits first" "quick" (Procs.name p);
     Alcotest.(check bool) "exit 0" true (st = Unix.WEXITED 0)
   | None -> Alcotest.fail "wait_any returned None with a proc running");
  Alcotest.(check bool) "a is still running" true (Procs.status a = None);
  Procs.stop_all [ a; quick ] ~grace_ms:2000;
  Alcotest.(check bool) "stop_all reaped a" true (gone (Procs.pid a))

let test_own_sigterm_stops_everything () =
  let exe = Lazy.force sleeper in
  let log = log_sink () in
  let a = Procs.spawn ~name:"a" ~env:[] ~argv:[| exe |] ~log in
  let c = Procs.spawn ~name:"c" ~env:[] ~argv:[| exe |] ~log in
  (* Something outside signals forge itself; it exits cleanly, which without
     fail_fast is not a reason to stop. *)
  let killer = Procs.spawn ~name:"killer" ~env:[] ~log
      ~argv:[| "sh"; "-c"; Printf.sprintf "sleep 1; kill -TERM %d" (Unix.getpid ()) |] in
  let statuses = Procs.supervise ~grace_ms:2000 [ a; c; killer ] in
  Alcotest.(check bool) "the killer exited 0" true
    (List.assoc "killer" statuses = Unix.WEXITED 0);
  List.iter (fun n ->
      Alcotest.(check bool) (n ^ " was stopped") true
        (List.assoc n statuses = Unix.WSIGNALED Sys.sigterm))
    [ "a"; "c" ];
  Alcotest.(check bool) "a is gone" true (gone (Procs.pid a));
  Alcotest.(check bool) "c is gone" true (gone (Procs.pid c))

let test_stop_kills_after_grace () =
  (* A process that ignores SIGTERM is SIGKILLed once the grace runs out. *)
  let log = log_sink () in
  let p = Procs.spawn ~name:"stubborn" ~env:[] ~log
      ~argv:[| "sh"; "-c"; "trap '' TERM; echo up; while :; do sleep 1; done" |] in
  ignore (wait_for ~timeout:10. (fun () -> contains (read_file (Procs.log_path p)) "up"));
  let t0 = Unix.gettimeofday () in
  Procs.stop p ~grace_ms:300;
  let elapsed = Unix.gettimeofday () -. t0 in
  Alcotest.(check bool) "SIGKILLed" true (Procs.status p = Some (Unix.WSIGNALED Sys.sigkill));
  Alcotest.(check bool) (Printf.sprintf "after the grace, not long after (%.2fs)" elapsed)
    true (elapsed >= 0.3 && elapsed < 5.);
  Alcotest.(check bool) "gone" true (gone (Procs.pid p))

let test_follow_prefixes_and_logs () =
  let lines = ref [] in
  let log = { (log_sink ()) with Procs.follow = Some (fun l -> lines := l :: !lines) } in
  let p = Procs.spawn ~name:"echo" ~env:[ ("GREETING", "hello") ] ~log
      ~argv:[| "sh"; "-c"; "echo \"$GREETING\"; echo there >&2; printf tail" |] in
  Alcotest.(check bool) "exited" true (Procs.wait_all ~timeout:10. [ p ]);
  Alcotest.(check (list string)) "each line prefixed, stderr too, last line flushed"
    [ "[echo] hello\n"; "[echo] there\n"; "[echo] tail\n" ] (List.rev !lines);
  Alcotest.(check string) "the log holds the raw output" "hello\nthere\ntail"
    (read_file (Procs.log_path p))

let test_unrunnable_exits_127 () =
  let log = log_sink () in
  let p = Procs.spawn ~name:"nope" ~env:[] ~log ~argv:[| "/no/such/program" |] in
  Alcotest.(check bool) "exited" true (Procs.wait_all ~timeout:10. [ p ]);
  Alcotest.(check bool) "127" true (Procs.status p = Some (Unix.WEXITED 127));
  Alcotest.(check bool) "the reason is in the log" true
    (contains (read_file (Procs.log_path p)) "cannot run /no/such/program")

let test_free_port () =
  let port = Procs.free_port () in
  Alcotest.(check bool) "a real port" true (port > 0 && port < 65536);
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect ~finally:(fun () -> Unix.close s) (fun () ->
      Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, port)))

let () =
  Alcotest.run "procs"
    [ ("procs",
       [ Alcotest.test_case "fail-fast stops the rest, logs complete" `Slow
           test_fail_fast_stops_the_rest;
         Alcotest.test_case "without fail-fast the rest keep running" `Slow
           test_without_fail_fast_the_rest_keep_running;
         Alcotest.test_case "forge's own SIGTERM stops everything" `Slow
           test_own_sigterm_stops_everything;
         Alcotest.test_case "stop SIGKILLs after the grace" `Quick test_stop_kills_after_grace;
         Alcotest.test_case "follow prefixes lines and still logs" `Quick
           test_follow_prefixes_and_logs;
         Alcotest.test_case "an unrunnable program exits 127" `Quick test_unrunnable_exits_127;
         Alcotest.test_case "free_port" `Quick test_free_port ]) ]
