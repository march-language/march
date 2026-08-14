(* Capability sandbox profile derivation (design §4.3, mechanism B).

   The profile is the security boundary, so the tests that matter are the
   ones proving it neither over-blocks nor under-blocks:
   - a granted capability must survive (a sandbox that blocks everything
     passes any "is it blocked?" test and is useless);
   - a withheld capability must be denied;
   - grants must flow DOWN the lattice (IO.Network grants IO.NetListen), and
     holding a child must satisfy the parent's class (IO.NetListen keeps
     network access). Getting that direction backwards silently denies a
     granted capability, which is indistinguishable from correct
     containment. *)

open March_forge

let has_deny profile needle =
  let re = Str.regexp_string needle in
  try ignore (Str.search_forward re profile 0); true with Not_found -> false

let profile caps = Cap_sandbox.profile_for ~caps ~binary:"/tmp/whatever"

let test_withheld_network_is_denied () =
  (* Deny-default: withholding means the ALLOW is absent, not that an
     explicit deny is present. *)
  let p = profile [ "IO.Console" ] in
  Alcotest.(check bool) "profile is deny-default" true (has_deny p "(deny default)");
  Alcotest.(check bool) "no network cap => no (allow network*)" false
    (has_deny p "(allow network*)")

let test_granted_child_keeps_parent_class () =
  (* IO.NetListen is a CHILD of IO.Network; holding it must keep network
     access. Regression: the subsumption ran held-over-parent and denied
     network to a program that had been granted IO.NetListen. *)
  Alcotest.(check bool) "IO.NetListen granted => network allowed" true
    (has_deny (profile [ "IO.NetListen" ]) "(allow network*)")

let test_granted_parent_covers_child () =
  Alcotest.(check bool) "IO.Network granted => network allowed" true
    (has_deny (profile [ "IO.Network" ]) "(allow network*)");
  Alcotest.(check bool) "IO (root) granted => network allowed" true
    (has_deny (profile [ "IO" ]) "(allow network*)")

let test_file_write_and_process_gating () =
  let pure = profile [ "IO.Console" ] in
  Alcotest.(check bool) "no write cap => no (allow file-write*)" false
    (has_deny pure "(allow file-write*)");
  Alcotest.(check bool) "no process cap => no (allow process-fork)" false
    (has_deny pure "(allow process-fork)");
  let w = profile [ "IO.FileWrite" ] in
  Alcotest.(check bool) "write granted => allowed" true
    (has_deny w "(allow file-write*)")

let test_target_binary_always_launchable () =
  (* Denying exec or read of the target prevents the process from starting
     at all — measured as exit 71 / SIGABRT. The profile must always carve
     these out or enforcement degenerates into "nothing runs". *)
  let p = Cap_sandbox.profile_for ~caps:[] ~binary:"/tmp/target-bin" in
  Alcotest.(check bool) "exec is permitted by the baseline" true
    (has_deny p "(allow process-exec)");
  Alcotest.(check bool) "target is read-allowed" true
    (has_deny p "(allow file-read* (literal \"/tmp/target-bin\"))");
  (* Without these the runtime aborts under deny-default -- the reason the
     first deny-default attempt was wrongly judged infeasible. *)
  List.iter
    (fun needed ->
      Alcotest.(check bool)
        (Printf.sprintf "baseline includes %s" needed) true (has_deny p needed))
    [ "(allow mach*)"; "(allow sysctl-read)"; "(allow ipc-posix-shm)" ]

let test_unenforceable_caps_are_declared_advisory () =
  (* These must never be silently treated as enforced: denying them kills
     the runtime, so a report claiming enforcement would be false. *)
  List.iter
    (fun cap ->
      match Cap_sandbox.enforceability cap with
      | Cap_sandbox.Advisory _ -> ()
      | Cap_sandbox.Enforced ->
        Alcotest.failf "%s is claimed Enforced but cannot be" cap)
    (* IO.FileRead is NOT in this list: it is genuinely Enforced on the
       bwrap backend and Advisory on SBPL, so it gets its own
       backend-aware test rather than a blanket claim. *)
    [ "IO.Clock"; "IO.Spawn"; "IO.Foreign" ];
  match Cap_sandbox.enforceability "IO.Network" with
  | Cap_sandbox.Enforced -> ()
  | Cap_sandbox.Advisory _ ->
    Alcotest.fail "IO.Network is enforceable and must be reported as such"


