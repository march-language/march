(* Capability runtime dictionaries — the typing and gating half.

   Design: specs/todos/2026-08-31-cap-runtime-dictionaries.md.

   A capability may declare a DICTIONARY TYPE:

     proof cap Ops with SessionOps

   [cap_impl(cap, dict)] attaches a dictionary; [cap_dict(cap)] reads it back
   as an [Option], the [None] case being "no dictionary — ambient/default
   implementation", which is every capability that exists today.

   Attaching a dictionary is forging a capability's BEHAVIOUR, which is the
   same threat model [check_mint_cap_sites] exists to defeat, so the gate is
   [mint_cap]'s gate: a public fn of the declaring module, with the result
   type pinned at the site.  These tests are the reject half of that gate;
   without them a dictionary is a hole straight through capability
   unforgeability. *)

open Test_helpers

let ok name src =
  Alcotest.test_case name `Quick (fun () ->
      let ctx = typecheck src in
      Alcotest.(check bool) (name ^ ": no error") false (has_errors ctx))

let bad name src =
  Alcotest.test_case name `Quick (fun () ->
      let ctx = typecheck src in
      Alcotest.(check bool) (name ^ ": error") true (has_errors ctx))

(* ── the `with` clause on a cap declaration ───────────────────────────── *)

let decl_ok = ok "cap declares a dictionary type" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  needs IO
  fn boot() : Cap(Session.Live) do
    mint_cap()
  end
end|}

let decl_unknown_type = bad "cap declares an undeclared dictionary type" {|mod Session do
  proof cap Live with Nope
end|}

let decl_non_record = bad "dictionary type must be a record" {|mod Session do
  type Ops = A | B
  proof cap Live with Ops
end|}

(* ── cap_impl: the gate ───────────────────────────────────────────────── *)

let impl_ok = ok "cap_impl in a public fn of the declaring module" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  needs IO
  fn boot() : Cap(Session.Live) do
    cap_impl(mint_cap(), { tick: fn n -> n + 1 })
  end
end|}

let impl_pfn = bad "cap_impl in a private fn is rejected" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  needs IO
  pfn boot() : Cap(Session.Live) do
    cap_impl(mint_cap(), { tick: fn n -> n + 1 })
  end
end|}

let impl_external = bad "cap_impl outside the declaring module is rejected" {|mod Top do
  mod Session do
    type Ops = { tick : (Int) -> Int }
    proof cap Live with Ops
  end
  mod App do
    needs Session.Live
    fn swap(c : Cap(Session.Live)) : Cap(Session.Live) do
      cap_impl(c, { tick: fn n -> n + 1 })
    end
  end
end|}

let impl_wrong_dict = bad "cap_impl with the wrong dictionary type is rejected" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  type Other = { blah : Int }
  proof cap Live with Ops
  needs IO
  fn boot() : Cap(Session.Live) do
    cap_impl(mint_cap(), { blah: 1 })
  end
end|}

let impl_no_dict_declared = bad "cap_impl on a cap with no `with` clause is rejected" {|mod Session do
  proof cap Live
  needs IO
  fn boot() : Cap(Session.Live) do
    cap_impl(mint_cap(), { tick: 1 })
  end
end|}

(* An IO cap has no declaring module, so the declaring-module rule has nothing
   to bind to.  Outside a --test build this must be refused outright; the
   test-build admission is a separate, build-mode-gated path. *)
let impl_io_cap = bad "cap_impl on an IO cap is rejected in a normal build" {|mod App do
  needs IO.Console
  type Ops = { write : (String) -> () }
  fn boot(c : Cap(IO.Console)) : Cap(IO.Console) do
    cap_impl(c, { write: fn s -> println(s) })
  end
end|}

(* Same forge vector [check_mint_cap_sites] rejects: a generalized let-bound
   lambda whose result cap never gets pinned is a supplier polymorphic in the
   capability. *)
let impl_unpinned = bad "cap_impl with an unpinned (generalized) result is rejected" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  needs IO
  fn boot() do
    let f = fn _ -> cap_impl(mint_cap(), { tick: fn n -> n + 1 })
    f
  end
end|}

(* ── cap_dict: reading it back ────────────────────────────────────────── *)

