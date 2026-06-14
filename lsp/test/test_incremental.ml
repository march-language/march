(* Tests for the Phase 5 incremental typecheck engine:
   env-returning incremental check, cached stdlib/deps envs, run_tir_pass memo. *)

module Tc = March_typecheck.Typecheck
module An = March_lsp_lib.Analysis
module Ast = March_ast.Ast

(* Wrap bare declarations in a module so they parse (March requires an
   explicit `mod Name do ... end`). *)
let parse decls =
  let src = "mod M do\n" ^ decls ^ "\nend\n" in
  let lb = Lexing.from_string src in
  March_desugar.Desugar.desugar_module
    (March_parser.Parser.module_
       (March_parser.Token_filter.make March_lexer.Lexer.token) lb)

(* ── Increment 0: check_module_with_env_full ─────────────────────────────── *)

let test_with_env_full_returns_env () =
  let base = parse "  fn helper() : Int do 41 end" in
  let (_e, _tm, base_env) = Tc.check_module_full base in
  let user = parse "  fn g() : Int do helper() end" in
  let (_errs, _tm2, final_env) = Tc.check_module_with_env_full base_env user in
  Alcotest.(check bool) "g bound"      true (Tc.StrMap.mem "g" final_env.Tc.vars);
  Alcotest.(check bool) "helper bound" true (Tc.StrMap.mem "helper" final_env.Tc.vars)

(* ── Increment A: cached stdlib base env ─────────────────────────────────── *)

module TCache = March_lsp_lib.Typecheck_cache

let test_base_env_memoized () =
  let e1 = TCache.base_env () in
  let e2 = TCache.base_env () in
  Alcotest.(check bool) "same cached base env" true (e1 == e2)

let test_derive_isolates_type_map () =
  let base = TCache.base_env () in
  let d = TCache.derive base in
  Alcotest.(check bool) "fresh type_map" true (d.Tc.type_map != base.Tc.type_map);
  Alcotest.(check bool) "fresh errors" true (d.Tc.errors != base.Tc.errors)

let no_error_diags (a : An.t) =
  List.for_all
    (fun (d : Linol_lsp.Lsp.Types.Diagnostic.t) ->
       d.severity <> Some Linol_lsp.Lsp.Types.DiagnosticSeverity.Error)
    a.An.diagnostics

let test_incremental_matches_diagnostics () =
  (* type error: Bool vs Int -> must still be reported under the layered path *)
  let bad = "mod M do\n  fn f() : Int do true end\nend\n" in
  let a = An.analyse ~filename:"t.march" ~src:bad in
  Alcotest.(check bool) "type error still reported" true (not (no_error_diags a));
  let ok = "mod M do\n  fn f() : Int do 41 end\nend\n" in
  let b = An.analyse ~filename:"t.march" ~src:ok in
  Alcotest.(check bool) "clean file has no errors" true (no_error_diags b)

(* ── Increment B: cached deps env ────────────────────────────────────────── *)

let test_deps_env_memoized () =
  let base = TCache.base_env () in
  let deps = (parse "  fn dep_fn() : Int do 7 end").Ast.mod_decls in
  let e1 = TCache.deps_env base ~deps in
  let e2 = TCache.deps_env base ~deps in
  Alcotest.(check bool) "deps env memoized" true (e1 == e2);
  Alcotest.(check bool) "dep_fn bound in deps env" true (Tc.StrMap.mem "dep_fn" e1.Tc.vars);
  Alcotest.(check bool) "deps env distinct from base" true (e1 != base)

let test_deps_env_empty_is_base () =
  let base = TCache.base_env () in
  Alcotest.(check bool) "no deps -> base" true (TCache.deps_env base ~deps:[] == base)

let test_clear_deps_drops_cache () =
  let base = TCache.base_env () in
  let deps = (parse "  fn dep_fn2() : Int do 9 end").Ast.mod_decls in
  let e1 = TCache.deps_env base ~deps in
  TCache.clear_deps ();
  let e2 = TCache.deps_env base ~deps in
  Alcotest.(check bool) "rebuilt after clear" true (e1 != e2)

(* ── Increment C: run_tir_pass source-hash memo ──────────────────────────── *)

let test_tir_pass_memoized () =
  let src = "mod M do\n  fn f(x: Int) : Int do x + 1 end\nend\n" in
  let a = An.analyse ~filename:"t.march" ~src in
  let a1 = An.run_tir_pass a in
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "tir insights memoized (same physical list)"
    true (a1.An.tir_fn_insights == a2.An.tir_fn_insights)

(* ── Increment D: didChangeWatchedFiles invalidation ─────────────────────── *)

let test_watched_invalidates () =
  let open March_lsp_lib.Server in
  Hashtbl.replace ws_index "fake-root" [];
  Alcotest.(check bool) "index populated" false (workspace_index_is_empty ());
  invalidate_workspace_index ();
  Alcotest.(check bool) "index cleared" true (workspace_index_is_empty ())

(* ── Increment E: debounce did_change ────────────────────────────────────── *)

let test_debounce_coalesces () =
  let open March_lsp_lib.Server in
  Alcotest.(check bool) "debounce window is a small positive interval"
    true (debounce_window > 0.0 && debounce_window < 1.0);
  (* Debounce reuses the monotonic version table: a burst of edits collapses
     so only the latest survives the window and is analysed/published. *)
  let vt = make_version_table () in
  let _  = bump_version vt "u" in   (* edit 1 *)
  let _  = bump_version vt "u" in   (* edit 2 *)
  let v3 = bump_version vt "u" in   (* edit 3 — the latest *)
  Alcotest.(check bool) "earlier edit superseded" false (is_current vt "u" 1);
  Alcotest.(check bool) "only the latest edit runs" true (is_current vt "u" v3)

let () =
  Alcotest.run "incremental"
    [ "with_env_full",
      [ Alcotest.test_case "returns final env" `Quick test_with_env_full_returns_env ];
      "base_env",
      [ Alcotest.test_case "memoized" `Quick test_base_env_memoized;
        Alcotest.test_case "derive isolates mutable state" `Quick test_derive_isolates_type_map;
        Alcotest.test_case "incremental matches diagnostics" `Quick test_incremental_matches_diagnostics ];
      "deps_env",
      [ Alcotest.test_case "memoized by content" `Quick test_deps_env_memoized;
        Alcotest.test_case "empty deps is base" `Quick test_deps_env_empty_is_base;
        Alcotest.test_case "clear_deps rebuilds" `Quick test_clear_deps_drops_cache ];
      "run_tir_pass",
      [ Alcotest.test_case "memoized by source" `Quick test_tir_pass_memoized ];
      "watched_files",
      [ Alcotest.test_case "invalidate clears index" `Quick test_watched_invalidates ];
      "debounce",
      [ Alcotest.test_case "coalesces keystroke bursts" `Quick test_debounce_coalesces ] ]
