(* Every builtin the typechecker accepts has a compiled lowering, or is
   explicitly listed as interpreter-only.

   A name in [Typecheck.builtin_bindings] typechecks and runs interpreted.
   If the LLVM emitter knows nothing about it, a call falls through to the
   generic extern-call path and `--compile` fails at LINK time with an
   undefined symbol named after the builtin (`_float_nan`, `_typed_array_slice`,
   ... see specs/progress/2026-09-22-compiled-lowering-float-builtins.md).
   Nothing checked that before this test.

   Accounting is total, in the shape of test_cap_symbols.ml: each
   [builtin_bindings] name must resolve through exactly one of
     1. a row in the codegen builtin table (lib/tir/llvm_builtins.ml),
     2. a [Builtin_name.t] constructor (an [emit_expr] arm in llvm_emit.ml),
     3. the SIMD grid ([Llvm_emit_simd.decode_simd_call]),
     4. [special_lowerings] below (lowered by some other named route),
     5. [interpreter_only] below (no compiled lowering exists yet),
   and anything unaccounted FAILS.  So adding a typechecked builtin without a
   lowering is a test failure until it is either lowered or consciously listed.

   The lists are kept HERE, not in production code, so the compiler cannot
   vacuously satisfy its own test. [interpreter_only] is also checked in the
   other direction: an entry that has gained a lowering fails too, so the list
   only shrinks. *)

(* Builtins lowered outside the codegen table and [Builtin_name], each by a
   route named in its comment. *)
let special_lowerings : string list =
  [ (* llvm_emit.ml emit_expr: short-circuit arms matched by raw name. *)
    "&&"; "||";
    (* llvm_emit.ml emit_atom: an ambient value, never called. *)
    "root_cap";
    (* lower_expr.ml: session-typed channel calls rewritten at lowering. *)
    "Chan.new"; "Chan.send"; "Chan.recv"; "Chan.close"; "Chan.choose";
    "Chan.offer";
    (* lower_expr.ml json_dispatch_rewrite: resolved to the derived
       JsonFrom$T / JsonFromEvents$T impl at the call site. *)
    "from_json"; "from_json_events";
    (* cap_passing.ml: rewritten to an empty capability ops record. *)
    "cap_ops_empty";
    (* stdlib/prelude.march defines a March fn of the same name. *)
    "head"; "tail"; "is_nil";
    (* Rejected at lowering with a positioned diagnostic
       (Lower_expr.interpreter_only_builtins), so a compiled call is a compile
       error, not a link error. *)
    "worker"; "dynamic_supervisor"; "Supervisor.spec"; "Supervisor.start_child";
    (* The generic extern-call path emits `call @<name>`, and the runtime
       defines a C function of exactly that name (runtime/march_runtime.c,
       runtime/march_http.c), so the call links. *)
    "__try_call"; "__try_call_val"; "dns_resolve"; "http_fetch";
    "http_fetch_available"; "uuid_v7"; "uuid_v7_at";
    "logger_add_field"; "logger_appender_names"; "logger_clear_appenders";
    "logger_clear_module_level"; "logger_dispatch"; "logger_field_count";
    "logger_get_fields"; "logger_module_level"; "logger_pop_to_depth";
    "logger_register_appender"; "logger_remove_appender";
    "logger_set_module_level" ]

(* INTERPRETER-ONLY: typechecked builtins with no compiled lowering. A call to
   any of these in a `--compile`d program fails at link time.

   This is the static-scan remainder recorded on 2026-09-22, NOT a triaged
   list: some may be target-gated, reached only through a stdlib wrapper that
   is itself interpreter-only, or simply dead. Triage is
   specs/todos/2026-09-22-triage-interpreter-only-builtins.md. Removing a name
   from here requires giving it a lowering (the reverse check below enforces
   that the list only shrinks); ADDING one is a decision to ship a builtin
   that cannot compile, and should come with a reason.

   Confirmed on 2026-09-22 by compiling a one-line call: char_is_alpha,
   char_to_uppercase, print_int, print_float, tap, respond and to_json each
   fail with `Undefined symbols: _<name>`. *)
let interpreter_only : string list =
  [ "App.stop";
    "Supervisor.count_children"; "Supervisor.stop_child";
    "Supervisor.which_children";
    "char_is_alpha"; "char_is_lowercase"; "char_is_uppercase";
    "char_to_lowercase"; "char_to_uppercase";
    "float_from_string";
    "print_float"; "print_int";
    "respond"; "tap"; "task_spawn_link"; "to_json" ]

let in_codegen_table name =
  List.exists
    (fun (b : March_tir.Llvm_builtins.builtin) ->
      String.equal b.March_tir.Llvm_builtins.march_name name)
    March_tir.Llvm_builtins.builtins

let lowered name =
  in_codegen_table name
  || March_tir.Builtin_name.of_string name <> None
  || March_tir.Llvm_emit_simd.decode_simd_call name <> None
  || List.mem name special_lowerings

let typechecked_builtins () =
  List.map fst March_typecheck.Typecheck_builtins.builtin_bindings
  |> List.sort_uniq compare

let test_every_builtin_lowered_or_listed () =
  let names = typechecked_builtins () in
  (* Non-vacuity: the walk must see builtins of every route, or a change to
     the binding list's shape would make this pass trivially. *)
  List.iter (fun (n, why) ->
      Alcotest.(check bool) (n ^ " is seen by the walk") true (List.mem n names);
      Alcotest.(check bool) (n ^ " is lowered (" ^ why ^ ")") true (lowered n))
    [ ("string_length", "codegen table"); ("int_max_value", "Builtin_name");
      ("float_nan", "Builtin_name"); ("typed_array_slice", "codegen table");
      ("simd_f32x4_add", "SIMD grid") ];
  let unaccounted =
    List.filter (fun n -> not (lowered n) && not (List.mem n interpreter_only)) names
  in
  if unaccounted <> [] then
    Alcotest.failf
      "%d typechecked builtin(s) have no compiled lowering: %s\n\
       A compiled call to one fails at LINK time. Lower it (a row in \
       lib/tir/llvm_builtins.ml backed by a runtime C function, or a \
       Builtin_name arm in llvm_emit.ml), or list it in [interpreter_only] in \
       test/test_builtin_compiled_lowering.ml with a reason."
      (List.length unaccounted) (String.concat ", " unaccounted)

let test_interpreter_only_is_not_stale () =
  let names = typechecked_builtins () in
  let stale =
    List.filter (fun n -> lowered n || not (List.mem n names)) interpreter_only
  in
  Alcotest.(check (list string))
    "every interpreter_only entry is a typechecked builtin with no lowering \
     (remove lowered or deleted names from the list)" [] stale

let test_special_lowerings_not_redundant () =
  let redundant =
    List.filter (fun n ->
        in_codegen_table n || March_tir.Builtin_name.of_string n <> None
        || List.mem n interpreter_only)
      special_lowerings
  in
  Alcotest.(check (list string))
    "special_lowerings lists only names no other route covers" [] redundant

let tests =
  [ Alcotest.test_case "every typechecked builtin is lowered or listed" `Quick
      test_every_builtin_lowered_or_listed;
    Alcotest.test_case "interpreter_only list is not stale" `Quick
      test_interpreter_only_is_not_stale;
    Alcotest.test_case "special_lowerings are not redundant" `Quick
      test_special_lowerings_not_redundant ]
