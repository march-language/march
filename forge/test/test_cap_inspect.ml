(* forge cap inspect gate logic (design §5.2, plan Task 6).

   The gate must be fail-closed: anything less than full coverage fails
   unless explicitly allowed, and --allow-foreign covers exactly the
   foreign-code case, never stripped/unstripped limitations. *)

open March_forge

(* A current-compiler binary carries markers for the caps it holds; [markers]
   defaults to [caps] so fixtures model that.  Pass ~markers:[] explicitly to
   model a pre-marker or non-March binary. *)
let mk ?(caps = []) ?markers ?(rt_symbols = []) ?(attribution = [])
    ?(build = Cap_binary.Dead_stripped) () =
  let markers = match markers with Some m -> m | None -> caps in
  { Cap_binary.caps; markers; attribution; rt_symbols; build; manifest = None }

let test_deny_uses_lattice_subsumption () =
  let t = mk ~caps:[ "IO.FileRead" ] () in
  let vs =
    Cmd_cap.gate_violations ~deny:[ "IO" ] ~allow_only:None
      ~allow_foreign:false t
  in
  Alcotest.(check bool) "--deny IO rejects IO.FileRead via the lattice" true
    (vs <> [])

let test_allow_only_rejects_outside_set () =
  let t = mk ~caps:[ "IO.Console"; "IO.FileRead" ] () in
  let vs =
    Cmd_cap.gate_violations ~deny:[]
      ~allow_only:(Some [ "IO.Console" ]) ~allow_foreign:false t
  in
  Alcotest.(check bool) "IO.FileRead outside --allow-only fails" true (vs <> []);
  let vs_ok =
    Cmd_cap.gate_violations ~deny:[]
      ~allow_only:(Some [ "IO.Console"; "IO.FileSystem" ]) ~allow_foreign:false
      (mk ~caps:[ "IO.Console"; "IO.FileRead" ] ())
  in
  (* IO.FileSystem subsumes IO.FileRead — allow-only works through the lattice
     in the permissive direction too. *)
  Alcotest.(check (list string)) "subsuming allow passes" [] vs_ok

let test_gate_fails_closed_on_reduced_coverage () =
  (* No deny/allow flags at all: reduced coverage still fails.  Stripping is
     an evasion, not a degradation (design §5.2). *)
  let stripped = mk ~build:Cap_binary.Symbols_removed () in
  Alcotest.(check bool) "symbols-removed fails" true
    (Cmd_cap.gate_violations ~deny:[] ~allow_only:None ~allow_foreign:false
       stripped
    <> []);
  let unstripped = mk ~build:Cap_binary.Unstripped () in
  Alcotest.(check bool) "unstripped fails" true
    (Cmd_cap.gate_violations ~deny:[] ~allow_only:None ~allow_foreign:false
       unstripped
    <> [])

let test_allow_foreign_covers_only_ffi () =
  let ffi = mk ~caps:[ "IO.Console"; "IO.Foreign" ] () in
  Alcotest.(check bool) "foreign code fails without --allow-foreign" true
    (Cmd_cap.gate_violations ~deny:[] ~allow_only:None ~allow_foreign:false ffi
    <> []);
  Alcotest.(check (list string)) "foreign code passes with --allow-foreign" []
    (Cmd_cap.gate_violations ~deny:[] ~allow_only:None ~allow_foreign:true ffi);
  (* --allow-foreign must NOT excuse a stripped binary. *)
  let stripped = mk ~build:Cap_binary.Symbols_removed () in
  Alcotest.(check bool) "--allow-foreign does not excuse stripping" true
    (Cmd_cap.gate_violations ~deny:[] ~allow_only:None ~allow_foreign:true
       stripped
    <> [])

let test_foreign_is_not_gated_as_a_cap () =
  (* IO.Foreign is a scope limitation, not a capability row: --deny IO must
     not double-report it as a denied capability (the coverage check already
     covers it). *)
  let ffi = mk ~caps:[ "IO.Foreign" ] () in
  let vs =
    Cmd_cap.gate_violations ~deny:[ "IO" ] ~allow_only:None
      ~allow_foreign:true ffi
  in
  Alcotest.(check (list string)) "no denied-capability violation for IO.Foreign"
    [] vs

let test_symbols_alone_never_certify () =
  (* Regression: a real forgepm hot-reload .so carrying 79 of 82 cap symbols
     and NO markers reported coverage:full — maximum false assurance on an
     artifact whose symbol set says nothing about usage.  Without markers,
     coverage must never be full, and the gate must fail closed. *)
  let no_markers = mk ~caps:[ "IO.Console" ] ~markers:[] () in
  Alcotest.(check bool) "gate fails closed without markers" true
    (Cmd_cap.gate_violations ~deny:[] ~allow_only:None ~allow_foreign:false
       no_markers
    <> []);
  Alcotest.(check bool) "--allow-foreign does not excuse missing markers" true
    (Cmd_cap.gate_violations ~deny:[] ~allow_only:None ~allow_foreign:true
       no_markers
    <> [])

let tests =
  [
    Alcotest.test_case "symbols alone never certify full coverage" `Quick
      test_symbols_alone_never_certify;
    Alcotest.test_case "deny uses lattice subsumption" `Quick
      test_deny_uses_lattice_subsumption;
    Alcotest.test_case "allow-only rejects outside set" `Quick
      test_allow_only_rejects_outside_set;
    Alcotest.test_case "gate fails closed on reduced coverage" `Quick
      test_gate_fails_closed_on_reduced_coverage;
    Alcotest.test_case "allow-foreign covers only FFI" `Quick
      test_allow_foreign_covers_only_ffi;
    Alcotest.test_case "IO.Foreign is not gated as a capability" `Quick
      test_foreign_is_not_gated_as_a_cap;
  ]

let () = Alcotest.run "cap_audit" [ ("cap_audit", tests) ]
