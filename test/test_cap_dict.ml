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
  fn boot(c : Cap(IO)) : Cap(Session.Live) do
    mint_cap(c)
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
  fn boot(c : Cap(IO)) : Cap(Session.Live) do
    cap_impl(mint_cap(c), { tick: fn n -> n + 1 })
  end
end|}

let impl_pfn = bad "cap_impl in a private fn is rejected" {|mod Session do
  type Ops = { tick : (Int) -> Int }
  proof cap Live with Ops
  needs IO
  pfn boot(c : Cap(IO)) : Cap(Session.Live) do
    cap_impl(mint_cap(c), { tick: fn n -> n + 1 })
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
  fn boot(c : Cap(IO)) : Cap(Session.Live) do
    cap_impl(mint_cap(c), { blah: 1 })
  end
end|}

let impl_no_dict_declared = bad "cap_impl on a cap with no `with` clause is rejected" {|mod Session do
  proof cap Live
  needs IO
  fn boot(c : Cap(IO)) : Cap(Session.Live) do
    cap_impl(mint_cap(c), { tick: 1 })
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
  fn boot(c : Cap(IO)) do
    let f = fn _ -> cap_impl(mint_cap(c), { tick: fn n -> n + 1 })
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

(* ── attenuation propagates the dictionary, but cannot attach one ─────── *)

let narrow_keeps_dict_type = ok "cap_narrow of a dictionaried cap still reads its dictionary" {|mod App do
  needs IO
  type Ops = { write : (String) -> () }
  fn go(c : Cap(IO)) : Int do
    let n = cap_narrow(c)
    consume(n)
  end
  fn consume(_c : Cap(IO.Console)) : Int do 1 end
end|}

(* Under --test the gate now OPENS: an IO capability's dictionary type is
   derived from the compiler's own builtin tables ([Io_ops_gen]), so `cap_impl`
   on one typechecks.  What is still missing is the BINDING SITE — nothing yet
   lets a test say "run this code with that mock" — so attaching one has no
   runtime effect.  Pinned so the change is deliberate rather than discovered
   later, and so the remaining gap stays visible. *)
let impl_io_cap_test_build =
  Alcotest.test_case "--test admits cap_impl on an IO capability"
    `Quick (fun () ->
      let saved = !March_typecheck.Typecheck.test_build in
      March_typecheck.Typecheck.test_build := true;
      let ctx =
        Fun.protect
          ~finally:(fun () -> March_typecheck.Typecheck.test_build := saved)
          (fun () -> typecheck {|mod App do
  needs IO.Console
  fn boot(c : Cap(IO.Console)) : Cap(IO.Console) do
    cap_impl(c, { cap_ops_empty(c) with print_line: Some(fn s -> print(s)) })
  end
end|})
      in
      Alcotest.(check bool) "admitted under --test" false (has_errors ctx))

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
  fn plain(c : Cap(IO)) : Cap(Session.Live) do
    mint_cap(c)
  end
  fn with_add(c : Cap(IO), k : Int) : Cap(Session.Live) do
    cap_impl(mint_cap(c), { tick: fn n -> n + k })
  end
  fn with_mul(c : Cap(IO), k : Int) : Cap(Session.Live) do
    cap_impl(mint_cap(c), { tick: fn n -> n * k })
  end
  fn run(c : Cap(Session.Live), n : Int) : Int do
    match cap_dict(c) do
      Some(d) -> d.tick(n)
      None    -> n
    end
  end
  fn swapped_add(n : Int, k : Int) : Int do run(with_add(root_cap, k), n) end
  fn swapped_mul(n : Int, k : Int) : Int do run(with_mul(root_cap, k), n) end
  fn defaulted(n : Int) : Int do run(plain(root_cap), n) end
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

   [mint_cap]'s counterpart — that a mint does NOT inherit the dictionary of
   the [Cap(IO)] it was minted from — is deliberately NOT tested here, because
   it is unobservable in well-typed code: [mint_cap] takes [Cap(IO)], and an IO
   capability cannot legally carry a dictionary (see [impl_io_cap]).  The
   interpreter still implements non-inheritance defensively; it becomes
   observable only if IO capabilities ever gain dictionaries.

   These bodies name [root_cap] directly, which reject/t152 forbids outside a
   test body.  That is fine HERE and only here: [eval_module] does not
   typecheck, and the typing of every construct below is already pinned by the
   accept/reject cases above. *)
let rt_narrow_propagates =
  Alcotest.test_case "cap_narrow propagates an attached dictionary" `Quick
    (fun () ->
      let src = {|mod Two do
  type Ops = { tick : (Int) -> Int }
  proof cap A with Ops
  proof cap B with Ops
  fn mk() : Cap(Two.A) do
    cap_impl(mint_cap(root_cap), { tick: fn n -> n + 100 })
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
        [ "print"; "print_line" ] (field_names "IO.Console");
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

(* ── capability-passing analysis invariants ───────────────────────────── *)

(* Regression: a nested local function that performs IO.

   `File.with_lines` has a local `fn do_lines(a, f)` calling `file_read_line`.
   Attributing that operation to the LOCAL's name put "do_lines" in the
   analysis table -- but a local is not in [tm_fns], so the elaboration never
   added parameters to it while the threading happily added an ARGUMENT at its
   call sites.  The compiled binary died with SIGBUS (rc=138).  Defun lifts
   such locals to top level later, which is why `--dump-tir` showed
   `fn do_lines` and made it look top-level all along.

   Two assertions, because either alone would have missed it: no entry may
   name something that is not a top-level function (the crash), and the
   ENCLOSING function must have picked the capability up (the missed
   threading that attributing upward also fixes). *)
let analysis_attributes_locals_to_their_owner =
  Alcotest.test_case "a nested local fn's IO is charged to its enclosing fn" `Quick
    (fun () ->
      let m =
        parse_and_desugar {|mod L do
  needs IO.FileRead
  fn outer(path : String) : Int do
    fn inner(n : Int) : Int do
      match file_read(path) do
        Ok(_)  -> n + 1
        Err(_) -> n
      end
    end
    inner(0)
  end
end|}
      in
      let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
      let tir =
        March_tir.Lower.lower_module ~type_map ~test_mode:false ~hot_reload:false m
      in
      let need = March_tir.Cap_passing.needed_caps tir in
      let toplevel =
        List.map (fun (fd : March_tir.Tir.fn_def) -> fd.March_tir.Tir.fn_name)
          tir.March_tir.Tir.tm_fns
      in
      let non_toplevel =
        Hashtbl.fold (fun k _ acc -> if List.mem k toplevel then acc else k :: acc)
          need []
      in
      Alcotest.(check (list string))
        "no entry names a non-top-level function" [] (List.sort compare non_toplevel);
      Alcotest.(check bool) "the enclosing fn picked up IO.FileRead" true
        (match Hashtbl.find_opt need "outer" with
         | Some caps -> List.mem "IO.FileRead" caps
         | None -> false))

(* ── what an actor's dispatch needs, as the spawn site will capture it ─── *)

(* v1 captured ONE capability per actor and returned `None` for two or more,
   so an actor that logged AND read the clock could not be mocked at all. The
   analysis now returns every capability the dispatch reaches, sorted, and the
   one-capability actor goes through the same list-shaped path rather than a
   special case -- pinned here at the analysis level so the two spawn shapes
   cannot drift apart, and by the `cap_mock_actor` / `cap_mock_actor_two`
   goldens at the emitted-code level. *)
let dispatch_caps_lists_every_capability =
  Alcotest.test_case "an actor's dispatch reports every capability it reaches"
    `Quick (fun () ->
      let m =
        parse_and_desugar {|mod D do
  needs IO.Console
  needs IO.Clock
  actor Two do
    state { n : Int }
    init  { n: 0 }
    on Tick(s : String) do
      print_line(s ++ int_to_string(unix_time_ms()))
      { state with n: state.n + 1 }
    end
  end
  actor One do
    state { n : Int }
    init  { n: 0 }
    on Say(s : String) do
      print_line(s)
      { state with n: state.n + 1 }
    end
  end
end|}
      in
      let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
      let tir =
        March_tir.Lower.lower_module ~type_map ~test_mode:false ~hot_reload:false m
      in
      let need = March_tir.Cap_passing.needed_caps tir in
      let dispatch_of actor =
        List.find
          (fun (fd : March_tir.Tir.fn_def) ->
             March_tir.Cap_passing.actor_of_dispatch fd.March_tir.Tir.fn_name
             = Some actor)
          tir.March_tir.Tir.tm_fns
      in
      Alcotest.(check (list string)) "two-capability actor: both, sorted"
        [ "IO.Clock"; "IO.Console" ]
        (March_tir.Cap_passing.dispatch_caps need (dispatch_of "Two"));
      Alcotest.(check (list string)) "one-capability actor: a one-element list"
        [ "IO.Console" ]
        (March_tir.Cap_passing.dispatch_caps need (dispatch_of "One")))

(* A supervisor's spawn glue spawns its `supervise`-block children itself, so
   it must carry the children's capabilities for the capture pattern inside it
   to have anything to attach. The child's own spawn fn is passed as a value
   to register_supervisor_child (for respawn) and stays frozen; it needs no
   parameters, only a record set on it. *)
let supervisor_glue_carries_children_caps =
  Alcotest.test_case "a supervisor's spawn glue needs its children's capabilities"
    `Quick (fun () ->
      let m =
        parse_and_desugar {|mod S do
  needs IO.Console
  actor Logger do
    state { n : Int }
    init  { n: 0 }
    on Say(s : String) do
      print_line(s)
      { state with n: state.n + 1 }
    end
  end
  actor Sup do
    state { w : Int }
    init  { w: 0 }
    supervise do
      strategy one_for_one
      max_restarts 5 within 60
      Logger w
    end
  end
end|}
      in
      let (_errors, type_map) = March_typecheck.Typecheck.check_module m in
      let tir =
        March_tir.Lower.lower_module ~type_map ~test_mode:false ~hot_reload:false m
      in
      let glue =
        List.find
          (fun (fd : March_tir.Tir.fn_def) ->
             March_tir.Cap_passing.actor_of_spawn fd.March_tir.Tir.fn_name = Some "Sup")
          tir.March_tir.Tir.tm_fns
      in
      Alcotest.(check (list string)) "the glue spawns Logger as a supervised child"
        [ "Logger" ]
        (March_tir.Cap_passing.supervised_children glue.March_tir.Tir.fn_body);
      let need = March_tir.Cap_passing.needed_caps tir in
      Alcotest.(check (option (list string))) "Sup_spawn carries the child's caps"
        (Some [ "IO.Console" ]) (Hashtbl.find_opt need "Sup_spawn");
      Alcotest.(check (option (list string))) "Logger_spawn stays frozen (passed as a value)"
        None (Hashtbl.find_opt need "Logger_spawn"))

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
  rt_dispatch; rt_swap; rt_default; rt_narrow_propagates;
  io_console_shape; shadow_list_matches_stdlib; io_clock_zero_arg; io_mut_has_no_dictionary;
  excluded_ops_are_documented; dict_fields_sorted;
  analysis_attributes_locals_to_their_owner;
  dispatch_caps_lists_every_capability;
  supervisor_glue_carries_children_caps;
  rendered_multi_arg_is_curried;
]