let dict_reads_option = ok "cap_dict yields Option of the declared dictionary" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  fn run(c : Cap(Session.Live), n : Int) : Int do
    match cap_dict(c) do
      Some(d) -> d.tick(n)
      None    -> n
    end
  end
end|}

let dict_not_bare = bad "cap_dict result is not the bare dictionary" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  fn run(c : Cap(Session.Live), n : Int) : Int do
    let d : Ops = cap_dict(c)
    d.tick(n)
  end
end|}

let dict_no_declaration = bad "cap_dict on a cap with no `with` clause is rejected" {|mod Session do
  proof cap Live
  fn run(c : Cap(Session.Live)) : Int do
    match cap_dict(c) do
      Some(_) -> 1
      None    -> 0
    end
  end
end|}

(* ── two modules, one bare dictionary name ───────────────────────────── *)

(* March has one global type namespace, so two modules that each declare
   `type Ops` both register the bare key "Ops" in [env.records], the later one
   winning.  The resolver used to try that bare key FIRST, so the earlier
   module's `cap_impl`/`cap_dict` resolved to the OTHER module's record and
   failed with "expected `Ops` but got `Ops`".  Hit in PR #601, where adding
   `type Ops` to ClusterNode broke Session.attach (worked around by renaming
   to ClusterOps).  Both modules attach AND read, and a third module reads
   each through its qualified cap, so the post-module sweep
   ([check_cap_impl_sites]) and the inline inference arm ([cap_dict]) are
   both covered, whichever module was declared last. *)
let two_mods_src = {|mod Top do
  mod Alpha do
    type Ops = { tick : (Int) -> Int }
    proof cap Live with Ops
    needs IO
    fn boot() : Cap(Alpha.Live) do
      cap_impl(mint_cap(), { tick: fn n -> n + 1 })
    end
    fn run(c : Cap(Alpha.Live), n : Int) : Int do
      match cap_dict(c) do
        Some(d) -> d.tick(n)
        None    -> n
      end
    end
  end
  mod Beta do
    type Ops = { name : (Int) -> String }
    proof cap Live with Ops
    needs IO
    fn boot() : Cap(Beta.Live) do
      cap_impl(mint_cap(), { name: fn n -> int_to_string(n) })
    end
    fn run(c : Cap(Beta.Live), n : Int) : String do
      match cap_dict(c) do
        Some(d) -> d.name(n)
        None    -> ""
      end
    end
  end
  mod User do
    needs Alpha.Live, Beta.Live
    fn a(c : Cap(Alpha.Live)) : Int do
      match cap_dict(c) do
        Some(d) -> d.tick(1)
        None    -> 0
      end
    end
    fn b(c : Cap(Beta.Live)) : String do
      match cap_dict(c) do
        Some(d) -> d.name(1)
        None    -> ""
      end
    end
  end
end|}

let two_mods_same_dict_name =
  ok "two modules each declaring `proof cap Live with Ops` both resolve"
    two_mods_src

(* The declaring module's record is not just "some Ops": handing Alpha's cap
   Beta's field still fails, so the fix did not loosen the check to a bare
   name match. *)
let two_mods_wrong_dict = bad "a same-named dictionary from the other module is still rejected" {|mod Top do
  mod Alpha do
    type Ops = { tick : (Int) -> Int }
    proof cap Live with Ops
    needs IO
    fn boot() : Cap(Alpha.Live) do
      cap_impl(mint_cap(), { name: fn n -> int_to_string(n) })
    end
  end
  mod Beta do
    type Ops = { name : (Int) -> String }
    proof cap Live with Ops
  end
end|}

(* ── attenuation propagates the dictionary, but cannot attach one ─────── *)

(* Ocap phase 7b retired `cap_narrow` with the IO capability values it
   narrowed: the attenuation this case once typed is now refused. *)
