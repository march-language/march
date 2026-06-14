(* Tests for the Phase 5 incremental typecheck engine:
   env-returning incremental check, cached stdlib/deps envs, run_tir_pass memo. *)

module Tc = March_typecheck.Typecheck
module An = March_lsp_lib.Analysis

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

let () =
  Alcotest.run "incremental"
    [ "with_env_full",
      [ Alcotest.test_case "returns final env" `Quick test_with_env_full_returns_env ];
      "base_env",
      [ Alcotest.test_case "memoized" `Quick test_base_env_memoized;
        Alcotest.test_case "derive isolates mutable state" `Quick test_derive_isolates_type_map;
        Alcotest.test_case "incremental matches diagnostics" `Quick test_incremental_matches_diagnostics ] ]
