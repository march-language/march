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

let gated name f =
  Alcotest.test_case name `Quick (fun () -> if z3_available () then f () else Alcotest.skip ())

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
    Alcotest.test_case "lemma hook: empty until @[lemma] exists (phase 2)" `Quick (fun () ->
        Alcotest.(check int) "no lemma key" 0 (List.length (R.lemma_key "app.march"))) ]