let narrow_keeps_dict_type =
  Alcotest.test_case "cap_narrow is retired (ocap phase 7b)" `Quick (fun () ->
      let ctx = typecheck {|mod App do
  needs IO
  fn go(c : Cap(IO)) : Int do
    let n = cap_narrow(c)
    consume(n)
  end
  fn consume(_c : Cap(IO.Console)) : Int do 1 end
end|} in
      Alcotest.(check bool) "cap_narrow_retired" true (has_error_with ctx "`cap_narrow` was retired");
      Alcotest.(check bool) "cap_param_retired" true (has_error_with ctx "takes a `Cap(IO)` parameter"))

(* Under --test the gate now OPENS: an IO capability's dictionary type is
   derived from the compiler's own builtin tables ([Io_ops_gen]), so `cap_impl`
   on one typechecks.  What is still missing is the BINDING SITE — nothing yet
   lets a test say "run this code with that mock" — so attaching one has no
   runtime effect.  Pinned so the change is deliberate rather than discovered
   later, and so the remaining gap stays visible. *)
let impl_io_cap_test_build =
  Alcotest.test_case "--test refuses cap_impl on an IO capability too (retired: use mock)"
    `Quick (fun () ->
      let saved = !March_typecheck.Typecheck.test_build in
      March_typecheck.Typecheck.test_build := true;
      let ctx =
        Fun.protect
          ~finally:(fun () -> March_typecheck.Typecheck.test_build := saved)
          (fun () -> typecheck {|mod App do
  needs IO.Console
  fn boot(c : Cap(IO.Console)) : Cap(IO.Console) do
    cap_impl(c, { cap_ops_empty(c) with print_line: Some(fn _ -> ()) })
  end
end|})
      in
      Alcotest.(check bool) "refused under --test" true (has_errors ctx))

(* ── runtime: the dictionary actually dispatches ──────────────────────── *)

let run_int src fn args =
  let env = eval_module src in
  match call_fn env fn args with
  | March_eval.Eval_types.VInt n -> n
  | _ -> Alcotest.fail "expected an Int result"

let dispatch_src = {|mod Session do
  needs IO
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  fn plain() : Cap(Session.Live) do
    mint_cap()
  end
  fn with_add(k : Int) : Cap(Session.Live) do
    cap_impl(mint_cap(), { tick: fn n -> n + k })
  end
  fn with_mul(k : Int) : Cap(Session.Live) do
    cap_impl(mint_cap(), { tick: fn n -> n * k })
  end
  fn run(c : Cap(Session.Live), n : Int) : Int do
    match cap_dict(c) do
      Some(d) -> d.tick(n)
      None    -> n
    end
  end
  fn swapped_add(n : Int, k : Int) : Int do run(with_add(k), n) end
  fn swapped_mul(n : Int, k : Int) : Int do run(with_mul(k), n) end
  fn defaulted(n : Int) : Int do run(plain(), n) end
end|}

let rt_dispatch =
  Alcotest.test_case "an attached dictionary is what dispatch reaches" `Quick
    (fun () ->
      Alcotest.(check int) "5 + 100" 105
        (run_int dispatch_src "swapped_add"
           [ March_eval.Eval_types.VInt 5; March_eval.Eval_types.VInt 100 ]))

(* The point of the whole item: same capability TYPE, same consumer, different
   behaviour, chosen at the binding site.  One dictionary alone cannot show
   this — it is indistinguishable from a hard-coded implementation. *)
let rt_swap =
  Alcotest.test_case "two dictionaries on one capability give two behaviours"
    `Quick (fun () ->
      let add =
        run_int dispatch_src "swapped_add"
          [ March_eval.Eval_types.VInt 5; March_eval.Eval_types.VInt 3 ] in
      let mul =
        run_int dispatch_src "swapped_mul"
          [ March_eval.Eval_types.VInt 5; March_eval.Eval_types.VInt 3 ] in
      Alcotest.(check int) "add dictionary" 8 add;
      Alcotest.(check int) "mul dictionary" 15 mul)

(* A capability with no dictionary is the sentinel, so the read is [None] and
   the consumer takes its ambient/default path.  This is every capability that
   exists today, so it is the case that must not regress. *)
