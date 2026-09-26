(** `forge test --upgrade-from <ref>` (distributed-deploys plan, 6.6 and
    II.8; build step 8) on the fixtures under forge/test/fixtures/upgrade:

    - v1: a one-pool topology app whose hook spawns a Tally actor (handlers
      Add and Legacy) and a feeder task that keeps sending Legacy, plus
      test/upgrade_traffic.march, the traffic driver (a session on the old
      code, one spanning the deploy, one on the new code).
    - good: Tally's Legacy handler changes; its message type does not. The
      upgrade must PASS: every session completes, nothing dropped.
    - migrates: Tally loses Legacy and converts it with tally_migrate_msg;
      the old feeder's Legacy messages must be converted, none dropped.
    - drops: Tally loses its Legacy handler with no migrate_msg, so every
      Legacy message the old feeder sends after Tally moves is dropped and
      counted. The upgrade must FAIL, naming the dropped messages.
    - live: the role body changes, and the new body spawns a task that reads
      the Vault the old version's hook created and starts an Echo session of
      its own. The upgrade must PASS and the traffic must get the NEW body's
      answer: the body is called from the generated (non-reloadable) entry,
      and the patch runs green threads and sessions against the host
      process's runtime (2026-09-25, the patch-carries-its-own-runtime fix).

    Each case makes a git repository from v1 (the ref), copies the new
    version over its working tree, and runs the real forge. Hermetic like
    test_topology_run.ml: the just-built march and forge on a private PATH,
    an empty MARCH_HOME, a private HOME (the deploy key `forge` mints goes
    nowhere), the staged runtime and stdlib. *)

let getenv_abs v =
  match Sys.getenv_opt v with
  | None | Some "" ->
    Printf.eprintf "test_upgrade_from: %s is not set (see forge/test/dune)\n" v;
    exit 2
  | Some p -> if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

let read_file path = try In_channel.with_open_bin path In_channel.input_all with Sys_error _ -> ""

let contains s sub =
  let n = String.length s and k = String.length sub in
  let rec go i = i + k <= n && (String.sub s i k = sub || go (i + 1)) in
  go 0

let hermetic_env = lazy (
  let march = getenv_abs "MARCH_TEST_BIN" and forge = getenv_abs "FORGE_TEST_BIN" in
  let bin = Filename.temp_dir "upgrade_bin_" "" in
  Unix.symlink march (Filename.concat bin "march");
  Unix.symlink forge (Filename.concat bin "forge");
  [ ("PATH", bin ^ ":" ^ Option.value ~default:"/usr/bin:/bin" (Sys.getenv_opt "PATH"));
    ("MARCH_HOME", Filename.temp_dir "upgrade_mh_" "");
    ("HOME", Filename.temp_dir "upgrade_home_" "");
    ("MARCH_RUNTIME_DIR", getenv_abs "MARCH_TEST_RUNTIME_DIR");
    ("MARCH_STDLIB", getenv_abs "MARCH_TEST_STDLIB_DIR");
    (* The drain report waits this long for every actor to move; the
       fixtures leave a held endpoint behind, so shorter is only faster. *)
    ("MARCH_UPGRADE_DRAIN_S", "20") ])

let environment () =
  let env = Lazy.force hermetic_env in
  let keep kv = not (List.exists (fun (k, _) -> String.length kv > String.length k
                                                 && String.sub kv 0 (String.length k + 1) = k ^ "=") env) in
  Array.append (Array.of_list (List.map (fun (k, v) -> k ^ "=" ^ v) env))
    (Array.of_list (List.filter keep (Array.to_list (Unix.environment ()))))

let sh ~dir cmd =
  let rc = Sys.command (Printf.sprintf "cd %s && %s" (Filename.quote dir) cmd) in
  if rc <> 0 then Alcotest.failf "in %s: `%s` exited %d" dir cmd rc

(** A git repository holding v1 as its one commit, with [version]'s files
    copied over the working tree. *)
let project version =
  let fx = getenv_abs "UPGRADE_FIXTURES_DIR" in
  let dir = Filename.temp_dir "upgrade_app_" "" in
  (* dune stages the fixtures read-only and cp keeps the mode: the copy
     must be writable for the new version to be copied over it. *)
  sh ~dir (Printf.sprintf "cp -R %s/. . && chmod -R u+w . && rm -rf .forge .march" (Filename.quote (Filename.concat fx "v1")));
  sh ~dir "git init -q && git add -A && git -c user.email=forge-test@example.invalid -c user.name=forge-test commit -q -m v1";
  sh ~dir (Printf.sprintf "cp -R %s/. . && chmod -R u+w ." (Filename.quote (Filename.concat fx version)));
  dir

