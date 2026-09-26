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
    "head"; "tail"; "is_nil" ]

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

(* ── The identity fallthrough ────────────────────────────────────────────

   [Llvm_builtins.mangle_extern] maps a March name to its C symbol through the
   row's [c_name].  A name with no [c_name] falls through to ITSELF, and if no
   row declares that symbol either, [Llvm_emit_call] synthesizes a `declare`
   from the call site's March types.  That call links whenever the runtime
   happens to define a C function of the same name, and its prototype was
   never checked against the C one: nothing ties the declare, the borrow
   classification or even the symbol's existence to the runtime.  Until
   2026-09-26 sixteen builtins (`__try_call`, `__try_call_val`, `http_fetch`,
   `http_fetch_available` and the twelve Logger v2 `logger_*`) compiled that
   way, listed in [special_lowerings] because "the runtime defines a C
   function of exactly that name".  One of them handed out a reference it did
   not own (RC underflow), a `$clo_wrap` path emitted the call with no declare
   at all ("use of undefined value '@logger_add_field'"), and every String
   argument leaked (specs/progress/2026-09-26-same-named-builtin-abi-audit.md).
   All sixteen are `march_*` symbols with explicit rows now.

   The guard below keeps it that way.  A row with no [c_name] reaches codegen
   under its own name, which is allowed only when
     - it has NO declare and one of the dedicated emit arms below owns it
       (native instructions, synthesized calls), or
     - it DECLARES its own symbol, and that symbol is `march_`-prefixed or one
       of the explicitly allowed unprefixed families.
   Anything else -- a new builtin added without a [c_name], or given one that
   is not declared -- fails here.  Names routed outside the table
   ([special_lowerings]) must not be runtime C functions at all: the Slow
   prototype test checks that against the compiled runtime. *)

(* Rows with neither a [c_name] nor a declare: each is emitted by a dedicated
   arm in llvm_emit / llvm_emit_task / llvm_emit_arith, never by name. *)
let dedicated_emit_rows : string list =
  [ "+"; "-"; "*"; "/"; "%"; "+."; "-."; "*."; "/."; "=="; "!="; "<"; "<=";
    ">"; ">=";
    "task_spawn"; "task_await"; "task_await_unwrap"; "task_yield";
    "task_spawn_steal"; "task_reductions"; "pmap_threshold"; "get_work_pool";
    "int_and"; "int_or"; "int_xor"; "int_not"; "int_shl"; "int_shr";
    "int_popcount"; "remote_ref_hashes" ]

(* Unprefixed C functions a row may declare as its own symbol.  The typed
   native arrays and the ring buffer predate the `march_` convention; each of
   their rows carries a declare that was checked against the C definition by
   the Slow test below.  Do not grow this list: give a new builtin a
   `march_`-prefixed [c_name]. *)
let unprefixed_own_symbol_families : string list = [ "native_"; "ring_buf_" ]
let unprefixed_own_symbol_names : string list =
  [ "bytes_to_u8_arr"; "u8_arr_to_bytes" ]

let has_prefix p s =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

(* The symbol a declare line names: `declare ptr  @foo(ptr %x)` -> "foo". *)
let declared_symbol (d : string) : string option =
  match String.index_opt d '@', String.index_opt d '(' with
  | Some a, Some p when p > a -> Some (String.sub d (a + 1) (p - a - 1))
  | _ -> None

let identity_fallthrough_violations () =
  List.filter_map
    (fun (b : March_tir.Llvm_builtins.builtin) ->
      let open March_tir.Llvm_builtins in
      let n = b.march_name in
      match b.c_name, b.declare_sig with
      | Some _, _ -> None
      | None, None ->
        if List.mem n dedicated_emit_rows then None
        else Some (n ^ " (no c_name, no declare, no dedicated emit arm)")
      | None, Some d ->
        if declared_symbol d <> Some n then
          Some (n ^ " (no c_name, but its declare names another symbol)")
        else if has_prefix "march_" n
             || List.exists (fun p -> has_prefix p n) unprefixed_own_symbol_families
             || List.mem n unprefixed_own_symbol_names
        then None
        else Some (n ^ " (unprefixed C symbol reached through the identity fallthrough)"))
    March_tir.Llvm_builtins.builtins