let rt_default =
  Alcotest.test_case "no dictionary reads as None and takes the default path"
    `Quick (fun () ->
      Alcotest.(check int) "identity default" 7
        (run_int dispatch_src "defaulted" [ March_eval.Eval_types.VInt 7 ]))

(* Attenuation must carry the dictionary across: a narrowed capability is the
   SAME authority, reduced, not a different one.

   Since ocap phase 7b `cap_narrow` is a retired builtin the checker refuses
   ([narrow_keeps_dict_type]); this runs the interpreter's builtin directly,
   [eval_module] does not typecheck, so the runtime behaviour stays pinned
   until the builtin is removed
   (specs/todos/2026-11-26-ocap-remove-deprecated-main-cap-form.md). A mint
   takes no capability (`mint_cap()`), so it has no dictionary to inherit. *)
let rt_narrow_propagates =
  Alcotest.test_case "cap_narrow propagates an attached dictionary" `Quick
    (fun () ->
      let src = {|mod Two do
  type Ops = { tick : (Int) -> Int }
  proof cap A with Ops
  proof cap B with Ops
  fn mk() : Cap(Two.A) do
    cap_impl(mint_cap(), { tick: fn n -> n + 100 })
  end
  fn read_b(c : Cap(Two.B), n : Int) : Int do
    match cap_dict(c) do
      Some(d) -> d.tick(n)
      None    -> n
    end
  end
  fn through_narrow(n : Int) : Int do read_b(cap_narrow(mk()), n) end
end|} in
      Alcotest.(check int) "narrow keeps the dictionary" 105
        (run_int src "through_narrow" [ March_eval.Eval_types.VInt 5 ]))

(* ── derived IO-capability dictionary shapes ──────────────────────────── *)

module G = March_typecheck.Io_ops_gen

let field_names cap = List.map fst (G.dict_fields cap)

(* `println` is NOT a field: stdlib/prelude.march defines `fn println(x) do
   print_line(show(x)) end`, so the builtin the table types `(String) -> ()` is
   dead and a user's `println(42)` resolves to the polymorphic March function.
   A field derived from the table would be typed for something nothing calls —
   which looks like a working mock and silently is not.  What IS interceptable
   is the `print_line` it delegates to. *)
let io_console_shape =
  Alcotest.test_case "IO.Console excludes the stdlib-shadowed println" `Quick
    (fun () ->
      Alcotest.(check (list string)) "fields"
        [ "io_read_byte"; "io_read_line"; "print"; "print_line"; "print_stderr" ]
        (field_names "IO.Console");
      Alcotest.(check (list string)) "println is reported as excluded"
        [ "println" ] (G.excluded_ops "IO.Console"))

(* The shadowed-builtin list is hand-maintained, which is exactly the shape
   that drifts, so check it against the stdlib sources.  A new stdlib function
   that shadows a cap-requiring builtin silently kills that builtin's field;
   this fails and says which name to add. *)
let shadow_list_matches_stdlib =
  Alcotest.test_case "shadowed_by_stdlib matches the stdlib sources" `Quick
    (fun () ->
      (* Identify the stdlib by a MARKER FILE, not by the directory name.
         `stdlib` alone matched `test/stdlib` — 97 stdlib TEST fixtures — when
         dune runs the suite with cwd = _build/default/test, which is how this
         passed locally (run from the repo root) and failed on both CI
         platforms.  `../stdlib` is the staged copy that test/dune declares as
         `(source_tree ../stdlib)`, so it is the one that is guaranteed to be
         there. *)
      let stdlib_dir =
        let candidates = [ "../stdlib"; "stdlib"; "../../../stdlib"; "../../stdlib" ] in
        match
          List.find_opt
            (fun d -> Sys.file_exists (Filename.concat d "prelude.march"))
            candidates
        with
        | Some d -> d
        | None ->
          Alcotest.failf "cannot find the stdlib (no prelude.march in: %s); cwd=%s"
            (String.concat ", " candidates) (Sys.getcwd ())
      in
      let defined = Hashtbl.create 512 in
      let re = Str.regexp "^[ \t]*p?fn[ \t]+\\([a-z_][A-Za-z0-9_]*\\)[ \t]*(" in
      let rec walk dir =
        Array.iter
          (fun e ->
             let path = Filename.concat dir e in
             if Sys.is_directory path then walk path
             else if Filename.check_suffix e ".march" then begin
               let ic = open_in path in
               (try
                  while true do
                    let line = input_line ic in
                    if Str.string_match re line 0 then
                      Hashtbl.replace defined (Str.matched_group 1 line) ()
                  done
                with End_of_file -> ());
               close_in ic
             end)
          (Sys.readdir dir)
      in
      walk stdlib_dir;
      (* Guard against a vacuous pass: if the walk ever finds nothing, an empty
         [shadowed_by_stdlib] would compare equal to an empty [actual] and this
         test would go green while checking nothing. *)
      Alcotest.(check bool)
        (Printf.sprintf "the walk found a plausible stdlib (%d fn definitions in %s)"
           (Hashtbl.length defined) stdlib_dir)
        true (Hashtbl.length defined > 500);
      let actual =
        List.map fst March_typecheck.Typecheck_builtins.builtin_cap_table
        |> List.sort_uniq String.compare
        |> List.filter (Hashtbl.mem defined)
      in
      Alcotest.(check (list string)) "cap-requiring builtins shadowed by stdlib"
        (List.sort String.compare G.shadowed_by_stdlib) actual)