(** Run `forge test --upgrade-from HEAD` in [dir]: its exit code and output. *)
let run_upgrade dir =
  let out = Filename.concat dir "forge.out" in
  (* Resolved before the fork: dune passes the binaries as paths relative
     to its cwd, which the child's chdir would break. *)
  let env = environment () in
  let forge = Filename.concat (List.hd (String.split_on_char ':' (List.assoc "PATH" (Lazy.force hermetic_env)))) "forge" in
  let pid =
    match Unix.fork () with
    | 0 ->
      (try
         Unix.chdir dir;
         let fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
         Unix.dup2 fd Unix.stdout;
         Unix.dup2 fd Unix.stderr;
         Unix.execve forge [| "forge"; "test"; "--upgrade-from"; "HEAD" |] env
       with _ -> Unix._exit 127)
    | pid -> pid
  in
  let (_, st) = Unix.waitpid [] pid in
  ((match st with Unix.WEXITED n -> n | _ -> 255), read_file out)

let leftovers dir =
  let ic = Unix.open_process_args_in "pgrep" [| "pgrep"; "-f"; dir |] in
  let s = String.trim (In_channel.input_all ic) in
  ignore (Unix.close_process_in ic);
  if s = "" then [] else String.split_on_char '\n' s

let expect out s = if not (contains out s) then Alcotest.failf "expected %S in forge's output:\n%s" s out

let after_run dir =
  Alcotest.(check (list string)) "no process left running" [] (leftovers dir);
  Alcotest.(check bool) "the ref's worktree was removed" false
    (Sys.file_exists (Filename.concat dir ".forge/upgrade/HEAD"));
  Alcotest.(check string) "the upgrade directory ignores itself" "*\n"
    (read_file (Filename.concat dir ".forge/upgrade/.gitignore"))

let test_clean_upgrade_passes () =
  let dir = project "good" in
  let (rc, out) = run_upgrade dir in
  if rc <> 0 then Alcotest.failf "expected the clean upgrade to pass, forge exited %d:\n%s" rc out;
  List.iter (expect out)
    [ "upgrade: checking out HEAD"; "upgrade: driving upgrade_traffic";
      "upgrade traffic: a session on the old code ok";
      "upgrade traffic: a session across the upgrade ok";
      "upgrade traffic: a session on the new code ok";
      "activated: Tally_dispatch";
      "app-1: converted 0, dropped 0, killed 0";
      "upgrade from HEAD passed: 1 test(s), 1 process(es), nothing dropped" ];
  after_run dir

let test_live_upgrade_passes () =
  let dir = project "live" in
  let (rc, out) = run_upgrade dir in
  if rc <> 0 then Alcotest.failf "expected the live upgrade to pass, forge exited %d:\n%s" rc out;
  List.iter (expect out)
    [ (* Both the role body (called from the generated, non-reloadable
         entry) and the task function it calls change. *)
      "activated: Serve.serve_one"; "activated: Serve.nested";
      "upgrade traffic: a session on the old code ok";
      "upgrade traffic: a session across the upgrade ok";
      "upgrade traffic: a session on the new code ok";
      (* The new body's task ran on the host runtime, saw the old state and
         completed a session of its own. *)
      "upgrade live: new code sees base=100, its own session answered 9";
      "upgrade traffic: a session on new code that spawns a task, reads the old Vault and starts a session ok";
      "app-1: converted 0, dropped 0, killed 0";
      "upgrade from HEAD passed: 1 test(s), 1 process(es), nothing dropped" ];
  after_run dir

let test_dropping_upgrade_fails () =
  let dir = project "drops" in
  let (rc, out) = run_upgrade dir in
  Alcotest.(check int) "forge exits 1" 1 rc;
  List.iter (expect out)
    [ "message type changed and it has no tally_migrate_msg";
      "upgrade traffic: all checks passed";   (* the sessions were fine: only the counters show it *)
      "upgrade from HEAD FAILED:";
      "app-1 dropped "; "message(s): an actor's message type changed and old code still sent it the old format" ];
  if contains out "dropped 0," then Alcotest.failf "nothing was dropped:\n%s" out;
  after_run dir

(* The fixture the step-8 progress entry said the passing case avoided: Tally
   REMOVES Legacy and converts it with tally_migrate_msg. The old feeder keeps
   sending Legacy after Tally moves; each one is an old-format message carrying
   the OLD build's actor-message tag, and must reach the user's match as
   TallyMsgV1.Legacy (specs/progress/2026-09-25-migrate-msg-actor-message-tags.md).
   Before the fix the compiled match panicked "non-exhaustive pattern match"
   and killed the process. *)
let test_migrating_upgrade_passes () =
  let dir = project "migrates" in
  let (rc, out) = run_upgrade dir in
  if rc <> 0 then Alcotest.failf "expected the migrating upgrade to pass, forge exited %d:\n%s" rc out;
  List.iter (expect out)
    [ "upgrade traffic: a session across the upgrade ok";
      "activated: Tally_dispatch";
      "upgrade from HEAD passed: 1 test(s), 1 process(es), nothing dropped" ];
  if contains out "non-exhaustive" then Alcotest.failf "migrate_msg panicked:\n%s" out;
  if contains out "app-1: converted 0," then
    Alcotest.failf "no old-format message was converted:\n%s" out;
  (* The counters, for the test log. *)
  List.iter (fun l -> if contains l "converted" || contains l "migrate_msg" || contains l "pinned"
                        || contains l "old epoch" then print_endline l)
    (String.split_on_char '\n' out);
  after_run dir

let test_refuses_without_a_topology () =
  let dir = Filename.temp_dir "upgrade_plain_" "" in
  sh ~dir "printf '[package]\\nname = \"plain\"\\nversion = \"0.1.0\"\\n' > forge.toml && mkdir src && printf 'mod Plain do\\n  fn main() do 0 end\\nend\\n' > src/plain.march";
  sh ~dir "git init -q && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -q -m v1";
  let (rc, out) = run_upgrade dir in
  Alcotest.(check int) "exits 1" 1 rc;
  expect out "--upgrade-from tests a topology app"

let () =
  Alcotest.run "upgrade-from" [
    ("forge test --upgrade-from", [
        Alcotest.test_case "a clean upgrade passes (sessions complete, nothing dropped)" `Slow test_clean_upgrade_passes;
        Alcotest.test_case "a patch that spawns a task, reads the old Vault and starts a session passes" `Slow test_live_upgrade_passes;
        Alcotest.test_case "an upgrade that drops messages fails on the counters" `Slow test_dropping_upgrade_fails;
        Alcotest.test_case "an upgrade that removes a handler and converts it with migrate_msg passes" `Slow test_migrating_upgrade_passes;
        Alcotest.test_case "not a topology app: refused" `Quick test_refuses_without_a_topology;
      ]);
  ]
