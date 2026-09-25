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
     5. [interpreter_only] below (no compiled lowering; a compiled call is
        REJECTED at lowering with a positioned diagnostic),
   and anything unaccounted FAILS.  So adding a typechecked builtin without a
   lowering is a test failure until it is either lowered or consciously listed.

   The lists are kept HERE, not in production code, so the compiler cannot
   vacuously satisfy its own test. [interpreter_only] is also checked in the
   other direction: an entry that has gained a lowering fails too. And it must
   equal [Lower_expr.interpreter_only_builtins] exactly, so every name on it is
   a compile-time error, never a link-time one. *)

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
    (* lower_expr.ml: folded into a string literal (the compiler version). *)
    "march_version";
    (* lower_expr.ml json_dispatch_rewrite: resolved to the derived
       JsonFrom$T / JsonFromEvents$T impl at the call site. *)
    "from_json"; "from_json_events";
    (* Interface dispatch (Lower_state.resolve_iface_method at lowering, Mono
       for a generic caller): resolved to the derived JsonTo$T.to_json impl by
       its argument's type. A call no impl resolves is reported by
       Llvm_calls.fail_if_unresolved_iface_method as a missing codec
       (including when NO type derives Json), not a link error. *)
    "to_json";
    (* lower_expr.ml: `tap(x)` is rewritten to `x` (the tap bus it also feeds
       interpreted has no reader outside the REPL); a first-class `tap` is a
       positioned lowering error. *)
    "tap";
    (* cap_passing.ml: rewritten to an empty capability ops record. *)
    "cap_ops_empty";
    (* stdlib/prelude.march defines a March fn of the same name. *)
    "head"; "tail"; "is_nil";
    (* The generic extern-call path emits `call @<name>`, and the runtime
       defines a C function of exactly that name (runtime/march_runtime.c,
       runtime/march_http.c), so the call links. *)
    "__try_call"; "__try_call_val"; "http_fetch";
    "http_fetch_available";
    "logger_add_field"; "logger_appender_names"; "logger_clear_appenders";
    "logger_clear_module_level"; "logger_dispatch"; "logger_field_count";
    "logger_get_fields"; "logger_module_level"; "logger_pop_to_depth";
    "logger_register_appender"; "logger_remove_appender";
    "logger_set_module_level" ]

(* INTERPRETER-ONLY: typechecked builtins with no compiled lowering. A
   compiled call to any of these is rejected at lowering with a positioned
   diagnostic (Lower_expr.interpreter_only_builtin_reasons carries each one's
   reason), so it is a compile error naming the March call site, never a
   link-time `Undefined symbols: _<name>`.

   Every name here acts on state only the interpreter has:
   - the value-level supervisor DSL (`worker`, `dynamic_supervisor`,
     `Supervisor.spec`, `Supervisor.start_child`) and the dynamic-supervisor
     registry it creates (`Supervisor.stop_child` / `which_children` /
     `count_children`) -- a compiled program supervises with
     `supervise do ... end`;
   - `App.stop`, the shutdown flag of an `app` declaration, which the compiled
     backend ignores;
   - `task_spawn_link`, the interpreter's eager task/actor link, which the
     compiled task runtime has no counterpart for.
   Triaged 2026-09-24 (specs/progress/2026-09-24-interpreter-only-builtins.md);
   ADDING a name is a decision to ship a builtin that cannot compile, and needs
   a reason in Lower_expr as well as here. *)
let interpreter_only : string list =
  [ "worker"; "dynamic_supervisor"; "Supervisor.spec"; "Supervisor.start_child";
    "Supervisor.stop_child"; "Supervisor.which_children";
    "Supervisor.count_children"; "App.stop"; "task_spawn_link" ]

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
       Builtin_name arm in llvm_emit.ml), or reject it at lowering \
       (Lower_expr.interpreter_only_builtin_reasons) and list it in \
       [interpreter_only] in test/test_builtin_compiled_lowering.ml."
      (List.length unaccounted) (String.concat ", " unaccounted)

let test_interpreter_only_is_not_stale () =
  let names = typechecked_builtins () in
  let stale =
    List.filter (fun n -> lowered n || not (List.mem n names)) interpreter_only
  in
  Alcotest.(check (list string))
    "every interpreter_only entry is a typechecked builtin with no lowering \
     (remove lowered or deleted names from the list)" [] stale

(* The allowlist is exactly the set the compiler rejects: a name listed here
   but not rejected would link-fail again, and a name rejected but not listed
   would be an unaccounted-for builtin hiding behind a diagnostic. *)
let test_interpreter_only_is_rejected_at_lowering () =
  Alcotest.(check (list string))
    "interpreter_only = Lower_expr.interpreter_only_builtins"
    (List.sort compare interpreter_only)
    (List.sort compare March_tir.Lower_expr.interpreter_only_builtins)

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
    Alcotest.test_case "interpreter_only is exactly the rejected set" `Quick
      test_interpreter_only_is_rejected_at_lowering;
    Alcotest.test_case "special_lowerings are not redundant" `Quick
      test_special_lowerings_not_redundant ]
