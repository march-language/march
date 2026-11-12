(* Stdlib-only builtins (G3 of
   specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md).

   [Typecheck_builtins.stdlib_only] lists builtins user code may not reference.
   The gate fires at name resolution, in [Typecheck.infer_expr]'s [EVar] arm:
   a reference to a gated name that still resolves to the builtin, from a span
   the stdlib loader does not own, is an error. It used to be a syntactic walk
   over [DFn]/[DLet]/[DActor] beside Check 1b, which the distributed-deploys
   review bypassed four ways (specs/progress/2026-09-24-dd-review-stdlib-only-
   gate-*.md); each bypass is a case below, and the sweep at the end tries
   every spelling the findings list.

   The mechanism tests install their own single entry for the duration of one
   check (they pin the MECHANISM, not the shipped table) and restore both refs
   afterwards; [test_shipped_table] and the sweep pin the shipped table. *)

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
    March_parser.Parse.module_of_lexbuf lexbuf
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

(* A parameter or local `let` of the gated name rebinds it: the reference
   resolves to that binding, not to the builtin. The [let]'s own right-hand
   side is the one place the builtin is still named, and it is not named
   here. *)
let test_param_and_let_shadow () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  fn wrap(pid_of_int) do
    pid_of_int(1)
  end
  fn local() do
    let pid_of_int = fn n -> n
    pid_of_int(2)
  end
end|}) in
  Alcotest.(check bool) "a param/let binding of the name is user code" false
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

(* ── The 2026-09-24 bypasses ──────────────────────────────────────────── *)

(* 2026-09-24-dd-review-stdlib-only-gate-let-shadow.md: a module-level
   `let pid_of_int = pid_of_int` used to count as a local declaration that
   shadowed the builtin for the WHOLE module, including its own right-hand
   side. The right-hand side is a reference to the builtin, checked before
   the new binding exists. *)
let test_module_let_self_alias_rejected () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  let pid_of_int = pid_of_int
  fn forge(n : Int) do
    pid_of_int(n)
  end
end|}) in
  Alcotest.(check bool) "the alias's right-hand side names the builtin" true
    (has_error_with ctx message)

let test_fn_local_self_alias_rejected () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  fn forge(n : Int) do
    let pid_of_int = pid_of_int
    pid_of_int(n)
  end
end|}) in
  Alcotest.(check bool) "a function-local self alias names the builtin" true
    (has_error_with ctx message)

(* 2026-09-24-dd-review-stdlib-only-gate-skips-impl-interface-test.md: the
   walker visited [DFn], [DLet] and [DActor] only. *)
let test_impl_method_rejected () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  interface Forger(a) do
    fn forge : a -> Int
  end
  impl Forger(Int) do
    fn forge(n) do
      let _ = pid_of_int(n)
      0
    end
  end
end|}) in
  Alcotest.(check bool) "an impl method body is gated" true
    (has_error_with ctx message)

(* A default body is typed where it is injected, into each impl that does not
   override it (a default no impl ever takes is never typed at all, and never
   runs); the impl below is what makes the default's body reach the
   typechecker, with the interface's own (user-file) spans. *)
let test_interface_default_rejected () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  interface Forger(a) do
    fn forge : a -> Int
    fn dflt : a -> Int do
      fn (_n) ->
        let _ = pid_of_int(0)
        0
    end
  end
  impl Forger(Int) do
    fn forge(n) do n end
  end
end|}) in
  Alcotest.(check bool) "an interface default method body is gated" true
    (has_error_with ctx message)

let test_test_blocks_rejected () =
  let check label src =
    let ctx = with_gate (fun () -> typecheck src) in
    Alcotest.(check bool) (label ^ " body is gated") true (has_error_with ctx message)
  in
  check "test" {|mod App do
  test "forge" do
    let _ = pid_of_int(0)
    ()
  end
end|};
  check "describe/test" {|mod App do
  describe "forging" do
    test "forge" do
      let _ = pid_of_int(0)
      ()
    end
  end
end|};
  check "setup" {|mod App do
  setup do
    let _ = pid_of_int(0)
    ()
  end
end|};
  check "setup_all" {|mod App do
  setup_all do
    let _ = pid_of_int(0)
    ()
  end
end|}

