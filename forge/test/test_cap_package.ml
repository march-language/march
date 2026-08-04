(* Per-package capability diff (forge/lib/cap_package.ml).

   This is the check the whole-binary audit structurally cannot make: a
   dependency abusing a capability the application already holds adds nothing
   to the program-wide union and passes `forge cap inspect --deny` cleanly. The
   per-package delta catches it, at the moment the dependency enters the tree.

   The subsumption direction is the part that has gone wrong before (twice, in
   the sandbox), so it is tested in both directions explicitly. *)

open March_forge

let test_widening_is_gained () =
  let c = Cap_package.diff ~old_caps:[] ~new_caps:[ "IO.Network" ] in
  Alcotest.(check bool) "pure -> networked is a widening" true
    (Cap_package.widens c)

let test_unchanged_is_silent () =
  let c =
    Cap_package.diff ~old_caps:[ "IO.Console" ] ~new_caps:[ "IO.Console" ]
  in
  Alcotest.(check bool) "identical sets do not widen" false
    (Cap_package.widens c);
  Alcotest.(check (option string)) "and produce no report" None
    (Cap_package.format_change ~name:"p" ~old_version:"1.0" ~new_version:"1.1" c)

let test_narrowing_is_not_a_widening () =
  (* IO.NetConnect is BELOW IO.Network: a version that used to need all of
     networking and now needs only outbound is safer, not riskier. Reporting
     that as a widening would train people to click through the real ones. *)
  let c =
    Cap_package.diff ~old_caps:[ "IO.Network" ] ~new_caps:[ "IO.NetConnect" ]
  in
  Alcotest.(check bool) "narrowing does not widen" false (Cap_package.widens c)

let test_broadening_within_a_family_is_a_widening () =
  (* The reverse of the above, and the case string equality would miss if it
     only compared set membership: IO.NetConnect -> IO.Network grants strictly
     more (inbound as well as outbound). *)
  let c =
    Cap_package.diff ~old_caps:[ "IO.NetConnect" ] ~new_caps:[ "IO.Network" ]
  in
  Alcotest.(check bool) "broadening within a family widens" true
    (Cap_package.widens c)

let test_new_sibling_capability_is_a_widening () =
  let c =
    Cap_package.diff
      ~old_caps:[ "IO.Console"; "IO.FileRead" ]
      ~new_caps:[ "IO.Console"; "IO.FileRead"; "IO.Network" ]
  in
  Alcotest.(check bool) "an added sibling widens" true (Cap_package.widens c);
  match Cap_package.format_change ~name:"json-parse" ~old_version:"1.4.2"
          ~new_version:"1.5.0" c with
  | None -> Alcotest.fail "a widening must produce a report"
  | Some s ->
    Alcotest.(check bool) "report names the gained capability" true
      (let re = Str.regexp_string "IO.Network" in
       try
         ignore (Str.search_forward re s 0);
         true
       with Not_found -> false)

let test_loss_alone_never_gates () =
  (* Dropping a capability is strictly safer and must not require an
     acknowledgement, or the gate becomes noise. It is still reported. *)
  let c =
    Cap_package.diff
      ~old_caps:[ "IO.Console"; "IO.Network" ]
      ~new_caps:[ "IO.Console" ]
  in
  Alcotest.(check bool) "a pure loss does not widen" false
    (Cap_package.widens c);
  Alcotest.(check bool) "but is still reported" true
    (Cap_package.format_change ~name:"p" ~old_version:"1" ~new_version:"2" c
    <> None)

let test_root_grant_covers_everything () =
  let c =
    Cap_package.diff ~old_caps:[ "IO" ] ~new_caps:[ "IO.Network"; "IO.FileWrite" ]
  in
  Alcotest.(check bool) "moving from IO to sub-capabilities does not widen"
    false (Cap_package.widens c)

let tests =
  [
    Alcotest.test_case "widening is gained" `Quick test_widening_is_gained;
    Alcotest.test_case "unchanged is silent" `Quick test_unchanged_is_silent;
    Alcotest.test_case "narrowing is not a widening" `Quick
      test_narrowing_is_not_a_widening;
    Alcotest.test_case "broadening within a family widens" `Quick
      test_broadening_within_a_family_is_a_widening;
    Alcotest.test_case "new sibling capability widens" `Quick
      test_new_sibling_capability_is_a_widening;
    Alcotest.test_case "loss alone never gates" `Quick
      test_loss_alone_never_gates;
    Alcotest.test_case "root grant covers everything" `Quick
      test_root_grant_covers_everything;
  ]

let () = Alcotest.run "cap_package" [ ("cap_package", tests) ]
