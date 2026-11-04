(* Refinement diagnostics in the editor and their invalidation by a
   dependency's reflected body (refinement reflection §7.2, I8; the phase-1
   RED row `lsp_invalidate`).  Drives [Refine_diag] over the REAL compiler
   (`--check --check-json --reflect-deps`), with a private HOME. *)

module R = March_lsp_lib.Refine_diag

let z3_available () =
  match March_refine.Solver.create () with
  | None -> false
  | Some s -> March_refine.Solver.close s; true

let exe () = Filename.concat (Filename.dirname Sys.executable_name) "../../bin/main.exe"

let rec remove_tree path =
  if Sys.is_directory path then begin
    Array.iter (fun n -> remove_tree (Filename.concat path n)) (Sys.readdir path);
    Unix.rmdir path
  end
  else Sys.remove path

let write dir f text = Out_channel.with_open_bin (Filename.concat dir f) (fun oc -> output_string oc text)

let util k = Printf.sprintf "mod Util do\n  fn is_small(n : Int) : Bool do n < %d end\nend\n" k

(* An edit that leaves is_small's definition alone: a comment above it (every
   position moves) and a new function beside it. *)
let util_with_extra k =
  Printf.sprintf
    "-- utilities\nmod Util do\n  fn other(n : Int) : Int do n + 3 end\n  fn is_small(n : Int) : Bool do n < %d end\nend\n" k

let app =
  {|mod App do
  fn need_small(n : {Int | _ < 10}) : Int do n end
  fn f(n : Int) : Int do
    if Util.is_small(n) do need_small(n) else 0 end
  end
end
|}

(* A scratch project: app.march + util.march side by side, a private HOME
   (the stdlib cache), and the compiler under test. *)
let with_project f =
  let dir = Filename.temp_dir "lsp_refine" "" and home = Filename.temp_dir "lsp_refine_home" "" in
  let saved = (Sys.getenv_opt "HOME", Sys.getenv_opt "MARCH_LSP_COMPILER") in
  Unix.putenv "HOME" home;
  Unix.putenv "MARCH_LSP_COMPILER" (exe ());
  Hashtbl.reset R.last;
  Fun.protect
    ~finally:(fun () ->
      (match saved with
       | Some h, c -> Unix.putenv "HOME" h; Unix.putenv "MARCH_LSP_COMPILER" (Option.value ~default:"" c)
       | None, _ -> ());
      (try remove_tree dir with _ -> ());
      try remove_tree home with _ -> ())
    (fun () -> f dir)

let unverified (r : R.result) = List.exists (fun (d : R.diag) -> d.R.d_code = "refinement_unverified") r.R.r_diags

let violated (r : R.result) = List.exists (fun (d : R.diag) -> d.R.d_code = "refinement_violated") r.R.r_diags

(* util.march at [util 1], app.march checked, then util.march at [util 100]
   (only the contract the test is about moves): exactly app.march is
   re-checked, and (with [violated_after]) the re-check rejects it. *)
let contract_case ~(util : int -> string) ~(app : string) ~(violated_after : bool) =
  with_project (fun dir ->
      write dir "util.march" (util 1);
      write dir "app.march" app;
      let app_path = Filename.concat dir "app.march" and util_path = Filename.concat dir "util.march" in
      if violated (R.check app_path) then Alcotest.fail "before the edit app.march is not rejected";
      write dir "util.march" (util 100);
      match R.on_change util_path with
      | [ (f, after) ] ->
        Alcotest.(check string) "the dependent re-checked" (R.canon app_path) f;
        if violated_after && not (violated after) then Alcotest.fail "after the edit app.march is refinement_violated"
      | rs -> Alcotest.failf "exactly app.march must be re-checked, got %d files" (List.length rs))

