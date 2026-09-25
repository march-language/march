(* Freshness tests for March_caps.Cap_symbols (design §4.3, mechanism C).

   For every builtin the typechecker attributes a capability to, the C symbol
   it lowers to must map to that same cap in Cap_symbols.table.  Cap-level
   coverage is NOT enough — a missing symbol under an otherwise-covered cap
   silently under-reports that builtin in the audit.

   Accounting is total: each builtin_cap_table entry must resolve through
   exactly one of
     1. its c_name row in the codegen builtin table (lib/tir/llvm_builtins.ml),
     2. the special-lowerings map below (builtins emitted outside that table),
     3. Cap_symbols.uncompiled_builtins (no compiled lowering exists at all),
   and anything unaccounted FAILS — a newly added cap builtin cannot silently
   escape the audit. *)

let test_known_mappings () =
  Alcotest.(check (option string))
    "file_read maps to IO.FileRead" (Some "IO.FileRead")
    (March_caps.Cap_symbols.cap_of_symbol "march_file_read");
  Alcotest.(check (option string))
    "underscore-prefixed Mach-O spelling works" (Some "IO.FileRead")
    (March_caps.Cap_symbols.cap_of_symbol "_march_file_read");
  Alcotest.(check (option string))
    "unknown symbol maps to nothing" None
    (March_caps.Cap_symbols.cap_of_symbol "march_list_map")

(* Builtins whose compiled lowering does not go through an llvm_builtins
   c_name row.  Kept here (not in Cap_symbols) so the production module
   cannot vacuously satisfy its own test. *)
let special_lowerings =
  [
    ("signal_watch", "march_signal_watch");
    ("signal_unwatch", "march_signal_unwatch");
    ("signal_raise_self", "march_signal_raise_self");
    ("task_spawn", "march_task_spawn_thunk");
    ("task_spawn_steal", "march_task_spawn_thunk");
    ("task_spawn_with_cancel", "march_task_spawn_with_cancel_thunk");
  ]

let test_no_drift_from_builtin_cap_table () =
  let problems =
    List.filter_map
      (fun (march_name, cap) ->
        if List.mem march_name March_caps.Cap_symbols.uncompiled_builtins then
          None
        else
          let symbol =
            match List.assoc_opt march_name special_lowerings with
            | Some s -> Some s
            | None -> (
                match
                  List.find_opt
                    (fun (b : March_tir.Llvm_builtins.builtin) ->
                      b.March_tir.Llvm_builtins.march_name = march_name)
                    March_tir.Llvm_builtins.builtins
                with
                | Some { March_tir.Llvm_builtins.c_name = Some c; _ } -> Some c
                | Some { March_tir.Llvm_builtins.c_name = None; _ } | None ->
                    None)
          in
          match symbol with
          | None ->
              Some
                (Printf.sprintf
                   "%s -> %s: UNACCOUNTED (no c_name, no special lowering, \
                    not listed uncompiled)"
                   march_name cap)
          | Some s ->
              if March_caps.Cap_symbols.cap_of_symbol s = Some cap then None
              else
                Some
                  (Printf.sprintf "%s (%s) -> %s: missing or mismapped in \
                                   Cap_symbols.table"
                     march_name s cap))
      March_typecheck.Typecheck.builtin_cap_table
  in
  Alcotest.(check (list string))
    "every cap-bearing builtin accounted for and correctly mapped" [] problems

(* The other direction: an [uncompiled_builtins] entry that HAS a lowering is
   stale, and staleness here is not cosmetic.  The drift test above skips
   listed names entirely, so a lowered builtin left on the list is a builtin
   whose symbol the audit never learns: unix_time_ms and uuid_v7 sat here
   (until 2026-09-25) while both compiled, and no binary using them carried an
   IO.Clock marker. *)
let test_uncompiled_builtins_not_stale () =
  let stale =
    List.filter
      (fun march_name ->
        List.mem_assoc march_name special_lowerings
        || List.exists
             (fun (b : March_tir.Llvm_builtins.builtin) ->
               b.March_tir.Llvm_builtins.march_name = march_name
               && b.March_tir.Llvm_builtins.c_name <> None)
             March_tir.Llvm_builtins.builtins
        || not
             (List.mem_assoc march_name
                March_typecheck.Typecheck.builtin_cap_table))
      March_caps.Cap_symbols.uncompiled_builtins
  in
  Alcotest.(check (list string))
    "every uncompiled_builtins entry is a cap builtin with no lowering" []
    stale

(* Every key is a march_-prefixed runtime symbol.  The binary audit matches
   RAW symbol names ([forge/lib/cap_binary.ml] reads the whole symbol table),
   so an unprefixed key also matches any user or foreign symbol of that
   spelling.  `dns_resolve` was such a key until 2026-09-25: a binary linking
   any C object that defines `dns_resolve` showed an IO.Network witness. *)
let test_table_keys_are_prefixed () =
  let unprefixed =
    List.filter
      (fun (sym, _) ->
        not (String.length sym > 6 && String.sub sym 0 6 = "march_"))
      March_caps.Cap_symbols.table
  in
  Alcotest.(check (list string))
    "every Cap_symbols key starts with march_" [] (List.map fst unprefixed);
  Alcotest.(check (option string))
    "the bare spelling dns_resolve is no capability witness" None
    (March_caps.Cap_symbols.cap_of_symbol "dns_resolve");
  Alcotest.(check (option string))
    "nor its Mach-O spelling" None
    (March_caps.Cap_symbols.cap_of_symbol "_dns_resolve");
  (* Positive control: without it the two absences above pass if IO.Network
     simply vanished from the table. *)
  Alcotest.(check (option string))
    "march_dns_resolve witnesses IO.Network" (Some "IO.Network")
    (March_caps.Cap_symbols.cap_of_symbol "march_dns_resolve");
  Alcotest.(check (option string))
    "march_uuid_v7 witnesses IO.Clock" (Some "IO.Clock")
    (March_caps.Cap_symbols.cap_of_symbol "march_uuid_v7");
  Alcotest.(check (option string))
    "march_unix_time_ms witnesses IO.Clock" (Some "IO.Clock")
    (March_caps.Cap_symbols.cap_of_symbol "march_unix_time_ms")

let tests =
  [
    Alcotest.test_case "known cap symbol mappings" `Quick test_known_mappings;
    Alcotest.test_case "no drift from builtin_cap_table" `Quick
      test_no_drift_from_builtin_cap_table;
    Alcotest.test_case "uncompiled_builtins is not stale" `Quick
      test_uncompiled_builtins_not_stale;
    Alcotest.test_case "table keys are march_-prefixed" `Quick
      test_table_keys_are_prefixed;
  ]