(* Linux backend: the same capability decisions expressed as bubblewrap
   flags.  Tested independently of which backend this host actually has, so
   the Linux mapping is covered when developing on macOS. *)
let test_bwrap_withholds_and_grants () =
  let pure = Cap_sandbox.bwrap_args ~caps:[ "IO.Console" ] () in
  Alcotest.(check bool) "no network cap => --unshare-net" true
    (List.mem "--unshare-net" pure);
  (* With neither read nor write granted the namespace is an ALLOW-LIST, so
     the root is deliberately not bound wholesale — see
     test_bwrap_read_scoping. A writable /tmp is still provided so failures
     mean the withheld capability rather than incidental breakage. *)
  Alcotest.(check bool) "no read cap => root not bound wholesale" false
    (List.mem "--ro-bind / /" pure);
  Alcotest.(check bool) "no write cap => still a writable /tmp" true
    (List.mem "--tmpfs /tmp" pure);
  let ro = Cap_sandbox.bwrap_args ~caps:[ "IO.FileRead" ] () in
  Alcotest.(check bool) "read but no write => read-only root" true
    (List.mem "--ro-bind / /" ro);
  let net = Cap_sandbox.bwrap_args ~caps:[ "IO.NetListen" ] () in
  Alcotest.(check bool) "network child grant => no --unshare-net" false
    (List.mem "--unshare-net" net);
  (* IO.FileWrite and IO.FileRead are SIBLINGS under IO.FileSystem, so
     granting write alone does not grant read: such a program gets the
     allow-list namespace with a writable /tmp, and cannot see the rest of
     the filesystem it would be writing to. Only IO.FileSystem (or IO)
     grants both and yields a fully writable bind. *)
  let w = Cap_sandbox.bwrap_args ~caps:[ "IO.FileWrite" ] () in
  Alcotest.(check bool) "write alone does not open the whole fs" false
    (List.mem "--dev-bind / /" w);
  Alcotest.(check bool) "write alone still gets a writable /tmp" true
    (List.mem "--tmpfs /tmp" w);
  let fs = Cap_sandbox.bwrap_args ~caps:[ "IO.FileSystem" ] () in
  Alcotest.(check bool) "IO.FileSystem => read+write bind" true
    (List.mem "--dev-bind / /" fs);
  let root = Cap_sandbox.bwrap_args ~caps:[ "IO" ] () in
  Alcotest.(check bool) "root grant => nothing withheld" true
    (root = [ "--dev-bind / /" ])


(* Read scoping (Linux).  Verified end-to-end in a 6.12 container using the
   flags this function emits: /etc/hosts DENIED without IO.FileRead, OK with
   it, OK under a root IO grant. *)
let test_bwrap_read_scoping () =
  let deny = Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~caps:[ "IO.Console" ] () in
  Alcotest.(check bool) "no read cap => allow-list namespace, not whole fs" true
    (List.exists (fun f -> f = "--ro-bind-try /usr /usr") deny);
  Alcotest.(check bool) "no read cap => root NOT bound wholesale" false
    (List.mem "--ro-bind / /" deny || List.mem "--dev-bind / /" deny);
  let grant = Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~caps:[ "IO.FileRead" ] () in
  Alcotest.(check bool) "read cap => whole fs visible" true
    (List.mem "--ro-bind / /" grant)

let test_binary_bound_after_tmpfs () =
  (* Regression: --tmpfs /tmp masks everything under it, including a binary
     living there, making the program unlaunchable. The bind must come after
     every tmpfs. Only the GRANTED direction exposes this — the denied
     direction passes either way. *)
  let check caps =
    let fl = Cap_sandbox.bwrap_args ~binary:"/tmp/app" ~caps () in
    let idx p = 
      let rec go i = function
        | [] -> -1
        | x :: tl -> if x = p then i else go (i + 1) tl
      in go 0 fl
    in
    let t = idx "--tmpfs /tmp" in
    let b = idx "--ro-bind-try '/tmp/app' '/tmp/app'" in
    if t >= 0 then
      Alcotest.(check bool)
        (Printf.sprintf "binary bound after tmpfs for %s"
           (String.concat "," caps))
        true (b > t)
  in
  check [ "IO.Console" ];
  check [ "IO.FileRead" ]