let gated name f =
  Alcotest.test_case name `Quick (fun () -> if z3_available () then f () else Alcotest.skip ())

let lst_src =
  "mod Lst do\n  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do\n    match xs do\n      Nil -> ys\n      Cons(h, t) -> Cons(h, cat(t, ys))\n    end\n  end\n  fn rev(xs : List(Int)) : List(Int) do\n    match xs do\n      Nil -> Nil\n      Cons(h, t) -> cat(rev(t), Cons(h, Nil))\n    end\n  end\n  @[lemma]\n  fn rev_cat(xs : List(Int), ys : List(Int)) : {Unit | rev(cat(xs, ys)) == cat(rev(ys), rev(xs))} do\n    ()\n  end\nend\n"

let title_at (a : March_lsp_lib.Analysis.t) src needle ~admitted ~stdlib =
  let line, col = Test_lsp_harness.pos_of src needle in
  List.map
    (fun (ca : Test_lsp_harness.Lsp.Types.CodeAction.t) -> ca.Test_lsp_harness.Lsp.Types.CodeAction.title)
    (March_lsp_lib.Lemma_rewrite.actions ~stdlib a ~line ~character:(col + 1) ~admitted)

let tests =
  [ gated "lsp_invalidate: a dependency's reflected body edit re-checks app.march, with no edit to it" (fun () ->
        with_project (fun dir ->
            write dir "util.march" (util 10);
            write dir "app.march" app;
            let app_path = Filename.concat dir "app.march" and util_path = Filename.concat dir "util.march" in
            let before = R.check app_path in
            if unverified before then Alcotest.fail "before the edit need_small is proved: no diagnostic";
            if not (List.exists (fun d -> d.R.dep_name = "Util.is_small") before.R.r_deps) then
              Alcotest.fail "app.march's key must name Util.is_small (a frontier function)";
            (* is_small: n < 10 -> n < 20, saved; app.march untouched *)
            write dir "util.march" (util 20);
            match R.on_change util_path with
            | [ (f, after) ] ->
              Alcotest.(check string) "the dependent re-checked" (R.canon app_path) f;
              if not (unverified after) then
                Alcotest.failf "after the edit need_small is refinement_unverified: %d diagnostics"
                  (List.length after.R.r_diags)
            | rs -> Alcotest.failf "exactly app.march must be re-checked, got %d files" (List.length rs)));
    gated "lsp_invalidate: an edit that moves no frontier hash re-checks nothing" (fun () ->
        with_project (fun dir ->
            write dir "util.march" (util 10);
            write dir "app.march" app;
            let app_path = Filename.concat dir "app.march" and util_path = Filename.concat dir "util.march" in
            ignore (R.check app_path);
            write dir "util.march" (util_with_extra 10);
            let n0 = !R.runs in
            Alcotest.(check int) "no dependent is stale" 0 (List.length (R.on_change util_path));
            Alcotest.(check int) "only util.march itself was checked" (n0 + 1) !R.runs));
    gated "lsp_invalidate: the key is the frontier, not the core (a skip that would become a proof re-checks)" (fun () ->
        (* A skipped obligation has no unsat core.  Keyed on cores, the edit
           that makes it provable would leave the stale skip on screen. *)
        with_project (fun dir ->
            write dir "util.march" (util 20);
            write dir "app.march" app;
            let app_path = Filename.concat dir "app.march" and util_path = Filename.concat dir "util.march" in
            if not (unverified (R.check app_path)) then Alcotest.fail "with n < 20 need_small is unverified";
            write dir "util.march" (util 10);
            match R.on_change util_path with
            | [ (_, after) ] -> if unverified after then Alcotest.fail "after the edit need_small is proved"
            | rs -> Alcotest.failf "app.march must be re-checked, got %d files" (List.length rs)));
    gated "lsp_invalidate: a callee's CONTRACT edit re-checks its caller (review round 1)" (fun () ->
        (* Util.need's parameter refinement is no reflected body: before the
           fix app.march's key listed only frontier bodies, so `v > 1` ->
           `v > 100` left `Util.need(3)` clean in the editor while a fresh
           --check reports refinement_violated. *)
        with_project (fun dir ->
            let util k = Printf.sprintf "mod Util do\n  fn need(n : {v : Int | v > %d}) : Int do n end\nend\n" k in
            write dir "util.march" (util 1);
            write dir "app.march" "mod App do\n  fn go2() : Int do\n    Util.need(3)\n  end\nend\n";
            let app_path = Filename.concat dir "app.march" and util_path = Filename.concat dir "util.march" in
            let violated (r : R.result) = List.exists (fun (d : R.diag) -> d.R.d_code = "refinement_violated") r.R.r_diags in
            if violated (R.check app_path) then Alcotest.fail "before the edit Util.need(3) satisfies v > 1";
            write dir "util.march" (util 100);
            match R.on_change util_path with
            | [ (f, after) ] ->
              Alcotest.(check string) "the dependent re-checked" (R.canon app_path) f;
              if not (violated after) then Alcotest.fail "after the edit Util.need(3) is refinement_violated"
            | rs -> Alcotest.failf "exactly app.march must be re-checked, got %d files" (List.length rs)));
    gated "lsp_invalidate: a callee going from blocked to reflected re-checks its caller (review round 1)" (fun () ->
        with_project (fun dir ->
            (* blocked: is_small has an effect, so it has no logic symbol and
               is in no frontier; app.march's key held nothing of it. *)
            write dir "util.march"
              "mod Util do\n  fn is_small(n : Int) : Bool do\n    println(\"x\")\n    n < 10\n  end\nend\n";
            write dir "app.march" app;
            let app_path = Filename.concat dir "app.march" and util_path = Filename.concat dir "util.march" in
            if not (unverified (R.check app_path)) then Alcotest.fail "with is_small blocked need_small is unverified";
            write dir "util.march" (util 10);
            match R.on_change util_path with
            | [ (_, after) ] -> if unverified after then Alcotest.fail "after the edit need_small is proved"
            | rs -> Alcotest.failf "app.march must be re-checked, got %d files" (List.length rs)));
    gated "lsp_invalidate: a third file's edit that unreflects a callee re-checks the caller (review round 1)" (fun () ->
        (* app calls Util.is_small, which calls Util2.lim.  lim gaining an
           effect makes is_small unreflected (R: callee not reflected): a
           change in util.march's functions that only util2.march's edit
           causes.  app.march's key holds the contract (and reflectability)
           of every function of another file it reaches, Util2.lim included. *)
        with_project (fun dir ->
            write dir "util.march" "mod Util do\n  fn is_small(n : Int) : Bool do n < Util2.lim(n) end\nend\n";
            let util2 eff =
              Printf.sprintf "mod Util2 do\n  fn lim(n : Int) : Int do\n    %s10\n  end\nend\n"
                (if eff then "println(\"x\")\n    " else "")
            in
            write dir "util2.march" (util2 false);
            write dir "app.march" app;
            let app_path = Filename.concat dir "app.march" and util2_path = Filename.concat dir "util2.march" in
            let before = R.check app_path in
            if not (List.exists (fun d -> d.R.dep_name = "Util.is_small") before.R.r_deps) then
              Alcotest.fail "app.march's key must name Util.is_small";
            write dir "util2.march" (util2 true);
            match R.on_change util2_path with
            | [ (f, _) ] -> Alcotest.(check string) "the dependent re-checked" (R.canon app_path) f
            | rs -> Alcotest.failf "app.march must be re-checked, got %d files" (List.length rs)));
    (* Review round 2: a contract edit the key must see, as (util before,
       util after, app); [violated_after] when the fresh check rejects app. *)
    gated "lsp_invalidate: twin heads in two nested modules are told apart (review round 2)" (fun () ->
        contract_case
          ~util:(fun a -> Printf.sprintf
                    "mod Util do\n  mod A do\n    fn need(n : {v : Int | v > %d}) : Int do n end\n  end\n  mod B do\n    fn need(n : {v : Int | v > 1}) : Int do n end\n  end\nend\n" a)
          ~app:"mod App do\n  fn go2() : Int do\n    Util.A.need(3)\n  end\nend\n" ~violated_after:true);
    gated "lsp_invalidate: a function named in a callee's refinement is keyed by its body (review round 2)" (fun () ->
        contract_case
          ~util:(fun k -> Printf.sprintf
                    "mod Util do\n  fn size() : Int do %d end\n  fn need(n : {Int | _ < size()}) : Int do n end\nend\n" (if k = 1 then 128 else 4))
          ~app:"mod App do\n  fn go2() : Int do\n    Util.need(5)\n  end\nend\n" ~violated_after:true);
    gated "lsp_invalidate: a measure named in a callee's refinement is keyed by its body (review round 2)" (fun () ->
        contract_case
          ~util:(fun k -> Printf.sprintf
                    "mod Util do\n  type T = L | N(T, Int)\n  @[measure]\n  fn sz(t : T) : Int do\n    match t do\n      L -> 0\n      N(r, _) -> %d + sz(r)\n    end\n  end\n  fn need(t : {T | sz(_) > 0}) : Int do 1 end\nend\n" (if k = 1 then 1 else 0))
          ~app:"mod App do\n  fn go2() : Int do\n    Util.need(Util.N(Util.L, 3))\n  end\nend\n" ~violated_after:false);
    gated "lsp_lemma_invalidate: a dependency lemma that stops proving withdraws its caller's fact" (fun () ->
        let util ~proved =
          Printf.sprintf
            {|mod Util do
  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
    match xs do
      Nil -> ys
      Cons(h, t) -> Cons(h, cat(t, ys))
    end
  end
  @[lemma]
  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do
    match xs do
      Nil -> ()
      Cons(_, t) -> %s
    end
  end
end
|}
            (if proved then "cat_nil(t)" else "()")
        in
        let app =
          {|mod App do
  fn need_eq(a : List(Int), b : {List(Int) | _ == a}) : Int do 0 end
  fn f(xs : List(Int)) : Int do
    Util.cat_nil(xs)
    need_eq(xs, Util.cat(xs, Nil))
  end
end
|}
        in
        with_project (fun dir ->
            write dir "util.march" (util ~proved:true);
            write dir "app.march" app;
            let app_path = Filename.concat dir "app.march" and util_path = Filename.concat dir "util.march" in
            let before = R.check app_path in
            if unverified before then Alcotest.fail "before the edit need_eq is proved through the lemma";
            (match R.lemma_key app_path with
             | [ (n, _, true) ] when n = "Util.cat_nil" -> ()
             | k -> Alcotest.failf "app.march's key must hold Util.cat_nil, admitted; got %d entries" (List.length k));
            write dir "util.march" (util ~proved:false);
            match R.on_change util_path with
            | [ (f, after) ] ->
              Alcotest.(check string) "the dependent re-checked" (R.canon app_path) f;
              if not (unverified after) then Alcotest.fail "after the edit need_eq is refinement_unverified";
              if R.lemma_admitted "Util.cat_nil" <> Some false then Alcotest.fail "the lemma is reported unproved"
            | rs -> Alcotest.failf "exactly app.march must be re-checked, got %d files" (List.length rs)));
    Alcotest.test_case "lsp_lemma_hover: hovering a lemma call shows its theorem" `Quick (fun () ->
        let src =
          "mod T do\n  fn inc(n : Int) : Int do n + 1 end\n  @[lemma]\n  fn inc_gt(n : Int) : {Unit | inc(n) > n} do\n    ()\n  end\n  fn f(k : Int) : Int do\n    inc_gt(k)\n    k\n  end\nend\n"
        in
        let a = March_lsp_lib.Analysis.analyse ~filename:"test.march" ~src in
        let line, col = Test_lsp_harness.pos_of src "inc_gt(k)" in
        match March_lsp_lib.Analysis.query_lemma_hover_at a ~line ~utf16_char:(col + 1) with
        | Some (n, p) ->
          Alcotest.(check string) "name" "inc_gt" n;
          Alcotest.(check string) "theorem" "inc(n) > n" p
        | None -> Alcotest.fail "no lemma hover on the call");
    Alcotest.test_case "lsp_lemma_rewrite: an admitted equation is offered as a rewrite, naming the lemma" `Quick (fun () ->
        let src =
          "mod T do\n  fn cat(xs : List(Int), ys : List(Int)) : List(Int) do\n    match xs do\n      Nil -> ys\n      Cons(h, t) -> Cons(h, cat(t, ys))\n    end\n  end\n  @[lemma]\n  fn cat_nil(xs : List(Int)) : {Unit | cat(xs, Nil) == xs} do\n    match xs do\n      Nil -> ()\n      Cons(_, t) -> cat_nil(t)\n    end\n  end\n  fn f(zs : List(Int)) : List(Int) do\n    cat(Cons(1, zs), Nil)\n  end\n  fn g(zs : List(Int)) : List(Int) do\n    cat(zs, zs)\n  end\nend\n"
        in
        let a = March_lsp_lib.Analysis.analyse ~filename:"test.march" ~src in
        let at needle =
          let line, col = Test_lsp_harness.pos_of src needle in
          (line, col + 1)
        in
        let acts ~admitted needle =
          let line, character = at needle in
          March_lsp_lib.Lemma_rewrite.actions a ~line ~character ~admitted
        in
        let proved n = if n = "cat_nil" then Some true else None in
        (match acts ~admitted:proved "cat(Cons(1, zs), Nil)" with
         | [ act ] ->
           Alcotest.(check string) "title" "Rewrite to `Cons(1, zs)` (by the proved lemma `cat_nil`)"
             act.Test_lsp_harness.Lsp.Types.CodeAction.title
         | l -> Alcotest.failf "expected one rewrite, got %d" (List.length l));
        (* An unproved lemma justifies nothing. *)
        if acts ~admitted:(fun _ -> Some false) "cat(Cons(1, zs), Nil)" <> [] then
          Alcotest.fail "an unproved lemma offers no rewrite";
        if acts ~admitted:(fun _ -> None) "cat(Cons(1, zs), Nil)" <> [] then
          Alcotest.fail "an unchecked lemma offers no rewrite";
        (* `cat(zs, zs)` is not an instance of `cat(xs, Nil)`. *)
        if acts ~admitted:proved "cat(zs, zs)" <> [] then Alcotest.fail "no rewrite where the left side does not match");
    Alcotest.test_case "lsp_lemma_rewrite_imported: a proved lemma of an imported file, its functions qualified" `Quick (fun () ->
        (* A forge project: the analysis resolves imports from its lib/. *)
        let dir = Filename.temp_dir "lemma_rw" "" in
        write dir "forge.toml" "[package]\nname = \"rw\"\nversion = \"0.1.0\"\n";
        Unix.mkdir (Filename.concat dir "lib") 0o755;
        write (Filename.concat dir "lib") "lst.march" lst_src;
        let src = "mod Main do\n  fn f(a : List(Int), b : List(Int)) : List(Int) do\n    Lst.rev(Lst.cat(a, b))\n  end\nend\n" in
        write (Filename.concat dir "lib") "main.march" src;
        let a = March_lsp_lib.Analysis.analyse ~filename:(Filename.concat (Filename.concat dir "lib") "main.march") ~src in
        let titles = title_at a src "Lst.rev(Lst.cat" ~stdlib:[] ~admitted:(fun n -> if n = "rev_cat" then Some true else None) in
        Alcotest.(check (list string)) "qualified rhs"
          [ "Rewrite to `Lst.cat(Lst.rev(b), Lst.rev(a))` (by the proved lemma `Lst.rev_cat`)" ] titles;
        if title_at a src "Lst.rev(Lst.cat" ~stdlib:[] ~admitted:(fun _ -> Some false) <> [] then
          Alcotest.fail "an unproved imported lemma offers nothing");
    Alcotest.test_case "lsp_lemma_rewrite_stdlib: a stdlib lemma the manifest lists is a rule" `Quick (fun () ->
        let dir = Filename.temp_dir "lemma_std" "" in
        write dir "lemmas.verified" "# manifest\nLst.rev_cat\tabc\n";
        let saved = !March_lsp_lib.Stdlib_cache.stdlib_dir in
        March_lsp_lib.Stdlib_cache.set_stdlib_dir (fun () -> Some dir);
        March_lsp_lib.Lemma_rewrite.stdlib_manifest := None;
        Fun.protect
          ~finally:(fun () ->
            March_lsp_lib.Stdlib_cache.set_stdlib_dir saved;
            March_lsp_lib.Lemma_rewrite.stdlib_manifest := None)
          (fun () ->
            let f = Filename.concat dir "lst.march" in
            write dir "lst.march" lst_src;
            let stdlib = [ March_ast.Ast.DMod (March_ast.Ast.{ txt = "Lst"; span = { dummy_span with file = f } }, March_ast.Ast.Public,
                                               (match March_parser.Parse.module_ ~filename:f lst_src with
                                                | Ok m -> m.March_ast.Ast.mod_decls
                                                | _ -> []), March_ast.Ast.{ dummy_span with file = f }) ] in
            let src = "mod Main do\n  fn f(a : List(Int), b : List(Int)) : List(Int) do\n    Lst.rev(Lst.cat(a, b))\n  end\nend\n" in
            let a = March_lsp_lib.Analysis.analyse ~filename:"main.march" ~src in
            let titles = title_at a src "Lst.rev(Lst.cat" ~stdlib ~admitted:(fun _ -> None) in
            Alcotest.(check (list string)) "stdlib rule"
              [ "Rewrite to `Lst.cat(Lst.rev(b), Lst.rev(a))` (by the proved lemma `Lst.rev_cat`)" ] titles;
            (* Not in the manifest: not a rule. *)
            write dir "lemmas.verified" "# manifest\n";
            March_lsp_lib.Lemma_rewrite.stdlib_manifest := None;
            if title_at a src "Lst.rev(Lst.cat" ~stdlib ~admitted:(fun _ -> None) <> [] then
              Alcotest.fail "an unlisted stdlib lemma offers nothing")) ]