let test_no_undeclared_identity_fallthrough () =
  (* Non-vacuity: one row of each accepted shape must be seen. *)
  let rows = List.map (fun (b : March_tir.Llvm_builtins.builtin) ->
      b.March_tir.Llvm_builtins.march_name) March_tir.Llvm_builtins.builtins in
  List.iter (fun n ->
      Alcotest.(check bool) (n ^ " is a table row") true (List.mem n rows))
    [ "+"; "native_int_arr_get"; "march_compare_int"; "logger_add_field";
      "__try_call" ];
  (* The sixteen that used to fall through now resolve to march_* symbols. *)
  List.iter (fun n ->
      let c = March_tir.Llvm_builtins.c_symbol_of_march_name n in
      Alcotest.(check bool) (n ^ " -> " ^ c ^ " is march_-prefixed") true
        (has_prefix "march_" c))
    [ "__try_call"; "__try_call_val"; "http_fetch"; "http_fetch_available";
      "logger_add_field"; "logger_field_count"; "logger_get_fields";
      "logger_pop_to_depth"; "logger_dispatch"; "logger_register_appender";
      "logger_remove_appender"; "logger_clear_appenders";
      "logger_appender_names"; "logger_set_module_level";
      "logger_clear_module_level"; "logger_module_level" ];
  let stale = List.filter (fun n -> not (List.mem n rows)) dedicated_emit_rows in
  Alcotest.(check (list string)) "dedicated_emit_rows are all table rows" [] stale;
  match identity_fallthrough_violations () with
  | [] -> ()
  | vs ->
    Alcotest.failf
      "%d builtin row(s) reach codegen through mangle_extern's identity \
       fallthrough without a checked prototype:\n  %s\n\
       Give each a `march_`-prefixed c_name and a declare_sig (plus its \
       PDeclare, a prototype in runtime/march_runtime.h and a borrow \
       classification), as specs/progress/2026-09-26-same-named-builtin-abi-audit.md did."
      (List.length vs) (String.concat "\n  " vs)

(* ── Declared prototypes vs the runtime's C definitions (Slow) ──────────

   Every `declare` in the native preamble is compared with the `define` clang
   emits for the runtime C source, at the LLVM type level (i64 / i32 / ptr /
   double / void / i1 per parameter and for the result).  A mismatch is a
   call through the wrong ABI: a C `bool` read as i64, a `double` passed in an
   integer register, a missing argument.  Before 2026-09-26 nothing compared
   them; the audit that added this found all 506 declared prototypes in
   agreement, one declare with NO definition (`march_dir_list_full`, a dead
   row, removed), and sixteen builtins that had no declare to compare at all.

   The runtime is compiled to IR with the same headers the driver uses
   (runtime/ plus OpenSSL for march_tls.c) and none of its flags.  The files
   `runtime/sources.list` builds into a native binary are read, plus the
   unit-test-only arena files, so the declares below that ONLY they define
   are compared too -- and pinned, because the driver never links them. *)

(* Declared unconditionally in the native preamble but defined only in the
   unit-test-only per-process arena runtime (march_message.c, march_heap.c),
   which the driver never links.  march_send_linear is emitted for a `send`
   whose message var is linear (llvm_emit.ml); that path is latent today (a
   destructured `let (m, _) = ...; send(pid, m)` still compiles to
   march_send), and a program that reached it would fail to link.  Recorded
   in specs/progress/2026-09-26-same-named-builtin-abi-audit.md; do not add
   names here. *)
let defined_only_in_unit_test_runtime =
  [ "march_msg_copy"; "march_msg_move"; "march_process_alloc"; "march_send_linear" ]

let runtime_dir () =
  Filename.concat (Filename.dirname Sys.executable_name) "../runtime"

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; s

let native_runtime_sources dir =
  read_file (Filename.concat dir "sources.list")
  |> String.split_on_char '\n'
  |> List.filter_map (fun line ->
      let line = String.trim line in
      if line = "" || line.[0] = '#' then None
      else
        match List.filter (( <> ) "") (String.split_on_char ' ' line
                                       |> List.concat_map (String.split_on_char '\t')) with
        | f :: role :: _ when List.mem role [ "core"; "http"; "hcr"; "unit-test-only" ] ->
          Some (f, role)
        | _ -> None)

