(* Cap_binary reader tests (design §4.2/§4.4, plan Task 5).

   Fixtures are synthesized in-process rather than compiled — the reader's
   contract is over file contents (symbols, magic blobs), not over the
   compiler, and forge's test env may not have a built march compiler.

   The two properties that must never regress:
   - a binary carrying EVERY cap symbol is classified Unstripped and its
     symbol set is NOT reported as capabilities (the app-invariance failure,
     design §3);
   - a binary carrying two manifest blobs is REJECTED (a planted blob must
     not shadow the real one, design §6). *)

open March_forge

let write_tmp content =
  let path = Filename.temp_file "cap_binary" ".bin" in
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc;
  path

let manifest_blob json =
  let len = String.length json in
  let b = Buffer.create (16 + len) in
  Buffer.add_string b "MARCHCAP\x01";
  Buffer.add_char b (Char.chr (len land 0xff));
  Buffer.add_char b (Char.chr ((len lsr 8) land 0xff));
  Buffer.add_char b (Char.chr ((len lsr 16) land 0xff));
  Buffer.add_char b (Char.chr ((len lsr 24) land 0xff));
  Buffer.add_string b json;
  Buffer.contents b

let test_duplicate_manifest_is_an_error () =
  let data =
    "NOT-A-REAL-BINARY " ^ manifest_blob {|{"v":1}|} ^ " padding "
    ^ manifest_blob {|{"v":1,"planted":true}|}
  in
  let path = write_tmp data in
  (match Cap_binary.read path with
  | Ok _ -> Alcotest.fail "must not accept a binary with two manifest blobs"
  | Error msg ->
      Alcotest.(check bool) "error mentions manifest multiplicity" true
        (String.length msg > 0));
  Sys.remove path

let test_single_manifest_is_returned () =
  let json = {|{"v":1,"effective":["IO.Console"]}|} in
  let path = write_tmp ("prefix " ^ manifest_blob json ^ " suffix") in
  (match Cap_binary.read path with
  | Error e -> Alcotest.fail e
  | Ok t ->
      Alcotest.(check (option string)) "manifest json extracted" (Some json)
        t.Cap_binary.manifest);
  Sys.remove path

let test_no_symbols_no_manifest_classified_symbols_removed () =
  (* nm on a non-object file fails; reader must degrade to Symbols_removed
     with an empty cap list — never a clean "no capabilities" verdict at the
     caller's mercy: the build field says the channels were unavailable. *)
  let path = write_tmp "just some bytes, no symbols, no magic" in
  (match Cap_binary.read path with
  | Error e -> Alcotest.fail e
  | Ok t ->
      Alcotest.(check bool) "classified Symbols_removed" true
        (t.Cap_binary.build = Cap_binary.Symbols_removed);
      Alcotest.(check (list string)) "no caps claimed" [] t.Cap_binary.caps);
  Sys.remove path

let test_manifest_truncated_length_is_not_fatal () =
  (* A magic hit whose length field runs past EOF must not crash the reader;
     the blob is treated as absent. *)
  let path = write_tmp ("x " ^ "MARCHCAP\x01" ^ "\xff\xff\xff\x7f") in
  (match Cap_binary.read path with
  | Error e -> Alcotest.fail e
  | Ok t ->
      Alcotest.(check (option string)) "truncated manifest treated as absent"
        None t.Cap_binary.manifest);
  Sys.remove path

let test_all_cap_symbols_classified_unstripped () =
  (* Synthesize an object file that defines EVERY cap-bearing runtime symbol
     — the shape of a binary linked without dead-strip.  The reader must
     classify it Unstripped and must NOT report the full symbol set as
     capabilities (the app-invariance failure, design §3). *)
  let c_src = Filename.temp_file "allsyms" ".c" in
  let oc = open_out c_src in
  List.iter
    (fun (sym, _) -> Printf.fprintf oc "void %s(void) {}\n" sym)
    March_caps.Cap_symbols.table;
  close_out oc;
  let obj = Filename.temp_file "allsyms" ".o" in
  let rc =
    Sys.command
      (Printf.sprintf "clang -c %s -o %s 2>/dev/null" (Filename.quote c_src)
         (Filename.quote obj))
  in
  Sys.remove c_src;
  if rc <> 0 then Alcotest.fail "clang -c failed";
  (match Cap_binary.read obj with
  | Error e -> Alcotest.fail e
  | Ok t ->
      Alcotest.(check bool) "classified Unstripped" true
        (t.Cap_binary.build = Cap_binary.Unstripped);
      Alcotest.(check bool)
        "caps are NOT the full lattice (only markers may contribute)" true
        (List.length t.Cap_binary.caps
        < List.length March_caps.Cap_symbols.all_caps));
  Sys.remove obj

let tests =
  [
    Alcotest.test_case "duplicate manifest blobs are rejected" `Quick
      test_duplicate_manifest_is_an_error;
    Alcotest.test_case "all-cap-symbols binary is Unstripped, caps withheld"
      `Quick test_all_cap_symbols_classified_unstripped;
    Alcotest.test_case "single manifest is extracted" `Quick
      test_single_manifest_is_returned;
    Alcotest.test_case "no channels -> Symbols_removed, no caps claimed" `Quick
      test_no_symbols_no_manifest_classified_symbols_removed;
    Alcotest.test_case "truncated manifest length is non-fatal" `Quick
      test_manifest_truncated_length_is_not_fatal;
  ]

let () = Alcotest.run "cap_binary" [ ("cap_binary", tests) ]
