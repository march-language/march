(* The two capability tables must agree.

   March has two, keyed differently, and both are load-bearing:

   - [Typecheck.builtin_cap_table] maps a MARCH NAME to a capability. It drives
     the source-level checks (Check 1b, and the severity flip that made an
     undeclared direct builtin call an error).
   - [Cap_symbols] maps a C SYMBOL to a capability. It drives
     [Cap_attrib.attribute], which charges emitted TIR to an owning module and
     is what `--cap-strict`'s ceiling reads.

   They are bridged by [Llvm_builtins.c_symbol_of_march_name], which returns the
   name UNCHANGED when a builtin has no [c_name] — a trampoline-lowered builtin
   like [task_spawn]. The bare name is not in [Cap_symbols], so attribution
   silently learned nothing about it while typecheck knew its capability
   exactly.

   The failure that produced this test is worth stating, because it did not look
   like a table mismatch. `--cap-strict` reported:

     `IO.Spawn` is used but cannot be attributed to any module — it is reached
     only through indirect calls, whose callee is not statically known

   on `bench/par_fib.march`, which calls [task_spawn] DIRECTLY in its own body
   and declares `needs IO.Spawn` on line 24. Nothing was indirect; the ceiling
   said so because [Unattributed] had no other explanation to offer. Four of a
   24-program sample failed this way, all of them parallel code, and none of
   them could be fixed by declaring anything — the author had already declared
   it.

   So this test asserts the bridge, not the fix: every capability-bearing
   builtin typecheck knows must resolve to the SAME capability through the path
   attribution uses. A new builtin that lands in one table and not the other
   fails here rather than in a user's `--cap-strict` build with a diagnostic
   that misdescribes its own cause. *)

let cap_via_attribution (march_name : string) : string option =
  (* Exactly the lookup [Cap_attrib.cap_of_call] performs. *)
  March_tir.Cap_attrib.cap_of_call march_name

let test_every_capability_builtin_is_attributable () =
  let missing =
    List.filter_map
      (fun (march_name, expected_cap) ->
         match cap_via_attribution march_name with
         | Some c when c = expected_cap -> None
         | Some c ->
           Some (Printf.sprintf
                   "%s: typecheck says %s, attribution says %s"
                   march_name expected_cap c)
         | None ->
           Some (Printf.sprintf
                   "%s: typecheck says %s, attribution resolves NOTHING"
                   march_name expected_cap))
      March_typecheck.Typecheck.builtin_cap_table
  in
  if missing <> [] then
    Alcotest.failf
      "%d capability-bearing builtin(s) are invisible to attribution, so \
       `--cap-strict` reports them as unattributable even when the module \
       declares them:\n  %s"
      (List.length missing)
      (String.concat "\n  " missing)

(* The specific builtins that were broken, pinned by name.  The bulk assertion
   above would catch a regression, but naming these keeps the original failure
   legible: all three are trampoline-lowered (c_name = None), which is the
   property that made them fall through. *)
let test_trampoline_lowered_spawn_builtins_resolve () =
  List.iter
    (fun name ->
       match cap_via_attribution name with
       | Some "IO.Spawn" -> ()
       | Some c -> Alcotest.failf "%s resolved to %s, expected IO.Spawn" name c
       | None ->
         Alcotest.failf
           "%s resolves to no capability — it is trampoline-lowered \
            (c_name = None), so c_symbol_of_march_name returns the bare name \
            and Cap_symbols does not know it"
           name)
    [ "task_spawn"; "task_spawn_steal"; "get_work_pool" ]

let tests =
  [ Alcotest.test_case "every capability builtin is attributable" `Quick
      test_every_capability_builtin_is_attributable;
    Alcotest.test_case "trampoline-lowered spawn builtins resolve" `Quick
      test_trampoline_lowered_spawn_builtins_resolve;
  ]