(* Zero-arg builtins are the interesting case: March auto-applies a zero-arg
   function as soon as it is named, so `unix_time` cannot be stored in a field
   as `() -> Float` and must take an explicit unit.  If that ever regresses,
   IO.Clock — the canonical thing to mock — silently loses its dictionary. *)
let io_clock_zero_arg =
  Alcotest.test_case "IO.Clock's zero-arg ops survive as unit-taking fields" `Quick
    (fun () ->
      Alcotest.(check (list string)) "fields"
        [ "unix_time"; "unix_time_ms"; "uuid_v7" ] (field_names "IO.Clock");
      Alcotest.(check bool) "IO.Clock has a dictionary" true (G.dict_ty "IO.Clock" <> None))

(* IO.Mut is entirely vault_*, all polymorphic, so it has NO dictionary. That
   is a documented hole, not an oversight — assert both halves so a future
   change that quietly drops operations shows up here. *)
let io_mut_has_no_dictionary =
  Alcotest.test_case "IO.Mut has no dictionary and says which ops it lost" `Quick
    (fun () ->
      Alcotest.(check bool) "no dictionary" true (G.dict_ty "IO.Mut" = None);
      Alcotest.(check (list string)) "a vault mock's handler is the open hook (ocap phase 7)"
        [ "open" ] (List.map fst (G.mock_fields "IO.Mut"));
      Alcotest.(check bool) "and every op is reported as excluded" true
        (List.length (G.excluded_ops "IO.Mut") = List.length (G.ops_of_cap "IO.Mut")
         && G.excluded_ops "IO.Mut" <> []))

(* Every operation that cannot be intercepted must appear in the documentation,
   or a mock silently fails to cover it and nothing says so. *)
let excluded_ops_are_documented =
  Alcotest.test_case "every un-interceptable op is named in --emit-io-ops" `Quick
    (fun () ->
      let doc = G.render () in
      let missing =
        List.concat_map G.excluded_ops (G.all_caps ())
        |> List.filter (fun op ->
            try ignore (Str.search_forward (Str.regexp_string op) doc 0); false
            with Not_found -> true)
      in
      Alcotest.(check (list string)) "undocumented exclusions" [] missing)

(* Typecheck_unify asserts that every TRecord is built with sorted fields; an
   unsorted one produces confusing "type mismatch" errors far from here. *)
let dict_fields_sorted =
  Alcotest.test_case "dictionary fields are sorted (TRecord invariant)" `Quick
    (fun () ->
      let unsorted =
        List.filter (fun cap ->
            let f = field_names cap in f <> List.sort String.compare f)
          (G.all_caps ())
      in
      Alcotest.(check (list string)) "caps with unsorted fields" [] unsorted)

(* ── `mock` blocks (ocap phase 7) ────────────────────────────────────── *)

(* [test_build] on for [f], restored after. *)
let in_test_build f =
  let saved = !March_typecheck.Typecheck.test_build in
  March_typecheck.Typecheck.test_build := true;
  Fun.protect ~finally:(fun () -> March_typecheck.Typecheck.test_build := saved) f