let test_actor_handler_rejected () =
  let ctx = with_gate (fun () -> typecheck {|mod App do
  actor Victim do
    state { n : Int }
    init { n: 0 }
    on Bump() do
      let _ = pid_of_int(state.n)
      { n: state.n + 1 }
    end
  end
end|}) in
  Alcotest.(check bool) "an actor handler body is gated" true
    (has_error_with ctx message)

(* 2026-09-24-dd-review-stdlib-only-gate-entry-named-like-stdlib.md: the
   driver used to add any entry file whose basename was in the stdlib
   manifest to [stdlib_source_files]. Provenance is now the directory the
   loader read the stdlib from ([TB.stdlib_roots]): a file under it is the
   stdlib's under any spelling; a file elsewhere is user code whatever its
   name. This exercises the root mechanism in-process; the driver's own
   behaviour is [test_driver_rejects_user_json_march] below. *)
let with_temp_dir f =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "march_stdlib_root_%d_%d" (Unix.getpid ()) (Random.bits ())) in
  Unix.mkdir dir 0o755;
  Fun.protect (fun () -> f dir)
    ~finally:(fun () ->
        Array.iter (fun f -> Sys.remove (Filename.concat dir f)) (Sys.readdir dir);
        Unix.rmdir dir)

let write_file path contents =
  let oc = open_out path in
  output_string oc contents;
  close_out oc

let with_stdlib_root dir f =
  let saved_roots = !TB.stdlib_roots and saved_rp = !TB.stdlib_realpath in
  TB.stdlib_realpath := (fun f -> try Some (Unix.realpath f) with _ -> None);
  TB.note_stdlib_root dir;
  Fun.protect f ~finally:(fun () ->
      TB.stdlib_roots := saved_roots;
      TB.stdlib_realpath := saved_rp)

let test_stdlib_root_provenance () =
  with_temp_dir (fun root ->
      with_temp_dir (fun elsewhere ->
          let inside = Filename.concat root "json.march" in
          let outside = Filename.concat elsewhere "json.march" in
          write_file inside caller;
          write_file outside caller;
          let (in_ctx, out_ctx, bare_ctx) =
            with_gate (fun () ->
                with_stdlib_root root (fun () ->
                    (typecheck_as ~file:inside caller,
                     typecheck_as ~file:outside caller,
                     (* The spelling the manifest-basename check keyed on. *)
                     typecheck_as ~file:"json.march" caller)))
          in
          Alcotest.(check bool) "a file under the stdlib root is the stdlib's" false
            (has_error_with in_ctx "internal to the standard library");
          Alcotest.(check bool) "the same name outside the root is user code" true
            (has_error_with out_ctx message);
          Alcotest.(check bool) "a bare stdlib-manifest basename is user code" true
            (has_error_with bare_ctx message)))

