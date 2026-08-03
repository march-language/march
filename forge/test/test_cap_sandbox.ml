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
  Alcotest.(check bool) "no network cap => deny network*" true
    (has_deny (profile [ "IO.Console" ]) "(deny network*)")

let test_granted_child_keeps_parent_class () =
  (* IO.NetListen is a CHILD of IO.Network; holding it must keep network
     access. Regression: the subsumption ran held-over-parent and denied
     network to a program that had been granted IO.NetListen. *)
  Alcotest.(check bool) "IO.NetListen granted => network NOT denied" false
    (has_deny (profile [ "IO.NetListen" ]) "(deny network*)")

let test_granted_parent_covers_child () =
  Alcotest.(check bool) "IO.Network granted => network NOT denied" false
    (has_deny (profile [ "IO.Network" ]) "(deny network*)");
  Alcotest.(check bool) "IO (root) granted => network NOT denied" false
    (has_deny (profile [ "IO" ]) "(deny network*)")

let test_file_write_and_process_gating () =
  let pure = profile [ "IO.Console" ] in
  Alcotest.(check bool) "no write cap => deny file-write*" true
    (has_deny pure "(deny file-write*)");
  Alcotest.(check bool) "no process cap => deny process-fork" true
    (has_deny pure "(deny process-fork)");
  let w = profile [ "IO.FileWrite" ] in
  Alcotest.(check bool) "write granted => not denied" false
    (has_deny w "(deny file-write*)")

let test_target_binary_always_launchable () =
  (* Denying exec or read of the target prevents the process from starting
     at all — measured as exit 71 / SIGABRT. The profile must always carve
     these out or enforcement degenerates into "nothing runs". *)
  let p = Cap_sandbox.profile_for ~caps:[] ~binary:"/tmp/target-bin" in
  Alcotest.(check bool) "target is exec-allowed" true
    (has_deny p "(allow process-exec (literal \"/tmp/target-bin\"))");
  Alcotest.(check bool) "target is read-allowed" true
    (has_deny p "(allow file-read* (literal \"/tmp/target-bin\"))")

let test_unenforceable_caps_are_declared_advisory () =
  (* These must never be silently treated as enforced: denying them kills
     the runtime, so a report claiming enforcement would be false. *)
  List.iter
    (fun cap ->
      match Cap_sandbox.enforceability cap with
      | Cap_sandbox.Advisory _ -> ()
      | Cap_sandbox.Enforced ->
        Alcotest.failf "%s is claimed Enforced but cannot be" cap)
    [ "IO.FileRead"; "IO.Clock"; "IO.Spawn"; "IO.Foreign" ];
  match Cap_sandbox.enforceability "IO.Network" with
  | Cap_sandbox.Enforced -> ()
  | Cap_sandbox.Advisory _ ->
    Alcotest.fail "IO.Network is enforceable and must be reported as such"

let tests =
  [
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
  ]

let () = Alcotest.run "cap_sandbox" [ ("cap_sandbox", tests) ]