let openssl_include () =
  let dirs = [ "/opt/homebrew/opt/openssl@3"; "/opt/homebrew/opt/openssl";
               "/usr/local/opt/openssl@3"; "/usr/local/opt/openssl" ] in
  match List.find_opt (fun d ->
      Sys.file_exists (Filename.concat d "include/openssl/ssl.h")) dirs with
  | Some d -> " -I" ^ Filename.quote (Filename.concat d "include")
  | None -> ""

(* Split a parameter list at top-level commas. *)
let split_params s =
  let parts = ref [] and buf = Buffer.create 16 and depth = ref 0 in
  String.iter (fun c ->
      match c with
      | '(' | '{' | '[' | '<' -> incr depth; Buffer.add_char buf c
      | ')' | '}' | ']' | '>' -> decr depth; Buffer.add_char buf c
      | ',' when !depth = 0 ->
        parts := String.trim (Buffer.contents buf) :: !parts; Buffer.clear buf
      | c -> Buffer.add_char buf c) s;
  let last = String.trim (Buffer.contents buf) in
  List.rev (if last = "" then !parts else last :: !parts)

let ir_attrs =
  [ "noundef"; "zeroext"; "signext"; "nonnull"; "nocapture"; "readonly";
    "writeonly"; "noalias"; "returned"; "inreg"; "nofree"; "immarg" ]

(* The LLVM type of one parameter, attributes and names dropped. *)
let param_ty p =
  let toks = List.filter (( <> ) "") (String.split_on_char ' ' p) in
  let rec go = function
    | [] -> "?"
    | "align" :: _ :: rest -> go rest
    | t :: rest when List.mem t ir_attrs || t.[0] = '%' || t.[0] = '#'
                     || has_prefix "dereferenceable" t -> go rest
    | t :: _ -> t
  in
  go toks

(* `define`/`declare` line -> (symbol, (ret, params)).  The return type is
   the last token before `@`, which skips linkage, visibility and return
   attributes (`define dso_local noalias ptr @f(`). *)
let parse_sig ~kw line : (string * (string * string list)) option =
  if not (has_prefix kw line) then None
  else
    match String.index_opt line '@' with
    | None -> None
    | Some at ->
      let before = String.sub line 0 at in
      let toks = List.filter (( <> ) "") (String.split_on_char ' ' before) in
      let ret = List.nth toks (List.length toks - 1) in
      (match String.index_from_opt line at '(' with
       | None -> None
       | Some lp ->
         let name = String.sub line (at + 1) (lp - at - 1) in
         let name =
           if String.length name >= 2 && name.[0] = '"' then
             String.sub name 1 (String.length name - 2) else name in
         (* matching close paren of the parameter list *)
         let depth = ref 0 and rp = ref (-1) in
         String.iteri (fun i c ->
             if !rp < 0 && i >= lp then
               match c with
               | '(' -> incr depth
               | ')' -> decr depth; if !depth = 0 then rp := i
               | _ -> ()) line;
         if !rp < 0 then None
         else
           let params = String.sub line (lp + 1) (!rp - lp - 1) in
           Some (name, (ret, List.map param_ty (split_params params))))

(* Libc symbols the preamble declares on purpose. *)
let declared_libc = [ "getenv" ]