let mock_ok name src =
  Alcotest.test_case name `Quick (fun () ->
      let ctx = in_test_build (fun () -> typecheck src) in
      Alcotest.(check bool) (name ^ ": no error") false (has_errors ctx))

let mock_bad name src =
  Alcotest.test_case name `Quick (fun () ->
      let ctx = in_test_build (fun () -> typecheck src) in
      Alcotest.(check bool) (name ^ ": error") true (has_errors ctx))

let mock_partial_literal = mock_ok "a mock handler literal may name only some fields" {|mod T do
  needs IO.Console
  fn f() : () do
    mock IO.Console with { print_line: Some(fn _ -> ()) } do
      Authority.ignore(println("x"))
    end
  end
end|}

let mock_named_handler = mock_ok "a named handler is the kind's whole record" {|mod T do
  needs IO.Clock
  fn f(h : { unix_time : Option(() -> Float), unix_time_ms : Option(() -> Int), uuid_v7 : Option(() -> String) }) : Int do
    mock IO.Clock with h do
      Authority.must(System.now_ms())
    end
  end
end|}

let mock_vault_handler = mock_ok "a vault mock's handler is the open hook" {|mod T do
  fn f() : () do
    mock IO.Mut("sessions") with { open: None } do
      ()
    end
  end
end|}

let mock_field_type = mock_bad "a handler field of the wrong type is refused" {|mod T do
  needs IO.Console
  fn f() : () do
    mock IO.Console with { print_line: Some(fn n -> n + 1) } do
      ()
    end
  end
end|}

let mock_unknown_field = mock_bad "a handler field the kind does not have is refused" {|mod T do
  needs IO.Console
  fn f() : () do
    mock IO.Console with { println: Some(fn _ -> ()) } do
      ()
    end
  end
end|}

let mock_two_kinds = mock_bad "a mock of two kinds is refused" {|mod T do
  needs IO.Console
  needs IO.Clock
  fn f() : () do
    mock IO.Console, IO.Clock with { print_line: None } do
      ()
    end
  end
end|}

let mock_computed_scope = mock_bad "a computed mock scope is refused" {|mod T do
  needs IO.FileRead
  fn f(d : String) : () do
    mock IO.FileRead(d) with { file_read: None } do
      ()
    end
  end
end|}

let mock_unmockable_kind = mock_bad "a kind with no operations to mock is refused" {|mod T do
  fn f() : () do
    mock IO with { open: None } do
      ()
    end
  end
end|}

let mock_outside_test = bad "a mock outside a test build is refused" {|mod T do
  needs IO.Console
  fn f() : () do
    mock IO.Console with { print_line: None } do
      ()
    end
  end
end|}

(* The test build's TIR rewrite: an interceptable operation's call is routed
   to its dispatch wrapper, and a wrapper's own call of the operation is not
   (it would call itself). *)
let mock_dispatch_rewrite =
  Alcotest.test_case "Mock_dispatch routes operations through their wrappers" `Quick
    (fun () ->
      let module T = March_tir.Tir in
      let v name = { T.v_name = name; v_ty = T.TFn ([ T.TString ], T.TUnit); v_lin = T.Unr } in
      let call name = T.EApp (v name, [ T.ALit (March_ast.Ast.LitString "x") ]) in
      let fn name body = { T.fn_name = name; fn_params = []; fn_ret_ty = T.TUnit;
                           fn_body = body; fn_kind = T.FnNormal } in
      let u = { T.v_name = "u"; v_ty = T.TUnit; v_lin = T.Unr } in
      let m = { T.tm_name = "M"; tm_types = []; tm_externs = []; tm_exports = [];
                tm_tests = []; tm_io_fns = [];
                T.tm_fns = [ fn "user" (T.ELet (u, call "print_line", call "print_line"));
                             fn "__march_dispatch_print_line" (call "print_line");
                             fn "other" (call "not_a_cap_op") ] } in
      let m' = March_tir.Mock_dispatch.rewrite m in
      let body n = (List.find (fun (f : T.fn_def) -> f.T.fn_name = n) m'.T.tm_fns).T.fn_body in
      let rec callees = function
        | T.EApp (v, _) -> [ v.T.v_name ]
        | T.ELet (_, a, b) -> callees a @ callees b
        | _ -> [] in
      Alcotest.(check (list string)) "user calls go through the wrapper"
        [ "__march_dispatch_print_line"; "__march_dispatch_print_line" ] (callees (body "user"));
      Alcotest.(check (list string)) "the wrapper keeps the real call"
        [ "print_line" ] (callees (body "__march_dispatch_print_line"));
      Alcotest.(check (list string)) "other builtins are untouched"
        [ "not_a_cap_op" ] (callees (body "other")))

(* A release build carries no dispatch wrapper and no mock registry call:
   the only shared change is in the authority's policy. *)
let release_build_has_no_wrappers =
  Alcotest.test_case "a release build's IR names no dispatch wrapper" `Quick
    (fun () ->
      let ir = emit_actor_ir {|mod R do
  needs IO.Console
  fn main() do
    println("hi")
  end
end|} in
      let has sub =
        let n = String.length ir and k = String.length sub in
        let rec go i = i + k <= n && (String.sub ir i k = sub || go (i + 1)) in
        go 0 in
      Alcotest.(check bool) "no __march_dispatch_" false (has "__march_dispatch_");
      Alcotest.(check bool) "no march_mock_register call" false (has "call i64 @march_mock_register"))

