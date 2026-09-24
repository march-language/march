(* Stdlib-only builtins (G3 of
   specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md).

   [Typecheck_builtins.stdlib_only] lists builtins user code may not reference;
   the gate is [Typecheck_caps.check_stdlib_only_refs]. The table landed EMPTY
   and build step 2 (unforgeable references) populated it, so the gate tests
   here still install their own single entry for the duration of one check
   (they pin the MECHANISM, not the shipped table) and restore both refs
   afterwards; the last case pins the shipped table itself. *)

open Test_helpers

module TB = March_typecheck.Typecheck_builtins

let hint = "use `Actor.pid_from_int(cap, n)` (see `Actor.introspect`)"

let with_gate ?(stdlib_files = []) f =
  let saved_gate = !TB.stdlib_only and saved_files = !TB.stdlib_source_files in
  TB.stdlib_only := [ ("pid_of_int", hint) ];
  TB.stdlib_source_files := stdlib_files;
  Fun.protect f ~finally:(fun () ->
      TB.stdlib_only := saved_gate;
      TB.stdlib_source_files := saved_files)

(* Parse with a real file name on every span, the way the driver loads a
   stdlib module. *)
let typecheck_as ~file src =
  let lexbuf = Lexing.from_string src in
  Lexing.set_filename lexbuf file;
  let m =
    March_parser.Parser.module_
      (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
  in
  let (errors, _) =
    March_typecheck.Typecheck.check_module (March_desugar.Desugar.desugar_module m)
  in
  errors

let message = "`pid_of_int` is internal to the standard library; " ^ hint

let caller = {|mod App do
  fn find(n : Int) do
    pid_of_int(n)
  end
end|}

let test_user_call_rejected () =
  let ctx = with_gate (fun () -> typecheck caller) in
  Alcotest.(check bool) "user call is an error naming the replacement" true
    (has_error_with ctx message)

let test_user_value_reference_rejected () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  fn forge() do
    let f = pid_of_int
    f(3)
  end
end|}) in
  Alcotest.(check bool) "a value reference is gated too" true
    (has_error_with ctx message)

let test_local_definition_shadows () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  fn pid_of_int(n : Int) : Int do
    n
  end
  fn use_it() : Int do
    pid_of_int(3)
  end
end|}) in
  Alcotest.(check bool) "a module's own pid_of_int is not the builtin" false
    (has_error_with ctx "internal to the standard library")

let test_stdlib_module_allowed () =
  let file = "stdlib/g3_fixture.march" in
  let ctx =
    with_gate ~stdlib_files:[ file ] (fun () -> typecheck_as ~file caller)
  in
  Alcotest.(check bool) "a stdlib module may call it" false
    (has_error_with ctx "internal to the standard library")

let test_user_file_named_like_stdlib_is_not_stdlib () =
  (* The gate asks "is this file one of the stdlib's", not "does its path
     look like one". *)
  let ctx =
    with_gate ~stdlib_files:[ "stdlib/other.march" ] (fun () ->
        typecheck_as ~file:"stdlib/g3_fixture.march" caller)
  in
  Alcotest.(check bool) "a file outside the stdlib set is user code" true
    (has_error_with ctx message)

let test_repl_is_user_code () =
  let ctx = with_gate (fun () ->
      let errors = March_errors.Errors.create () in
      let env = March_typecheck.Typecheck.base_env errors (Hashtbl.create 16) in
      let m = parse_and_desugar caller in
      fst (March_typecheck.Typecheck.check_module_with_env env m)) in
  Alcotest.(check bool) "the REPL path runs the gate" true
    (has_error_with ctx message)

(* The shipped table: the four reference-forging builtins, each pointing at
   the `Actor` wrapper that takes a `Cap(Actor.Introspect)`. Every suggestion
   names `Actor.introspect`, the one minting function, so a user who hits the
   gate is told where the cap comes from. *)
let test_shipped_table () =
  let gated = List.map fst !TB.stdlib_only in
  Alcotest.(check (list string)) "the four forging builtins, the epoch holds and the drain flag are gated"
    [ "pid_of_int"; "actor_pid_indices"; "actor_whereis"; "actor_registered";
      "epoch_hold"; "epoch_release"; "epoch_draining"; "epoch_drain";
      "delivery_origin_set"; "delivery_origin_clear"; "delivery_failed_watch" ]
    gated;
  List.iter (fun (name, hint) ->
      Alcotest.(check bool) (name ^ " suggestion names Actor.introspect") true
        (let n = String.length "`Actor.introspect`" in
         let rec go i = i + n <= String.length hint && (String.sub hint i n = "`Actor.introspect`" || go (i + 1)) in go 0))
    (List.filter (fun (name, _) -> name <> "epoch_hold" && name <> "epoch_release" && name <> "epoch_draining" && name <> "epoch_drain"
                             && name <> "delivery_origin_set" && name <> "delivery_origin_clear"
                             && name <> "delivery_failed_watch")
       !TB.stdlib_only);
  (* No throwaway entry installed: the shipped table itself gates user code. *)
  Alcotest.(check bool) "user code may no longer call pid_of_int" true
    (has_error_with (typecheck caller)
       "`pid_of_int` is internal to the standard library; use `Actor.pid_from_int(cap, n)` (see `Actor.introspect`)");
  Alcotest.(check bool) "nor actor_whereis" true
    (has_error_with (typecheck {|mod App do
  fn find(n : String) do
    actor_whereis(n)
  end
end|}) "`actor_whereis` is internal to the standard library; use `Actor.whereis(cap, name)`")

let tests =
  [ ("stdlib-only builtins",
     [ Alcotest.test_case "user call rejected" `Quick test_user_call_rejected;
       Alcotest.test_case "user value reference rejected" `Quick
         test_user_value_reference_rejected;
       Alcotest.test_case "local definition shadows" `Quick
         test_local_definition_shadows;
       Alcotest.test_case "stdlib module allowed" `Quick test_stdlib_module_allowed;
       Alcotest.test_case "stdlib-looking path is not stdlib" `Quick
         test_user_file_named_like_stdlib_is_not_stdlib;
       Alcotest.test_case "REPL is user code" `Quick test_repl_is_user_code;
       Alcotest.test_case "shipped table gates the four forging builtins" `Quick
         test_shipped_table ]) ]