let test_declares_match_runtime_definitions () =
  if Sys.command "clang --version > /dev/null 2>&1" <> 0 then
    Alcotest.fail "clang is required to compile the runtime to LLVM IR";
  let rt = runtime_dir () in
  let files = native_runtime_sources rt in
  Alcotest.(check bool) "sources.list lists march_runtime.c" true
    (List.mem_assoc "march_runtime.c" files);
  let tmp = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_abi_%d" (Unix.getpid ())) in
  ignore (Sys.command ("mkdir -p " ^ Filename.quote tmp));
  let defs : (string, string * string list) Hashtbl.t = Hashtbl.create 4096 in
  let test_only_defs : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (f, role) ->
      let src = Filename.concat rt f in
      let ll = Filename.concat tmp (Filename.remove_extension f ^ ".ll") in
      let err = Filename.concat tmp (Filename.remove_extension f ^ ".err") in
      let cmd = Printf.sprintf "clang -S -emit-llvm -O0 -w -I %s%s -o %s %s 2> %s"
          (Filename.quote rt) (openssl_include ()) (Filename.quote ll)
          (Filename.quote src) (Filename.quote err) in
      if Sys.command cmd <> 0 then
        Alcotest.failf "clang could not compile %s to IR:\n%s" f (read_file err);
      String.split_on_char '\n' (read_file ll)
      |> List.iter (fun line ->
          let internal =
            List.exists (fun w -> List.mem w [ "internal"; "private" ])
              (String.split_on_char ' ' line) in
          if not internal then
            match parse_sig ~kw:"define " line with
            | Some (n, s) ->
              if role = "unit-test-only" then begin
                if not (Hashtbl.mem defs n) then begin
                  Hashtbl.replace defs n s; Hashtbl.replace test_only_defs n ()
                end
              end else begin
                Hashtbl.replace defs n s; Hashtbl.remove test_only_defs n
              end
            | None -> ()))
    files;
  ignore (Sys.command ("rm -rf " ^ Filename.quote tmp));
  let buf = Buffer.create 65536 in
  March_tir.Llvm_builtins.emit_preamble ~is_wasm:false ~triple:"x" buf;
  let decls =
    String.split_on_char '\n' (Buffer.contents buf)
    |> List.filter_map (fun l -> parse_sig ~kw:"declare " (String.trim l))
    |> List.filter (fun (n, _) -> not (has_prefix "llvm." n))
  in
  let show (r, ps) = Printf.sprintf "%s(%s)" r (String.concat ", " ps) in
  let checked = ref 0 and problems = ref [] in
  List.iter (fun (n, sg) ->
      match Hashtbl.find_opt defs n with
      | None ->
        if not (List.mem n declared_libc) then
          problems := Printf.sprintf "%s: declared %s, but no runtime C file defines it"
              n (show sg) :: !problems
      | Some d ->
        incr checked;
        if d <> sg then
          problems := Printf.sprintf "%s: declared %s, C defines %s" n (show sg) (show d)
                      :: !problems)
    decls;
  (* Non-vacuity: the comparison must have covered the table, including the
     rows this audit added. *)
  Alcotest.(check bool)
    (Printf.sprintf "compared %d declares (expected > 400)" !checked) true (!checked > 400);
  List.iter (fun n ->
      Alcotest.(check bool) (n ^ " was compared") true
        (Hashtbl.mem defs n && List.mem_assoc n decls))
    [ "march_logger_add_field"; "march_try_call_val"; "march_http_fetch";
      "march_string_byte_length"; "native_float_arr_get" ];
  let test_only_declared =
    List.filter (fun (n, _) -> Hashtbl.mem test_only_defs n) decls
    |> List.map fst |> List.sort_uniq compare in
  Alcotest.(check (list string))
    "declares defined only by the unit-test-only arena runtime"
    (List.sort compare defined_only_in_unit_test_runtime) test_only_declared;
  (* Names routed outside the table must not be satisfied by a same-named C
     function: that is the identity fallthrough again, unchecked. *)
  List.iter (fun n ->
      if Hashtbl.mem defs n then
        problems := Printf.sprintf
            "%s: listed in special_lowerings, but the runtime defines a C \
             function of that name -- give it a march_* row instead" n :: !problems)
    special_lowerings;
  match List.rev !problems with
  | [] -> ()
  | ps -> Alcotest.failf "%d prototype problem(s):\n  %s" (List.length ps)
            (String.concat "\n  " ps)

let tests =
  [ Alcotest.test_case "every typechecked builtin is lowered or listed" `Quick
      test_every_builtin_lowered_or_listed;
    Alcotest.test_case "interpreter_only list is not stale" `Quick
      test_interpreter_only_is_not_stale;
    Alcotest.test_case "interpreter_only is exactly the rejected set" `Quick
      test_interpreter_only_is_rejected_at_lowering;
    Alcotest.test_case "special_lowerings are not redundant" `Quick
      test_special_lowerings_not_redundant;
    Alcotest.test_case "no builtin reaches codegen through an unchecked \
                        identity fallthrough" `Quick
      test_no_undeclared_identity_fallthrough;
    Alcotest.test_case "every declared runtime prototype matches its C \
                        definition" `Slow
      test_declares_match_runtime_definitions ]