(* ── the surface spelling of a multi-argument field ───────────────────── *)

(* `Io_ops_gen.march_ty` once rendered a curried arrow as `(A, B) -> C`. In
   March that is a function of ONE argument that is a tuple (`Tuple.apply`
   calls its `f : (a, b) -> c` as `f(t)`), so `--emit-io-ops` printed every
   multi-argument field in a form that means the wrong thing. That leaked into a
   design record and a day of probing that concluded a record field could not
   hold a two-argument function at all. The compiler-built dictionaries were
   never affected -- they are built from `ty` values, not this string -- which
   is why a real 2-argument mock worked while the "same" shape typed by hand
   did not.

   Two assertions: the rendering is the documented curried spelling, and that
   rendering ROUND-TRIPS -- pasted into a record field it typechecks against a
   two-parameter lambda. The second is the one that catches the bug; the first
   only says what the fix looks like. *)
let rendered_multi_arg_is_curried =
  Alcotest.test_case "a multi-argument field renders curried, and round-trips"
    `Quick (fun () ->
      let open March_typecheck.Typecheck_types in
      let t_int = TCon ("Int", []) and t_str = TCon ("String", []) in
      let two = TArrow (t_int, TArrow (t_str, t_int)) in
      Alcotest.(check string) "curried spelling"
        "Int -> String -> Int" (G.march_ty two);
      (* an arrow in argument position must be parenthesised: `->` is
         right-associative, so `(A -> B) -> C` is not `A -> B -> C` *)
      let hof = TArrow (TArrow (t_int, t_int), t_int) in
      Alcotest.(check string) "arrow argument parenthesised"
        "(Int -> Int) -> Int" (G.march_ty hof);
      let src = Printf.sprintf {|mod RT do
  type Ops = { f : %s }
  fn use_it(o : Ops) : Int do o.f(1, "x") end
  fn mk() : Ops do { f: fn (a, _s) -> a + 1 } end
end|} (G.march_ty two) in
      let ctx = typecheck src in
      Alcotest.(check bool) "rendered field type round-trips against a 2-param lambda"
        false (has_errors ctx))

let tests = [
  decl_ok; decl_unknown_type; decl_non_record;
  impl_ok; impl_pfn; impl_external; impl_wrong_dict; impl_no_dict_declared;
  impl_io_cap; impl_io_cap_test_build; impl_unpinned;
  dict_reads_option; dict_not_bare; dict_no_declaration;
  narrow_keeps_dict_type;
  two_mods_same_dict_name; two_mods_wrong_dict;
  rt_dispatch; rt_swap; rt_default; rt_narrow_propagates;
  io_console_shape; shadow_list_matches_stdlib; io_clock_zero_arg; io_mut_has_no_dictionary;
  excluded_ops_are_documented; dict_fields_sorted;
  mock_partial_literal; mock_named_handler; mock_vault_handler; mock_field_type;
  mock_unknown_field; mock_two_kinds; mock_computed_scope; mock_unmockable_kind;
  mock_outside_test; mock_dispatch_rewrite; release_build_has_no_wrappers;
  rendered_multi_arg_is_curried;
]