(* The driver end to end: a user file named `json.march` calling `pid_of_int`
   exits 1 with the gate's error, interpreted or `--check`ed; the same file
   under `--stdlib-source` is accepted (the CI ratchet's spelling). *)
let compiler_exe =
  Filename.concat (Filename.dirname Sys.executable_name) "../bin/main.exe"

let run_compiler args =
  let out = Filename.temp_file "stdlib_only_driver" ".out" in
  let cmd =
    Printf.sprintf "%s %s > %s 2>&1"
      (Filename.quote compiler_exe) (String.concat " " (List.map Filename.quote args))
      (Filename.quote out)
  in
  let rc = Sys.command cmd in
  let ic = open_in_bin out in
  let text = really_input_string ic (in_channel_length ic) in
  close_in ic;
  Sys.remove out;
  (rc, text)

let contains ~needle hay =
  let nl = String.length needle and hl = String.length hay in
  let rec scan i = i + nl <= hl && (String.sub hay i nl = needle || scan (i + 1)) in
  nl = 0 || scan 0

let forge_src = {|mod Forge do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let p = pid_of_int(0)
    let q = actor_whereis("x")
    let r = actor_registered()
    println("forged")
  end
end
|}

let test_driver_rejects_user_json_march () =
  if not (Sys.file_exists compiler_exe) then
    Alcotest.failf "compiler not found at %s" compiler_exe;
  with_temp_dir (fun dir ->
      let json = Filename.concat dir "json.march" in
      write_file json forge_src;
      let (rc, out) = run_compiler [ "--check"; json ] in
      Alcotest.(check int) "--check on a user json.march exits 1" 1 rc;
      List.iter (fun n ->
          Alcotest.(check bool) (n ^ " is reported") true
            (contains ~needle:("`" ^ n ^ "` is internal to the standard library") out))
        [ "pid_of_int"; "actor_whereis"; "actor_registered" ];
      let (rc, out) = run_compiler [ json ] in
      Alcotest.(check int) "running it interpreted exits 1" 1 rc;
      Alcotest.(check bool) "and never prints `forged`" false (contains ~needle:"forged" out);
      let (rc, out) = run_compiler [ "--check"; "--stdlib-source"; json ] in
      Alcotest.(check int) "--stdlib-source exempts the entry explicitly" 0 rc;
      Alcotest.(check bool) "with no gate error" false
        (contains ~needle:"internal to the standard library" out))

(* The shipped table: the four reference-forging builtins, each pointing at
   the `Actor` wrapper that takes a `Cap(Actor.Introspect)`. Every suggestion
   names `Actor.introspect`, the one minting function, so a user who hits the
   gate is told where the cap comes from. *)
let test_shipped_table () =
  let gated = List.map fst !TB.stdlib_only in
  Alcotest.(check (list string)) "the four forging builtins, the epoch holds and the drain flag are gated"
    [ "pid_of_int"; "actor_pid_indices"; "observe_query"; "observe_count_send"; "actor_inspect"; "actor_whereis"; "actor_registered";
      "epoch_hold"; "epoch_release"; "epoch_draining"; "epoch_drain"; "epoch_hold_next_spawn"; "epoch_holds";
      "delivery_origin_set"; "delivery_origin_clear"; "delivery_failed_watch";
      (* ocap phase 1: the capability check point (stdlib/authority.march) *)
      "cap_check_raw"; "cap_launch_text"; "reload_request";
      "handle_new"; "handle_enter"; "handle_leave"; "handle_close"; "handle_detach";
      "handle_is_closed"; "handle_aux";
      "file_open_write"; "file_write_handle"; "file_seek";
      "dir_open"; "dir_open_write"; "file_open_at"; "dir_list_at" ]
    gated;
  List.iter (fun (name, hint) ->
      Alcotest.(check bool) (name ^ " suggestion names Actor.introspect") true
        (contains ~needle:"`Actor.introspect`" hint))
    (List.filter (fun (name, _) -> name <> "observe_count_send" && name <> "actor_inspect" && name <> "epoch_hold" && name <> "epoch_release" && name <> "epoch_draining" && name <> "epoch_drain" && name <> "epoch_hold_next_spawn" && name <> "epoch_holds" && name <> "reload_request"
                             && name <> "delivery_origin_set" && name <> "delivery_origin_clear"
                             && name <> "delivery_failed_watch"
                             && not (String.length name > 7 && String.sub name 0 7 = "handle_")
                             && not (List.mem name [ "file_open_write"; "file_write_handle"; "file_seek";
                                                     "dir_open"; "dir_open_write"; "file_open_at"; "dir_list_at";
                                                     "cap_check_raw"; "cap_launch_text" ]))
       !TB.stdlib_only);
  List.iter (fun name ->
      Alcotest.(check bool) (name ^ " suggestion names Authority.check") true
        (contains ~needle:"`Authority.check(kind, target)`" (List.assoc name !TB.stdlib_only)))
    [ "cap_check_raw"; "cap_launch_text" ];
  Alcotest.(check bool) "actor_inspect suggestion names Actor.debug" true
    (contains ~needle:"`Actor.debug`" (List.assoc "actor_inspect" !TB.stdlib_only));
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

(* ocap phase 2 (Task 2): the seven handle primitives are stdlib-only, and
   each points the user at the module open functions that make handles. *)
let handle_primitives =
  [ "handle_new"; "handle_enter"; "handle_leave"; "handle_close"; "handle_detach";
    "handle_is_closed"; "handle_aux" ]

let test_handle_primitives_gated () =
  let ctx = typecheck {|mod App do
  fn forge() do
    handle_new(3, 0, 0)
  end
end|} in
  let gate =
    List.find_opt (fun (d : March_errors.Errors.diagnostic) ->
        d.severity = March_errors.Errors.Error
        && contains ~needle:"`handle_new` is internal to the standard library" d.message)
      ctx.March_errors.Errors.diagnostics
  in
  (match gate with
   | None -> Alcotest.fail "user code calling handle_new(3, 0, 0) is not gated"
   | Some d ->
     Alcotest.(check string) "the code is stdlib_internal"
       March_errors.Errors.Code.stdlib_internal d.code;
     Alcotest.(check bool) "the message names \"handles are made by\"" true
       (contains ~needle:"handles are made by" d.message));
  List.iter (fun name ->
      Alcotest.(check bool) (name ^ " is in the shipped table") true
        (match List.assoc_opt name !TB.stdlib_only with
         | Some hint -> contains ~needle:"handles are made by their module's open functions" hint
         | None -> false))
    handle_primitives

(* ocap phase 2 (Task 4): the raw file builtins behind File.Handle are
   stdlib-only, so a guessed Int handle cannot write or seek an open file. *)
let test_raw_file_handle_builtins_gated () =
  List.iter (fun (call, name) ->
      let ctx = typecheck (Printf.sprintf {|mod App do
  fn forge() do
    %s
  end
end|} call) in
      let gated =
        List.exists (fun (d : March_errors.Errors.diagnostic) ->
            d.severity = March_errors.Errors.Error
            && d.code = March_errors.Errors.Code.stdlib_internal
            && contains ~needle:(Printf.sprintf "`%s` is internal to the standard library" name)
                 d.message)
          ctx.March_errors.Errors.diagnostics
      in
      Alcotest.(check bool) (name ^ " is refused in user code") true gated)
    [ ({|file_open_write("/tmp/x", 0)|}, "file_open_write");
      ({|file_write_handle(-2, "x")|}, "file_write_handle");
      ({|file_seek(-2, 0)|}, "file_seek");
      (* Task 7: the File.Dir builtins. *)
      ({|dir_open("/etc")|}, "dir_open");
      ({|dir_open_write("/tmp")|}, "dir_open_write");
      ({|file_open_at(3, "passwd", 0)|}, "file_open_at");
      ({|dir_list_at(3, "")|}, "dir_list_at") ]

(* ── Adversarial sweep over the shipped table ─────────────────────────────
   Every gated name, in every spelling the review's findings list (and
   `actor_pid_indices`, the builtin under `Actor.list`, through an interface
   default method), must draw exactly the same error text: the message the
   table carries for that name. One expression per (name, shape); the shape
   supplies the declaration kind and the call site. *)

let shapes : (string * (string -> string)) list =
  [ ("fn call", fun call -> Printf.sprintf {|mod App do
  fn go() do
    let _ = %s
    0
  end
end|} call);
    ("fn value reference", fun call ->
       let name = String.sub call 0 (String.index call '(') in
       Printf.sprintf {|mod App do
  fn go() do
    let f = %s
    0
  end
end|} name);
    ("module-level let self-alias", fun call ->
       let name = String.sub call 0 (String.index call '(') in
       Printf.sprintf {|mod App do
  let %s = %s
  fn go() do 0 end
end|} name name);
    ("fn-local let self-alias", fun call ->
       let name = String.sub call 0 (String.index call '(') in
       Printf.sprintf {|mod App do
  fn go() do
    let %s = %s
    0
  end
end|} name name);
    ("impl method", fun call -> Printf.sprintf {|mod App do
  interface Forger(a) do
    fn forge : a -> Int
  end
  impl Forger(Int) do
    fn forge(n) do
      let _ = %s
      n
    end
  end
end|} call);
    ("interface default method", fun call -> Printf.sprintf {|mod App do
  interface Forger(a) do
    fn forge : a -> Int
    fn dflt : a -> Int do
      fn (_n) ->
        let _ = %s
        0
    end
  end
  impl Forger(Int) do
    fn forge(n) do n end
  end
end|} call);
    ("test block", fun call -> Printf.sprintf {|mod App do
  test "forge" do
    let _ = %s
    ()
  end
end|} call);
    ("describe/test block", fun call -> Printf.sprintf {|mod App do
  describe "forging" do
    test "forge" do
      let _ = %s
      ()
    end
  end
end|} call);
    ("setup block", fun call -> Printf.sprintf {|mod App do
  setup do
    let _ = %s
    ()
  end
end|} call);
    ("setup_all block", fun call -> Printf.sprintf {|mod App do
  setup_all do
    let _ = %s
    ()
  end
end|} call);
    ("actor handler", fun call -> Printf.sprintf {|mod App do
  actor Victim do
    state { n : Int }
    init { n: 0 }
    on Bump() do
      let _ = %s
      { n: state.n + 1 }
    end
  end
end|} call);
    ("actor init", fun call -> Printf.sprintf {|mod App do
  actor Victim do
    state { n : Int }
    init do
      let _ = %s
      { n: 0 }
    end
    on Bump() do state end
  end
end|} call);
    ("pipe", fun call ->
       let name = String.sub call 0 (String.index call '(') in
       let arg = String.sub call (String.index call '(' + 1)
           (String.length call - String.index call '(' - 2) in
       Printf.sprintf {|mod App do
  fn go() do
    let _ = %s |> %s
    0
  end
end|} (if arg = "" then "()" else arg) name);
    ("nested module fn", fun call -> Printf.sprintf {|mod App do
  mod Inner do
    fn go() do
      let _ = %s
      0
    end
  end
end|} call);
    ("REPL fragment", fun call -> Printf.sprintf {|mod App do
  fn go() do
    let _ = %s
    0
  end
end|} call) ]

(* One call per gated name, well-typed where possible. *)
let calls =
  [ ("pid_of_int", "pid_of_int(0)");
    ("actor_pid_indices", "actor_pid_indices()");
    ("observe_query", "observe_query(\"PING\")");
    ("observe_count_send", "observe_count_send(())");
    (* Not well-typed (no ungated expression yields a Pid here), but the
       pipe spelling needs one plain argument; the gate fires before the
       arity check, and the sweep asserts only the gate's message. *)
    ("actor_inspect", "actor_inspect(0)");
    ("actor_whereis", "actor_whereis(\"x\")");
    ("actor_registered", "actor_registered()");
    ("epoch_hold", "epoch_hold()");
    ("epoch_release", "epoch_release()") ]

let expected_message name =
  Printf.sprintf "`%s` is internal to the standard library; %s." name
    (List.assoc name !TB.stdlib_only)

let errors_of ~shape src =
  if shape = "REPL fragment" then begin
    let errors = March_errors.Errors.create () in
    let env = March_typecheck.Typecheck.base_env errors (Hashtbl.create 16) in
    fst (March_typecheck.Typecheck.check_module_with_env env (parse_and_desugar src))
  end else typecheck src

let test_adversarial_sweep () =
  let failures = ref [] in
  List.iter (fun (name, call) ->
      List.iter (fun (shape, mk) ->
          let src = mk call in
          let ctx = errors_of ~shape src in
          let msg = expected_message name in
          let exact =
            List.exists (fun (d : March_errors.Errors.diagnostic) ->
                d.severity = March_errors.Errors.Error && d.message = msg)
              ctx.March_errors.Errors.diagnostics
          in
          if not exact then
            failures :=
              Printf.sprintf "%s via %s: expected exactly\n  %s\ngot:\n%s" name shape msg
                (String.concat "\n"
                   (List.map (fun (d : March_errors.Errors.diagnostic) -> "  " ^ d.message)
                      ctx.March_errors.Errors.diagnostics))
              :: !failures)
        shapes)
    calls;
  if !failures <> [] then
    Alcotest.failf "%d sweep case(s) not gated with the table's message:\n%s"
      (List.length !failures) (String.concat "\n\n" (List.rev !failures))

(* And the sweep's negative control: every shape, with the gated name rebound
   by a user binding, is silent. Without this the sweep could pass on a gate
   that rejects the NAME rather than the builtin. *)
let test_sweep_negative_control () =
  let src = {|mod App do
  fn pid_of_int(n : Int) : Int do n end
  fn actor_pid_indices() : List(Int) do [] end
  fn actor_whereis(s : String) : Option(Int) do None end
  fn actor_registered() : List(String) do [] end
  fn epoch_hold() : () do () end
  fn epoch_release() : () do () end
  interface Forger(a) do
    fn forge : a -> Int
    fn dflt : a -> Int do
      fn (_n) ->
        let _ = actor_pid_indices()
        0
    end
  end
  impl Forger(Int) do
    fn forge(n) do
      let _ = pid_of_int(n)
      let _ = actor_whereis("x")
      n
    end
  end
  actor Victim do
    state { n : Int }
    init { n: 0 }
    on Bump() do
      let _ = actor_registered()
      { n: state.n + 1 }
    end
  end
  test "t" do
    let _ = epoch_hold()
    let _ = epoch_release()
    ()
  end
end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "user bindings of every gated name are not the builtins" false
    (has_error_with ctx "internal to the standard library")


(* ── @[stdlib_internal]: the gate for stdlib FUNCTIONS (ocap phase 2, task 3) ──
   A stdlib module's `@[stdlib_internal] fn` may be named only from a span the
   stdlib owns. Each source below is one `mod`; they are parsed under their own
   file name and nested into one entry module, the way the driver nests the
   stdlib's modules beside the user's. *)
let internal_message = "`Inner.raw` is internal to the standard library; use the handle API in `Inner`."

let inner_src = {|mod Inner do
  @[stdlib_internal]
  fn raw(fd : Int) : Int do fd end
end|}

let typecheck_files (files : (string * string) list) =
  let nested = List.map (fun (file, src) ->
      let lexbuf = Lexing.from_string src in
      Lexing.set_filename lexbuf file;
      let m = March_parser.Parse.module_of_lexbuf lexbuf in
      let sp = March_ast.Ast.dummy_span in
      March_ast.Ast.DMod (m.March_ast.Ast.mod_name, March_ast.Ast.Public,
                          m.March_ast.Ast.mod_decls, sp)) files in
  let entry = { March_ast.Ast.mod_name = { March_ast.Ast.txt = "Entry"; span = March_ast.Ast.dummy_span };
                mod_decls = nested } in
  let (errors, _) =
    March_typecheck.Typecheck.check_module (March_desugar.Desugar.desugar_module entry) in
  errors

let internal_ctx user_src =
  with_gate ~stdlib_files:[ "inner.march"; "other.march" ] (fun () ->
      typecheck_files [ ("inner.march", inner_src); ("app.march", user_src) ])

let test_internal_fn_call_refused () =
  let ctx = internal_ctx {|mod App do
  fn go() : Int do Inner.raw(3) end
end|} in
  Alcotest.(check bool) "a user call is refused" true (has_error_with ctx internal_message)

let test_internal_fn_value_refused () =
  let ctx = internal_ctx {|mod App do
  fn go() : Int do
    let f = Inner.raw
    f(3)
  end
end|} in
  Alcotest.(check bool) "a value reference is refused" true (has_error_with ctx internal_message)

let test_internal_fn_stdlib_ok () =
  let ctx = with_gate ~stdlib_files:[ "inner.march"; "other.march" ] (fun () ->
      typecheck_files [ ("inner.march", inner_src);
                        ("other.march", {|mod Other do
  fn go() : Int do Inner.raw(3) end
end|}) ]) in
  Alcotest.(check bool) "a stdlib module may call it" false
    (has_error_with ctx "internal to the standard library")

let test_internal_fn_user_shadow_ok () =
  let ctx = internal_ctx {|mod App do
  fn raw(fd : Int) : Int do fd end
  fn go() : Int do raw(3) end
end|} in
  Alcotest.(check bool) "a user fn named raw is not Inner.raw" false
    (has_error_with ctx "internal to the standard library")


(* Fix round 1: every import form rebinds a member under another key, so the
   spelled-name gate alone would miss it. *)
let inner_two_src = {|mod Inner do
  @[stdlib_internal]
  fn raw(fd : Int) : Int do fd end
  fn other(n : Int) : Int do n end
end|}

let internal_ctx2 user_src =
  with_gate ~stdlib_files:[ "inner.march"; "other.march" ] (fun () ->
      typecheck_files [ ("inner.march", inner_two_src); ("app.march", user_src) ])

let refused ctx = has_error_with ctx "is internal to the standard library"

let test_internal_use_all_refused () =
  let ctx = internal_ctx2 {|mod App do
  use Inner.*
  fn go() : Int do raw(3) end
end|} in
  Alcotest.(check bool) "use Inner.* leaves raw out, so raw(3) is unbound" true
    (has_errors ctx)

let test_internal_use_names_refused () =
  let ctx = internal_ctx2 {|mod App do
  use Inner.{raw}
  fn go() : Int do raw(3) end
end|} in
  Alcotest.(check bool) "explicit import is stdlib_internal" true
    (has_error_with ctx "`Inner.raw` is internal to the standard library; use the handle API in `Inner`.")

let test_internal_use_except_refused () =
  let ctx = internal_ctx2 {|mod App do
  import Inner, except: [other]
  fn go() : Int do raw(3) end
end|} in
  Alcotest.(check bool) "use Inner.{except ..} leaves raw out" true (has_errors ctx)

let test_internal_alias_refused () =
  let ctx = internal_ctx2 {|mod App do
  alias Inner, as: I
  fn go() : Int do I.raw(3) end
end|} in
  Alcotest.(check bool) "I.raw does not resolve" true (has_errors ctx)

let test_internal_use_other_still_works () =
  let ctx = internal_ctx2 {|mod App do
  use Inner.*
  fn go() : Int do other(3) end
end|} in
  Alcotest.(check bool) "non-internal members still import" false (has_errors ctx)

let test_internal_use_all_stdlib_ok () =
  let ctx = with_gate ~stdlib_files:[ "inner.march"; "other.march" ] (fun () ->
      typecheck_files [ ("inner.march", inner_src);
                        ("other.march", {|mod Other do
  use Inner.*
  fn go() : Int do raw(3) end
end|}) ]) in
  Alcotest.(check bool) "a stdlib module may use Inner.* and call raw" false
    (has_errors ctx)

let test_internal_dotted_use_refused () =
  let ctx = with_gate ~stdlib_files:[ "inner.march"; "other.march" ] (fun () ->
      typecheck_files [ ("inner.march", {|mod Outer do
  mod Inner do
    @[stdlib_internal]
    fn raw(fd : Int) : Int do fd end
  end
end|});
                        ("app.march", {|mod App do
  use Outer.Inner
  fn go() : Int do Inner.raw(3) end
end|}) ]) in
  Alcotest.(check bool) "dotted use A.B does not rebind raw" true (has_errors ctx)

let test_internal_same_name_user_module_ok () =
  let ctx = internal_ctx {|mod Inner do
  fn raw(fd : Int) : Int do fd end
  fn go() : Int do Inner.raw(3) end
end|} in
  Alcotest.(check bool) "a user module named Inner owns its own Inner.raw" false
    (refused ctx)

let tests =
  [ ("stdlib-only builtins",
     [ Alcotest.test_case "user call rejected" `Quick test_user_call_rejected;
       Alcotest.test_case "user value reference rejected" `Quick
         test_user_value_reference_rejected;
       Alcotest.test_case "local definition shadows" `Quick test_local_definition_shadows;
       Alcotest.test_case "param and local let shadow" `Quick test_param_and_let_shadow;
       Alcotest.test_case "stdlib module allowed" `Quick test_stdlib_module_allowed;
       Alcotest.test_case "stdlib-looking path is not stdlib" `Quick
         test_user_file_named_like_stdlib_is_not_stdlib;
       Alcotest.test_case "REPL is user code" `Quick test_repl_is_user_code;
       Alcotest.test_case "module-level let self-alias rejected" `Quick
         test_module_let_self_alias_rejected;
       Alcotest.test_case "fn-local let self-alias rejected" `Quick
         test_fn_local_self_alias_rejected;
       Alcotest.test_case "impl method rejected" `Quick test_impl_method_rejected;
       Alcotest.test_case "interface default method rejected" `Quick
         test_interface_default_rejected;
       Alcotest.test_case "test/describe/setup/setup_all rejected" `Quick
         test_test_blocks_rejected;
       Alcotest.test_case "actor handler rejected" `Quick test_actor_handler_rejected;
       Alcotest.test_case "stdlib root provenance, not basename" `Quick
         test_stdlib_root_provenance;
       Alcotest.test_case "driver rejects a user json.march" `Quick
         test_driver_rejects_user_json_march;
       Alcotest.test_case "shipped table gates the four forging builtins" `Quick
         test_shipped_table;
       Alcotest.test_case "handle_primitives_gated" `Quick test_handle_primitives_gated;
       Alcotest.test_case "raw_file_handle_builtins_gated" `Quick test_raw_file_handle_builtins_gated;
       Alcotest.test_case "internal_fn_call_refused" `Quick test_internal_fn_call_refused;
       Alcotest.test_case "internal_fn_value_refused" `Quick test_internal_fn_value_refused;
       Alcotest.test_case "internal_fn_stdlib_ok" `Quick test_internal_fn_stdlib_ok;
       Alcotest.test_case "internal_fn_user_shadow_ok" `Quick test_internal_fn_user_shadow_ok;
       Alcotest.test_case "internal_use_all_refused" `Quick test_internal_use_all_refused;
       Alcotest.test_case "internal_use_names_refused" `Quick test_internal_use_names_refused;
       Alcotest.test_case "internal_use_except_refused" `Quick test_internal_use_except_refused;
       Alcotest.test_case "internal_alias_refused" `Quick test_internal_alias_refused;
       Alcotest.test_case "internal_use_other_still_works" `Quick test_internal_use_other_still_works;
       Alcotest.test_case "internal_use_all_stdlib_ok" `Quick test_internal_use_all_stdlib_ok;
       Alcotest.test_case "internal_dotted_use_refused" `Quick test_internal_dotted_use_refused;
       Alcotest.test_case "internal_same_name_user_module_ok" `Quick test_internal_same_name_user_module_ok;
       Alcotest.test_case "adversarial sweep: every name, every spelling, same text" `Quick
         test_adversarial_sweep;
       Alcotest.test_case "sweep negative control: rebound names are silent" `Quick
         test_sweep_negative_control ]) ]