let test_filereads_enforceability_matches_backend () =
  (* IO.FileRead is Enforced on Linux (allow-list namespace) and Advisory on
     macOS (dyld must map libs first). Whichever host runs the suite, the
     claim must match what that backend can actually do. *)
  match Cap_sandbox.enforceability "IO.FileRead" with
  | Cap_sandbox.Enforced ->
    Alcotest.(check bool) "Enforced only claimed on the bwrap backend" true
      (Sys.file_exists "/usr/bin/bwrap" || Sys.file_exists "/bin/bwrap")
  | Cap_sandbox.Advisory _ ->
    Alcotest.(check bool) "Advisory only on a non-bwrap backend" true
      (not (Sys.file_exists "/usr/bin/bwrap" || Sys.file_exists "/bin/bwrap"))

let test_forge_fix_applies_capability_errors () =
  (* A capability-incorrect module must be repaired by `forge fix`, not
     refused. Both fixes are error-severity: the missing grant on `main`
     and the missing `needs` line. `collect_all_fixes` used to set
     `has_errors` on exactly the diagnostics that carry a fix (the ones
     `parse_fix_line` doesn't discard), so `forge fix` refused precisely
     when it had safe work to do. *)
  let dir = Filename.concat (Filename.get_temp_dir_name ()) "forge_fix_caps" in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  ignore (Sys.command (Printf.sprintf "mkdir -p %s/lib" (Filename.quote dir)));
  let src = Filename.concat dir "lib/ffc.march" in
  let oc = open_out src in
  output_string oc "mod Ffc do\n  fn main() do\n    println(\"hi\")\n  end\nend\n";
  close_out oc;
  let toml = open_out (Filename.concat dir "forge.toml") in
  output_string toml "[package]\nname = \"ffc\"\nversion = \"0.1.0\"\ntype = \"app\"\n\n[deps]\n";
  close_out toml;
  let rc = Sys.command (Printf.sprintf "cd %s && forge fix > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "forge fix succeeds on capability errors" 0 rc;
  let ic = open_in src in
  let n = in_channel_length ic in
  let content = really_input_string ic n in
  close_in ic;
  Alcotest.(check bool) "needs line inserted" true
    (has_deny content "needs IO.Console");
  Alcotest.(check bool) "grant parameter inserted" true
    (has_deny content "Cap(IO.Console)")

let test_scaffolded_app_builds_clean () =
  let dir = Filename.concat (Filename.get_temp_dir_name ()) "forge_new_clean" in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  let rc_new = Sys.command
    (Printf.sprintf "cd %s && forge new %s > /dev/null 2>&1"
       (Filename.quote (Filename.get_temp_dir_name ())) "forge_new_clean") in
  Alcotest.(check int) "forge new succeeds" 0 rc_new;
  let rc_check = Sys.command
    (Printf.sprintf "cd %s && forge check > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app checks clean" 0 rc_check;
  let rc_build = Sys.command
    (Printf.sprintf "cd %s && forge build > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app builds" 0 rc_build;
  let rc_test = Sys.command
    (Printf.sprintf "cd %s && forge test > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app's tests run" 0 rc_test

let tests =
  [
    Alcotest.test_case "bwrap read scoping" `Quick test_bwrap_read_scoping;
    Alcotest.test_case "binary bound after tmpfs" `Quick test_binary_bound_after_tmpfs;
    Alcotest.test_case "IO.FileRead enforceability matches backend" `Quick
      test_filereads_enforceability_matches_backend;
    Alcotest.test_case "bwrap withholds and grants correctly" `Quick
      test_bwrap_withholds_and_grants;
    Alcotest.test_case "withheld network is denied" `Quick
      test_withheld_network_is_denied;
    Alcotest.test_case "granted child keeps parent class" `Quick
      test_granted_child_keeps_parent_class;
    Alcotest.test_case "granted parent covers child" `Quick
      test_granted_parent_covers_child;
    Alcotest.test_case "file-write and process gating" `Quick
      test_file_write_and_process_gating;
    Alcotest.test_case "target binary is always launchable" `Quick
      test_target_binary_always_launchable;
    Alcotest.test_case "unenforceable caps declared advisory" `Quick
      test_unenforceable_caps_are_declared_advisory;
    Alcotest.test_case "forge fix applies capability errors" `Quick
      test_forge_fix_applies_capability_errors;
    Alcotest.test_case "scaffolded app builds clean" `Quick
      test_scaffolded_app_builds_clean;
  ]

let () = Alcotest.run "cap_sandbox" [ ("cap_sandbox", tests) ]
